#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "../TCWorker.m"
#include <assert.h>

// Exercise the actual private long-capture result assembler and production
// hook without NSApplication, windows, recording, permissions or clipboard.
// Only SCStream's documented completion is simulated, on the main queue.
void TCShowImageTranslation(const void *image, const void *regions, const void *owner,
                           double x, double y, double width, double height,
                           TCImageTranslationCompletion completion) { abort(); }
void TCDismissImageTranslation(void) { }

@interface TCLongTestWorker : TCWorker
@property NSUInteger finishCalls;
@property NSUInteger failureCalls;
@property int failureCode;
@property BOOL saved;
@property NSImage *receivedImage;
@end
@implementation TCLongTestWorker
- (void)setPhaseValue:(char)value { self.phase = value; }
- (void)finish:(NSImage *)image save:(BOOL)save {
    self.finishCalls++;
    self.saved = save;
    self.receivedImage = image;
    self.terminal = YES;
}
- (void)end:(int)code {
    self.failureCalls++;
    self.failureCode = code;
    self.terminal = YES;
}
@end

@interface TCLongTestStream : NSObject
@property NSUInteger removes;
@property NSUInteger stops;
@property NSUInteger completions;
@property BOOL failStop;
@property BOOL failRemove;
@end
@implementation TCLongTestStream
- (BOOL)removeStreamOutput:(id)output type:(SCStreamOutputType)type error:(NSError **)error {
    assert(type == SCStreamOutputTypeScreen && output);
    self.removes++;
    if (self.failRemove) {
        if (error) *error = [NSError errorWithDomain:@"SyntheticStream" code:1 userInfo:nil];
        return NO;
    }
    return YES;
}
- (void)stopCaptureWithCompletionHandler:(void (^)(NSError *))completion {
    self.stops++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        self.completions++;
        completion(self.failStop ? [NSError errorWithDomain:@"SyntheticStream" code:2 userInfo:nil] : nil);
    });
}
@end

static char StreamAssociation, ImageAssociation;
static id TestStream(id object, SEL selector) { return objc_getAssociatedObject(object, &StreamAssociation); }
static void TestSetStream(id object, SEL selector, id stream) {
    objc_setAssociatedObject(object, &StreamAssociation, stream, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static id TestResult(id object, SEL selector) { return objc_getAssociatedObject(object, &ImageAssociation); }

static Class LoadManager(void) {
    NSError *error = nil;
    NSString *framework = @"/Applications/bro截图.app/Contents/Frameworks/JietuFramework.framework";
    assert([[NSBundle bundleWithPath:framework] loadAndReturnError:&error]);
    for (NSString *name in RequiredABI()) {
        Class cls = NSClassFromString(name);
        for (NSString *key in RequiredABI()[name]) {
            BOOL meta = [key hasPrefix:@"+"];
            SEL sel = NSSelectorFromString(meta ? [key substringFromIndex:1] : key);
            Method method = meta ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
            assert(method && !strcmp(method_getTypeEncoding(method), [RequiredABI()[name][key] UTF8String]));
        }
    }
    Class base = NSClassFromString(@"JTLongCaptureManager");
    nativeLongDone = (void *)method_getImplementation(class_getInstanceMethod(base, @selector(captureDidFinish:)));
    Class cls = objc_allocateClassPair(base, "TCLongSyntheticManager", 0);
    assert(cls);
    assert(class_addMethod(cls, @selector(stream), (IMP)TestStream, "@16@0:8"));
    assert(class_addMethod(cls, @selector(setStream:), (IMP)TestSetStream, "v24@0:8@16"));
    assert(class_addMethod(cls, NSSelectorFromString(@"resImage"), (IMP)TestResult, "@16@0:8"));
    assert(class_addMethod(cls, NSSelectorFromString(@"captureDidFinishWithImage:needSave:isHighResolution:"),
                           (IMP)FinishHook, "v32@0:8@16B24B28"));
    objc_registerClassPair(cls);
    return cls;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSString *mode = @(argv[1]);
        Class cls = LoadManager();
        id manager = [[cls alloc] init];
        TCLongTestStream *stream = [TCLongTestStream new];
        TCLongTestWorker *test = [TCLongTestWorker new];
        worker = test;
        test.longActive = YES;
        BOOL absent = [mode isEqualToString:@"no-stream"];
        BOOL cancel = [mode isEqualToString:@"cancel"];
        BOOL empty = [mode isEqualToString:@"empty"];
        BOOL save = ![mode isEqualToString:@"copy"];
        stream.failStop = [mode isEqualToString:@"stop-error"];
        stream.failRemove = [mode isEqualToString:@"remove-error"];
        if (!absent) TestSetStream(manager, NULL, stream);
        if (!empty) objc_setAssociatedObject(manager, &ImageAssociation,
            [[NSImage alloc] initWithSize:NSMakeSize(100, 320)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSNotification *note = [NSNotification notificationWithName:@"captureDidFinish" object:@(save)];
        dispatch_async(dispatch_get_main_queue(), ^{
            assert(NSThread.isMainThread);
            if ([mode isEqualToString:@"original-main-stop"]) {
                puts("ENTER original native main-thread stop"); fflush(stdout);
                nativeLongDone(manager, @selector(captureDidFinish:), note);
                puts("UNEXPECTED original returned"); fflush(stdout); exit(3);
            }
            LongDoneHook(manager, @selector(captureDidFinish:), note);
            if ([mode isEqualToString:@"duplicate"]) LongDoneHook(manager, @selector(captureDidFinish:), note);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            // A delayed main-queue completion must leave this queue responsive.
            if (!absent) assert(stream.completions == 0 && test.finishCalls == 0);
            if (cancel) [test end:TC_WORKER_EXIT_CANCELLED];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            assert(NSApp == nil);
            if (cancel) {
                assert(test.finishCalls == 0 && test.failureCalls == 1 && test.failureCode == TC_WORKER_EXIT_CANCELLED);
            } else if (empty || stream.failStop) {
                assert(test.finishCalls == 0 && test.failureCalls == 1 && test.failureCode == TC_WORKER_EXIT_LONG_CAPTURE_FAILURE);
            } else {
                assert(test.finishCalls == 1 && test.failureCalls == 0 && test.saved == save);
                assert(test.receivedImage.size.height == 320 && test.receivedImage.size.width == 100);
            }
            assert(stream.stops == (absent ? 0 : 1));
            printf("PASS %s: main queue responsive, native result/save flag preserved, finish=%lu failure=%lu\n",
                   argv[1], (unsigned long)test.finishCalls, (unsigned long)test.failureCalls);
            fflush(stdout); exit(0);
        });
        CFRunLoopRun();
    }
    return 4;
}

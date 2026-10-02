#import "TCWorker.h"
#import "TCSession.h"
#import "TCOCR.h"
#import "TCImageAnalysis.h"
#import "TCImageTranslation.h"
#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <Vision/Vision.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <ImageIO/ImageIO.h>

// Every private call/hook below is gated by its full arm64 type encoding.
@interface NSObject (TCPrivate)
+ (id)sharedInstance;
+ (BOOL)isScreenHighResolution:(NSScreen *)screen;
- (BOOL)startCaptureByRequest:(id)request;
- (BOOL)isCapturing;
- (void)setRunAlone:(BOOL)value;
- (void)setHighResolution:(BOOL)value;
- (void)setPlaySound:(BOOL)value;
- (void)setShowSwitch:(BOOL)value;
- (void)setNeedSelectSavePath:(BOOL)value;
- (NSArray *)windowControllers;
- (NSImage *)screenImage;
- (NSWindow *)window;
- (SCStream *)stream;
- (void)setStream:(SCStream *)stream;
- (id)toolbarWindowController;
- (NSImage *)generateCapturedImage;
- (NSView *)captureView;
- (NSRect)selectedRect;
- (void)hideToolbar;
- (void)showToolbar;
- (id)editViewController;
- (NSView *)editView;
- (void)editDidBegin:(id)notification;
- (id)initWithSuperView:(NSView *)view centerPoint:(NSPoint)center size:(NSSize)size;
- (NSPoint)center;
- (NSSize)size;
- (void)setSize:(NSSize)size;
- (void)updateControlPoints;
- (void)transformDidChange;
- (CGFloat)degrees;
- (void)addItem:(id)item;
- (NSMutableArray *)itemArray;
- (void)unfocus;
@end

static NSDictionary *RequiredABI(void) {
    return @{
        @"JTCaptureManager": @{@"+sharedInstance":@"@16@0:8", @"startCaptureByRequest:":@"B24@0:8@16", @"isCapturing":@"B16@0:8", @"windowControllers":@"@16@0:8", @"captureDidFinishWithImage:needSave:isHighResolution:":@"v32@0:8@16B24B28", @"captureDidCancel":@"v16@0:8", @"prepareToOCRWithImage:isHighResolution:":@"v28@0:8@16B24", @"prepareToLongCapture:":@"v24@0:8@16"},
        @"JTCaptureUtilities": @{@"+imageOfScreen:":@"@24@0:8@16", @"+isScreenHighResolution:":@"B24@0:8@16"},
        @"JTCaptureSetting": @{@"+sharedInstance":@"@16@0:8", @"setRunAlone:":@"v20@0:8B16", @"setHighResolution:":@"v20@0:8B16", @"setPlaySound:":@"v20@0:8B16"},
        @"JTCaptureRequest": @{@"setShowSwitch:":@"v20@0:8B16", @"setNeedSelectSavePath:":@"v20@0:8B16"},
        @"JTCaptureWindowController": @{@"screenImage":@"@16@0:8", @"initWithFrame:screen:":@"@56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48"},
        @"JTCaptureViewController": @{@"showToolbar":@"v16@0:8", @"hideToolbar":@"v16@0:8", @"toolbarWindowController":@"@16@0:8", @"generateCapturedImage":@"@16@0:8", @"captureView":@"@16@0:8", @"editViewController":@"@16@0:8", @"editDidBegin:":@"v24@0:8@16"},
        @"JTEditViewController": @{@"editView":@"@16@0:8"},
        @"JTEditView": @{@"addItem:":@"v24@0:8@16", @"itemArray":@"@16@0:8", @"itemIsBottomLevel:":@"B24@0:8@16", @"undoManager":@"@16@0:8", @"unfocus":@"v16@0:8"},
        @"JTRoundRectItem": @{@"initWithSuperView:centerPoint:size:":@"@56@0:8@16{CGPoint=dd}24{CGSize=dd}40", @"drawGraph":@"v16@0:8", @"copyWithZone:":@"@24@0:8^{_NSZone=}16", @"center":@"{CGPoint=dd}16@0:8", @"size":@"{CGSize=dd}16@0:8", @"setSize:":@"v32@0:8{CGSize=dd}16", @"updateControlPoints":@"v16@0:8", @"transformDidChange":@"v16@0:8", @"degrees":@"d16@0:8"},
        @"JTCaptureView": @{@"selectedRect":@"{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8"},
        @"JTLongCaptureManager": @{@"+sharedInstance":@"@16@0:8", @"prepareToLongCapture":@"v16@0:8", @"isCapturing":@"B16@0:8", @"stream":@"@16@0:8", @"setStream:":@"v24@0:8@16", @"window":@"@16@0:8", @"captureDidFinish:":@"v24@0:8@16", @"captureDidFinishWithImage:needSave:isHighResolution:":@"v32@0:8@16B24B28", @"captureDidCancel":@"v16@0:8"}
    };
}
BOOL TCVerifyEngine(NSError **error) {
    NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"JietuFramework.framework"];
    if (![[NSBundle bundleWithPath:path] loadAndReturnError:error]) return NO;
    NSDictionary *specs = RequiredABI();
    for (NSString *name in specs) {
        Class cls = NSClassFromString(name);
        for (NSString *key in specs[name]) {
            BOOL meta = [key hasPrefix:@"+"];
            SEL sel = NSSelectorFromString(meta ? [key substringFromIndex:1] : key);
            Method method = meta ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
            NSString *expected = specs[name][key];
            if (!method || strcmp(method_getTypeEncoding(method), expected.UTF8String)) {
                if (error) *error = [NSError errorWithDomain:@"TCPrivateABI" code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"接口不匹配 %@ %@；拒绝显示截图窗口", name, key]}];
                return NO;
            }
        }
    }
    return YES;
}

@interface TCPinToolbarButton : NSButton
@property(weak) id captureController;
@end
@implementation TCPinToolbarButton
@end

// A rectangular native edit item retains only its pixelated crop. Native
// controls, move/resize, hit testing and undo keep using the existing editor.
static char MosaicBitmapKey;
static Class mosaicItemClass;
static IMP nativeMosaicCopy;
static BOOL (*nativeBottomLevel)(id, SEL, id);
static void (*nativeMosaicAdd)(id, SEL, id);
static void MosaicDraw(id receiver, SEL selector) {
    NSBitmapImageRep *bitmap = objc_getAssociatedObject(receiver,&MosaicBitmapKey);
    if (!bitmap) return;
    NSPoint center = [(NSObject *)receiver center]; NSSize size = [receiver size];
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(context);
    CGContextTranslateCTM(context,center.x,center.y);
    CGContextRotateCTM(context,[receiver degrees]*M_PI/180.0);
    CGContextSetInterpolationQuality(context,kCGInterpolationNone);
    CGContextDrawImage(context,CGRectMake(-size.width/2,-size.height/2,size.width,size.height),bitmap.CGImage);
    CGContextRestoreGState(context);
}
static id MosaicCopy(id receiver, SEL selector, NSZone *zone) NS_RETURNS_RETAINED;
static id MosaicCopy(id receiver, SEL selector, NSZone *zone) {
    id result = CFBridgingRelease(((void *(*)(id,SEL,NSZone *))nativeMosaicCopy)(receiver,selector,zone));
    objc_setAssociatedObject(result,&MosaicBitmapKey,objc_getAssociatedObject(receiver,&MosaicBitmapKey),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}
static void MosaicAdd(id receiver, SEL selector, id item) {
    // Keep native add/remove undo registration. Its bottom-level insertion
    // skips that registration, so move our regular item after adding it.
    nativeMosaicAdd(receiver,selector,item);
    if (![item isKindOfClass:mosaicItemClass]) return;
    NSMutableArray *items = [(NSObject *)receiver itemArray];
    NSUInteger source = [items indexOfObjectIdenticalTo:item];
    if (source == NSNotFound) return;
    NSUInteger target = 0;
    while (target < source && ([items[target] isKindOfClass:mosaicItemClass] ||
           nativeBottomLevel(receiver,NSSelectorFromString(@"itemIsBottomLevel:"),items[target]))) target++;
    if (target == source) return;
    [items removeObjectAtIndex:source]; [items insertObject:item atIndex:target];
}
static Class PrepareMosaicItemClass(void) {
    if (mosaicItemClass) return mosaicItemClass;
    if (NSClassFromString(@"BroScreenshotMosaicItem")) return Nil;
    Class base = NSClassFromString(@"JTRoundRectItem");
    Class cls = objc_allocateClassPair(base,"BroScreenshotMosaicItem",0);
    if (!cls) return Nil;
    Method draw = class_getInstanceMethod(base,@selector(drawGraph));
    Method copy = class_getInstanceMethod(base,@selector(copyWithZone:));
    if (!class_addMethod(cls,@selector(drawGraph),(IMP)MosaicDraw,method_getTypeEncoding(draw)) ||
        !class_addMethod(cls,@selector(copyWithZone:),(IMP)MosaicCopy,method_getTypeEncoding(copy))) {
        objc_disposeClassPair(cls); return Nil;
    }
    nativeMosaicCopy = method_getImplementation(copy);
    objc_registerClassPair(cls); mosaicItemClass = cls;
    Class edit = NSClassFromString(@"JTEditView");
    nativeBottomLevel = (void *)method_getImplementation(class_getInstanceMethod(edit,NSSelectorFromString(@"itemIsBottomLevel:")));
    nativeMosaicAdd = (void *)method_setImplementation(class_getInstanceMethod(edit,@selector(addItem:)),(IMP)MosaicAdd);
    return cls;
}
static BOOL ApplyMosaicItems(NSView *edit, NSData *png, NSArray<NSDictionary *> *regions, NSError **error) {
    if (![edit isKindOfClass:NSClassFromString(@"JTEditView")] || NSIsEmptyRect(edit.bounds) || !PrepareMosaicItemClass()) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)png,NULL);
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source,0,NULL) : NULL;
    if (source) CFRelease(source);
    if (!image) return NO;
    CGFloat width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSMutableArray *items = [NSMutableArray new];
    for (NSDictionary *region in regions) {
        NSRect pixels = NSMakeRect([region[@"x"] doubleValue]*width,[region[@"y"] doubleValue]*height,
                                  [region[@"width"] doubleValue]*width,[region[@"height"] doubleValue]*height);
        pixels = NSIntersectionRect(NSIntegralRect(pixels),NSMakeRect(0,0,width,height));
        CGImageRef crop = CGImageCreateWithImageInRect(image,CGRectMake(pixels.origin.x,height-NSMaxY(pixels),pixels.size.width,pixels.size.height));
        if (!crop) { CGImageRelease(image); return NO; }
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:crop]; CGImageRelease(crop);
        NSRect rect = NSMakeRect(edit.bounds.origin.x+pixels.origin.x/width*edit.bounds.size.width,
                                edit.bounds.origin.y+pixels.origin.y/height*edit.bounds.size.height,
                                pixels.size.width/width*edit.bounds.size.width,pixels.size.height/height*edit.bounds.size.height);
        id item = [[mosaicItemClass alloc] initWithSuperView:edit centerPoint:NSMakePoint(NSMidX(rect),NSMidY(rect)) size:rect.size];
        if (!item || !bitmap) { CGImageRelease(image); return NO; }
        [(NSObject *)item setSize:rect.size];
        [(NSObject *)item updateControlPoints]; [(NSObject *)item transformDidChange];
        objc_setAssociatedObject(item,&MosaicBitmapKey,bitmap,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [items addObject:item];
    }
    CGImageRelease(image);
    NSUndoManager *undo = [(id)edit undoManager];
    // One click is one undo group, preserving all earlier native annotations.
    [undo beginUndoGrouping];
    for (id item in items) [(id)edit addItem:item];
    [undo setActionName:@"AI马赛克"]; [undo endUndoGrouping];
    [(id)edit unfocus]; [edit setNeedsDisplay:YES];
    return YES;
}

@interface TCWorker : NSObject <NSApplicationDelegate>
@property id manager;
@property id request;
@property NSArray<NSScreen *> *screens;
@property NSMutableDictionary<NSNumber *, NSImage *> *images;
@property NSDictionary<NSNumber *, NSValue *> *screenFrames;
@property NSTimer *pulseTimer;
@property id localKeys;
@property char phase;
@property BOOL terminal;
@property BOOL longTransition;
@property BOOL longActive;
@property BOOL longCompleting;
@property BOOL editorRequested;
@property NSTimeInterval phaseStarted;
@property NSMapTable<NSWindow *, NSPanel *> *pinToolbarPanels;
@property id translationController;
@property NSMapTable<NSWindow *, NSNumber *> *translationMouseState;
@property BOOL translationRecognizing;
@property id mosaicController;
@property NSUUID *mosaicOperation;
@property NSMapTable<NSWindow *, NSNumber *> *mosaicMouseState;
@property NSPanel *mosaicProgress;
- (void)finish:(NSImage *)image save:(BOOL)save;
- (void)ocr:(NSImage *)image;
- (void)end:(int)code;
- (void)setPhaseValue:(char)value;
- (void)showPinToolbarForController:(id)controller;
- (void)hidePinToolbarForController:(id)controller;
- (void)pinSelection:(TCPinToolbarButton *)sender;
- (void)analyzeSelection:(TCPinToolbarButton *)sender;
- (void)translateSelection:(TCPinToolbarButton *)sender;
- (void)translationDone:(NSData *)png action:(int32_t)action;
- (void)mosaicSelection:(TCPinToolbarButton *)sender;
- (void)cancelMosaic:(id)sender;
- (void)completeMosaic:(NSData *)png regions:(NSArray *)regions operation:(NSUUID *)token view:(NSView *)edit error:(NSError *)error;
@end
static TCWorker *worker; // Keep delegate alive, including under ARC -O2.
static void TranslationDone(const uint8_t *bytes, size_t length, int32_t action) {
    NSData *png = bytes && length ? [NSData dataWithBytes:bytes length:length] : nil;
    [worker translationDone:png action:action];
}
static void (*nativeCancel)(id, SEL);
static void (*nativeLongTransition)(id, SEL, id);
static void (*nativeLongDone)(id, SEL, id);
static void (*nativeShowToolbar)(id, SEL);
static void (*nativeHideToolbar)(id, SEL);
static void ShowToolbarHook(id receiver, SEL sel) {
    nativeShowToolbar(receiver, sel);
    [worker showPinToolbarForController:receiver];
}
static void HideToolbarHook(id receiver, SEL sel) {
    [worker hidePinToolbarForController:receiver];
    nativeHideToolbar(receiver, sel);
}
static id ScreenImageHook(id receiver, SEL sel, NSScreen *screen) {
    NSNumber *display = screen.deviceDescription[@"NSScreenNumber"];
    NSImage *image = worker.images[display];
    // A display changed between preflight and asynchronous native window creation.
    // Exit before that constructor can create an empty full-screen window.
    if (!image || !NSEqualRects(screen.frame, [worker.screenFrames[display] rectValue])) TCWorkerFinish(22);
    return image;
}
static void FinishHook(id receiver, SEL sel, id image, BOOL save, BOOL high) {
    dispatch_async(dispatch_get_main_queue(), ^{ [worker finish:image save:save]; });
}
static void CancelHook(id receiver, SEL sel) {
    if (worker.longTransition) { nativeCancel(receiver, sel); return; }
    dispatch_async(dispatch_get_main_queue(), ^{ if (!worker.terminal) [worker end:10]; });
}
static void LongCancelHook(id receiver, SEL sel) {
    dispatch_async(dispatch_get_main_queue(), ^{ if (!worker.terminal) [worker end:10]; });
}
static void OCRHook(id receiver, SEL sel, id image, BOOL high) {
    dispatch_async(dispatch_get_main_queue(), ^{ [worker ocr:image]; });
}
static void LongTransitionHook(id receiver, SEL sel, id notification) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ LongTransitionHook(receiver, sel, notification); }); return; }
    if (!notification || worker.terminal || worker.longActive) return;
    worker.longActive = YES;
    for (NSPanel *panel in worker.pinToolbarPanels.objectEnumerator) [panel orderOut:nil];
    [worker setPhaseValue:'L'];
    worker.longTransition = YES;
    @try { nativeLongTransition(receiver, sel, notification); }
    @finally { worker.longTransition = NO; }
    NSLog(@"long_capture_transition native_cancel_is_not_terminal=1");
}
static void CompleteLongCapture(id receiver, SEL sel, id notification) {
    if (worker.terminal) return;
    worker.longActive = NO;
    // The stream is already stopped and cleared. Native code still reads its
    // assembled resImage and save choice, then invokes our existing FinishHook.
    nativeLongDone(receiver, sel, notification);
    dispatch_async(dispatch_get_main_queue(), ^{ if (!worker.terminal) [worker end:25]; });
}
static void LongDoneHook(id receiver, SEL sel, id notification) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ LongDoneHook(receiver, sel, notification); }); return; }
    if (!notification || worker.terminal || worker.longCompleting) return;
    worker.longCompleting = YES;
    [worker setPhaseValue:'F'];
    SCStream *stream = [receiver stream];
    if (!stream) { CompleteLongCapture(receiver, sel, notification); return; }
    // Native captureDidFinish: waits forever for stopCapture's completion on
    // this main thread. Stop asynchronously first so main-thread callbacks,
    // cancellation and heartbeats can run. Do not publish a partial result if
    // stopping fails; the parent guard still owns emergency process cleanup.
    NSError *removeError = nil;
    if (![stream removeStreamOutput:receiver type:SCStreamOutputTypeScreen error:&removeError])
        NSLog(@"long_remove_output_failed domain=%@ code=%ld", removeError.domain ?: @"unknown", (long)removeError.code);
    [stream stopCaptureWithCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (worker.terminal) return;
            if (error) {
                NSLog(@"long_stop_failed domain=%@ code=%ld", error.domain, (long)error.code);
                [worker end:TC_WORKER_EXIT_LONG_CAPTURE_FAILURE]; return;
            }
            [receiver setStream:nil];
            CompleteLongCapture(receiver, sel, notification);
        });
    }];
}
static void Replace(NSString *name, NSString *selector, IMP hook) {
    method_setImplementation(class_getInstanceMethod(NSClassFromString(name), NSSelectorFromString(selector)), hook);
}
static void HideAllWindows(void) {
    for (NSWindow *window in [NSApp.windows copy]) [window orderOut:nil];
}
static void UncaughtException(NSException *exception) {
    NSLog(@"worker_exception %@", exception.name);
    TCWorkerFinish(26); // Never invoke untrusted private cleanup during unwinding.
}
@implementation TCWorker
- (void)setPhaseValue:(char)value {
    self.phase = value; self.phaseStarted = NSProcessInfo.processInfo.systemUptime;
    TCWorkerPulse(value);
    NSLog(@"worker_phase=%c", value);
}
- (void)end:(int)code {
    self.terminal = YES;
    [self cancelMosaic:nil];
    TCDismissImageTranslation();
    HideAllWindows();
    NSLog(@"worker_terminal=%d", code);
    TCWorkerFinish(code); // OS owns the final destruction of every native window/stream.
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self setPhaseValue:'P'];
    self.pulseTimer = [NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    for (NSString *mode in @[NSRunLoopCommonModes, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode])
        [NSRunLoop.mainRunLoop addTimer:self.pulseTimer forMode:mode];
    self.localKeys = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode == 53) { [worker end:10]; return nil; }
        return event;
    }];
    // No permission prompt from worker. The visible parent owns the normal request UI.
    if (!CGPreflightScreenCaptureAccess()) { [self end:20]; return; }
    NSError *error = nil;
    if (!TCVerifyEngine(&error)) { NSLog(@"engine_error=%@", error); [self end:21]; return; }
    Class managerClass = NSClassFromString(@"JTCaptureManager");
    nativeCancel = (void *)method_getImplementation(class_getInstanceMethod(managerClass, NSSelectorFromString(@"captureDidCancel")));
    nativeLongTransition = (void *)method_getImplementation(class_getInstanceMethod(managerClass, NSSelectorFromString(@"prepareToLongCapture:")));
    nativeLongDone = (void *)method_getImplementation(class_getInstanceMethod(NSClassFromString(@"JTLongCaptureManager"), NSSelectorFromString(@"captureDidFinish:")));
    nativeShowToolbar = (void *)method_getImplementation(class_getInstanceMethod(NSClassFromString(@"JTCaptureViewController"), NSSelectorFromString(@"showToolbar")));
    nativeHideToolbar = (void *)method_getImplementation(class_getInstanceMethod(NSClassFromString(@"JTCaptureViewController"), NSSelectorFromString(@"hideToolbar")));
    self.pinToolbarPanels = [NSMapTable weakToStrongObjectsMapTable];
    Replace(@"JTCaptureViewController", @"showToolbar", (IMP)ShowToolbarHook);
    Replace(@"JTCaptureViewController", @"hideToolbar", (IMP)HideToolbarHook);
    Replace(@"JTCaptureManager", @"captureDidCancel", (IMP)CancelHook);
    Replace(@"JTCaptureManager", @"captureDidFinishWithImage:needSave:isHighResolution:", (IMP)FinishHook);
    Replace(@"JTCaptureManager", @"prepareToOCRWithImage:isHighResolution:", (IMP)OCRHook);
    Replace(@"JTCaptureManager", @"prepareToLongCapture:", (IMP)LongTransitionHook);
    Replace(@"JTLongCaptureManager", @"captureDidCancel", (IMP)LongCancelHook);
    Replace(@"JTLongCaptureManager", @"captureDidFinishWithImage:needSave:isHighResolution:", (IMP)FinishHook);
    Replace(@"JTLongCaptureManager", @"captureDidFinish:", (IMP)LongDoneHook);
    method_setImplementation(class_getClassMethod(NSClassFromString(@"JTCaptureUtilities"), NSSelectorFromString(@"imageOfScreen:")), (IMP)ScreenImageHook);
    self.screens = NSScreen.screens;
    self.images = [NSMutableDictionary new];
    NSMutableDictionary *frames = [NSMutableDictionary new];
    for (NSScreen *screen in self.screens) frames[screen.deviceDescription[@"NSScreenNumber"]] = [NSValue valueWithRect:screen.frame];
    self.screenFrames = frames;
    if (!self.screens.count) { [self end:22]; return; }
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [worker end:22]; }];
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content, NSError *captureError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!content || captureError) { NSLog(@"preflight_error=%@", captureError); [worker end:22]; return; }
            [worker captureScreenAtIndex:0 content:content];
        });
    }];
}
- (void)captureScreenAtIndex:(NSUInteger)index content:(SCShareableContent *)content {
    if (index == self.screens.count) { [self startEditor]; return; }
    NSScreen *screen = self.screens[index];
    NSNumber *number = screen.deviceDescription[@"NSScreenNumber"];
    SCDisplay *display = nil;
    for (SCDisplay *d in content.displays) if (d.displayID == number.unsignedIntValue) { display = d; break; }
    if (!display) { [self end:22]; return; }
    SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
    SCStreamConfiguration *config = [SCStreamConfiguration new];
    // Match the native controller's 1x/2x scale calculation, not display mode pixels.
    CGFloat scale = [NSClassFromString(@"JTCaptureUtilities") isScreenHighResolution:screen] ? 2.0 : 1.0;
    config.width = (size_t)llround(screen.frame.size.width * scale);
    config.height = (size_t)llround(screen.frame.size.height * scale);
    config.showsCursor = NO;
    config.captureResolution = SCCaptureResolutionBest;
    [SCScreenshotManager captureImageWithFilter:filter configuration:config completionHandler:^(CGImageRef image, NSError *error) {
        CGImageRef retained = image ? CGImageRetain(image) : NULL;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Do not inspect luminance: an entirely black desktop is a valid capture.
            BOOL valid = !error && retained && CGImageGetWidth(retained) == config.width && CGImageGetHeight(retained) == config.height && CGImageGetDataProvider(retained);
            if (valid) worker.images[number] = [[NSImage alloc] initWithCGImage:retained size:screen.frame.size];
            if (retained) CGImageRelease(retained);
            if (!valid) { NSLog(@"screen_image_failed display=%@ error=%@", number, error); [worker end:22]; return; }
            [worker captureScreenAtIndex:index + 1 content:content];
        });
    }];
}
- (void)startEditor {
    if (NSScreen.screens.count != self.screens.count) { [self end:22]; return; }
    id settings = [NSClassFromString(@"JTCaptureSetting") sharedInstance];
    [settings setRunAlone:YES]; [settings setHighResolution:YES]; [settings setPlaySound:NO];
    self.manager = [NSClassFromString(@"JTCaptureManager") sharedInstance];
    self.request = [NSClassFromString(@"JTCaptureRequest") new];
    [self.request setShowSwitch:NO]; [self.request setNeedSelectSavePath:YES];
    [NSApp activateIgnoringOtherApps:YES];
    self.editorRequested = YES;
    if (![self.manager startCaptureByRequest:self.request]) [self end:23];
    // The native start queues window construction asynchronously; tick verifies it.
}
- (void)tick:(NSTimer *)timer {
    TCWorkerPulse(self.phase);
    NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - self.phaseStarted;
    if (self.phase == 'P' && self.editorRequested) {
        NSArray *controllers = [self.manager windowControllers];
        NSUInteger visible = 0;
        for (id c in controllers) if ([c window].visible && [c screenImage]) visible++;
        if (visible == self.screens.count) [self setPhaseValue:'E'];
    }
    if (self.phase == 'L' && elapsed > 5) {
        id longManager = [NSClassFromString(@"JTLongCaptureManager") sharedInstance];
        if (![longManager isCapturing] || ![longManager window].visible) [self end:25];
    }
    // Bound background processing, but never time out a responsive editor/save panel.
    if ((self.phase == 'O' || self.phase == 'A' || self.phase == 'M' || self.phase == 'F' || self.translationRecognizing) && elapsed > 120) [self end:27];
}
- (BOOL)beginResult:(NSImage *)image phase:(char)phase {
    if (self.terminal) return NO;
    self.terminal = YES; // Suppress stale native cancel/finish callbacks during save/OCR.
    HideAllWindows();
    [self setPhaseValue:phase];
    if (![image isKindOfClass:NSImage.class] || image.size.width <= 0 || image.size.height <= 0) { [self end:24]; return NO; }
    if (self.longActive) {
        SCStream *stream = [[NSClassFromString(@"JTLongCaptureManager") sharedInstance] stream];
        [stream stopCaptureWithCompletionHandler:^(NSError *error) { if (error) NSLog(@"long_stop=%@", error); }];
    }
    return YES;
}
- (void)positionPinToolbar:(NSPanel *)panel besideWindow:(NSWindow *)toolbar {
    NSRect frame = toolbar.frame;
    NSRect screen = (toolbar.screen ?: NSScreen.mainScreen).frame;
    CGFloat width = panel.frame.size.width, height = panel.frame.size.height;
    CGFloat x = NSMaxX(frame) + 3;
    if (x + width > NSMaxX(screen)) x = NSMinX(frame) - width - 3;
    CGFloat y = NSMidY(frame) - height / 2;
    x = MIN(MAX(x, NSMinX(screen)), NSMaxX(screen) - width);
    y = MIN(MAX(y, NSMinY(screen)), NSMaxY(screen) - height);
    [panel setFrameOrigin:NSMakePoint(x, y)];
}
- (void)toolbarFrameChanged:(NSNotification *)notification {
    NSWindow *toolbar = notification.object;
    NSPanel *panel = [self.pinToolbarPanels objectForKey:toolbar];
    if (panel) [self positionPinToolbar:panel besideWindow:toolbar];
}
- (void)showPinToolbarForController:(id)controller {
    if (self.terminal || self.longActive || self.translationController || self.mosaicController) return;
    NSWindowController *windowController = [controller toolbarWindowController];
    if (![windowController isKindOfClass:NSWindowController.class]) return;
    NSWindow *toolbar = windowController.window;
    if (!toolbar.visible) return;
    NSPanel *panel = [self.pinToolbarPanels objectForKey:toolbar];
    if (!panel) {
        panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 284, 30)
                                          styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                            backing:NSBackingStoreBuffered defer:NO];
        panel.releasedWhenClosed = NO;
        panel.hidesOnDeactivate = NO;
        panel.backgroundColor = NSColor.controlBackgroundColor;
        panel.level = toolbar.level;
        panel.collectionBehavior = toolbar.collectionBehavior;
        NSArray *titles = @[@"置顶", @"二维码", @"AI马赛克", @"翻译"];
        NSArray *tips = @[@"将选区和标注置顶到桌面，保留剪贴板",
                         @"本机识别二维码/条码，只显示结果，不打开链接",
                         @"本机识别后直接在选区添加马赛克，可继续标注和撤销",
                         @"译文直接显示在截图中的原文字位置，支持切换原图、复制和保存译图（macOS 15+）"];
        for (NSInteger i = 0; i < 4; i++) {
            TCPinToolbarButton *button = [[TCPinToolbarButton alloc] initWithFrame:NSMakeRect(i ? 50 + (i - 1) * 78 : 0, 0, i ? 78 : 50, 30)];
            button.title = titles[i]; button.toolTip = tips[i];
            button.accessibilityLabel = titles[i];
            button.bezelStyle = NSBezelStyleRounded;
            button.target = self;
            button.action = i == 3 ? @selector(translateSelection:) : (i ? @selector(analyzeSelection:) : @selector(pinSelection:));
            if (i == 3) { if (@available(macOS 15.0, *)) {} else button.enabled = NO; }
            button.tag = i;
            button.captureController = controller;
            [panel.contentView addSubview:button];
        }
        [self.pinToolbarPanels setObject:panel forKey:toolbar];
        [toolbar addChildWindow:panel ordered:NSWindowAbove];
        for (NSString *name in @[NSWindowDidMoveNotification, NSWindowDidResizeNotification])
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(toolbarFrameChanged:) name:name object:toolbar];
    }
    [self positionPinToolbar:panel besideWindow:toolbar];
    [panel orderFront:nil];
}
- (void)hidePinToolbarForController:(id)controller {
    NSWindowController *windowController = [controller toolbarWindowController];
    if ([windowController isKindOfClass:NSWindowController.class])
        [[self.pinToolbarPanels objectForKey:windowController.window] orderOut:nil];
}
- (void)pinSelection:(TCPinToolbarButton *)sender {
    id controller = sender.captureController;
    if (self.terminal || self.longActive || ![controller isKindOfClass:NSClassFromString(@"JTCaptureViewController")]) return;
    NSImage *image = [controller generateCapturedImage];
    if (![self beginResult:image phase:'F']) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSData *tiff = image.TIFFRepresentation;
            NSBitmapImageRep *rep = tiff ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!png.length) { [worker end:24]; return; }
                // Private result channel: pin never writes the user's general clipboard.
                NSPasteboard *board = [NSPasteboard pasteboardWithName:[NSString stringWithFormat:@"local.yichen.TencentCapture.pin-%d", getpid()]];
                [board clearContents];
                BOOL ok = [board setData:png forType:@"local.yichen.TencentCapture.pin-png"];
                [worker end:ok ? TC_WORKER_EXIT_PIN_SUCCESS : TC_WORKER_EXIT_ENCODING_FAILURE];
            });
        }
    });
}
- (void)analyzeSelection:(TCPinToolbarButton *)sender {
    if (sender.tag == 2) { [self mosaicSelection:sender]; return; }
    id controller = sender.captureController;
    if (self.terminal || self.longActive || ![controller isKindOfClass:NSClassFromString(@"JTCaptureViewController")]) return;
    NSImage *image = [controller generateCapturedImage];
    if (![self beginResult:image phase:'A']) return;
    BOOL codes = sender.tag == 1;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;
            NSData *data = image.TIFFRepresentation;
            NSArray *values = codes ? TCRecognizeImageCodes(data, &error) : nil;
            NSUInteger count = 0;
            NSData *redacted = codes ? nil : TCRedactImage(data, &count, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if ((codes && !values) || (!codes && !redacted.length)) {
                    NSLog(@"image_analysis_failed domain=%@ code=%ld", error.domain ?: @"encoding", (long)error.code);
                    [worker end:codes ? TC_WORKER_EXIT_CODE_FAILURE : TC_WORKER_EXIT_REDACTION_FAILURE];
                    return;
                }
                if (codes && !values.count) { [worker end:TC_WORKER_EXIT_CODE_EMPTY]; return; }
                NSPasteboard *board = [NSPasteboard pasteboardWithName:[NSString stringWithFormat:@"local.yichen.TencentCapture.analysis-%d", getpid()]];
                [board clearContents];
                BOOL written;
                if (codes) written = [board setString:[values componentsJoinedByString:@"\n\n"] forType:@"local.yichen.TencentCapture.code-text"];
                else written = [board setData:redacted forType:@"local.yichen.TencentCapture.redacted-png"] &&
                               [board setString:@(count).stringValue forType:@"local.yichen.TencentCapture.redaction-count"];
                NSLog(@"image_analysis_completed mode=%@ count=%lu", codes ? @"codes" : @"redaction", (unsigned long)(codes ? values.count : count));
                [worker end:written ? (codes ? TC_WORKER_EXIT_CODE_SUCCESS : TC_WORKER_EXIT_REDACTION_SUCCESS) : TC_WORKER_EXIT_ENCODING_FAILURE];
            });
        }
    });
}
- (void)cancelMosaic:(id)sender {
    if (!self.mosaicController) return;
    id controller = self.mosaicController;
    self.mosaicOperation = nil; self.mosaicController = nil;
    for (NSWindow *window in self.mosaicMouseState.keyEnumerator)
        window.ignoresMouseEvents = [[self.mosaicMouseState objectForKey:window] boolValue];
    self.mosaicMouseState = nil;
    [self.mosaicProgress.parentWindow removeChildWindow:self.mosaicProgress];
    [self.mosaicProgress close]; self.mosaicProgress = nil;
    if (!self.terminal) { [self setPhaseValue:'E']; [controller showToolbar]; }
}
- (void)mosaicSelection:(TCPinToolbarButton *)sender {
    id controller = sender.captureController;
    if (self.terminal || self.longActive || self.translationController || self.mosaicController ||
        ![controller isKindOfClass:NSClassFromString(@"JTCaptureViewController")]) return;
    [controller editDidBegin:nil];
    NSView *edit = [[controller editViewController] editView];
    if (![edit isKindOfClass:NSClassFromString(@"JTEditView")]) return;
    NSWindow *owner = edit.window;
    if (!owner) return;
    [(id)edit unfocus];
    NSImage *image = [controller generateCapturedImage];
    if (![image isKindOfClass:NSImage.class] || NSIsEmptyRect(edit.bounds)) return;
    self.mosaicController = controller; self.mosaicOperation = [NSUUID UUID];
    NSUUID *token = self.mosaicOperation;
    self.mosaicMouseState = [NSMapTable weakToStrongObjectsMapTable];
    for (id c in [self.manager windowControllers]) {
        NSWindow *window = [c window]; if (!window) continue;
        [self.mosaicMouseState setObject:@(window.ignoresMouseEvents) forKey:window];
        window.ignoresMouseEvents = YES;
    }
    [controller hideToolbar]; [self setPhaseValue:'M'];
    NSRect screen = (owner.screen ?: NSScreen.mainScreen).visibleFrame;
    NSRect area = [owner convertRectToScreen:[edit convertRect:edit.bounds toView:nil]];
    CGFloat x = MAX(NSMinX(screen),MIN(NSMinX(area),NSMaxX(screen)-300));
    CGFloat y = NSMinY(area)-60;
    if (y < NSMinY(screen)) y = MIN(NSMaxY(area)+4,NSMaxY(screen)-56);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(x,y,300,56)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    panel.releasedWhenClosed = NO; panel.hidesOnDeactivate = NO;
    panel.level = owner.level; panel.collectionBehavior = owner.collectionBehavior;
    panel.backgroundColor = NSColor.windowBackgroundColor;
    NSProgressIndicator *progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(10,18,20,20)];
    progress.style = NSProgressIndicatorStyleSpinning; [progress startAnimation:nil]; [panel.contentView addSubview:progress];
    NSTextField *label = [NSTextField labelWithString:@"正在识别并添加马赛克…"];
    label.frame = NSMakeRect(40,18,180,20); [panel.contentView addSubview:label];
    NSButton *cancel = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancelMosaic:)];
    cancel.frame = NSMakeRect(230,13,60,30); [panel.contentView addSubview:cancel];
    self.mosaicProgress = panel; [owner addChildWindow:panel ordered:NSWindowAbove]; [panel orderFront:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {
            NSError *error = nil;
            NSData *data = image.TIFFRepresentation;
            NSArray *regions = TCImageMosaicRegions(data,&error);
            NSData *png = regions.count ? TCPixelateImageRegions(data,regions,&error) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [worker completeMosaic:png regions:regions operation:token view:edit error:error];
            });
        }
    });
}
- (void)completeMosaic:(NSData *)png regions:(NSArray *)regions operation:(NSUUID *)token view:(NSView *)edit error:(NSError *)error {
    if (self.terminal || ![self.mosaicOperation isEqual:token]) return;
    NSError *failure = error;
    BOOL applied = regions && (!regions.count || (png.length && ApplyMosaicItems(edit,png,regions,&failure)));
    [self cancelMosaic:nil];
    if (!applied || !regions.count) {
        NSAlert *alert = [NSAlert new]; alert.messageText = @"AI马赛克";
        alert.informativeText = applied ? @"未识别到敏感内容，可继续使用马赛克工具手动遮挡。" :
            (failure.localizedDescription ?: @"无法添加马赛克，请重试或使用手动马赛克工具。");
        [alert runModal];
    } else NSLog(@"editor_mosaic_applied regions=%lu undo_group=1",(unsigned long)regions.count);
}
- (void)translateSelection:(TCPinToolbarButton *)sender {
    id controller = sender.captureController;
    if (self.terminal || self.longActive || self.translationController || self.mosaicController ||
        ![controller isKindOfClass:NSClassFromString(@"JTCaptureViewController")]) return;
    NSView *capture = [controller captureView];
    if (![capture isKindOfClass:NSClassFromString(@"JTCaptureView")]) return;
    NSView *view = [(NSViewController *)controller view];
    NSRect selectedInCapture = [(id)capture selectedRect];
    NSRect selected = [view backingAlignedRect:[capture convertRect:selectedInCapture toView:view]
                                       options:NSAlignAllEdgesInward];
    NSWindow *owner = view.window;
    NSRect frame = [owner convertRectToScreen:[view convertRect:selected toView:nil]];
    NSImage *image = [controller generateCapturedImage];
    if (!owner || NSIsEmptyRect(frame) || ![image isKindOfClass:NSImage.class]) return;
    self.translationController = controller;
    self.translationMouseState = [NSMapTable weakToStrongObjectsMapTable];
    for (id c in [self.manager windowControllers]) {
        NSWindow *window = [c window]; if (!window) continue;
        [self.translationMouseState setObject:@(window.ignoresMouseEvents) forKey:window];
        window.ignoresMouseEvents = YES;
    }
    [controller hideToolbar];
    self.translationRecognizing = YES;
    [self setPhaseValue:'T'];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (worker.terminal) return;
            worker.translationRecognizing = NO;
            [worker setPhaseValue:'T'];
            if (!png.length) {
                NSAlert *alert = [NSAlert new]; alert.messageText = @"无法读取截图";
                alert.informativeText = @"请返回编辑后重新框选。";
                [alert runModal]; [worker translationDone:nil action:0]; return;
            }
            TCShowImageTranslation((__bridge const void *)png, NULL,
                (__bridge const void *)owner, frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, TranslationDone);
        });
    });
}
- (void)translationDone:(NSData *)png action:(int32_t)action {
    id controller = self.translationController; self.translationController = nil;
    for (NSWindow *window in self.translationMouseState.keyEnumerator)
        window.ignoresMouseEvents = [[self.translationMouseState objectForKey:window] boolValue];
    self.translationMouseState = nil;
    if (self.terminal) return;
    if (action == 0) { [self setPhaseValue:'E']; [controller showToolbar]; return; }
    NSImage *image = png.length ? [[NSImage alloc] initWithData:png] : nil;
    [self finish:image save:action == 2];
}
- (void)finish:(NSImage *)image save:(BOOL)save {
    if (![self beginResult:image phase:'F']) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSData *tiff = image.TIFFRepresentation;
            NSBitmapImageRep *rep = tiff ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!png.length || !tiff.length) { [worker end:24]; return; }
                if (save) { [worker savePNG:png]; return; }
                NSPasteboardItem *item = [NSPasteboardItem new];
                [item setData:png forType:NSPasteboardTypePNG]; [item setData:tiff forType:NSPasteboardTypeTIFF];
                [item setData:png forType:@"local.yichen.TencentCapture.captured-png"];
                NSPasteboard *board = NSPasteboard.generalPasteboard;
                [board clearContents]; BOOL ok = [board writeObjects:@[item]];
                [worker end:ok ? 0 : 24];
            });
        }
    });
}
- (void)savePNG:(NSData *)png {
    [self setPhaseValue:'S'];
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePNG];
    panel.nameFieldStringValue = @"截图.png";
    [NSApp activateIgnoringOtherApps:YES];
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) { [worker end:11]; return; }
        [worker setPhaseValue:'F'];
        NSURL *url = panel.URL;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil; BOOL ok = [png writeToURL:url options:NSDataWritingAtomic error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!ok) NSLog(@"save_failed=%@", error);
                [worker end:ok ? 1 : 28];
            });
        });
    }];
}
- (void)ocr:(NSImage *)image {
    if (![self beginResult:image phase:'O']) return;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    NSLog(@"ocr_started width=%.0f height=%.0f", image.size.width, image.size.height);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSData *data = image.TIFFRepresentation;
            NSError *error = nil;
            NSString *text = TCRecognizeImageText(data, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"ocr_completed elapsed=%.3f characters=%lu error_domain=%@ error_code=%ld", NSProcessInfo.processInfo.systemUptime - started, (unsigned long)text.length, error.domain ?: @"none", (long)error.code);
                if (!text.length) { [worker end:text ? 12 : 29]; return; }
                NSPasteboardItem *item = [NSPasteboardItem new];
                [item setString:text forType:NSPasteboardTypeString];
                [item setString:text forType:@"local.yichen.TencentCapture.ocr-text"];
                NSPasteboard *board = NSPasteboard.generalPasteboard;
                [board clearContents]; BOOL written = [board writeObjects:@[item]];
                [worker end:written ? 2 : 24];
            });
        }
    });
}
@end
int TCRunCaptureWorker(void) {
    // Guard starts before loading AppKit/engine or making any windows.
    if (TCWorkerGuardStart() != 0) return 30;
    NSSetUncaughtExceptionHandler(UncaughtException);
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    worker = [TCWorker new]; NSApp.delegate = worker;
    [NSApp run];
    TCWorkerFinish(10);
    return 10;
}

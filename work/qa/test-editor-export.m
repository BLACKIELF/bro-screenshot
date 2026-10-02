#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "../TCWorker.m"
#include <assert.h>

// Actual native export methods on offscreen synthetic views. AppKit may
// initialize NSApplication while caching views; no windows, activation,
// event loop, screen access, save panel, clipboard or input events are used.
void TCShowImageTranslation(const void *image, const void *regions, const void *owner,
    double x,double y,double width,double height,TCImageTranslationCompletion completion) { abort(); }
void TCDismissImageTranslation(void) { }
@interface NSObject (TCExportTest)
- (id)initWithFrame:(NSRect)frame;
- (void)setBackgroundImage:(NSImage *)image;
- (NSImage *)imageEdited;
- (void)setEditViewController:(id)controller;
- (void)setNeedScreenCapture:(BOOL)value;
- (void)setDelegate:(id)delegate;
- (void)captureDidFinish:(NSNotification *)notification;
- (BOOL)undo;
- (BOOL)redo;
- (NSArray *)itemArray;
- (void)setNormalStrokeColor:(NSColor *)color;
- (void)setNormalStrokeWidth:(CGFloat)width;
@end
@interface TCExportSink : NSObject
@property NSImage *image;
@property BOOL saved;
@property NSUInteger calls;
@end
@implementation TCExportSink
- (void)captureDidFinishWithImage:(NSImage *)image needSave:(BOOL)save {
    self.image=image;self.saved=save;self.calls++;
}
@end
static void CheckABI(NSString *name,NSString *selector,NSString *encoding) {
    Method method=class_getInstanceMethod(NSClassFromString(name),NSSelectorFromString(selector));
    assert(method && !strcmp(method_getTypeEncoding(method),encoding.UTF8String));
}
static NSBitmapImageRep *Pixels(NSImage *image) {
    assert(image);
    NSBitmapImageRep *rep=[NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];assert(rep);
    return rep;
}
static void Pixel(NSBitmapImageRep *rep,CGFloat x,CGFloat y,double r,double g,double b) {
    NSColor *color=[rep colorAtX:(NSInteger)(x*rep.pixelsWide) y:(NSInteger)(y*rep.pixelsHigh)];
    if (!(fabs(color.redComponent-r)<.04 && fabs(color.greenComponent-g)<.04 && fabs(color.blueComponent-b)<.04)) {
        fprintf(stderr,"Export pixel %.3f,%.3f actual %.3f %.3f %.3f expected %.3f %.3f %.3f\n",x,y,color.redComponent,color.greenComponent,color.blueComponent,r,g,b);abort();
    }
}
static void Matches(NSBitmapImageRep *before,NSBitmapImageRep *after,NSArray *regions) {
    assert(before.pixelsWide==after.pixelsWide && before.pixelsHigh==after.pixelsHigh);
    for (NSInteger y=0;y<before.pixelsHigh;y++) for (NSInteger x=0;x<before.pixelsWide;x++) {
        NSPoint point=NSMakePoint((x+.5)/before.pixelsWide,1-(y+.5)/before.pixelsHigh);
        BOOL replaced=NO;
        for (NSDictionary *region in regions) {
            NSRect rect=NSMakeRect([region[@"x"] doubleValue],[region[@"y"] doubleValue],
                                  [region[@"width"] doubleValue],[region[@"height"] doubleValue]);
            if (NSPointInRect(point,rect)) { replaced=YES;break; }
        }
        if (replaced) continue;
        NSColor *a=[[before colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        NSColor *b=[[after colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        if (fabs(a.redComponent-b.redComponent)>1./255 || fabs(a.greenComponent-b.greenComponent)>1./255 ||
            fabs(a.blueComponent-b.blueComponent)>1./255 || fabs(a.alphaComponent-b.alphaComponent)>1./255) {
            fprintf(stderr,"Native export changed an unselected pixel %ld,%ld\n",(long)x,(long)y);abort();
        }
    }
}
static void AddAnnotation(NSView *view,CGFloat scale,NSPoint point) {
    NSSize size=NSMakeSize(100/scale,20/scale);
    id item=[[NSClassFromString(@"JTRoundRectItem") alloc] initWithSuperView:view
        centerPoint:NSMakePoint(point.x/scale,point.y/scale) size:size];
    [item setSize:size];[item updateControlPoints];[item transformDidChange];
    [item setNormalStrokeColor:NSColor.blackColor];[item setNormalStrokeWidth:2/scale];
    NSUndoManager *undo=[(id)view undoManager];
    [undo beginUndoGrouping];[(id)view addItem:item];[undo endUndoGrouping];
}
int main(void) {
    @autoreleasepool {
        NSError *error=nil;
        assert([[NSBundle bundleWithPath:@"/Applications/bro截图.app/Contents/Frameworks/JietuFramework.framework"] loadAndReturnError:&error]);
        for (NSString *name in RequiredABI()) for (NSString *selector in RequiredABI()[name]) {
            BOOL meta=[selector hasPrefix:@"+"];SEL sel=NSSelectorFromString(meta ? [selector substringFromIndex:1] : selector);
            Method method=meta ? class_getClassMethod(NSClassFromString(name),sel) : class_getInstanceMethod(NSClassFromString(name),sel);
            assert(method && !strcmp(method_getTypeEncoding(method),[RequiredABI()[name][selector] UTF8String]));
        }
        CheckABI(@"JTEditViewController",@"initWithFrame:",@"@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16");
        CheckABI(@"JTEditViewController",@"setBackgroundImage:",@"v24@0:8@16");
        CheckABI(@"JTEditViewController",@"imageEdited",@"@16@0:8");
        CheckABI(@"JTCaptureViewController",@"setEditViewController:",@"v24@0:8@16");
        CheckABI(@"JTCaptureViewController",@"setNeedScreenCapture:",@"v20@0:8B16");
        CheckABI(@"JTCaptureViewController",@"setDelegate:",@"v24@0:8@16");
        CheckABI(@"JTCaptureViewController",@"captureDidFinish:",@"v24@0:8@16");
        CheckABI(@"JTRoundRectItem",@"setNormalStrokeColor:",@"v24@0:8@16");
        CheckABI(@"JTRoundRectItem",@"setNormalStrokeWidth:",@"v24@0:8d16");
        NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:600 pixelsHigh:300 bitsPerSample:8
            samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [NSColor.blueColor setFill];NSRectFill(NSMakeRect(0,0,600,150));
        [NSColor.greenColor setFill];NSRectFill(NSMakeRect(0,150,600,150));[NSGraphicsContext restoreGraphicsState];
        NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSArray *regions=@[@{@"x":@.1,@"y":@.2,@"width":@.2,@"height":@.1},@{@"x":@.6,@"y":@.7,@"width":@.2,@"height":@.1}];
        NSBitmapImageRep *patch=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:600 pixelsHigh:300 bitsPerSample:8
            samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:patch];
        [NSColor.blueColor setFill];NSRectFill(NSMakeRect(0,0,600,150));
        [NSColor.greenColor setFill];NSRectFill(NSMakeRect(0,150,600,150));
        [NSColor.redColor setFill];NSRectFill(NSMakeRect(60,60,120,30));
        [NSColor.yellowColor setFill];NSRectFill(NSMakeRect(360,210,120,30));[NSGraphicsContext restoreGraphicsState];
        NSData *patched=[patch representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        Pixel([NSBitmapImageRep imageRepWithData:patched],.15,.75,1,0,0);
        Pixel([NSBitmapImageRep imageRepWithData:patched],.7,.25,1,1,0);
        for (CGFloat scale=1;scale<=2;scale++) {
            NSRect frame=NSMakeRect(0,0,600/scale,300/scale);
            NSViewController *edit=[[NSClassFromString(@"JTEditViewController") alloc] initWithFrame:frame];
            NSImage *background=[[NSImage alloc] initWithData:png];background.size=frame.size;
            [(id)edit setBackgroundImage:background];NSView *view=[(id)edit editView];
            NSUndoManager *undo=[(id)view undoManager];undo.groupsByEvent=NO;
            NSViewController *capture=[[NSClassFromString(@"JTCaptureViewController") alloc] initWithNibName:nil bundle:nil];
            capture.view=[[NSView alloc] initWithFrame:frame];[capture.view addSubview:edit.view];
            [(id)capture setEditViewController:edit];[(id)capture setNeedScreenCapture:YES];
            TCExportSink *sink=[TCExportSink new];[(NSObject *)capture setDelegate:sink];
            AddAnnotation(view,scale,NSMakePoint(120,75));
            NSBitmapImageRep *baseline=Pixels([(id)edit imageEdited]);
            assert(ApplyMosaicItems(view,patched,regions,&error));
            assert(!NSApp.windows.count && !NSApp.isActive && !edit.view.window && !capture.view.window);
            NSImage *export=[(id)edit imageEdited];assert(NSEqualSizes(export.size,frame.size));
            NSBitmapImageRep *result=Pixels(export);
            Pixel(result,.15,.75,1,0,0);Pixel(result,.7,.25,1,1,0);
            Pixel(result,.2,215./300,0,0,0);
            Matches(baseline,result,regions);
            AddAnnotation(view,scale,NSMakePoint(420,225));
            NSBitmapImageRep *combined=Pixels([(id)edit imageEdited]);
            Pixel(combined,.7,65./300,0,0,0);
            Matches(baseline,combined,regions);
            for (NSUInteger save=0;save<2;save++) {
                [(id)capture captureDidFinish:[NSNotification notificationWithName:@"captureDidFinish" object:@(save)]];
                assert(sink.calls==save+1 && sink.saved==(BOOL)save && NSEqualSizes(sink.image.size,frame.size));
                Pixel(Pixels(sink.image),.15,.75,1,0,0);Pixel(Pixels(sink.image),.7,.25,1,1,0);
                Pixel(Pixels(sink.image),.2,215./300,0,0,0);Pixel(Pixels(sink.image),.7,65./300,0,0,0);
                NSBitmapImageRep *roundTrip=[NSBitmapImageRep imageRepWithData:[Pixels(sink.image) representationUsingType:NSBitmapImageFileTypePNG properties:@{}]];
                Pixel(roundTrip,.15,.75,1,0,0);
                Matches(combined,roundTrip,@[]);
            }
            assert([(NSObject *)view undo]);Matches(result,Pixels([(id)edit imageEdited]),@[]);
            assert([(NSObject *)view undo]);Matches(baseline,Pixels([(id)edit imageEdited]),@[]);
            assert([(NSObject *)view redo]);Matches(result,Pixels([(id)edit imageEdited]),@[]);
            assert([(NSObject *)view redo]);Matches(combined,Pixels([(id)edit imageEdited]),@[]);
        }
        assert(!NSApp.windows.count && !NSApp.isActive);
        puts("PASS native editor export: actual imageEdited and captureDidFinish copy/save callbacks, patches and previous/later annotations, every exterior pixel retained at 1x/2x logical scale, PNG round trip, exact group and annotation undo/redo exports; no windows, activation, event loop, screen access or clipboard.");
    }
    return 0;
}

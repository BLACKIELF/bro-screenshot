#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <CoreText/CoreText.h>
#import "../TCWorker.m"
#include <assert.h>

// Offscreen native objects only: no NSApplication, windows, capture or clipboard.
void TCShowImageTranslation(const void *image, const void *regions, const void *owner,
    double x,double y,double width,double height,TCImageTranslationCompletion completion) { abort(); }
void TCDismissImageTranslation(void) { }
@interface NSObject (TCMosaicTest)
- (NSArray *)itemArray;
- (BOOL)undo;
- (BOOL)redo;
- (void)drawGraph;
- (void)setCenter:(NSPoint)point;
- (void)setSize:(NSSize)size;
- (void)setNormalStrokeColor:(NSColor *)color;
- (void)setNormalStrokeWidth:(CGFloat)width;
- (NSArray *)pointsArray;
@end
@interface TCTestMosaicController : NSObject
@property NSUInteger shows;
@end
@implementation TCTestMosaicController
- (void)showToolbar { self.shows++; }
@end
@interface TCTestMosaicWorker : TCWorker
@end
@implementation TCTestMosaicWorker
- (void)setPhaseValue:(char)phase { self.phase=phase; }
@end
static NSBitmapImageRep *Render(NSView *view) {
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,600,300,8,0,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color);assert(context);
    [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
    CGContextSetShouldAntialias(context,false);
    CGContextScaleCTM(context,600/view.bounds.size.width,300/view.bounds.size.height);
    [view drawRect:view.bounds];[NSGraphicsContext restoreGraphicsState];
    CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:image];CGImageRelease(image);return rep;
}
static void Pixel(NSBitmapImageRep *rep,NSInteger x,NSInteger y,double r,double g,double b,double a) {
    NSColor *color=[rep colorAtX:x y:y];
    if (!(fabs(color.redComponent-r)<.03 && fabs(color.greenComponent-g)<.03 && fabs(color.blueComponent-b)<.03 && fabs(color.alphaComponent-a)<.03)) {
        fprintf(stderr,"Pixel %ld,%ld actual %.3f %.3f %.3f %.3f expected %.3f %.3f %.3f %.3f\n",(long)x,(long)y,color.redComponent,color.greenComponent,color.blueComponent,color.alphaComponent,r,g,b,a);abort();
    }
}
static NSData *SensitiveFixture(void) {
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,1200,340,8,0,color,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color);assert(context);
    CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,CGRectMake(0,0,1200,340));
    CTFontRef font=CTFontCreateWithName(CFSTR("Helvetica"),42,NULL);
    NSArray *lines=@[@"HELLO 2026 ORDER ABC123",@"Phone 13900000000",@"Email qa+demo@example.test",@"Card 6222021234567890"];
    for (NSUInteger i=0;i<lines.count;i++) {
        NSAttributedString *text=[[NSAttributedString alloc] initWithString:lines[i] attributes:@{(__bridge NSString *)kCTFontAttributeName:(__bridge id)font}];
        CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
        CGContextSetTextPosition(context,36,270-66*i);CTLineDraw(line,context);CFRelease(line);
    }
    CGImageRef image=CGBitmapContextCreateImage(context);
    NSData *png=[[[NSBitmapImageRep alloc] initWithCGImage:image] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    CGImageRelease(image);CGContextRelease(context);CFRelease(font);return png;
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
        NSBitmapImageRep *image=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:600 pixelsHigh:300 bitsPerSample:8 samplesPerPixel:4
             hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:image];
        [NSColor.blueColor setFill];NSRectFill(NSMakeRect(0,0,600,150));
        [NSColor.greenColor setFill];NSRectFill(NSMakeRect(0,150,600,150));[NSGraphicsContext restoreGraphicsState];
        NSData *png=[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSArray *regions=@[@{@"x":@.1,@"y":@.2,@"width":@.2,@"height":@.1},@{@"x":@.6,@"y":@.7,@"width":@.2,@"height":@.1}];
        for (CGFloat scale=1;scale<=2;scale++) {
            NSView *view=[[NSClassFromString(@"JTEditView") alloc] initWithFrame:NSMakeRect(0,0,600/scale,300/scale)];
            NSUndoManager *undo=[(id)view undoManager];undo.groupsByEvent=NO;
            id prior=[[NSClassFromString(@"JTRoundRectItem") alloc] initWithSuperView:view centerPoint:NSMakePoint(120/scale,75/scale) size:NSMakeSize(100/scale,20/scale)];
            [prior setSize:NSMakeSize(100/scale,20/scale)];
            [prior updateControlPoints];[prior transformDidChange];
            [prior setNormalStrokeColor:NSColor.redColor];[prior setNormalStrokeWidth:2/scale];
            [undo beginUndoGrouping];[(id)view addItem:prior];[undo endUndoGrouping];
            assert(ApplyMosaicItems(view,png,regions,&error));
            NSArray *items=[(id)view itemArray];assert(items.count==3 && items.lastObject==prior);
            assert([items[0] isKindOfClass:mosaicItemClass] && [items[1] isKindOfClass:mosaicItemClass]);
            NSBitmapImageRep *render=Render(view);
            Pixel(render,80,225,0,0,1,1);Pixel(render,420,75,0,1,0,1);Pixel(render,20,225,0,0,0,0);
            // Existing red annotation is drawn above the automatic mosaic.
            Pixel(render,120,215,1,0,0,1);
            id item=items[0]; id copy=[item copy];assert(objc_getAssociatedObject(copy,&MosaicBitmapKey)==objc_getAssociatedObject(item,&MosaicBitmapKey));
            assert([(id)item pointsArray].count==8 && NSEqualSizes([(NSObject *)item size],NSMakeSize(120/scale,30/scale)));
            NSPoint original=[(NSObject *)copy center];[copy setCenter:NSMakePoint(original.x+10,original.y+10)];[copy setSize:NSMakeSize(30,20)];
            assert(!NSEqualPoints([(NSObject *)copy center],[(NSObject *)item center]));
            assert([(NSObject *)view undo]);assert([(id)view itemArray].count==1 && [(id)view itemArray].lastObject==prior);
            assert([(NSObject *)view redo]);assert([(id)view itemArray].count==3);Pixel(Render(view),80,225,0,0,1,1);
            // An ordinary annotation added afterwards remains on top and can
            // be undone independently before undoing the entire AI operation.
            id later=[[NSClassFromString(@"JTRoundRectItem") alloc] initWithSuperView:view centerPoint:NSMakePoint(420/scale,225/scale) size:NSMakeSize(100/scale,20/scale)];
            [later setSize:NSMakeSize(100/scale,20/scale)];[later updateControlPoints];[later transformDidChange];
            [later setNormalStrokeColor:NSColor.redColor];[later setNormalStrokeWidth:2/scale];
            [undo beginUndoGrouping];[(id)view addItem:later];[undo endUndoGrouping];
            Pixel(Render(view),420,65,1,0,0,1);assert([(id)view itemArray].lastObject==later);
            assert([(NSObject *)view undo]);assert([(id)view itemArray].count==3);
            assert([(NSObject *)view undo]);assert([(id)view itemArray].count==1);
            assert([(NSObject *)view redo]);assert([(NSObject *)view redo]);assert([(id)view itemArray].count==4);
        }
        NSView *view=[[NSClassFromString(@"JTEditView") alloc] initWithFrame:NSMakeRect(0,0,600,300)];
        TCTestMosaicController *controller=[TCTestMosaicController new];TCTestMosaicWorker *test=[TCTestMosaicWorker new];
        NSUUID *old=[NSUUID UUID];test.mosaicController=controller;test.mosaicOperation=old;test.phase='M';
        [test cancelMosaic:nil];assert(test.phase=='E' && !test.terminal && controller.shows==1);
        [test completeMosaic:png regions:regions operation:old view:view error:nil];assert([(id)view itemArray].count==0);
        NSUUID *current=[NSUUID UUID];test.mosaicController=controller;test.mosaicOperation=current;test.phase='M';
        [test completeMosaic:png regions:regions operation:old view:view error:nil];assert([(id)view itemArray].count==0);
        [test completeMosaic:png regions:regions operation:current view:view error:nil];assert([(id)view itemArray].count==2 && !test.terminal && test.phase=='E');
        [test completeMosaic:png regions:regions operation:current view:view error:nil];assert([(id)view itemArray].count==2);
        test.terminal=YES;test.mosaicOperation=[NSUUID UUID];
        [test completeMosaic:png regions:regions operation:test.mosaicOperation view:view error:nil];assert([(id)view itemArray].count==2);
        NSData *fixture=SensitiveFixture();
        for (NSUInteger i=0;i<2;i++) {
            NSArray *sensitive=TCImageMosaicRegions(fixture,&error);assert(sensitive.count>=3 && !error);
            for (NSDictionary *region in sensitive) assert([region[@"text"] length]==0);
            NSData *redacted=TCPixelateImageRegions(fixture,sensitive,&error);assert(redacted.length && !error);
            NSArray *ocr=TCImageTextRegions(redacted,&error);assert(ocr.count && !error);
            NSMutableArray *texts=[NSMutableArray new];for (NSDictionary *region in ocr) [texts addObject:region[@"text"]];
            NSString *text=[texts componentsJoinedByString:@"\n"];
            assert([text.uppercaseString containsString:@"HELLO"] && TCSensitiveTextRanges(text).count==0);
        }
        assert(TCImageMosaicRegions(png,&error).count==0 && !error);
        assert(TCPixelateImageRegions(png,@[],&error).length && !error);
        NSArray *invalid=@[@{@"x":@.9,@"y":@.1,@"width":@.2,@"height":@.2}];
        assert(!TCPixelateImageRegions(png,invalid,&error) && error.code==4);
        assert(!TCImageMosaicRegions([@"invalid image" dataUsingEncoding:NSUTF8StringEncoding],&error) && error);
        assert(NSApp==nil);
        puts("PASS native editor mosaic: 1x/2x placement, bottom-origin crops, original/later annotations above mosaic, grouped undo/redo, copied crop retained, native control points, cancel/stale/duplicate/terminal completion; repeated real Vision helper detection/redaction/output OCR, no-hit and invalid input; no NSApplication, window or clipboard.");
    }
    return 0;
}

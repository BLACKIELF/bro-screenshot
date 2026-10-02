#import <Cocoa/Cocoa.h>
#import "../TCImageTranslation.h"
#include <assert.h>

static void PreserveGraphic(NSBitmapImageRep *before,NSBitmapImageRep *after,NSRect rect) {
    for (NSInteger y=NSMinY(rect);y<NSMaxY(rect);y++) for (NSInteger x=NSMinX(rect);x<NSMaxX(rect);x++) {
        NSColor *a=[[before colorAtX:x y:before.pixelsHigh-1-y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        NSColor *b=[[after colorAtX:x y:after.pixelsHigh-1-y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        if (fabs(a.redComponent-b.redComponent)>1./255 || fabs(a.greenComponent-b.greenComponent)>1./255 ||
            fabs(a.blueComponent-b.blueComponent)>1./255 || fabs(a.alphaComponent-b.alphaComponent)>1./255) {
            fprintf(stderr,"long translation erased a nearby graphic at %ld,%ld\n",(long)x,(long)y);exit(1);
        }
    }
}
static void ChangedInside(NSBitmapImageRep *before,NSBitmapImageRep *after,NSRect permitted) {
    assert(before.pixelsWide==after.pixelsWide && before.pixelsHigh==after.pixelsHigh);
    NSUInteger changed=0;
    for (NSInteger y=0;y<before.pixelsHigh;y++) for (NSInteger x=0;x<before.pixelsWide;x++) {
        NSColor *a=[[before colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        NSColor *b=[[after colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        BOOL differs=fabs(a.redComponent-b.redComponent)>1./255 || fabs(a.greenComponent-b.greenComponent)>1./255 ||
                     fabs(a.blueComponent-b.blueComponent)>1./255 || fabs(a.alphaComponent-b.alphaComponent)>1./255;
        if (!differs) continue;
        if (!NSPointInRect(NSMakePoint(x+.5,before.pixelsHigh-y-.5),permitted)) {
            fprintf(stderr,"translation altered an exterior pixel: x=%ld y=%ld\n",(long)x,(long)y);exit(1);
        }
        changed++;
    }
    assert(changed>100);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSString *folder = [NSString stringWithUTF8String:argv[1]];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:400 pixelsHigh:240
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        NSRect box = NSMakeRect(40,140,160,32);
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,400,240));
        [NSColor.redColor setFill]; NSRectFill(NSMakeRect(220,142,48,24));
        [NSColor.blueColor setFill]; NSRectFill(NSMakeRect(42,115,80,10));
        [@"Original" drawAtPoint:box.origin withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:24],
                                                       NSForegroundColorAttributeName:NSColor.blackColor}];
        [NSGraphicsContext restoreGraphicsState];
        NSData *before = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSArray *regions = @[@{@"id":@"0",@"text":@"Original",@"x":@(40./400),@"y":@(140./240),
                              @"width":@(160./400),@"height":@(32./240)}];
        NSError *error = nil;
        NSData *after = TCRenderImageTranslations(before,regions,@{@"0":@"OK"},&error);
        assert(after.length && !error);
        assert([before writeToFile:[folder stringByAppendingPathComponent:@"short-before.png"] atomically:YES]);
        assert([after writeToFile:[folder stringByAppendingPathComponent:@"short-after.png"] atomically:YES]);
        NSBitmapImageRep *original = [NSBitmapImageRep imageRepWithData:before];
        NSBitmapImageRep *result = [NSBitmapImageRep imageRepWithData:after];
        assert(result.pixelsWide==400 && result.pixelsHigh==240);
        NSRect permitted = NSInsetRect(box,-2,-2);
        ChangedInside(original,result,permitted);
        NSData *longAfter=TCRenderImageTranslations(before,regions,
            @{@"0":@"After the screenshot is finished, you can copy this image or save it for later, while keeping nearby icons intact."},&error);
        assert(longAfter.length && !error);
        assert([longAfter writeToFile:[folder stringByAppendingPathComponent:@"long-after.png"] atomically:YES]);
        NSBitmapImageRep *longResult=[NSBitmapImageRep imageRepWithData:longAfter];
        PreserveGraphic(original,longResult,NSMakeRect(220,142,48,24));
        PreserveGraphic(original,longResult,NSMakeRect(42,115,80,10));
        ChangedInside(original,longResult,permitted);
        NSMutableString *overflow=[NSMutableString new];
        for (NSUInteger i=0;i<5000;i++) [overflow appendString:@"translation "];
        assert(!TCRenderImageTranslations(before,regions,@{@"0":overflow},&error) &&
               [error.domain isEqualToString:@"TCImageTranslation"] && error.code==3);
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [[NSColor colorWithDeviceRed:.1 green:.12 blue:.15 alpha:1] setFill]; NSRectFill(NSMakeRect(0,0,400,240));
        [@"Original" drawAtPoint:box.origin withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:24],
                                                       NSForegroundColorAttributeName:NSColor.whiteColor}];
        [NSGraphicsContext restoreGraphicsState];
        NSData *dark = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSData *darkAfter = TCRenderImageTranslations(dark,regions,@{@"0":@"OK"},&error);
        assert(darkAfter.length && !error);
        assert([dark writeToFile:[folder stringByAppendingPathComponent:@"dark-before.png"] atomically:YES]);
        assert([darkAfter writeToFile:[folder stringByAppendingPathComponent:@"dark-after.png"] atomically:YES]);
        NSBitmapImageRep *darkResult = [NSBitmapImageRep imageRepWithData:darkAfter];
        // These blank pixels have the same source color. Compare inside and
        // outside the replaced region within the same output color profile.
        NSColor *outside = [darkResult colorAtX:10 y:85], *inside = [darkResult colorAtX:190 y:85];
        if (fabs(outside.redComponent-inside.redComponent)>1./255 ||
            fabs(outside.greenComponent-inside.greenComponent)>1./255 ||
            fabs(outside.blueComponent-inside.blueComponent)>1./255) {
            fprintf(stderr,"dark background fill differs: exterior=%.4f,%.4f,%.4f interior=%.4f,%.4f,%.4f\n",
                    outside.redComponent,outside.greenComponent,outside.blueComponent,
                    inside.redComponent,inside.greenComponent,inside.blueComponent);
            return 1;
        }
        puts("PASS translation layout: original position/dimensions, short and long translations preserve every exterior pixel and nearby icons/lines, oversized text fails clearly, dark fill matches its surroundings; no Vision, GUI or clipboard.");
    }
    return 0;
}

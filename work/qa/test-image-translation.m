#import <Cocoa/Cocoa.h>
#import "../TCImageTranslation.h"
#import "../TCOCR.h"
#include <assert.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2); NSString *folder = [NSString stringWithUTF8String:argv[1]];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:1200 pixelsHigh:600
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,1200,600));
        [[NSColor colorWithDeviceRed:.1 green:.12 blue:.15 alpha:1] setFill]; NSRectFill(NSMakeRect(0,0,1200,280));
        [[NSColor colorWithDeviceRed:0 green:.4 blue:1 alpha:1] setFill]; NSRectFill(NSMakeRect(1050,510,100,60));
        NSArray *texts = @[@"截图完成后，可以复制和保存。", @"请检查翻译结果。", @"Hello, welcome to the screenshot test."];
        NSArray *ys = @[@440,@340,@150];
        for (NSUInteger i=0;i<3;i++) [texts[i] drawAtPoint:NSMakePoint(50,[ys[i] doubleValue])
            withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:i==2 ? 38 : 46],
                                 NSForegroundColorAttributeName:i==2 ? NSColor.whiteColor : NSColor.blackColor}];
        [NSGraphicsContext restoreGraphicsState];
        NSData *before = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        assert([before writeToFile:[folder stringByAppendingPathComponent:@"inline-before.png"] atomically:YES]);
        NSError *error = nil; NSArray *regions = TCImageTextRegions(before, &error); assert(regions.count >= 3 && !error);
        NSMutableDictionary *translations = [NSMutableDictionary new];
        for (NSDictionary *unit in regions) {
            NSString *text=unit[@"text"];
            translations[unit[@"id"]]=[text containsString:@"Hello"] ? @"你好，欢迎参加截图测试。" :
                    ([text containsString:@"检查"] ? @"Please check the translation result." : @"After the screenshot, you can copy and save it.");
            assert([unit[@"y"] doubleValue] >= 0 && [unit[@"height"] doubleValue] > 0);
        }
        NSData *after = TCRenderImageTranslations(before, regions, translations, &error); assert(after.length && !error);
        assert([after writeToFile:[folder stringByAppendingPathComponent:@"inline-render-fixture.png"] atomically:YES]);
        NSBitmapImageRep *rendered = [NSBitmapImageRep imageRepWithData:after]; assert(rendered.pixelsWide==1200 && rendered.pixelsHigh==600);
        NSColor *tile=[rendered colorAtX:1100 y:50]; assert(tile.blueComponent>.98 && tile.redComponent<.02);
        NSString *recognized = TCRecognizeImageText(after,&error); assert(recognized.length && !error);
        assert([recognized containsString:@"After"] && [recognized containsString:@"Please"] && [recognized containsString:@"你好"]);
        assert(![recognized containsString:@"Hello"] && ![recognized containsString:@"截图完成"]);
        assert([recognized containsString:@"save it."] && [recognized containsString:@"translation result."]);
        NSArray *roundtrip=TCImageTextRegions(after,&error);
        BOOL upperEnglish=NO, lowerChinese=NO;
        for (NSDictionary *unit in roundtrip) {
            if ([unit[@"text"] containsString:@"After"] && [unit[@"y"] doubleValue]>.6) upperEnglish=YES;
            if ([unit[@"text"] containsString:@"你好"] && [unit[@"y"] doubleValue]<.4) lowerChinese=YES;
        }
        assert(upperEnglish && lowerChinese);
        assert(!TCImageTextRegions([NSData dataWithBytes:"invalid" length:7],&error) && error);
        NSData *unchanged=TCRenderImageTranslations(before,@[],@{},&error);assert(unchanged.length && !error);
        puts("PASS image translation: real Vision boxes, Chinese and English placement, wrapping, light and dark background, original text replaced, dimensions and graphic preserved, invalid image and empty translation.");
    }
}

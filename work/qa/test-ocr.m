#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import "../TCOCR.h"

int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        if (TCRecognizeImageText(nil, &error) != nil || !error) return 1;
        CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, 900, 180, 8, 0, color, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(color);
        if (!context) return 2;
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, CGRectMake(0, 0, 900, 180));
        CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 64, NULL);
        NSAttributedString *label = [[NSAttributedString alloc] initWithString:@"HELLO 2026" attributes:@{(__bridge NSString *)kCTFontAttributeName:(__bridge id)font}];
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)label);
        CGContextSetTextPosition(context, 40, 60);
        CTLineDraw(line, context);
        CGImageRef image = CGBitmapContextCreateImage(context);
        NSData *data = [[[NSBitmapImageRep alloc] initWithCGImage:image] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        CFRelease(line); CFRelease(font); CGImageRelease(image); CGContextRelease(context);
        error = nil;
        NSString *text = TCRecognizeImageText(data, &error);
        if (!text) { fprintf(stderr, "OCR runtime unavailable/failure: %s\n", error.description.UTF8String); return 3; }
        if (![text.uppercaseString containsString:@"HELLO"] || ![text containsString:@"2026"]) {
            fprintf(stderr, "Unexpected synthetic OCR: %s\n", text.UTF8String); return 4;
        }
        puts("PASS OCR: empty input rejected; offscreen HELLO 2026 recognized; no NSApplication/capture/pasteboard");
    }
    return 0;
}

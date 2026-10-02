#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import "../TCImageAnalysis.h"
#import "../TCOCR.h"
#include <assert.h>

static NSData *TextImage(NSArray<NSString *> *lines) {
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 1200, 340, 8, 0, color, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color); assert(context);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1); CGContextFillRect(context, CGRectMake(0, 0, 1200, 340));
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 42, NULL);
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSAttributedString *label = [[NSAttributedString alloc] initWithString:lines[i]
                attributes:@{(__bridge NSString *)kCTFontAttributeName:(__bridge id)font}];
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)label);
        CGContextSetTextPosition(context, 36, 270 - 66 * i); CTLineDraw(line, context); CFRelease(line);
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    NSData *png = [[[NSBitmapImageRep alloc] initWithCGImage:image] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    CGImageRelease(image); CGContextRelease(context); CFRelease(font);
    return png;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(TCSensitiveTextRanges(@"HELLO 2026 ORDER ABC123").count == 0);
        assert(TCSensitiveTextRanges(@"139 0000 0000").count == 1);
        assert(TCSensitiveTextRanges(@"qa+demo@example.test").count == 1);
        assert(TCSensitiveTextRanges(@"qatdemo@ example.test").count == 1);
        NSError *error = nil; NSUInteger count = 99;
        assert(!TCRedactImage(nil, &count, &error) && error && count == 0);
        assert(!TCRecognizeImageCodes([@"not an image" dataUsingEncoding:NSUTF8StringEncoding], &error) && error);
        NSData *before = TextImage(@[@"HELLO 2026 ORDER ABC123", @"Phone 13900000000", @"Email qa+demo@example.test", @"Card 6222021234567890"]);
        if (argc == 2) assert([before writeToFile:[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"privacy-before.png"] atomically:YES]);
        NSString *original = TCRecognizeImageText(before, &error);
        if (!original || TCSensitiveTextRanges(original).count < 3)
            fprintf(stderr, "Synthetic fixture OCR: %s\n", (original ?: error.description).UTF8String);
        assert(original && TCSensitiveTextRanges(original).count >= 3);
        NSData *after = TCRedactImage(before, &count, &error);
        assert(after && !error && count >= 3);
        NSString *masked = TCRecognizeImageText(after, &error);
        assert(masked && [masked.uppercaseString containsString:@"HELLO"] && [masked containsString:@"2026"]);
        assert(TCSensitiveTextRanges(masked).count == 0);
        NSBitmapImageRep *input = [NSBitmapImageRep imageRepWithData:before], *output = [NSBitmapImageRep imageRepWithData:after];
        assert(input.pixelsWide == output.pixelsWide && input.pixelsHigh == output.pixelsHigh);
        for (NSInteger y = 0; y < input.pixelsHigh; y += 20)
            assert([[input colorAtX:5 y:y] isEqual:[output colorAtX:5 y:y]]);
        NSData *plain = TextImage(@[@"HELLO 2026 ORDER ABC123"]);
        NSData *tiff = [[NSImage alloc] initWithData:plain].TIFFRepresentation;
        NSData *noHit = TCRedactImage(tiff, &count, &error);
        assert(noHit && count == 0 && !error && [noHit length] > 8);
        const unsigned char *bytes = noHit.bytes;
        assert(bytes[0] == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G');
        assert([TCRecognizeImageText(noHit, &error) containsString:@"HELLO"]);
        assert(TCRecognizeImageCodes(plain, &error).count == 0 && !error);
        NSString *payload = @"https://example.test/qa/bro-screenshot";
        CIFilter *generator = [CIFilter filterWithName:@"CIQRCodeGenerator"];
        [generator setValue:[payload dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
        CIImage *qr = [generator.outputImage imageByApplyingTransform:CGAffineTransformMakeScale(10, 10)];
        CGImageRef qrImage = [[CIContext contextWithOptions:nil] createCGImage:qr fromRect:qr.extent];
        assert(qrImage);
        NSData *qrPNG = [[[NSBitmapImageRep alloc] initWithCGImage:qrImage] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        CGImageRelease(qrImage);
        NSArray *codes = TCRecognizeImageCodes(qrPNG, &error);
        assert(codes.count == 1 && [codes.firstObject isEqualToString:payload] && !error);
        if (argc == 2) {
            NSString *directory = [NSString stringWithUTF8String:argv[1]];
            assert([before writeToFile:[directory stringByAppendingPathComponent:@"privacy-before.png"] atomically:YES]);
            assert([after writeToFile:[directory stringByAppendingPathComponent:@"privacy-after.png"] atomically:YES]);
            assert([qrPNG writeToFile:[directory stringByAppendingPathComponent:@"qr-fixture.png"] atomically:YES]);
        }
        puts("PASS image analysis: real Vision QR round-trip, empty/invalid images, OCR detects sensitive input, output removes sensitive ranges and preserves public text/border/dimensions, no-hit TIFF becomes valid PNG.");
    }
    return 0;
}

#import "TCImageAnalysis.h"
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static void AnalysisError(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"TCImageAnalysis" code:code
                                      userInfo:@{NSLocalizedDescriptionKey:message}];
}
static CGImageRef ReadImage(NSData *data, NSError **error) {
    if (error) *error = nil;
    CGImageSourceRef source = data.length ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    if (source) CFRelease(source);
    size_t width = image ? CGImageGetWidth(image) : 0;
    size_t height = image ? CGImageGetHeight(image) : 0;
    if (!width || !height || width > (64 * 1024 * 1024) / height) {
        if (image) CGImageRelease(image);
        AnalysisError(error, 1, @"图片为空、无法读取或尺寸过大");
        return NULL;
    }
    return image;
}
static NSData *EncodePNG(CGImageRef image, NSError **error) {
    NSMutableData *png = [NSMutableData new];
    CGImageDestinationRef destination = image ? CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png,
                                       (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL) : NULL;
    if (destination) CGImageDestinationAddImage(destination, image, NULL);
    BOOL encoded = destination && CGImageDestinationFinalize(destination);
    if (destination) CFRelease(destination);
    if (!encoded) { AnalysisError(error, 3, @"遮挡图片无法编码"); return nil; }
    return png;
}
NSArray<NSString *> *TCRecognizeImageCodes(NSData *data, NSError **error) {
    CGImageRef image = ReadImage(data, error);
    if (!image) return nil;
    VNDetectBarcodesRequest *request = [VNDetectBarcodesRequest new];
    BOOL ok = [[[VNImageRequestHandler alloc] initWithCGImage:image options:@{}]
               performRequests:@[request] error:error];
    CGImageRelease(image);
    if (!ok) return nil;
    NSMutableOrderedSet<NSString *> *values = [NSMutableOrderedSet new];
    for (VNBarcodeObservation *observation in request.results)
        if (observation.payloadStringValue.length) [values addObject:observation.payloadStringValue];
    return values.array;
}
NSArray<NSValue *> *TCSensitiveTextRanges(NSString *text) {
    static NSArray<NSRegularExpression *> *patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *sources = @[
            @"(?<![0-9])(?:\\+?86[ -]?)?1[3-9](?:[ -]?[0-9]){9}(?![0-9])",
            @"[A-Z0-9._%+-]+[ \\t]*@[ \\t]*[A-Z0-9.-]+[ \\t]*\\.[ \\t]*[A-Z]{2,}",
            @"(?<![0-9])[1-9][0-9]{5}(?:18|19|20)[0-9]{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])[0-9]{3}[0-9X](?![0-9])",
            @"(?<![0-9])(?:[0-9][ -]?){15,18}[0-9](?![0-9])"
        ];
        NSMutableArray *compiled = [NSMutableArray new];
        for (NSString *pattern in sources)
            [compiled addObject:[NSRegularExpression regularExpressionWithPattern:pattern
                                  options:NSRegularExpressionCaseInsensitive error:NULL]];
        patterns = compiled;
    });
    NSMutableArray<NSValue *> *ranges = [NSMutableArray new];
    for (NSRegularExpression *pattern in patterns) {
        for (NSTextCheckingResult *match in [pattern matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
            NSValue *range = [NSValue valueWithRange:match.range];
            if (![ranges containsObject:range]) [ranges addObject:range];
        }
    }
    return ranges;
}
NSData *TCRedactImage(NSData *data, NSUInteger *regionCount, NSError **error) {
    if (regionCount) *regionCount = 0;
    CGImageRef image = ReadImage(data, error);
    if (!image) return nil;
    VNRecognizeTextRequest *text = [VNRecognizeTextRequest new];
    text.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    text.recognitionLanguages = @[@"zh-Hans", @"en-US"];
    text.usesLanguageCorrection = YES;
    VNDetectFaceRectanglesRequest *faces = [VNDetectFaceRectanglesRequest new];
    BOOL ok = [[[VNImageRequestHandler alloc] initWithCGImage:image options:@{}]
               performRequests:@[text, faces] error:error];
    if (!ok) { CGImageRelease(image); return nil; }
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSMutableArray<NSValue *> *regions = [NSMutableArray new];
    for (VNRecognizedTextObservation *observation in text.results) {
        VNRecognizedText *candidate = [observation topCandidates:1].firstObject;
        for (NSValue *range in TCSensitiveTextRanges(candidate.string ?: @"")) {
            VNRectangleObservation *precise = [candidate boundingBoxForRange:range.rangeValue error:NULL];
            CGRect box = precise ? precise.boundingBox : observation.boundingBox;
            CGRect pixels = CGRectMake(box.origin.x * width, box.origin.y * height,
                                       box.size.width * width, box.size.height * height);
            [regions addObject:[NSValue valueWithRect:NSRectFromCGRect(CGRectInset(pixels, -4, -4))]];
        }
    }
    for (VNFaceObservation *face in faces.results) {
        CGRect box = face.boundingBox;
        CGRect pixels = CGRectMake(box.origin.x * width, box.origin.y * height,
                                   box.size.width * width, box.size.height * height);
        [regions addObject:[NSValue valueWithRect:NSRectFromCGRect(CGRectInset(pixels, -pixels.size.width * 0.12, -pixels.size.height * 0.12))]];
    }
    if (!regions.count) { NSData *png = EncodePNG(image, error); CGImageRelease(image); return png; }
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, color, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color);
    if (!context) { CGImageRelease(image); AnalysisError(error, 2, @"遮挡图片无法创建"); return nil; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGImageRelease(image);
    CGContextSetRGBFillColor(context, 0.08, 0.08, 0.08, 1);
    CGContextSetShouldAntialias(context, false);
    for (NSValue *region in regions) {
        CGRect rect = CGRectIntersection(CGRectIntegral(NSRectToCGRect(region.rectValue)), CGRectMake(0, 0, width, height));
        if (!CGRectIsEmpty(rect)) CGContextFillRect(context, rect);
    }
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    NSData *png = EncodePNG(result, error);
    if (result) CGImageRelease(result);
    if (!png) return nil;
    if (regionCount) *regionCount = regions.count;
    return png;
}

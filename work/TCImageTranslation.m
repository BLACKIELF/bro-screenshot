#import "TCImageTranslation.h"
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreText/CoreText.h>
#import <mach-o/dyld.h>
#import <fcntl.h>

static void TranslationImageError(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"TCImageTranslation" code:code
                                      userInfo:@{NSLocalizedDescriptionKey:message}];
}
static CGImageRef TranslationImage(NSData *data, NSError **error) {
    if (error) *error = nil;
    CGImageSourceRef source = data.length ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    if (source) CFRelease(source);
    size_t width = image ? CGImageGetWidth(image) : 0, height = image ? CGImageGetHeight(image) : 0;
    if (!width || !height || width > (64 * 1024 * 1024) / height) {
        if (image) CGImageRelease(image);
        TranslationImageError(error, 1, @"截图为空、无法读取或尺寸过大"); return NULL;
    }
    return image;
}
NSArray<NSDictionary *> *TCImageTextRegionsDirect(NSData *data, NSError **error) {
    CGImageRef image = TranslationImage(data, error);
    if (!image) return nil;
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.automaticallyDetectsLanguage = YES;
    request.usesLanguageCorrection = YES;
    BOOL ok = [[[VNImageRequestHandler alloc] initWithCGImage:image options:@{}] performRequests:@[request] error:error];
    CGImageRelease(image);
    if (!ok) return nil;
    NSMutableArray *regions = [NSMutableArray new];
    for (VNRecognizedTextObservation *observation in request.results) {
        NSString *text = [observation topCandidates:1].firstObject.string;
        if (!text.length) continue;
        CGRect box = observation.boundingBox;
        if (CGRectIsEmpty(box)) continue;
        [regions addObject:@{@"id":@(regions.count).stringValue, @"text":text,
                             @"x":@(box.origin.x), @"y":@(box.origin.y),
                             @"width":@(box.size.width), @"height":@(box.size.height)}];
    }
    return regions;
}
static NSArray<NSDictionary *> *ImageTextRegionsOnce(NSData *data, NSError **error) {
    if (error) *error = nil;
    if (!data.length || data.length > 256 * 1024 * 1024) {
        TranslationImageError(error, 1, @"截图为空或数据过大，请缩小选区"); return nil;
    }
    uint32_t pathLength = 0;
    (void)_NSGetExecutablePath(NULL, &pathLength);
    char *path = calloc(pathLength + 1, 1);
    if (!path || _NSGetExecutablePath(path, &pathLength) != 0) {
        free(path); TranslationImageError(error, 5, @"无法定位本机识别组件"); return nil;
    }
    NSString *directory = [[@(path) stringByResolvingSymlinksInPath] stringByDeletingLastPathComponent];
    free(path);
    NSURL *helper = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"BroOCRHelper"]];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:helper.path]) {
        TranslationImageError(error, 5, @"本机识别组件缺失，请重新构建 bro截图"); return nil;
    }
    NSTask *task = [NSTask new]; task.executableURL = helper;
    NSPipe *input = [NSPipe pipe], *output = [NSPipe pipe];
    if (fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != 0) {
        TranslationImageError(error, 5, @"无法安全启动本机识别任务"); return nil;
    }
    task.standardInput = input; task.standardOutput = output;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) { if (error) *error = launchError; return nil; }
    [input.fileHandleForReading closeAndReturnError:NULL];
    [output.fileHandleForWriting closeAndReturnError:NULL];
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    __block NSData *reply = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            NSMutableData *bytes = [NSMutableData new];
            for (;;) {
                NSData *chunk = [output.fileHandleForReading readDataOfLength:65536];
                if (!chunk.length) { reply = bytes; break; }
                if (bytes.length + chunk.length > 8 * 1024 * 1024) { if (task.running) [task terminate]; break; }
                [bytes appendData:chunk];
            }
        } @catch (NSException *exception) { }
        dispatch_semaphore_signal(finished);
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try { [input.fileHandleForWriting writeData:data]; }
        @catch (NSException *exception) { }
        [input.fileHandleForWriting closeFile];
    });
    if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 110 * NSEC_PER_SEC))) {
        if (task.running) [task terminate];
        [task waitUntilExit]; [output.fileHandleForReading closeFile];
        TranslationImageError(error, 6, @"文字识别等待过久，请重新框选后重试"); return nil;
    }
    [task waitUntilExit]; [output.fileHandleForReading closeFile];
    NSDictionary *object = reply ? [NSJSONSerialization JSONObjectWithData:reply options:0 error:NULL] : nil;
    if (![object isKindOfClass:NSDictionary.class]) {
        TranslationImageError(error, 7, @"本机识别未返回有效结果，请重试"); return nil;
    }
    NSDictionary *failure = object[@"error"];
    if ([failure isKindOfClass:NSDictionary.class]) {
        NSString *message = [failure[@"message"] isKindOfClass:NSString.class] ? failure[@"message"] : @"本机文字识别失败";
        NSString *domain = [failure[@"domain"] isKindOfClass:NSString.class] ? failure[@"domain"] : @"TCImageTranslation";
        NSInteger code = [failure[@"code"] isKindOfClass:NSNumber.class] ? [failure[@"code"] integerValue] : 8;
        if (error) *error = [NSError errorWithDomain:domain code:code userInfo:@{NSLocalizedDescriptionKey:message}];
        return nil;
    }
    NSArray *regions = object[@"regions"];
    if (task.terminationStatus != 0 || ![regions isKindOfClass:NSArray.class]) {
        TranslationImageError(error, 7, @"本机识别未返回有效结果，请重试"); return nil;
    }
    NSMutableSet *ids = [NSMutableSet new];
    for (id region in regions) {
        if (![region isKindOfClass:NSDictionary.class] || ![region[@"id"] isKindOfClass:NSString.class] ||
            ![region[@"text"] isKindOfClass:NSString.class] || [ids containsObject:region[@"id"]]) {
            TranslationImageError(error, 7, @"识别文字块格式错误"); return nil;
        }
        for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
            id value = region[key];
            if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue]) ||
                [value doubleValue] < 0 || [value doubleValue] > 1) {
                TranslationImageError(error, 7, @"识别文字位置无效"); return nil;
            }
        }
        [ids addObject:region[@"id"]];
    }
    return regions;
}
NSArray<NSDictionary *> *TCImageTextRegions(NSData *data, NSError **error) {
    NSError *failure = nil;
    NSArray *regions = ImageTextRegionsOnce(data, &failure);
    // This host occasionally returns a reader error even for a valid screenshot.
    // A new helper succeeded on retry. Retry that exact failure once; never retry
    // malformed images, missing helpers, timeouts or other system errors.
    if (!regions && [failure.domain isEqualToString:@"TextRecognition.CRImageReaderError"] && failure.code == 1)
        regions = ImageTextRegionsOnce(data, &failure);
    if (error) *error = regions ? nil : failure;
    return regions;
}
NSRect TCImageTranslationPanelFrame(NSRect image, NSRect visible, NSRect *toolbar) {
    CGFloat width = MIN(560, visible.size.width - 20), height = 116;
    CGFloat x = MAX(NSMinX(visible) + 10, MIN(NSMinX(image), NSMaxX(visible) - width - 10));
    CGFloat sideY = MAX(NSMinY(visible), MIN(NSMaxY(image) - height, NSMaxY(visible) - height));
    NSRect choices[] = {NSMakeRect(x, NSMinY(image) - height - 4, width, height),
                        NSMakeRect(x, NSMaxY(image) + 4, width, height),
                        NSMakeRect(NSMaxX(image) + 4, sideY, width, height),
                        NSMakeRect(NSMinX(image) - width - 4, sideY, width, height)};
    for (int i = 0; i < 4; i++) {
        if (NSContainsRect(visible, choices[i]) && !NSIntersectsRect(image, choices[i])) {
            *toolbar = choices[i]; return NSUnionRect(image, *toolbar);
        }
    }
    // A full-screen selection cannot leave room for controls. Keep the image
    // anchored and use the screen edge with the smallest unavoidable overlap.
    CGFloat leastOverlap = CGFLOAT_MAX;
    for (int i = 0; i < 4; i++) {
        NSRect choice = choices[i];
        choice.origin.x = MAX(NSMinX(visible) + 10, MIN(choice.origin.x, NSMaxX(visible) - width - 10));
        choice.origin.y = MAX(NSMinY(visible), MIN(choice.origin.y, NSMaxY(visible) - height));
        NSRect overlap = NSIntersectionRect(image, choice);
        CGFloat area = NSIsEmptyRect(overlap) ? 0 : overlap.size.width * overlap.size.height;
        if (area < leastOverlap) { leastOverlap = area; *toolbar = choice; }
    }
    return NSUnionRect(image, *toolbar);
}
static NSRect RegionRect(NSDictionary *unit, NSSize size) {
    return NSMakeRect([unit[@"x"] doubleValue] * size.width, [unit[@"y"] doubleValue] * size.height,
                      [unit[@"width"] doubleValue] * size.width, [unit[@"height"] doubleValue] * size.height);
}
// Pick the most common border color, avoiding the foreground text inside the box.
static NSColor *BorderColor(CGContextRef bitmap, NSRect box) {
    const uint8_t *pixels = CGBitmapContextGetData(bitmap);
    NSInteger width = CGBitmapContextGetWidth(bitmap), height = CGBitmapContextGetHeight(bitmap);
    size_t rowBytes = CGBitmapContextGetBytesPerRow(bitmap);
    NSMutableDictionary<NSNumber *, NSNumber *> *counts = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, NSColor *> *colors = [NSMutableDictionary new];
    for (int side = 0; side < 4; side++) for (int i = 0; i < 24; i++) {
        CGFloat t = (i + 0.5) / 24;
        NSInteger x = lround(side < 2 ? NSMinX(box) + t * box.size.width : (side == 2 ? NSMinX(box) - 2 : NSMaxX(box) + 2));
        NSInteger y = lround(side >= 2 ? NSMinY(box) + t * box.size.height : (side == 0 ? NSMinY(box) - 2 : NSMaxY(box) + 2));
        x = MAX(0, MIN(width - 1, x));
        y = MAX(0, MIN(height - 1, height - 1 - y));
        const uint8_t *sample = pixels + y * rowBytes + x * 4;
        if (!sample[3]) continue;
        // Sample the rendered bitmap's RGB values, so filling uses the same
        // color space. Converting through NSColor can brighten dark backgrounds.
        NSColor *color = [NSColor colorWithDeviceRed:(double)sample[0] / sample[3]
                          green:(double)sample[1] / sample[3] blue:(double)sample[2] / sample[3] alpha:1];
        NSUInteger r = lround(color.redComponent * 255), g = lround(color.greenComponent * 255), b = lround(color.blueComponent * 255);
        NSNumber *key = @(((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4));
        counts[key] = @([counts[key] unsignedIntegerValue] + 1); colors[key] = color;
    }
    NSNumber *best = nil;
    for (NSNumber *key in counts) if (!best || counts[key].integerValue > counts[best].integerValue) best = key;
    return best ? colors[best] : NSColor.whiteColor;
}
static CTFrameRef TranslationTextFrame(NSString *text, CGFloat fontSize, NSColor *foreground, NSRect layout) {
    NSFont *font = [NSFont systemFontOfSize:fontSize];
    CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef)font.fontName, fontSize, NULL);
    NSDictionary *attributes = @{(__bridge NSString *)kCTFontAttributeName:(__bridge id)ctFont,
                    (__bridge NSString *)kCTForegroundColorAttributeName:(__bridge id)foreground.CGColor};
    NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CFRelease(ctFont);
    CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
    CGPathRef path = CGPathCreateWithRect(NSRectToCGRect(NSInsetRect(layout, 1, 1)), NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
    CGPathRelease(path); CFRelease(setter);
    return frame;
}
NSData *TCRenderImageTranslations(NSData *data, NSArray<NSDictionary *> *regions,
                                  NSDictionary<NSString *, NSString *> *translations, NSError **error) {
    CGImageRef original = TranslationImage(data, error);
    if (!original) return nil;
    NSSize size = NSMakeSize(CGImageGetWidth(original), CGImageGetHeight(original));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(NULL, size.width, size.height, 8, 0, space,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap) { CGImageRelease(original); TranslationImageError(error, 2, @"无法创建译图"); return nil; }
    CGContextDrawImage(bitmap, CGRectMake(0, 0, size.width, size.height), original); CGImageRelease(original);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:bitmap flipped:NO];
    NSMutableArray *draws = [NSMutableArray new];
    for (NSDictionary *unit in regions) {
        NSString *text = translations[unit[@"id"]];
        if (!text.length || [text isEqualToString:unit[@"text"]]) continue;
        NSRect box = RegionRect(unit, size);
        if (box.size.width <= 0 || box.size.height <= 0 || !isfinite(box.size.width) || !isfinite(box.size.height) ||
            !isfinite(box.origin.x) || !isfinite(box.origin.y)) continue;
        NSRect cover = NSIntersectionRect(NSInsetRect(box, -2, -2), NSMakeRect(0, 0, size.width, size.height));
        if (NSIsEmptyRect(cover)) continue;
        NSColor *background = BorderColor(bitmap, box);
        CGFloat luminance = background.redComponent * .2126 + background.greenComponent * .7152 + background.blueComponent * .0722;
        NSColor *foreground = luminance < .5 ? NSColor.whiteColor : NSColor.blackColor;
        // Allow wrapping into nearby blank space, stopping before other OCR boxes.
        CGFloat right = MIN(size.width - 2, NSMaxX(box) + box.size.width * .5);
        CGFloat bottom = MAX(2, NSMinY(box) - box.size.height * .75);
        for (NSDictionary *other in regions) {
            if (other == unit) continue;
            NSRect next = RegionRect(other, size);
            if (NSMinX(next) >= NSMaxX(box) && NSMinY(next) < NSMaxY(box) && NSMaxY(next) > NSMinY(box)) right = MIN(right, NSMinX(next) - 3);
            if (NSMaxY(next) <= NSMinY(box) && NSMinX(next) < right && NSMaxX(next) > NSMinX(box)) bottom = MAX(bottom, NSMaxY(next) + 3);
        }
        NSRect layout = NSMakeRect(NSMinX(cover), MIN(bottom, NSMinY(cover)),
                                   MAX(cover.size.width, right - NSMinX(cover)), NSMaxY(cover) - MIN(bottom, NSMinY(cover)));
        CGFloat fontSize = MAX(4, box.size.height * .85);
        // Short translations already fit where the source text was. Do not
        // erase adjacent graphics just because extra wrapping space is available.
        CTFrameRef textFrame = TranslationTextFrame(text, fontSize, foreground, cover);
        if (CTFrameGetVisibleStringRange(textFrame).length == (CFIndex)text.length) layout = cover;
        else { CFRelease(textFrame); textFrame = NULL; }
        while (!textFrame && fontSize >= 4) {
            textFrame = TranslationTextFrame(text, fontSize, foreground, layout);
            // Use the very same layout engine for fitting and drawing. NSString
            // measurement can otherwise accept text whose final wrapped line clips.
            CFRange visible = CTFrameGetVisibleStringRange(textFrame);
            if (visible.length == (CFIndex)text.length) break;
            CFRelease(textFrame); textFrame = NULL;
            fontSize -= .5;
        }
        if (!textFrame) {
            [NSGraphicsContext restoreGraphicsState]; CGContextRelease(bitmap);
            TranslationImageError(error, 3, @"译文太长，原位置放不下。请放大内容后重新截图。"); return nil;
        }
        [draws addObject:@{@"rect":[NSValue valueWithRect:layout], @"background":background,
                           @"frame":CFBridgingRelease(textFrame)}];
    }
    for (NSDictionary *draw in draws) {
        NSColor *color = draw[@"background"];
        CGContextSetRGBFillColor(bitmap, color.redComponent, color.greenComponent, color.blueComponent, 1);
        CGContextFillRect(bitmap, NSRectToCGRect([draw[@"rect"] rectValue]));
    }
    for (NSDictionary *draw in draws) {
        NSRect rect = [draw[@"rect"] rectValue]; CGContextSaveGState(bitmap); CGContextClipToRect(bitmap, NSRectToCGRect(rect));
        CGContextSetTextMatrix(bitmap, CGAffineTransformIdentity);
        CTFrameDraw((__bridge CTFrameRef)draw[@"frame"], bitmap);
        CGContextRestoreGState(bitmap);
    }
    [NSGraphicsContext restoreGraphicsState];
    CGImageRef result = CGBitmapContextCreateImage(bitmap); CGContextRelease(bitmap);
    NSMutableData *png = [NSMutableData new];
    CGImageDestinationRef destination = result ? CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL) : NULL;
    if (destination) CGImageDestinationAddImage(destination, result, NULL);
    BOOL ok = destination && CGImageDestinationFinalize(destination);
    if (destination) CFRelease(destination); if (result) CGImageRelease(result);
    if (!ok) { TranslationImageError(error, 4, @"译图编码失败"); return nil; }
    return png;
}

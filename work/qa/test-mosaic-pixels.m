#import <Cocoa/Cocoa.h>
#import "../TCImageAnalysis.m"
#include <assert.h>

static const size_t W = 32, H = 24;
static CGBitmapInfo Format(void) { return kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big; }
static CGContextRef Bitmap(size_t width, size_t height) {
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, color, Format());
    CGColorSpaceRelease(color); assert(context); return context;
}
static NSData *Pixels(CGImageRef image) {
    CGContextRef context = Bitmap(W, H);
    CGContextDrawImage(context, CGRectMake(0, 0, W, H), image);
    NSData *data = [NSData dataWithBytes:CGBitmapContextGetData(context) length:W * H * 4];
    CGContextRelease(context); return data;
}
static NSData *Output(CGImageRef image, NSArray<NSValue *> *regions) {
    NSError *error = nil;
    NSData *png = PixelateImage(image, regions, &error);
    assert(png.length && !error);
    CGImageRef result = ReadImage(png, &error); assert(result && !error);
    assert(CGImageGetWidth(result) == W && CGImageGetHeight(result) == H);
    NSData *data = Pixels(result); CGImageRelease(result); return data;
}
static NSValue *Box(CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    return [NSValue valueWithRect:NSMakeRect(x, y, width, height)];
}
static void Color(NSData *data, size_t x, size_t y, int r, int g, int b, int a) {
    const uint8_t *p = (const uint8_t *)data.bytes + ((H - 1 - y) * W + x) * 4;
    int expected[] = {r, g, b, a};
    for (size_t i = 0; i < 4; i++) {
        if (abs((int)p[i] - expected[i]) > 1)
            fprintf(stderr, "color mismatch x=%zu y=%zu channel=%zu actual=%u expected=%d\n", x, y, i, p[i], expected[i]);
        assert(abs((int)p[i] - expected[i]) <= 1);
    }
}
int main(void) {
    @autoreleasepool {
        CGContextRef context = Bitmap(W, H);
        uint8_t *p = CGBitmapContextGetData(context);
        for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++) {
            uint8_t *pixel = p + (y * W + x) * 4;
            pixel[0] = (x + H - 1 - y) % 2 ? 255 : 0; pixel[1] = 0;
            pixel[2] = (x + H - 1 - y) % 2 ? 0 : 255; pixel[3] = 255;
        }
        CGImageRef image = CGBitmapContextCreateImage(context); assert(image);
        NSData *before = Pixels(image);
        NSData *after = Output(image, @[Box(5, 4, 16, 8)]);
        for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++) {
            size_t quartzY = H - 1 - y;
            if (x >= 5 && x < 21 && quartzY >= 4 && quartzY < 12) Color(after, x, quartzY, 128, 0, 128, 255);
            else assert(!memcmp((const uint8_t *)before.bytes + (y * W + x) * 4,
                                (const uint8_t *)after.bytes + (y * W + x) * 4, 4));
        }
        NSData *edge = Output(image, @[Box(-4, -4, 12, 12), Box(29, 21, 7, 7)]);
        Color(edge, 0, 0, 128, 0, 128, 255);
        // The odd 3x3 edge cell has four red and five blue source pixels.
        Color(edge, 31, 23, 113, 0, 142, 255);
        assert([Output(image, @[]) isEqual:before]);
        CGImageRelease(image);

        // Asymmetric vertical colors catch a bitmap-row / Quartz-origin swap.
        for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++) {
            uint8_t *pixel = p + (y * W + x) * 4;
            pixel[0] = y < H / 2 ? 255 : 0; pixel[1] = 0;
            pixel[2] = y < H / 2 ? 0 : 255; pixel[3] = 255;
        }
        image = CGBitmapContextCreateImage(context); assert(image);
        NSData *vertical = Output(image, @[Box(0, 0, 8, 8)]);
        Color(vertical, 0, 0, 0, 0, 255, 255);
        Color(vertical, 7, 7, 0, 0, 255, 255);
        Color(vertical, 0, H - 1, 255, 0, 0, 255);
        CGImageRelease(image);

        // Shifted overlap must read original colors, not already-mosaicked ones.
        for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++) {
            uint8_t *pixel = p + (y * W + x) * 4;
            pixel[0] = x < 8 ? 255 : 0; pixel[1] = 0;
            pixel[2] = x < 8 ? 0 : 255; pixel[3] = 255;
        }
        image = CGBitmapContextCreateImage(context); assert(image);
        NSData *overlap = Output(image, @[Box(4, 4, 8, 8), Box(8, 4, 8, 8)]);
        Color(overlap, 4, 4, 128, 0, 128, 255);
        Color(overlap, 8, 4, 0, 0, 255, 255);
        Color(overlap, 15, 11, 0, 0, 255, 255);
        CGImageRelease(image);

        for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++) {
            uint8_t *pixel = p + (y * W + x) * 4;
            pixel[0] = (x + H - 1 - y) % 2 ? 128 : 0; pixel[1] = 0; pixel[2] = 0;
            pixel[3] = (x + H - 1 - y) % 2 ? 128 : 0;
        }
        image = CGBitmapContextCreateImage(context); assert(image);
        NSData *alpha = Output(image, @[Box(0, 0, 8, 8)]);
        Color(alpha, 0, 0, 64, 0, 0, 64);
        Color(alpha, 7, 7, 64, 0, 0, 64);
        Color(alpha, 20, 20, 0, 0, 0, 0);
        CGImageRelease(image); CGContextRelease(context);
        assert(NSApp == nil);
        puts("PASS mosaic pixels: full-cell color mean, exact region placement, unchanged exterior/dimensions, clipped edge cells, immutable-source overlap and premultiplied alpha; no GUI or clipboard.");
    }
    return 0;
}

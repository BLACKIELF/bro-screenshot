#ifndef TC_PIN_GEOMETRY_H
#define TC_PIN_GEOMETRY_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

// Keep aspect ratio and the point under the pointer; contain skinny images too.
static inline CGRect TCPinZoomFrame(CGRect frame, CGSize imageSize, CGRect visible, CGPoint anchor, double factor) {
    if (frame.size.width <= 0 || frame.size.height <= 0 || visible.size.width <= 0 ||
        visible.size.height <= 0 || !isfinite(imageSize.width) || !isfinite(imageSize.height) ||
        imageSize.width <= 0 || imageSize.height <= 0 || !isfinite(factor) || factor <= 0) return frame;
    // AppKit rounds window sizes. Always derive height from the source image,
    // so rounding in an earlier zoom cannot accumulate or survive a reset.
    double height = frame.size.width * imageSize.height / imageSize.width;
    double maximum = fmin(visible.size.width * 0.95 / frame.size.width,
                          visible.size.height * 0.95 / height);
    double minimum = fmin(maximum, fmax(60.0 / frame.size.width, 60.0 / height));
    factor = fmax(minimum, fmin(maximum, factor));
    double xRatio = fmax(0, fmin(1, (anchor.x - frame.origin.x) / frame.size.width));
    double yRatio = fmax(0, fmin(1, (anchor.y - frame.origin.y) / frame.size.height));
    CGSize size = CGSizeMake(frame.size.width * factor, height * factor);
    CGPoint origin = CGPointMake(anchor.x - xRatio * size.width, anchor.y - yRatio * size.height);
    origin.x = fmax(visible.origin.x, fmin(CGRectGetMaxX(visible) - size.width, origin.x));
    origin.y = fmax(visible.origin.y, fmin(CGRectGetMaxY(visible) - size.height, origin.y));
    return (CGRect){origin, size};
}
#endif

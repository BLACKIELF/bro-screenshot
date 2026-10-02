#include "../TCPinGeometry.h"
#include <assert.h>
#include <stdio.h>

static void contained(CGRect frame, CGRect visible) {
    assert(CGRectGetMinX(frame) >= CGRectGetMinX(visible) - 0.001);
    assert(CGRectGetMinY(frame) >= CGRectGetMinY(visible) - 0.001);
    assert(CGRectGetMaxX(frame) <= CGRectGetMaxX(visible) + 0.001);
    assert(CGRectGetMaxY(frame) <= CGRectGetMaxY(visible) + 0.001);
}
int main(void) {
    CGRect screen = CGRectMake(-1920, 30, 1920, 1050);
    CGRect frame = CGRectMake(-1500, 100, 800, 400);
    CGPoint anchor = CGPointMake(-1300, 200);
    CGRect zoomed = TCPinZoomFrame(frame, CGSizeMake(800, 400), screen, anchor, 1.2);
    contained(zoomed, screen);
    assert(fabs(zoomed.size.width / zoomed.size.height - 2) < 0.0001);
    assert(fabs((anchor.x - zoomed.origin.x) / zoomed.size.width - 0.25) < 0.0001);
    assert(fabs((anchor.y - zoomed.origin.y) / zoomed.size.height - 0.25) < 0.0001);
    CGRect skinny = TCPinZoomFrame(CGRectMake(-2300, 2000, 5, 5000), CGSizeMake(5, 5000), screen, anchor, 1000);
    contained(skinny, screen);
    assert(fabs(skinny.size.width / skinny.size.height - 0.001) < 0.00001);
    assert(CGRectEqualToRect(TCPinZoomFrame(frame, CGSizeMake(800, 400), screen, anchor, NAN), frame));
    assert(CGRectEqualToRect(TCPinZoomFrame(frame, CGSizeMake(800, 400), screen, anchor, -1), frame));
    assert(CGRectEqualToRect(TCPinZoomFrame(frame, CGSizeZero, screen, anchor, 1), frame));
    CGRect rounded = CGRectMake(-1000, 100, 211, 60);
    CGRect reset = TCPinZoomFrame(rounded, CGSizeMake(1200, 340), screen,
                                 CGPointMake(CGRectGetMidX(rounded), CGRectGetMidY(rounded)), 1200.0 / 211.0);
    contained(reset, screen);
    assert(fabs(reset.size.width - 1200) < 0.001 && fabs(reset.size.height - 340) < 0.001);
    for (int i = 0; i < 40; i++) {
        CGRect next = TCPinZoomFrame(rounded, CGSizeMake(1200, 340), screen,
                                    CGPointMake(CGRectGetMidX(rounded), CGRectGetMidY(rounded)), i % 2 ? 1.07 : 0.94);
        assert(fabs(next.size.width / next.size.height - 1200.0 / 340.0) < 0.0001);
        rounded = CGRectMake(round(next.origin.x), round(next.origin.y), round(next.size.width), round(next.size.height));
    }
    puts("PASS pin geometry: source aspect ratio, reset after AppKit rounding, repeated zoom, pointer anchor, skinny image bounds, negative screen origin, invalid input.");
    return 0;
}

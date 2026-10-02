#import <Foundation/Foundation.h>

NSArray<NSString *> *TCRecognizeImageCodes(NSData *data, NSError **error);
NSData *TCRedactImage(NSData *data, NSUInteger *regionCount, NSError **error);
// Normalized bottom-origin boxes for the short recognition helper/editor.
NSArray<NSDictionary *> *TCDetectImageMosaicRegionsDirect(NSData *data, NSError **error);
NSData *TCPixelateImageRegions(NSData *data, NSArray<NSDictionary *> *regions, NSError **error);
NSArray<NSValue *> *TCSensitiveTextRanges(NSString *text);

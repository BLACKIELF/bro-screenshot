#import <Foundation/Foundation.h>

NSArray<NSString *> *TCRecognizeImageCodes(NSData *data, NSError **error);
NSData *TCRedactImage(NSData *data, NSUInteger *regionCount, NSError **error);
NSArray<NSValue *> *TCSensitiveTextRanges(NSString *text);

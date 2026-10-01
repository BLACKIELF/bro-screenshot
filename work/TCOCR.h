#import <Foundation/Foundation.h>
// nil indicates failure; an empty string is a successful request with no text.
NSString *TCRecognizeImageText(NSData *imageData, NSError **error);

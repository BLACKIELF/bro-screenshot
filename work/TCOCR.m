#import "TCOCR.h"
#import "TCImageTranslation.h"

NSString *TCRecognizeImageText(NSData *imageData, NSError **error) {
    if (!imageData.length) {
        if (error) *error = [NSError errorWithDomain:@"TCOCR" code:1 userInfo:@{NSLocalizedDescriptionKey:@"图像数据为空"}];
        return nil;
    }
    NSArray *regions = TCImageTextRegions(imageData, error);
    if (!regions) return nil;
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSDictionary *region in regions) {
        NSString *text = region[@"text"];
        if (text.length) [lines addObject:text];
    }
    return [lines componentsJoinedByString:@"\n"];
}

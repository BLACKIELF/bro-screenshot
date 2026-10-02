#import <Foundation/Foundation.h>
#import "../TCImageTranslation.h"
#include <assert.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2 || argc == 3);
        BOOL mosaic = argc == 3 && !strcmp(argv[2],"--mosaic");
        assert(argc == 2 || mosaic);
        NSString *mode = [NSString stringWithUTF8String:argv[1]];
        NSError *error = nil;
        NSData *input = [(mosaic ? [@"mosaic-" stringByAppendingString:mode] : mode) dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *regions = mosaic ? TCImageMosaicRegions(input, &error) : TCImageTextRegions(input, &error);
        NSInteger calls = [[NSString stringWithContentsOfFile:@"calls" encoding:NSUTF8StringEncoding error:NULL] integerValue];
        if ([mode isEqual:@"retry"]) assert(regions.count == 1 && !error && calls == 2);
        else if ([mode isEqual:@"persistent"]) assert(!regions && error.code == 1 && calls == 2);
        else assert(!regions && error.code == 3 && calls == 1);
        printf("PASS bounded %s recovery: %s, attempts=%ld\n", mosaic ? "mosaic" : "OCR", argv[1], (long)calls);
    }
}

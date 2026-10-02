#import <Foundation/Foundation.h>
#import "TCImageTranslation.h"
#import "TCImageAnalysis.h"
#include <unistd.h>
#include <fcntl.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        pid_t owner = getppid();
        if (owner <= 1) return 125;
        BOOL mosaic = argc == 2 && !strcmp(argv[1], "--mosaic");
        if (argc > 1 && !mosaic) return 64;
        // The screenshot worker owns this short task. A cancelled/dead worker
        // must not leave a recognition process running after it disappears.
        dispatch_source_t guardian = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
        dispatch_source_set_timer(guardian, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, 0);
        dispatch_source_set_event_handler(guardian, ^{ if (getppid() != owner) _exit(125); });
        dispatch_resume(guardian);
        NSMutableData *input = [NSMutableData new];
        NSError *error = nil;
        for (;;) {
            NSData *chunk = [NSFileHandle.fileHandleWithStandardInput readDataOfLength:65536];
            if (!chunk.length) break;
            if (input.length + chunk.length > 256 * 1024 * 1024) {
                error = [NSError errorWithDomain:@"TCImageOCRHelper" code:1
                    userInfo:@{NSLocalizedDescriptionKey:@"截图数据过大，请缩小选区"}]; break;
            }
            [input appendData:chunk];
        }
        NSArray *regions = error ? nil : (mosaic ? TCDetectImageMosaicRegionsDirect(input, &error) : TCImageTextRegionsDirect(input, &error));
        NSDictionary *result = regions ? @{@"regions":regions} :
            @{@"error":@{@"domain":error.domain ?: @"TCImageOCRHelper", @"code":@(error.code),
                @"message":error.localizedDescription ?: @"文字识别失败"}};
        NSData *reply = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
        (void)fcntl(STDOUT_FILENO, F_SETNOSIGPIPE, 1);
        BOOL sent = reply.length && fwrite(reply.bytes, 1, reply.length, stdout) == reply.length;
        fflush(stdout); dispatch_source_cancel(guardian);
        return regions && sent ? 0 : 1;
    }
}

#import "TCOCR.h"
#import <Vision/Vision.h>

NSString *TCRecognizeImageText(NSData *imageData, NSError **error) {
    if (!imageData.length) {
        if (error) *error = [NSError errorWithDomain:@"TCOCR" code:1 userInfo:@{NSLocalizedDescriptionKey:@"图像数据为空"}];
        return nil;
    }
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.recognitionLanguages = @[@"zh-Hans", @"en-US"];
    request.usesLanguageCorrection = YES;
    NSError *requestError = nil;
    if (![[[VNImageRequestHandler alloc] initWithData:imageData options:@{}] performRequests:@[request] error:&requestError]) {
        if (error) *error = requestError ?: [NSError errorWithDomain:@"TCOCR" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Vision 识别请求返回失败，未提供系统错误详情"}];
        return nil;
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (VNRecognizedTextObservation *observation in request.results) {
        NSString *text = [observation topCandidates:1].firstObject.string;
        if (text.length) [lines addObject:text];
    }
    return [lines componentsJoinedByString:@"\n"];
}

#import "SCITrimResult.h"

@implementation SCITrimResult

+ (instancetype)requestWithMode:(SCITrimResultMode)mode
                      sourceURL:(NSURL *)sourceURL
                   startSeconds:(NSTimeInterval)startSeconds
                durationSeconds:(NSTimeInterval)durationSeconds {
    SCITrimResult *result = [[self alloc] init];
    result.mode = mode;
    result.sourceURL = sourceURL;
    result.startSeconds = MAX(0.0, startSeconds);
    result.durationSeconds = MAX(0.0, durationSeconds);
    return result;
}

@end

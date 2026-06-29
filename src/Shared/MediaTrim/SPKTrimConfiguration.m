#import "SPKTrimConfiguration.h"

@implementation SPKTrimDoneOption

+ (instancetype)optionWithTitle:(NSString *)title
                     identifier:(NSString *)identifier
                       iconName:(NSString *)iconName {
    SPKTrimDoneOption *option = [[self alloc] init];
    option.title = title;
    option.identifier = identifier;
    option.iconName = iconName;
    return option;
}

@end

@implementation SPKTrimConfiguration

- (instancetype)init {
    self = [super init];
    if (self) {
        _mediaKind = SPKTrimMediaKindVideo;
        _allowsSingleFrame = YES;
        _minimumDuration = 0.3;
        _title = @"Trim";
    }
    return self;
}

+ (instancetype)configurationWithVideoURL:(NSURL *)videoURL {
    SPKTrimConfiguration *config = [[self alloc] init];
    config.sourceURL = videoURL;
    config.mediaKind = SPKTrimMediaKindVideo;
    return config;
}

@end

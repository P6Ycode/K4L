#import "SCITrimConfiguration.h"

@implementation SCITrimDoneOption

+ (instancetype)optionWithTitle:(NSString *)title
                     identifier:(NSString *)identifier
                       iconName:(NSString *)iconName {
    SCITrimDoneOption *option = [[self alloc] init];
    option.title = title;
    option.identifier = identifier;
    option.iconName = iconName;
    return option;
}

@end

@implementation SCITrimConfiguration

- (instancetype)init {
    self = [super init];
    if (self) {
        _mediaKind = SCITrimMediaKindVideo;
        _allowsSingleFrame = YES;
        _minimumDuration = 0.3;
        _title = @"Trim";
    }
    return self;
}

+ (instancetype)configurationWithVideoURL:(NSURL *)videoURL {
    SCITrimConfiguration *config = [[self alloc] init];
    config.sourceURL = videoURL;
    config.mediaKind = SCITrimMediaKindVideo;
    return config;
}

@end

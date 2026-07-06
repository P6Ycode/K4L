#import "TweakSettings.h"

#import "Topics/SPKAboutSettingsProvider.h"
#import "Topics/SPKDataSettingsProvider.h"
#import "Topics/SPKDownloadsSettingsProvider.h"
#import "Topics/SPKFeedSettingsProvider.h"
#import "Topics/SPKGallerySettingsProvider.h"
#import "Topics/SPKGeneralSettingsProvider.h"
#import "Topics/SPKInstantsSettingsProvider.h"
#import "Topics/SPKInterfaceSettingsProvider.h"
#import "Topics/SPKMessagesSettingsProvider.h"
#import "Topics/SPKProfileAnalyzerSettingsProvider.h"
#import "Topics/SPKProfileSettingsProvider.h"
#import "Topics/SPKReelsSettingsProvider.h"
#import "Topics/SPKStoriesSettingsProvider.h"
#import "Topics/SPKToolsSettingsProvider.h"

@implementation SPKTweakSettings

+ (NSArray *)sections {
    return @[
        @{
            @"header" : @"",
            @"rows" : @[
                [SPKGeneralSettingsProvider rootSetting],
                [SPKInterfaceSettingsProvider rootSetting],
                [SPKFeedSettingsProvider rootSetting],
                [SPKStoriesSettingsProvider rootSetting],
                [SPKReelsSettingsProvider rootSetting],
                [SPKMessagesSettingsProvider rootSetting],
                [SPKInstantsSettingsProvider rootSetting],
                [SPKProfileSettingsProvider rootSetting]
            ]
        },
        @{
            @"header" : @"",
            @"rows" : @[
                [SPKGallerySettingsProvider rootSetting],
                [SPKDownloadsSettingsProvider rootSetting],
                [SPKProfileAnalyzerSettingsProvider rootSetting]
            ]
        },
        @{
            @"header" : @"",
            @"rows" : @[
                [SPKToolsSettingsProvider rootSetting],
                [SPKDataSettingsProvider rootSetting]
            ]
        },
        @{
            @"header" : @"",
            @"rows" : @[
                [SPKAboutSettingsProvider rootSetting]
            ]
        }
    ];
}

+ (NSString *)title {
    return @"Sparkle";
}

@end

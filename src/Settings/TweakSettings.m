#import "TweakSettings.h"

#import "Topics/SCIAboutSettingsProvider.h"
#import "Topics/SCIFeedSettingsProvider.h"
#import "Topics/SCIGeneralSettingsProvider.h"
#import "Topics/SCIInstantsSettingsProvider.h"
#import "Topics/SCIInterfaceSettingsProvider.h"
#import "Topics/SCIGallerySettingsProvider.h"
#import "Topics/SCIDownloadsSettingsProvider.h"
#import "Topics/SCIMessagesSettingsProvider.h"
#import "Topics/SCIProfileSettingsProvider.h"
#import "Topics/SCIProfileAnalyzerSettingsProvider.h"
#import "Topics/SCIReelsSettingsProvider.h"
#import "Topics/SCIStoriesSettingsProvider.h"
#import "Topics/SCIToolsSettingsProvider.h"

@implementation SCITweakSettings

+ (NSArray *)sections {
    return @[
        @{
            @"header": @"",
            @"rows": @[
                [SCIGeneralSettingsProvider rootSetting],
                [SCIInterfaceSettingsProvider rootSetting],
                [SCIFeedSettingsProvider rootSetting],
                [SCIStoriesSettingsProvider rootSetting],
                [SCIReelsSettingsProvider rootSetting],
                [SCIMessagesSettingsProvider rootSetting],
                [SCIInstantsSettingsProvider rootSetting],
                [SCIProfileSettingsProvider rootSetting]
            ]
        },
        @{
            @"header": @"",
            @"rows": @[
                [SCIGallerySettingsProvider rootSetting],
                [SCIDownloadsSettingsProvider rootSetting],
                [SCIProfileAnalyzerSettingsProvider rootSetting]
            ]
        },
        @{
            @"header": @"",
            @"rows": @[
                [SCIToolsSettingsProvider rootSetting]
            ]
        },
        @{
            @"header": @"",
            @"rows": @[
                [SCIAboutSettingsProvider rootSetting]
            ]
        }
    ];
}

+ (NSString *)title {
    return @"SCInsta Settings";
}

+ (NSDictionary *)menus {
    return @{};
}

@end

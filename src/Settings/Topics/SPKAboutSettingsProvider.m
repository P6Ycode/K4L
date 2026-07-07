#import "SPKAboutSettingsProvider.h"

#import "../../AssetUtils.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "../SPKTopicSettingsSupport.h"

@implementation SPKAboutSettingsProvider

+ (SPKSetting *)rootSetting {
    // Larger, bolder title so it reads in balance with the 44pt donate glyph.
    SPKSetting *donate = SPKSettingApplyIconTint([SPKSetting linkCellWithTitle:@"Donate to waffle"
                                                                      subtitle:@""
                                                                          icon:[SPKAssetUtils instagramIconNamed:@"donate" pointSize:44.0]
                                                                           url:@"https://ko-fi.com/sparkle_ig"],
                                                 [SPKUtils SPKColor_InstagramFavorite]);
    donate.userInfo = @{@"titleFont" : [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold]};

    return SPKTopicNavigationSetting(@"About", @"info", 24.0, @[
        SPKTopicSection(@"Support", @[
            donate
        ],
                        @"Consider donating to support the tweak's development."),
        SPKTopicSection(@"Information", @[
            [SPKSetting staticCellWithTitle:@"Sparkle"
                                   subtitle:SPKVersionString
                                       icon:SPKSettingsIcon(@"action")],
            [SPKSetting staticCellWithTitle:@"Instagram"
                                   subtitle:[SPKUtils IGVersionString]
                                       icon:SPKSettingsIcon(@"app")],
            [SPKSetting staticCellWithTitle:@"Bundle ID"
                                   subtitle:[[NSBundle mainBundle] bundleIdentifier]
                                       icon:SPKSettingsIcon(@"key")]
        ],
                        nil),
        SPKTopicSection(@"", @[
            [SPKSetting linkCellWithTitle:@"waffle"
                                 subtitle:@"Sparkle developer"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/117626247?v=4"
                                      url:@"https://github.com/efibalogh"],
            [SPKSetting linkCellWithTitle:@"View Source Code"
                                 subtitle:@"Tap to open on GitHub"
                                 imageUrl:@"https://i.imgur.com/BBUNzeP.png"
                                      url:@"https://github.com/efibalogh/sparkle-ig"]
        ],
                        nil),
        SPKTopicSection(@"Community", @[
            [SPKSetting linkCellWithTitle:@"Telegram Channel"
                                 subtitle:@"Join the community for updates and support"
                                 imageUrl:@"https://upload.wikimedia.org/wikipedia/commons/thumb/8/82/Telegram_logo.svg/960px-Telegram_logo.svg.png"
                                      url:@"https://t.me/sparkle_ig"]
        ],
                        nil),
        SPKTopicSection(@"Credits", @[
            [SPKSetting linkCellWithTitle:@"SoCuul • SCInsta"
                                 subtitle:@"Base project Sparkle is built on"
                                 imageUrl:@"https://i.imgur.com/c9CbytZ.png"
                                      url:@"https://github.com/SoCuul/SCInsta"],
            [SPKSetting linkCellWithTitle:@"Ryuk • RyukGram"
                                 subtitle:@"Code, inspiration, help"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/51106560?v=4"
                                      url:@"https://github.com/faroukbmiled/"],
            [SPKSetting linkCellWithTitle:@"@n3d1117 • InstaSane"
                                 subtitle:@"Following feed mode"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/11541888?v=4"
                                      url:@"https://github.com/n3d1117/InstaSane"],
            [SPKSetting linkCellWithTitle:@"@asdfzxcvbn • zxPluginsInject"
                                 subtitle:@"Fixes for sideloaded installs"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/109937991?v=4"
                                      url:@"https://github.com/asdfzxcvbn/zxPluginsInject"]
        ],
                        nil),
    ]);
}

@end

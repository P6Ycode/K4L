#import "SPKAboutSettingsProvider.h"

#import "../SPKTopicSettingsSupport.h"
#import "../../Tweak.h"
#import "../../Utils.h"

@implementation SPKAboutSettingsProvider

+ (SPKSetting *)rootSetting {
    return SPKTopicNavigationSetting(@"About", @"info", 24.0, @[
        SPKTopicSection(@"Support", @[
            SPKSettingApplyIconTint([SPKSetting linkCellWithTitle:@"Donate to the Original Developer"
                                                         subtitle:@""
                                                             icon:SPKSettingsIcon(@"heart_filled")
                                                              url:@"https://ko-fi.com/SoCuul"],
                                   [SPKUtils SPKColor_InstagramFavorite])
        ], @"Consider donating to support this tweak's development"),
        SPKTopicSection(@"Credits", @[
            [SPKSetting linkCellWithTitle:@"SoCuul"
                                 subtitle:@"Original developer"
                                 imageUrl:@"https://i.imgur.com/c9CbytZ.png"
                                      url:@"https://sparkle.dev"],
            [SPKSetting linkCellWithTitle:@"Edoardo (@n3d1117)"
                                 subtitle:@"Following feed mode"
                                 imageUrl:@"https://avatars.githubusercontent.com/n3d1117"
                                      url:@"https://github.com/n3d1117/InstaSane"],
            [SPKSetting linkCellWithTitle:@"..."
                                 subtitle:@"... developer"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/117626247?v=4"
                                      url:@"https://example.com"],
            [SPKSetting linkCellWithTitle:@"View Source Code"
                                 subtitle:@"Tap to open on GitHub"
                                 imageUrl:@"https://i.imgur.com/BBUNzeP.png"
                                      url:@"https://github.com/efibalogh/sparkle-ig"]
        ], nil),
        SPKTopicSection(@"Information", @[
            [SPKSetting staticCellWithTitle:@"Tweak"
                                   subtitle:SPKVersionString
                                       icon:SPKSettingsIcon(@"action")],
            [SPKSetting staticCellWithTitle:@"Instagram"
                                   subtitle:[SPKUtils IGVersionString]
                                       icon:SPKSettingsIcon(@"app")],
            [SPKSetting staticCellWithTitle:@"Bundle ID"
                                   subtitle:[[NSBundle mainBundle] bundleIdentifier]
                                       icon:SPKSettingsIcon(@"key")]
        ], nil)
    ]);
}

@end

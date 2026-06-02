#import "SCIAboutSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../../Tweak.h"
#import "../../Utils.h"

@implementation SCIAboutSettingsProvider

+ (SCISetting *)rootSetting {
    return SCITopicNavigationSetting(@"About", @"info", 24.0, @[
        SCITopicSection(@"Support", @[
            SCISettingApplyIconTint([SCISetting linkCellWithTitle:@"Donate to the Original Developer"
                                                         subtitle:@""
                                                             icon:SCISettingsIcon(@"heart_filled")
                                                              url:@"https://ko-fi.com/SoCuul"],
                                   [SCIUtils SCIColor_InstagramFavorite])
        ], @"Consider donating to support this tweak's development"),
        SCITopicSection(@"Credits", @[
            [SCISetting linkCellWithTitle:@"SoCuul"
                                 subtitle:@"Original developer"
                                 imageUrl:@"https://i.imgur.com/c9CbytZ.png"
                                      url:@"https://socuul.dev"],
            [SCISetting linkCellWithTitle:@"Edoardo (@n3d1117)"
                                 subtitle:@"Following feed mode (from InstaSane)"
                                 imageUrl:@"https://avatars.githubusercontent.com/n3d1117"
                                      url:@"https://github.com/n3d1117/InstaSane"],
            [SCISetting linkCellWithTitle:@"..."
                                 subtitle:@"... developer"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/117626247?v=4"
                                      url:@"https://example.com"],
            [SCISetting linkCellWithTitle:@"View Source Code"
                                 subtitle:@"Tap to open on GitHub"
                                 imageUrl:@"https://i.imgur.com/BBUNzeP.png"
                                      url:@"https://github.com/efibalogh/SCInsta"]
        ], nil),
        SCITopicSection(@"Information", @[
            [SCISetting staticCellWithTitle:@"Tweak"
                                   subtitle:SCIVersionString
                                       icon:SCISettingsIcon(@"action")],
            [SCISetting staticCellWithTitle:@"Instagram"
                                   subtitle:[SCIUtils IGVersionString]
                                       icon:SCISettingsIcon(@"app")],
            [SCISetting staticCellWithTitle:@"Bundle ID"
                                   subtitle:[[NSBundle mainBundle] bundleIdentifier]
                                       icon:SCISettingsIcon(@"key")]
        ], nil)
    ]);
}

@end

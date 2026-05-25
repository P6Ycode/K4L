#import "SCIInterfaceSettingsProvider.h"
#import "SCINotificationSettingsProvider.h"
#import "../SCITopicSettingsSupport.h"
#import "../../Utils.h"
#import "../../Shared/UI/SCIChrome.h"

@implementation SCIInterfaceSettingsProvider

+ (SCISetting *)experimentalLiquidGlassSetting {
    if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"26.0")) {
        return nil;
    }
    SCISetting *setting = [SCISetting switchCellWithTitle:@"Liquid Glass"
                                                subtitle:@"Force-enable Liquid Glass UI across Instagram"
                                             defaultsKey:@"interface_liquid_glass"
                                          requiresRestart:YES];
    setting.icon = SCISettingsIcon(@"warning_filled");
    setting.userInfo = @{@"deferRestartPrompt": @YES};
    return SCISettingApplyIconTint(setting, [UIColor systemOrangeColor]);
}

+ (SCISetting *)rootSetting {
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        SCITopicSection(@"Notifications", @[
            [SCISetting navigationCellWithTitle:@"Notifications"
                                      subtitle:nil
                                           icon:SCISettingsIcon(@"notification")
                                    navSections:[SCINotificationSettingsProvider sections]]
        ], nil),
        SCITopicSection(@"Tabs", @[
            [SCISetting menuCellWithTitle:@"Tab Icon Order" icon:SCISettingsIcon(@"sort") menu:SCINavigationIconOrderingMenu()],
            [SCISetting menuCellWithTitle:@"Swipe Between Tabs" icon:SCISettingsIcon(@"left_right") menu:SCISwipeBetweenTabsMenu()],
        ], @"Control the order of the tabs:\n"
           @"   - Default: Instagram default\n"
           @"   - Standard: Home, Reels, Messages, Explore, Profile\n"
           @"   - Classic: Messages in the top right corner\n"
           @"   - Alternate: Home and Reels tabs swapped\n"
           @"To get the old layout back, use Classic and disable swiping between tabs."),
        SCITopicSection(@"", @[
            [SCISetting switchCellWithTitle:@"Hide Feed Tab" icon:SCISettingsIcon(@"home") defaultsKey:@"interface_hide_feed_tab" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Hide Explore Tab" icon:SCISettingsIcon(@"search") defaultsKey:@"interface_hide_explore_tab" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Hide Messages Tab" icon:SCISettingsIcon(@"messages") defaultsKey:@"interface_hide_msgs_tab" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Hide Reels Tab" icon:SCISettingsIcon(@"reels") defaultsKey:@"interface_hide_reels_tab" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Hide Create Tab" icon:SCISettingsIcon(@"plus") defaultsKey:@"interface_hide_create_tab" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Hide Profile Tab" icon:SCISettingsIcon(@"user_circle") defaultsKey:@"interface_hide_profile_tab" requiresRestart:YES]
        ], nil),
        SCITopicSection(@"Explore & Search", @[
            [SCISetting switchCellWithTitle:@"Hide Explore Posts Grid" icon:SCISettingsIcon(@"explore_grid") defaultsKey:@"interface_hide_explore_grid"],
            [SCISetting switchCellWithTitle:@"Hide Trending Searches" icon:SCISettingsIcon(@"trending") defaultsKey:@"interface_hide_trending_searches"],
            [SCISetting switchCellWithTitle:@"Open Clipboard Link" icon:SCISettingsIcon(@"link") defaultsKey:@"interface_open_clipboard_link"]
        ], @"1. Hide the grid of suggested posts on the explore tab.\n"
           @"2. Hide the trending searches under the explore search bar.\n"
           @"3. Long press the Explore tab to open the Instagram URL in your clipboard."),
        SCITopicSection(@"Capture", @[
            ({  SCISetting *s = [SCISetting switchCellWithTitle:@"Hide UI on Capture"
                                                          icon:SCISettingsIcon(@"camera")
                                                   defaultsKey:@"interface_hide_ui_on_capture"];
                s.switchChangeHandler = ^(BOOL isOn) {
                    [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:@"interface_hide_ui_on_capture"];
                    [[NSNotificationCenter defaultCenter] postNotificationName:SCIHideUIOnCapturePreferenceDidChangeNotification object:nil];
                };
                s;
            })
        ], @"Redacts SCInsta overlay buttons (action button, seen/mentions buttons, etc.) from screenshots, screen recordings, and mirroring."),
        SCITopicSection(@"Display", @[
            [SCISetting switchCellWithTitle:@"Disable Follow Button HDR"
                                       icon:SCISettingsIcon(@"user_follow")
                                defaultsKey:@"interface_disable_follow_button_edr"
                            requiresRestart:YES]
        ], @"Prevents Instagram follow buttons from using EDR/HDR text in normal layout.")
    ]];

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"26.0")) {
        SCISetting *liquidGlass = [SCISetting switchCellWithTitle:@"Liquid Glass"
                                                         subtitle:@""
                                                      defaultsKey:@"interface_liquid_glass"
                                                  requiresRestart:YES];
        liquidGlass.icon = SCISettingsIcon(@"warning_filled");
        liquidGlass.switchValueProvider = ^BOOL{
            return [SCIUtils getBoolPref:@"interface_liquid_glass"];
        };
        liquidGlass.switchChangeHandler = ^(BOOL isOn) {
            [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:@"interface_liquid_glass"];
            [SCIUtils showRestartConfirmation];
        };
        [sections addObject:SCITopicSection(@"Liquid Glass", @[
            SCISettingApplyIconTint(liquidGlass, [UIColor systemOrangeColor])
        ], @"Force-enable Liquid Glass UI across Instagram.")];
    }

    return SCITopicNavigationSetting(@"Interface", @"interface", 24.0, sections);
}

@end

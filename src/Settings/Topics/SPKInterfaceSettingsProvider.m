#import "SPKInterfaceSettingsProvider.h"
#import "../../Shared/UI/SPKChrome.h"
#import "../../Utils.h"
#import "../SPKPreferenceAvailability.h"
#import "../SPKPreferences.h"
#import "../SPKTopicSettingsSupport.h"
#import "SPKNotificationSettingsProvider.h"

@implementation SPKInterfaceSettingsProvider

+ (SPKSetting *)rootSetting {
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        SPKTopicSection(@"Notifications", @[
            [SPKSetting navigationCellWithTitle:@"Notifications"
                                       subtitle:nil
                                           icon:SPKSettingsIcon(@"notification")
                                    navSections:[SPKNotificationSettingsProvider sections]]
        ],
                        nil),
        SPKTopicSection(@"Tabs", @[
            [SPKSetting menuCellWithTitle:@"Launch Tab"
                                     icon:SPKSettingsIcon(@"home")
                                     menu:SPKLaunchTabMenu()],
            [SPKSetting menuCellWithTitle:@"Tab Icon Order"
                                     icon:SPKSettingsIcon(@"sort")
                                     menu:SPKNavigationIconOrderingMenu()],
            [SPKSetting menuCellWithTitle:@"Swipe Between Tabs"
                                     icon:SPKSettingsIcon(@"left_right")
                                     menu:SPKSwipeBetweenTabsMenu()],
        ],
                        @"Control the order of the tabs:\n"
                        @"   - Default: Instagram default\n"
                        @"   - Standard: Home, Reels, Messages, Explore, Profile\n"
                        @"   - Classic: Messages in the top right corner\n"
                        @"   - Alternate: Home and Reels tabs swapped\n"
                        @"To get the old layout back, use Classic and disable swiping between tabs."),
        SPKTopicSection(@"", @[
            [SPKSetting switchCellWithTitle:@"Hide Feed Tab"
                                       icon:SPKSettingsIcon(@"home")
                                defaultsKey:@"interface_hide_feed_tab"
                            requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Hide Explore Tab"
                                       icon:SPKSettingsIcon(@"search")
                                defaultsKey:@"interface_hide_explore_tab"
                            requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Hide Messages Tab"
                                       icon:SPKSettingsIcon(@"messages")
                                defaultsKey:@"interface_hide_msgs_tab"
                            requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Hide Reels Tab"
                                       icon:SPKSettingsIcon(@"reels")
                                defaultsKey:@"interface_hide_reels_tab"
                            requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Hide Create Tab"
                                       icon:SPKSettingsIcon(@"plus")
                                defaultsKey:@"interface_hide_create_tab"
                            requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Hide Profile Tab"
                                       icon:SPKSettingsIcon(@"user_circle")
                                defaultsKey:@"interface_hide_profile_tab"
                            requiresRestart:YES]
        ],
                        nil),
        SPKTopicSection(@"Explore & Search", @[
            [SPKSetting switchCellWithTitle:@"Hide Explore Posts Grid"
                                       icon:SPKSettingsIcon(@"explore_grid")
                                defaultsKey:@"interface_hide_explore_grid"],
            [SPKSetting switchCellWithTitle:@"Hide Trending Searches"
                                       icon:SPKSettingsIcon(@"trending")
                                defaultsKey:@"interface_hide_trending_searches"],
            [SPKSetting switchCellWithTitle:@"Open Clipboard Link"
                                       icon:SPKSettingsIcon(@"link")
                                defaultsKey:@"interface_open_clipboard_link"]
        ],
                        @"1. Hide the grid of suggested posts on the explore tab.\n"
                        @"2. Hide the trending searches under the explore search bar.\n"
                        @"3. Long press the Explore tab to open the Instagram URL in your clipboard."),
        SPKTopicSection(@"Capture", @[
            ({
                SPKSetting *s = [SPKSetting switchCellWithTitle:@"Hide UI on Capture"
                                                           icon:nil
                                                    defaultsKey:@"interface_hide_ui_on_capture"];
                s.switchChangeHandler = ^(BOOL isOn) {
                    [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:@"interface_hide_ui_on_capture"];
                    [[NSNotificationCenter defaultCenter] postNotificationName:SPKHideUIOnCapturePreferenceDidChangeNotification object:nil];
                };
                s;
            })
        ],
                        @"Redacts Sparkle UI elements from screenshots, screen recordings, and mirroring.")
    ]];

    {
        BOOL liquidGlassAvailable = SPKPrefIsAvailable(kSPKPrefInterfaceLiquidGlass);
        SPKSetting *liquidGlass = [SPKSetting switchCellWithTitle:@"Liquid Glass"
                                                         subtitle:liquidGlassAvailable ? @"" : @"Requires iOS 26 or later"
                                                      defaultsKey:kSPKPrefInterfaceLiquidGlass
                                                  requiresRestart:YES];
        liquidGlass.switchValueProvider = ^BOOL {
            return [SPKUtils getBoolPref:kSPKPrefInterfaceLiquidGlass];
        };
        liquidGlass.switchChangeHandler = ^(BOOL isOn) {
            if (!SPKPrefIsAvailable(kSPKPrefInterfaceLiquidGlass))
                return;
            [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:kSPKPrefInterfaceLiquidGlass];
            [SPKUtils showRestartConfirmation];
        };
        SPKSetting *progressiveBlur = [SPKSetting switchCellWithTitle:@"Progressive Blur"
                                                             subtitle:liquidGlassAvailable ? @"" : @"Requires iOS 26 or later"
                                                          defaultsKey:kSPKPrefInterfaceProgressiveBlur
                                                      requiresRestart:YES];
        SPKSetting *tabBarBehavior = [SPKSetting menuCellWithTitle:@"Tab Bar Behavior"
                                                              icon:nil
                                                              menu:SPKLiquidGlassTabBarStateMenu()];
        tabBarBehavior.defaultsKey = kSPKPrefInterfaceLiquidGlassTabBarMode;
        tabBarBehavior.enabledProvider = ^BOOL {
            return [SPKUtils getBoolPref:kSPKPrefInterfaceLiquidGlass];
        };
        if (!liquidGlassAvailable) {
            liquidGlass.userInfo = @{@"enabled" : @NO};
            progressiveBlur.userInfo = @{@"enabled" : @NO};
        }

        [sections addObject:SPKTopicSection(@"Liquid Glass & Blur", @[
                      liquidGlass,
                      progressiveBlur,
                      tabBarBehavior,
                  ],
                                            @"1. Force-enable Instagram's native Liquid Glass UI.\n"
                                            @"2. Restore the native progressive navigation bar blur on scroll.\n"
                                            @"3. Configure how the tab bar behaves while scrolling.")];
    }

    return SPKTopicNavigationSetting(@"Interface", @"interface", 24.0, sections);
}

@end

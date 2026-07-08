#import "SPKInterfaceSettingsProvider.h"
#import "../../Shared/UI/SPKChrome.h"
#import "../../Utils.h"
#import "../SPKPreferenceAvailability.h"
#import "../SPKPreferences.h"
#import "../SPKTopicSettingsSupport.h"
#import "SPKNotificationSettingsProvider.h"

// The navigable tab keys. The create "+" is a composer launcher rather than a
// destination, so it is excluded — hiding it can never leave the app tab-less.
static NSArray<NSString *> *SPKDestinationTabHideKeys(void) {
    return @[
        @"interface_hide_feed_tab",
        @"interface_hide_explore_tab",
        @"interface_hide_reels_tab",
        @"interface_hide_msgs_tab",
        @"interface_hide_profile_tab",
    ];
}

// YES if turning on `keyToEnable` would leave every navigable tab hidden.
static BOOL SPKEnablingKeyHidesEveryTab(NSString *keyToEnable) {
    for (NSString *key in SPKDestinationTabHideKeys()) {
        if ([key isEqualToString:keyToEnable])
            continue;
        if (![SPKUtils getBoolPref:key])
            return NO;
    }
    return YES;
}

// A "Hide … Tab" switch that can't hide the last remaining navigable tab: when
// this is the only tab still visible its switch is greyed out and can't be
// turned on, while any already-hidden tab can always be turned back on.
static SPKSetting *SPKHideTabSwitch(NSString *title, NSString *iconName, NSString *key) {
    SPKSetting *row = [SPKSetting switchCellWithTitle:title
                                                 icon:SPKSettingsIcon(iconName)
                                          defaultsKey:key
                                      requiresRestart:YES];
    row.switchValueProvider = ^BOOL {
        return [SPKUtils getBoolPref:key];
    };
    row.enabledProvider = ^BOOL {
        if ([SPKUtils getBoolPref:key])
            return YES;
        return !SPKEnablingKeyHidesEveryTab(key);
    };
    // Toggling one tab decides whether its siblings become the "last" visible
    // one, so reload to refresh their greyed state.
    row.reloadsTableOnSwitchChange = YES;
    row.switchChangeHandler = ^(BOOL isOn) {
        [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:SPKEffectivePreferenceKey(key)];
        [SPKUtils showRestartConfirmation];
    };
    return row;
}

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
            SPKHideTabSwitch(@"Hide Feed Tab", @"home", @"interface_hide_feed_tab"),
            SPKHideTabSwitch(@"Hide Explore Tab", @"search", @"interface_hide_explore_tab"),
            ({
                // Classic puts Messages back in the top-right corner instead of the
                // bottom bar (that layout is where the Create "+" becomes a tab), so
                // the "tab" toggle doesn't apply — hide it whenever Create's does show.
                SPKSetting *hideMessagesTab = SPKHideTabSwitch(@"Hide Messages Tab", @"messages", @"interface_hide_msgs_tab");
                hideMessagesTab.hiddenProvider = ^BOOL {
                    return [[SPKUtils getStringPref:@"interface_nav_order"] isEqualToString:@"classic"];
                };
                hideMessagesTab;
            }),
            SPKHideTabSwitch(@"Hide Reels Tab", @"reels", @"interface_hide_reels_tab"),
            ({
                // The create button is only a dedicated tab in the Classic tab
                // order; the other layouts fold it into the composer, so the
                // toggle is meaningless there and is hidden.
                SPKSetting *hideCreateTab = [SPKSetting switchCellWithTitle:@"Hide Create Tab"
                                                                       icon:SPKSettingsIcon(@"plus")
                                                                defaultsKey:@"interface_hide_create_tab"
                                                            requiresRestart:YES];
                hideCreateTab.hiddenProvider = ^BOOL {
                    return ![[SPKUtils getStringPref:@"interface_nav_order"] isEqualToString:@"classic"];
                };
                hideCreateTab;
            }),
            SPKHideTabSwitch(@"Hide Profile Tab", @"user_circle", @"interface_hide_profile_tab")
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

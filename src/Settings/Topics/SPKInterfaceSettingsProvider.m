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

static BOOL SPKIsMessagesOnlyMode(void) {
    BOOL msgsVisible = ![SPKUtils getBoolPref:@"interface_hide_msgs_tab"];
    BOOL feedHidden = [SPKUtils getBoolPref:@"interface_hide_feed_tab"];
    BOOL exploreHidden = [SPKUtils getBoolPref:@"interface_hide_explore_tab"];
    BOOL reelsHidden = [SPKUtils getBoolPref:@"interface_hide_reels_tab"];
    BOOL profileHidden = [SPKUtils getBoolPref:@"interface_hide_profile_tab"];
    
    BOOL usesClassic = [[SPKUtils getStringPref:@"interface_nav_order"] isEqualToString:@"classic"];
    BOOL createHidden = !usesClassic || [SPKUtils getBoolPref:@"interface_hide_create_tab"];
    
    return msgsVisible && feedHidden && exploreHidden && reelsHidden && profileHidden && createHidden;
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
        SPKTopicSection(@"Messages Only Mode", @[
            ({
                SPKSetting *s = [SPKSetting switchCellWithTitle:@"Hide Tab Bar"
                                                           icon:nil
                                                    defaultsKey:@"interface_hide_tab_bar_in_messages_only"];
                s.enabledProvider = ^BOOL {
                    return SPKIsMessagesOnlyMode();
                };
                s;
            }),
            ({
                SPKSetting *s = [SPKSetting switchCellWithTitle:@"Header Shortcut Button"
                                                           icon:nil
                                                    defaultsKey:@"interface_show_header_button_in_messages_only"];
                s.enabledProvider = ^BOOL {
                    return SPKIsMessagesOnlyMode();
                };
                s;
            })
        ],
                        @"These settings are accessible when only the Messages tab is enabled.\n"
                        @"1. Hides the tab bar to free up screen space. Sparkle settings can be accessed via long pressing the right navigation bar button.\n"
                        @"2. Shows the feed header shortcut on the left side of the Messages navigation bar."),
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
        // Tab Bar Behavior is shared by both presentations: it configures the
        // scroll behavior of the (pill/glass) tab bar and is enabled whenever
        // the Liquid Glass pref is on.
        SPKSetting *(^tabBarBehaviorCell)(void) = ^SPKSetting * {
            SPKSetting *tabBarBehavior = [SPKSetting menuCellWithTitle:@"Tab Bar Behavior"
                                                                  icon:nil
                                                                  menu:SPKLiquidGlassTabBarStateMenu()];
            tabBarBehavior.defaultsKey = kSPKPrefInterfaceLiquidGlassTabBarMode;
            tabBarBehavior.enabledProvider = ^BOOL {
                return [SPKUtils getBoolPref:kSPKPrefInterfaceLiquidGlass];
            };
            return tabBarBehavior;
        };

        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"26.0")) {
            // Full Liquid Glass: real glass material, progressive blur, tab bar.
            SPKSetting *liquidGlass = [SPKSetting switchCellWithTitle:@"Liquid Glass"
                                                          defaultsKey:kSPKPrefInterfaceLiquidGlass
                                                      requiresRestart:YES];
            liquidGlass.switchValueProvider = ^BOOL {
                return [SPKUtils getBoolPref:kSPKPrefInterfaceLiquidGlass];
            };
            liquidGlass.switchChangeHandler = ^(BOOL isOn) {
                [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:kSPKPrefInterfaceLiquidGlass];
                [SPKUtils showRestartConfirmation];
            };
            SPKSetting *progressiveBlur = [SPKSetting switchCellWithTitle:@"Progressive Blur"
                                                             defaultsKey:kSPKPrefInterfaceProgressiveBlur
                                                          requiresRestart:YES];

            [sections addObject:SPKTopicSection(@"Liquid Glass & Blur", @[
                          liquidGlass,
                          progressiveBlur,
                          tabBarBehaviorCell(),
                      ],
                                                @"1. Force-enable Instagram's native Liquid Glass UI.\n"
                                                @"2. Restore the native progressive navigation bar blur on scroll.\n"
                                                @"3. Configure how the tab bar behaves while scrolling.")];
        } else {
            // Pre-iOS 26 can't render the glass material, but the same tab bar
            // experiment gates still reshape the bar into the floating pill.
            // Expose that as a focused toggle sharing the Liquid Glass pref.
            SPKSetting *pillTabBar = [SPKSetting switchCellWithTitle:@"Pill-Shaped Tab Bar"
                                                        defaultsKey:kSPKPrefInterfaceLiquidGlass
                                                    requiresRestart:YES];
            pillTabBar.switchValueProvider = ^BOOL {
                return [SPKUtils getBoolPref:kSPKPrefInterfaceLiquidGlass];
            };
            pillTabBar.switchChangeHandler = ^(BOOL isOn) {
                [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:kSPKPrefInterfaceLiquidGlass];
                [SPKUtils showRestartConfirmation];
            };

            [sections addObject:SPKTopicSection(@"Tab Bar", @[
                          pillTabBar,
                          tabBarBehaviorCell(),
                      ],
                                                @"Reshape the tab bar into the iOS 26-style floating pill. "
                                                @"The Liquid Glass material itself requires iOS 26, so on this "
                                                @"device only the pill shape is applied.")];
        }
    }

    return SPKTopicNavigationSetting(@"Interface", @"interface", 24.0, sections);
}

@end

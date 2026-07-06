#import "SPKReelsSettingsProvider.h"

#import "../../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../SPKTopicSettingsSupport.h"

static NSString *const kSPKReelsActionButtonEnabledKey = @"reels_action_btn";

@implementation SPKReelsSettingsProvider

+ (SPKSetting *)rootSetting {
    return SPKTopicNavigationSetting(@"Reels", @"reels", 24.0, @[
        SPKTopicSection(@"Action Button", @[
            [SPKSetting switchCellWithTitle:@"Reels Action Button"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:kSPKReelsActionButtonEnabledKey],
            SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSourceReels),
            SPKActionButtonConfigurationNavigationSetting(SPKActionButtonSourceReels, @"Reels", SPKActionButtonSupportedActionsForSource(SPKActionButtonSourceReels), SPKActionButtonDefaultSectionsForSource(SPKActionButtonSourceReels))
        ],
                        @"Choose what tapping the action button does. Long press opens the full menu."),
        SPKTopicSection(@"Behavior", @[
            [SPKSetting menuCellWithTitle:@"Tap Controls"
                                     icon:SPKSettingsIcon(@"play")
                                     menu:SPKReelsTapControlMenu()],
            [SPKSetting switchCellWithTitle:@"Show Progress Scrubber"
                                       icon:SPKSettingsIcon(@"clock")
                                defaultsKey:@"reels_show_scrubber"],
            [SPKSetting switchCellWithTitle:@"Disable Auto-Unmuting Reels"
                                       icon:SPKSettingsIcon(@"volume_off")
                                defaultsKey:@"reels_disable_auto_unmute"
                            requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Disable Reels Tab Refresh"
                                       icon:SPKSettingsIcon(@"arrow_cw")
                                defaultsKey:@"reels_disable_tab_refresh"]
        ],
                        @"Tap Controls changes what happens when you tap on a reel. Auto-unmuting controls prevent reels from unmuting when volume or silent mode changes."),
        SPKTopicSection(@"Limits", @[
            [SPKSetting switchCellWithTitle:@"Disable Scrolling Reels"
                                       icon:SPKSettingsIcon(@"autoscroll")
                                defaultsKey:@"reels_disable_scrolling"
                            requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Prevent Doom Scrolling"
                                       icon:SPKSettingsIcon(@"arrow_down")
                                defaultsKey:@"reels_prevent_doom_scroll"],
            [SPKSetting stepperCellWithTitle:@"Doom Scrolling Limit"
                                    subtitle:@"Only loads %@ %@"
                                 defaultsKey:@"reels_doom_scroll_limit"
                                         min:1
                                         max:100
                                        step:1
                                       label:@"reels"
                               singularLabel:@"reel"]
        ],
                        nil),
        SPKTopicSection(@"Layout", @[
            [SPKSetting switchCellWithTitle:@"Hide Reels Header"
                                       icon:SPKSettingsIcon(@"reels")
                                defaultsKey:@"reels_hide_header"],
            [SPKSetting switchCellWithTitle:@"Hide Repost Button"
                                       icon:SPKSettingsIcon(@"repost")
                                defaultsKey:@"reels_hide_repost_btn"
                            requiresRestart:YES]
        ],
                        nil),
        SPKTopicSection(@"Metrics", @[
            [SPKSetting switchCellWithTitle:@"Hide Like Count"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"reels_hide_like_count"],
            [SPKSetting switchCellWithTitle:@"Hide Comment Count"
                                       icon:SPKSettingsIcon(@"comment")
                                defaultsKey:@"reels_hide_comment_count"],
            [SPKSetting switchCellWithTitle:@"Hide Repost Count"
                                       icon:SPKSettingsIcon(@"repost")
                                defaultsKey:@"reels_hide_repost_count"],
            [SPKSetting switchCellWithTitle:@"Hide Reshare Count"
                                       icon:SPKSettingsIcon(@"messages")
                                defaultsKey:@"reels_hide_reshare_count"],
            [SPKSetting switchCellWithTitle:@"Hide Save Count"
                                       icon:SPKSettingsIcon(@"save")
                                defaultsKey:@"reels_hide_save_count"]
        ],
                        nil),
        SPKTopicSection(@"Confirmation", @[
            [SPKSetting switchCellWithTitle:@"Confirm Like"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"reels_confirm_like"],
            [SPKSetting switchCellWithTitle:@"Confirm Double Tap"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"reels_confirm_double_tap_like"],
            [SPKSetting switchCellWithTitle:@"Confirm Reel Refresh"
                                       icon:SPKSettingsIcon(@"arrow_cw")
                                defaultsKey:@"reels_confirm_refresh"],
            [SPKSetting switchCellWithTitle:@"Confirm Repost"
                                       icon:SPKSettingsIcon(@"repost")
                                defaultsKey:@"reels_confirm_repost"]
        ],
                        @"Shows confirmation alerts before the enabled reels actions are performed.")
    ]);
}

@end

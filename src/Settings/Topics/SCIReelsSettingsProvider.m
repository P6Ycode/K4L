#import "SCIReelsSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"

static NSString * const kSCIReelsActionButtonEnabledKey = @"reels_action_btn";

@implementation SCIReelsSettingsProvider

+ (SCISetting *)rootSetting {
    return SCITopicNavigationSetting(@"Reels", @"reels", 24.0, @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Reels Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIReelsActionButtonEnabledKey],
            SCIActionButtonDefaultActionNavigationSetting(SCIActionButtonSourceReels),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceReels, @"Reels", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceReels), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceReels))
        ], @"Choose what tapping the action button does. Long press opens the full menu."),
        SCITopicSection(@"Behavior", @[
            [SCISetting menuCellWithTitle:@"Tap Controls" icon:SCISettingsIcon(@"play") menu:SCIReelsTapControlMenu()],
            [SCISetting switchCellWithTitle:@"Show Progress Scrubber" icon:SCISettingsIcon(@"clock") defaultsKey:@"reels_show_scrubber"],
            [SCISetting switchCellWithTitle:@"Disable Auto-Unmuting Reels" icon:SCISettingsIcon(@"volume_off") defaultsKey:@"reels_disable_auto_unmute" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Disable Reels Tab Refresh" icon:SCISettingsIcon(@"arrow_cw") defaultsKey:@"reels_disable_tab_refresh"]
        ], @"Tap Controls changes what happens when you tap on a reel. Auto-unmuting controls prevent reels from unmuting when volume or silent mode changes."),
        SCITopicSection(@"Limits", @[
            [SCISetting switchCellWithTitle:@"Disable Scrolling Reels" icon:SCISettingsIcon(@"autoscroll") defaultsKey:@"reels_disable_scrolling" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Prevent Doom Scrolling" icon:SCISettingsIcon(@"arrow_down") defaultsKey:@"reels_prevent_doom_scroll"],
            [SCISetting stepperCellWithTitle:@"Doom Scrolling Limit" subtitle:@"Only loads %@ %@" defaultsKey:@"reels_doom_scroll_limit" min:1 max:100 step:1 label:@"reels" singularLabel:@"reel"]
        ], nil),
        SCITopicSection(@"Layout", @[
            [SCISetting switchCellWithTitle:@"Hide Reels Header" icon:SCISettingsIcon(@"reels") defaultsKey:@"reels_hide_header"],
            [SCISetting switchCellWithTitle:@"Hide Repost Button" icon:SCISettingsIcon(@"repost") defaultsKey:@"reels_hide_repost_btn" requiresRestart:YES]
        ], nil),
        SCITopicSection(@"Metrics", @[
            [SCISetting switchCellWithTitle:@"Hide Like Count" icon:SCISettingsIcon(@"heart") defaultsKey:@"reels_hide_like_count"],
            [SCISetting switchCellWithTitle:@"Hide Comment Count" icon:SCISettingsIcon(@"comment") defaultsKey:@"reels_hide_comment_count"],
            [SCISetting switchCellWithTitle:@"Hide Repost Count" icon:SCISettingsIcon(@"repost") defaultsKey:@"reels_hide_repost_count"],
            [SCISetting switchCellWithTitle:@"Hide Reshare Count" icon:SCISettingsIcon(@"messages") defaultsKey:@"reels_hide_reshare_count"],
            [SCISetting switchCellWithTitle:@"Hide Save Count" icon:SCISettingsIcon(@"save") defaultsKey:@"reels_hide_save_count"]
        ], nil),
        SCITopicSection(@"Confirmation", @[
            [SCISetting switchCellWithTitle:@"Confirm Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"reels_confirm_like"],
            [SCISetting switchCellWithTitle:@"Confirm Double Tap" icon:SCISettingsIcon(@"heart") defaultsKey:@"reels_confirm_double_tap_like"],
            [SCISetting switchCellWithTitle:@"Confirm Reel Refresh" icon:SCISettingsIcon(@"arrow_cw") defaultsKey:@"reels_confirm_refresh"],
            [SCISetting switchCellWithTitle:@"Confirm Repost" icon:SCISettingsIcon(@"repost") defaultsKey:@"reels_confirm_repost"]
        ], @"Shows confirmation alerts before the enabled reels actions are performed.")
    ]);
}

@end

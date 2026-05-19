#import "SCIReelsSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"

static NSString * const kSCIReelsActionButtonEnabledKey = @"action_button_reels_enabled";
static NSString * const kSCIReelsActionButtonDefaultActionKey = @"action_button_reels_default_action";

@implementation SCIReelsSettingsProvider

+ (SCISetting *)rootSetting {
    return SCITopicNavigationSetting(@"Reels", @"reels", 24.0, @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Reels Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIReelsActionButtonEnabledKey],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Default Tap Action" icon:SCISettingsIcon(@"action") menu:SCIActionButtonDefaultActionMenu(kSCIReelsActionButtonDefaultActionKey, @"Reels", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceReels))], SCISettingsIcon(@"action")),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceReels, @"Reels", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceReels), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceReels))
        ], @"Choose what tapping the action button does. Long press opens the full menu."),
        SCITopicSection(@"Behavior", @[
            [SCISetting menuCellWithTitle:@"Tap Controls" icon:SCISettingsIcon(@"play") menu:SCIReelsTapControlMenu()],
            [SCISetting switchCellWithTitle:@"Show Progress Scrubber" icon:SCISettingsIcon(@"clock") defaultsKey:@"reels_show_scrubber"],
            [SCISetting switchCellWithTitle:@"Disable Auto-Unmuting Reels" icon:SCISettingsIcon(@"volume_off") defaultsKey:@"disable_auto_unmuting_reels" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Disable Reels Tab Refresh" icon:SCISettingsIcon(@"arrow_cw") defaultsKey:@"disable_reels_tab_refresh"]
        ], @"Tap Controls changes what happens when you tap on a reel. Auto-unmuting controls prevent reels from unmuting when volume or silent mode changes."),
        SCITopicSection(@"Limits", @[
            [SCISetting switchCellWithTitle:@"Disable Scrolling Reels" icon:SCISettingsIcon(@"autoscroll") defaultsKey:@"disable_scrolling_reels" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Prevent Doom Scrolling" icon:SCISettingsIcon(@"arrow_down") defaultsKey:@"prevent_doom_scrolling"],
            [SCISetting stepperCellWithTitle:@"Doom Scrolling Limit" subtitle:@"Only loads %@ %@" defaultsKey:@"doom_scrolling_reel_count" min:1 max:100 step:1 label:@"reels" singularLabel:@"reel"]
        ], nil),
        SCITopicSection(@"Layout", @[
            [SCISetting switchCellWithTitle:@"Hide Reels Header" icon:SCISettingsIcon(@"reels") defaultsKey:@"hide_reels_header"],
            [SCISetting switchCellWithTitle:@"Hide Repost Button" icon:SCISettingsIcon(@"repost") defaultsKey:@"hide_repost_button_reels" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Hide Suggested Accounts" icon:SCISettingsIcon(@"users") defaultsKey:@"hide_suggested_users_reels"]
        ], nil),
        SCITopicSection(@"Metrics", @[
            [SCISetting switchCellWithTitle:@"Hide Like Count" icon:SCISettingsIcon(@"heart") defaultsKey:@"hide_reels_like_count"],
            [SCISetting switchCellWithTitle:@"Hide Comment Count" icon:SCISettingsIcon(@"comment") defaultsKey:@"hide_reels_comment_count"],
            [SCISetting switchCellWithTitle:@"Hide Repost Count" icon:SCISettingsIcon(@"repost") defaultsKey:@"hide_reels_repost_count"],
            [SCISetting switchCellWithTitle:@"Hide Reshare Count" icon:SCISettingsIcon(@"messages") defaultsKey:@"hide_reels_reshare_count"],
            [SCISetting switchCellWithTitle:@"Hide Save Count" icon:SCISettingsIcon(@"save") defaultsKey:@"hide_reels_save_count"]
        ], nil),
        SCITopicSection(@"Confirmation", @[
            [SCISetting switchCellWithTitle:@"Confirm Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"like_confirm_reels"],
            [SCISetting switchCellWithTitle:@"Confirm Double Tap" icon:SCISettingsIcon(@"heart") defaultsKey:@"like_confirm_reels_double_tap"],
            [SCISetting switchCellWithTitle:@"Confirm Reel Refresh" icon:SCISettingsIcon(@"arrow_cw") defaultsKey:@"refresh_reel_confirm"],
            [SCISetting switchCellWithTitle:@"Confirm Repost" icon:SCISettingsIcon(@"repost") defaultsKey:@"repost_confirm_reels"]
        ], @"Shows confirmation alerts before the enabled reels actions are performed.")
    ]);
}

@end

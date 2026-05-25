#import "SCIFeedSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"

static NSString * const kSCIFeedActionButtonEnabledKey = @"feed_action_btn";
static NSString * const kSCIFeedActionButtonDefaultActionKey = @"feed_action_btn_default_action";

@implementation SCIFeedSettingsProvider

+ (SCISetting *)rootSetting {
    return SCITopicNavigationSetting(@"Feed", @"feed", 24.0, @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Feed Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIFeedActionButtonEnabledKey],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Default Tap Action" icon:SCISettingsIcon(@"action") menu:SCIActionButtonDefaultActionMenu(kSCIFeedActionButtonDefaultActionKey, @"Feed", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceFeed))], SCISettingsIcon(@"action")),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceFeed, @"Feed", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceFeed), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceFeed))
        ], @"Choose what tapping the action button does. Long press opens the full menu."),
        SCITopicSection(@"Layout", @[
            [SCISetting switchCellWithTitle:@"Hide Stories Tray" icon:SCISettingsIcon(@"story") defaultsKey:@"feed_hide_stories_tray"],
            [SCISetting switchCellWithTitle:@"Hide Entire Feed" icon:SCISettingsIcon(@"feed") defaultsKey:@"feed_hide_entire_feed"],
            [SCISetting switchCellWithTitle:@"Hide Suggested Posts" icon:SCISettingsIcon(@"carousel") defaultsKey:@"feed_hide_suggested_posts"],
            [SCISetting switchCellWithTitle:@"Hide Suggested Accounts" icon:SCISettingsIcon(@"users") defaultsKey:@"general_hide_suggested_users_feed"],
            [SCISetting switchCellWithTitle:@"Hide Suggested Reels" icon:SCISettingsIcon(@"reels_gallery") defaultsKey:@"feed_hide_suggested_reels"],
            [SCISetting switchCellWithTitle:@"Hide Suggested Threads" icon:SCISettingsIcon(@"threads") defaultsKey:@"feed_hide_suggested_threads"],
            [SCISetting switchCellWithTitle:@"Hide Repost Button" icon:SCISettingsIcon(@"repost") defaultsKey:@"feed_hide_repost_btn" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Hide Metrics" icon:SCISettingsIcon(@"info") defaultsKey:@"feed_hide_metrics"]
        ], nil),
        SCITopicSection(@"Media", @[
            [SCISetting switchCellWithTitle:@"Long Press to Expand" icon:SCISettingsIcon(@"expand") defaultsKey:@"feed_long_press_expand"],
            [SCISetting switchCellWithTitle:@"Disable Video Autoplay" icon:SCISettingsIcon(@"autoplay_off") defaultsKey:@"feed_disable_autoplay" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Start Expanded Videos Muted" icon:SCISettingsIcon(@"volume_off") defaultsKey:@"feed_expanded_vid_start_muted"],
        ], @"Long press media in the feed to open it expanded. Autoplay controls prevent feed videos from playing automatically."),
        SCITopicSection(@"Refresh", @[
            [SCISetting switchCellWithTitle:@"Disable Home Tab Refresh" icon:SCISettingsIcon(@"home") defaultsKey:@"feed_disable_home_refresh"],
            [SCISetting switchCellWithTitle:@"Disable Background Refresh" icon:SCISettingsIcon(@"arrow_cw") defaultsKey:@"feed_disable_bg_refresh"]
        ], @"Prevents refreshes from re-tapping the Home tab or from background app activity."),
        SCITopicSection(@"Confirmation", @[
            [SCISetting switchCellWithTitle:@"Confirm Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"feed_confirm_post_like"],
            [SCISetting switchCellWithTitle:@"Confirm Double-Tap Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"feed_confirm_double_tap_like"],
            [SCISetting switchCellWithTitle:@"Confirm Repost" icon:SCISettingsIcon(@"repost") defaultsKey:@"feed_confirm_repost"],
            [SCISetting switchCellWithTitle:@"Confirm Posting Comment" icon:SCISettingsIcon(@"comment") defaultsKey:@"feed_confirm_post_comment"]
        ], @"Shows confirmation alerts before the enabled feed actions are performed."),
        SCITopicSection(@"Comments", @[
            [SCISetting switchCellWithTitle:@"Swipe to Close Comments" icon:SCISettingsIcon(@"left_right") defaultsKey:@"feed_comments_swipe_close"],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Swipe Direction" icon:SCISettingsIcon(@"left_right") menu:SCISwipeCloseCommentsDirectionMenu()], SCISettingsIcon(@"left_right")),
            [SCISetting switchCellWithTitle:@"Confirm Comment Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"feed_confirm_comment_like"],
            [SCISetting switchCellWithTitle:@"Hide Comment Shopping" icon:SCISettingsIcon(@"shopping_bag") defaultsKey:@"feed_hide_comment_shopping"]
        ], @"Swipe to Close Comments adds horizontal swipe gestures to comment sheets. Hide Comment Shopping removes commerce carousels in comment threads.")
    ]);
}

@end

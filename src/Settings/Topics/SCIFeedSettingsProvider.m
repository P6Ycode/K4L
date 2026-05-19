#import "SCIFeedSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"

static NSString * const kSCIFeedActionButtonEnabledKey = @"action_button_feed_enabled";
static NSString * const kSCIFeedActionButtonDefaultActionKey = @"action_button_feed_default_action";

@implementation SCIFeedSettingsProvider

+ (SCISetting *)rootSetting {
    return SCITopicNavigationSetting(@"Feed", @"feed", 24.0, @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Feed Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIFeedActionButtonEnabledKey],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Default Tap Action" icon:SCISettingsIcon(@"action") menu:SCIActionButtonDefaultActionMenu(kSCIFeedActionButtonDefaultActionKey, @"Feed", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceFeed))], SCISettingsIcon(@"action")),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceFeed, @"Feed", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceFeed), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceFeed))
        ], @"Choose what tapping the action button does. Long press opens the full menu."),
        SCITopicSection(@"Layout", @[
            [SCISetting switchCellWithTitle:@"Hide Stories Tray" icon:SCISettingsIcon(@"story") defaultsKey:@"hide_stories_tray"],
            [SCISetting switchCellWithTitle:@"Hide Entire Feed" icon:SCISettingsIcon(@"feed") defaultsKey:@"hide_entire_feed"],
            [SCISetting switchCellWithTitle:@"Hide Suggested Posts" icon:SCISettingsIcon(@"carousel") defaultsKey:@"no_suggested_post"],
            [SCISetting switchCellWithTitle:@"Hide Suggested Accounts" icon:SCISettingsIcon(@"users") defaultsKey:@"hide_suggested_users_feed"],
            [SCISetting switchCellWithTitle:@"Hide Suggested Reels" icon:SCISettingsIcon(@"reels_gallery") defaultsKey:@"no_suggested_reels"],
            [SCISetting switchCellWithTitle:@"Hide Suggested Threads" icon:SCISettingsIcon(@"threads") defaultsKey:@"no_suggested_threads"],
            [SCISetting switchCellWithTitle:@"Hide Repost Button" icon:SCISettingsIcon(@"repost") defaultsKey:@"hide_repost_button_feed" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Hide Metrics" icon:SCISettingsIcon(@"info") defaultsKey:@"hide_metrics"]
        ], nil),
        SCITopicSection(@"Media", @[
            [SCISetting switchCellWithTitle:@"Long Press to Expand" icon:SCISettingsIcon(@"expand") defaultsKey:@"enable_long_press_expand"],
            [SCISetting switchCellWithTitle:@"Disable Video Autoplay" icon:SCISettingsIcon(@"autoplay_off") defaultsKey:@"disable_feed_autoplay" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Start Expanded Videos Muted" icon:SCISettingsIcon(@"volume_off") defaultsKey:@"expanded_video_start_muted"],
        ], @"Long press media in the feed to open it expanded. Autoplay controls prevent feed videos from playing automatically."),
        SCITopicSection(@"Refresh", @[
            [SCISetting switchCellWithTitle:@"Disable Home Tab Refresh" icon:SCISettingsIcon(@"home") defaultsKey:@"disable_home_button_refresh"],
            [SCISetting switchCellWithTitle:@"Disable Background Refresh" icon:SCISettingsIcon(@"arrow_cw") defaultsKey:@"disable_bg_refresh"]
        ], @"Prevents refreshes from re-tapping the Home tab or from background app activity."),
        SCITopicSection(@"Confirmation", @[
            [SCISetting switchCellWithTitle:@"Confirm Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"like_confirm_feed_post_likes"],
            [SCISetting switchCellWithTitle:@"Confirm Double-Tap Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"like_confirm_feed_double_tap_likes"],
            [SCISetting switchCellWithTitle:@"Confirm Repost" icon:SCISettingsIcon(@"repost") defaultsKey:@"repost_confirm_feed"],
            [SCISetting switchCellWithTitle:@"Confirm Posting Comment" icon:SCISettingsIcon(@"comment") defaultsKey:@"post_comment_confirm"]
        ], @"Shows confirmation alerts before the enabled feed actions are performed."),
        SCITopicSection(@"Comments", @[
            [SCISetting switchCellWithTitle:@"Confirm Comment Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"like_confirm_comment_likes"],
            [SCISetting switchCellWithTitle:@"Hide Comment Shopping" icon:SCISettingsIcon(@"shopping_bag") defaultsKey:@"hide_comment_commerce_carousel"]
        ], @"Hide Comment Shopping removes commerce carousels in comment threads.")
    ]);
}

@end

#import "SCIGeneralSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../../Shared/MediaDownload/SCIMediaFFmpeg.h"
#import "../../Shared/MediaDownload/SCIMediaQualityManager.h"
#import "../../Utils.h"

@implementation SCIGeneralSettingsProvider

+ (SCISetting *)rootSetting {
    BOOL ffmpegAvailable = [SCIMediaFFmpeg isAvailable];
    if (!ffmpegAvailable) {
        [[NSUserDefaults standardUserDefaults] setObject:@"high_ignore_dash" forKey:@"media_video_quality_default"];
    }

    SCISetting *videoQualitySetting = [SCISetting menuCellWithTitle:@"Default Video Quality"
                                                           subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                               icon:SCISettingsIcon(@"video")
                                                               menu:SCIMediaVideoQualityMenu()];
    videoQualitySetting.userInfo = @{@"enabled": @(ffmpegAvailable)};

    SCISetting *encodingSettings = [SCISetting navigationCellWithTitle:@"Encoding Settings"
                                                              subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                                  icon:SCISettingsIcon(@"settings")
                                                        viewController:[SCIMediaQualityManager encodingSettingsViewController]];
    encodingSettings.userInfo = @{@"enabled": @(ffmpegAvailable)};

    SCISetting *encodingLogs = [SCISetting navigationCellWithTitle:@"View Encoding Logs"
                                                          subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                              icon:SCISettingsIcon(@"logs")
                                                    viewController:[SCIMediaFFmpeg logsViewController]];
    encodingLogs.userInfo = @{@"enabled": @(ffmpegAvailable)};

    NSString *qualityFooter = ffmpegAvailable ? @"\"High\" merges DASH files for best quality. \"High (Ignore Dash)\" uses ready-to-play files. \"Always Ask\" prompts for selection." : @"FFmpegKit is required for video quality options and encoding features.";

    return SCITopicNavigationSetting(@"General", @"settings", 24.0, @[
        SCITopicSection(@"Behavior", @[
            [SCISetting switchCellWithTitle:@"Copy Text" icon:SCISettingsIcon(@"text") defaultsKey:@"copy_description"],
            [SCISetting switchCellWithTitle:@"No Recent Searches" icon:SCISettingsIcon(@"search") defaultsKey:@"no_recent_searches"],
            [SCISetting switchCellWithTitle:@"Copy Links Without Tracking" icon:SCISettingsIcon(@"user_unfollow") defaultsKey:@"remove_user_from_copied_share_link"],
            [SCISetting switchCellWithTitle:@"Hold Send to Copy Link" icon:SCISettingsIcon(@"link") defaultsKey:@"share_button_long_press_copy_link"],
        ], @"1. Long press on text fields across the app to copy.\n"
           @"2. Search bars will no longer save recent searches.\n"
           @"3. Remove the user and tracking identifiers from copied links.\n"
           @"4. Long press the send/share button to copy the post link."),
        SCITopicSection(@"Group", @[
            [SCISetting switchCellWithTitle:@"Hide Create Group Button" icon:SCISettingsIcon(@"group") defaultsKey:@"hide_create_group_button"],
            [SCISetting switchCellWithTitle:@"Confirm Create Group" icon:SCISettingsIcon(@"group") defaultsKey:@"confirm_create_group_button"],
        ], @"1. Hide the create group button from the Instagram send/share sheet.\n"
           @"2. Show a confirmation alert when you try to create a group."),
        SCITopicSection(@"Recommendations", @[
            [SCISetting navigationCellWithTitle:@"Ads"
                                       subtitle:@""
                                           icon:SCISettingsIcon(@"ads")
                                    navSections:@[
                SCITopicSection(@"Ads", @[
                    [SCISetting switchCellWithTitle:@"Hide Feed Ads" defaultsKey:@"hide_ads_feed"],
                    [SCISetting switchCellWithTitle:@"Hide Story Ads" defaultsKey:@"hide_ads_stories"],
                    [SCISetting switchCellWithTitle:@"Hide Reels Ads" defaultsKey:@"hide_ads_reels"],
                    [SCISetting switchCellWithTitle:@"Hide Explore Ads" defaultsKey:@"hide_ads_explore"],
                    [SCISetting switchCellWithTitle:@"Hide Reels Shopping CTA" defaultsKey:@"hide_reels_shopping_cta"]
                ], nil)
            ]],
            [SCISetting navigationCellWithTitle:@"Meta AI"
                                       subtitle:@""
                                           icon:SCISettingsIcon(@"meta_ai")
                                    navSections:@[
                SCITopicSection(@"", @[
                    [SCISetting switchCellWithTitle:@"Hide in Direct" defaultsKey:@"hide_meta_ai_direct"],
                    [SCISetting switchCellWithTitle:@"Hide in Explore & Search" defaultsKey:@"hide_meta_ai_explore"],
                    [SCISetting switchCellWithTitle:@"Hide in Comments" defaultsKey:@"hide_meta_ai_comments"],
                    [SCISetting switchCellWithTitle:@"Hide in Creation Tools" defaultsKey:@"hide_meta_ai_creation"],
                    [SCISetting switchCellWithTitle:@"Hide Global AI Chrome" defaultsKey:@"hide_meta_ai_global"]
                ], @"Direct includes inbox, composer, recipients, themes, and message menus. Global chrome covers generic Meta AI buttons, placeholders, and branded entry points.")
            ]],
            [SCISetting navigationCellWithTitle:@"Suggested Users"
                                       subtitle:@""
                                           icon:SCISettingsIcon(@"users")
                                    navSections:@[
                SCITopicSection(@"Suggested Users", @[
                    [SCISetting switchCellWithTitle:@"Hide Feed Suggestions" defaultsKey:@"hide_suggested_users_feed"],
                    [SCISetting switchCellWithTitle:@"Hide Reels Suggestions" defaultsKey:@"hide_suggested_users_reels"],
                    [SCISetting switchCellWithTitle:@"Hide Direct Suggestions" defaultsKey:@"hide_suggested_users_direct"],
                    [SCISetting switchCellWithTitle:@"Hide Search Suggestions" defaultsKey:@"hide_suggested_users_search"],
                    [SCISetting switchCellWithTitle:@"Hide Profile Suggestions" defaultsKey:@"hide_suggested_users_profile"],
                    [SCISetting switchCellWithTitle:@"Hide Activity Suggestions" defaultsKey:@"hide_suggested_users_activity"],
                    [SCISetting switchCellWithTitle:@"Hide Follow-List Suggestions" defaultsKey:@"hide_suggested_users_follow_lists"],
                    [SCISetting switchCellWithTitle:@"Hide Subscription Suggestions" defaultsKey:@"hide_suggested_users_subscriptions"]
                ], nil)
            ]]
        ], @"Control ads, AI and suggestions visibility by surface."),
        SCITopicSection(@"Media Saving", @[
            [SCISetting switchCellWithTitle:@"Enhanced Media Resolution" icon:SCISettingsIcon(@"hd") defaultsKey:@"enhanced_media_resolution"],
            [SCISetting menuCellWithTitle:@"Default Photo Quality" icon:SCISettingsIcon(@"photo") menu:SCIMediaPhotoQualityMenu()],
            videoQualitySetting,
            encodingSettings,
            encodingLogs
        ], qualityFooter),
        SCITopicSection(@"Storage", @[
            [SCISetting buttonCellWithTitle:@"Clear Cache" subtitle:@"" icon:SCISettingsIcon(@"trash") action:^(void) {
                [SCIUtils cleanCache];
                SCINotify(kSCINotificationSettingsClearCache, @"Cache cleared", nil, @"circle_check_filled", SCINotificationToneForIconResource(@"circle_check_filled"));
            }],
            [SCISetting menuCellWithTitle:@"Auto Clear Cache" icon:SCISettingsIcon(@"clock") menu:SCICacheAutoClearMenu()]
        ], @"Automatic clearing is checked whenever Instagram becomes active."),
        SCITopicSection(@"App", @[
            [SCISetting switchCellWithTitle:@"Change App Icon" icon:SCISettingsIcon(@"app") defaultsKey:@"teen_app_icons" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Disable App Haptics" icon:SCISettingsIcon(@"haptics") defaultsKey:@"disable_haptics"]
        ], @"1. Hold down on the Instagram text on the home screen to bring up the app icon selection menu.\n"
           @"2. Disables haptics and vibrations within the app."),
    ]);
}

@end

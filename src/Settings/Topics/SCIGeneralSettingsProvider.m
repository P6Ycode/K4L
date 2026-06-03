#import "SCIGeneralSettingsProvider.h"

#import "../SCIAppIconCatalog.h"
#import "../SCIAppIconPickerViewController.h"
#import "../SCITopicSettingsSupport.h"
#import "../../Shared/MediaDownload/SCIMediaFFmpeg.h"
#import "../../Shared/MediaDownload/SCIMediaQualityManager.h"
#import "../../Shared/MediaDownload/SCIDownloadHistoryViewController.h"
#import "../../Shared/MediaDownload/SCIDownloadQueueManager.h"
#import "../../Utils.h"
#import "../../AssetUtils.h"

@implementation SCIGeneralSettingsProvider

+ (SCISetting *)appIconSetting {
    SCIAppIconPickerViewController *controller = [[SCIAppIconPickerViewController alloc] initWithSelectedIdentifier:[SCIAppIconCatalog currentAppIconIdentifier]
                                                                                                          onSelect:nil];
    SCISetting *setting = [SCISetting navigationCellWithTitle:@"App Icon"
                                                     subtitle:@""
                                                         icon:SCISettingsIcon(@"app")
                                               viewController:controller];
    setting.accessoryTextProvider = ^NSString *{
        SCIAppIconItem *currentIcon = [SCIAppIconCatalog currentAppIcon];
        return currentIcon.displayName.length > 0 ? currentIcon.displayName : @"Default";
    };
    return setting;
}

+ (UIMenu *)audioPageDefaultActionMenu {
    NSArray<NSDictionary *> *items = @[
        @{@"title": @"Save to Files", @"value": @"files", @"icon": @"audio_download"},
        @{@"title": @"Share", @"value": @"share", @"icon": @"share"},
        @{@"title": @"Save to Gallery", @"value": @"gallery", @"icon": @"media"},
        @{@"title": @"Play", @"value": @"play", @"icon": @"play"},
        @{@"title": @"Copy Download URL", @"value": @"copy_url", @"icon": @"link"},
        @{@"title": @"None", @"value": @"none", @"icon": @"action"}
    ];
    NSMutableArray<UICommand *> *commands = [NSMutableArray array];
    for (NSDictionary *item in items) {
        [commands addObject:[UICommand commandWithTitle:item[@"title"]
                                                  image:[SCIAssetUtils instagramIconNamed:item[@"icon"] pointSize:22.0]
                                                 action:@selector(menuChanged:)
                                           propertyList:@{@"defaultsKey": @"general_audio_page_default_action", @"value": item[@"value"], @"iconName": item[@"icon"]}]];
    }
    return [UIMenu menuWithChildren:commands];
}

+ (SCISetting *)rootSetting {
    BOOL ffmpegAvailable = [SCIMediaFFmpeg isAvailable];
    if (!ffmpegAvailable) {
        [[NSUserDefaults standardUserDefaults] setObject:@"high_ignore_dash" forKey:@"general_media_vid_quality"];
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
    encodingSettings.searchSectionsProvider = ^NSArray *{
        return [SCIMediaQualityManager encodingSettingsSearchSections];
    };

    SCISetting *encodingLogs = [SCISetting navigationCellWithTitle:@"View Encoding Logs"
                                                          subtitle:@""
                                                              icon:SCISettingsIcon(@"logs")
                                                    viewController:[SCIMediaFFmpeg logsViewController]];
    encodingLogs.userInfo = @{@"enabled": @YES};

    NSString *qualityFooter = ffmpegAvailable ? @"\"High\" merges DASH files for best quality. \"Default\" uses ready-to-play files. \"Always Ask\" prompts for selection." : @"FFmpegKit is required for video quality options and encoding features.";

    SCISetting *clearCacheSetting = [SCISetting buttonCellWithTitle:@"Clear Cache" subtitle:@"" icon:SCISettingsIcon(@"trash") action:^(void) {
        [SCIUtils cleanCache];
        SCINotify(kSCINotificationSettingsClearCache, @"Cache cleared", nil, @"circle_check_filled", SCINotificationToneForIconResource(@"circle_check_filled"));
    }];
    clearCacheSetting.tintColor = [SCIUtils SCIColor_InstagramDestructive];
    clearCacheSetting.iconTintColor = [SCIUtils SCIColor_InstagramDestructive];
    clearCacheSetting.accessoryTextProvider = ^NSString *{
        return [SCIUtils formattedCacheSize];
    };

    return SCITopicNavigationSetting(@"General", @"settings", 24.0, @[
        SCITopicSection(@"Behavior", @[
            [SCISetting switchCellWithTitle:@"Copy Text" icon:SCISettingsIcon(@"text") defaultsKey:@"general_copy_text"],
            [SCISetting switchCellWithTitle:@"No Recent Searches" icon:SCISettingsIcon(@"search") defaultsKey:@"general_no_recent_searches"],
            [SCISetting switchCellWithTitle:@"Copy Links Without Tracking" icon:SCISettingsIcon(@"user_unfollow") defaultsKey:@"general_strip_share_link_tracking"],
            [SCISetting switchCellWithTitle:@"Hold Send to Copy Link" icon:SCISettingsIcon(@"link") defaultsKey:@"general_hold_send_copy_link"],
        ], @"1. Long press on text fields across the app to copy.\n"
           @"2. Search bars will no longer save recent searches.\n"
           @"3. Remove the user and tracking identifiers from copied links.\n"
           @"4. Long press the send/share button to copy the post link."),
        SCITopicSection(@"Group", @[
            [SCISetting switchCellWithTitle:@"Hide Create Group Button" icon:SCISettingsIcon(@"group") defaultsKey:@"general_hide_create_group"],
            [SCISetting switchCellWithTitle:@"Confirm Create Group" icon:SCISettingsIcon(@"group") defaultsKey:@"general_confirm_create_group"],
        ], @"1. Hide the create group button from the Instagram send/share sheet.\n"
           @"2. Show a confirmation alert when you try to create a group."),
        SCITopicSection(@"Recommendations", @[
            [SCISetting navigationCellWithTitle:@"Ads"
                                       subtitle:@""
                                           icon:SCISettingsIcon(@"ads")
                                    navSections:@[
                SCITopicSection(@"Ads", @[
                    [SCISetting switchCellWithTitle:@"Hide Feed Ads" defaultsKey:@"general_hide_ads_feed"],
                    [SCISetting switchCellWithTitle:@"Hide Story Ads" defaultsKey:@"general_hide_ads_stories"],
                    [SCISetting switchCellWithTitle:@"Hide Reels Ads" defaultsKey:@"general_hide_ads_reels"],
                    [SCISetting switchCellWithTitle:@"Hide Explore Ads" defaultsKey:@"general_hide_ads_explore"],
                    [SCISetting switchCellWithTitle:@"Hide Reels Shopping CTA" defaultsKey:@"general_hide_reels_shopping_cta"]
                ], nil)
            ]],
            [SCISetting navigationCellWithTitle:@"Meta AI"
                                       subtitle:@""
                                           icon:SCISettingsIcon(@"meta_ai")
                                    navSections:@[
                SCITopicSection(@"", @[
                    [SCISetting switchCellWithTitle:@"Hide in Direct" defaultsKey:@"general_hide_meta_ai_msgs"],
                    [SCISetting switchCellWithTitle:@"Hide in Explore & Search" defaultsKey:@"general_hide_meta_ai_explore"],
                    [SCISetting switchCellWithTitle:@"Hide in Comments" defaultsKey:@"general_hide_meta_ai_comments"],
                    [SCISetting switchCellWithTitle:@"Hide in Creation Tools" defaultsKey:@"general_hide_meta_ai_creation"],
                    [SCISetting switchCellWithTitle:@"Hide Global AI Chrome" defaultsKey:@"general_hide_meta_ai_global"]
                ], @"Direct includes inbox, composer, recipients, themes, and message menus. Global chrome covers generic Meta AI buttons, placeholders, and branded entry points.")
            ]],
            [SCISetting navigationCellWithTitle:@"Suggested Users"
                                       subtitle:@""
                                           icon:SCISettingsIcon(@"users")
                                    navSections:@[
                SCITopicSection(@"Suggested Users", @[
                    [SCISetting switchCellWithTitle:@"Hide Feed Suggestions" defaultsKey:@"general_hide_suggested_users_feed"],
                    [SCISetting switchCellWithTitle:@"Hide Reels Suggestions" defaultsKey:@"general_hide_suggested_users_reels"],
                    [SCISetting switchCellWithTitle:@"Hide Direct Suggestions" defaultsKey:@"general_hide_suggested_users_msgs"],
                    [SCISetting switchCellWithTitle:@"Hide Search Suggestions" defaultsKey:@"general_hide_suggested_users_search"],
                    [SCISetting switchCellWithTitle:@"Hide Profile Suggestions" defaultsKey:@"general_hide_suggested_users_profile"],
                    [SCISetting switchCellWithTitle:@"Hide Activity Suggestions" defaultsKey:@"general_hide_suggested_users_activity"],
                    [SCISetting switchCellWithTitle:@"Hide Follow-List Suggestions" defaultsKey:@"general_hide_suggested_users_follow_lists"],
                    [SCISetting switchCellWithTitle:@"Hide Subscription Suggestions" defaultsKey:@"general_hide_suggested_users_subscriptions"]
                ], nil)
            ]]
        ], @"Control ads, AI and suggestions visibility by surface."),
        SCITopicSection(@"Media Saving", @[
            [SCISetting switchCellWithTitle:@"Enhanced Media Resolution" icon:SCISettingsIcon(@"hd") defaultsKey:@"general_enhanced_media_resolution"],
            [SCISetting switchCellWithTitle:@"Detect Duplicate Downloads" icon:SCISettingsIcon(@"media") defaultsKey:@"general_detect_duplicate_downloads"],
            [SCISetting stepperCellWithTitle:@"Parallel Downloads" subtitle:@"%@ concurrent %@" defaultsKey:kSCIDownloadMaxConcurrentKey min:1 max:4 step:1 label:@"downloads" singularLabel:@"download"],
            [SCISetting stepperCellWithTitle:@"History Limit" subtitle:@"%@ saved %@" defaultsKey:kSCIDownloadHistoryLimitKey min:50 max:1000 step:50 label:@"entries" singularLabel:@"entry"],
            [SCISetting navigationCellWithTitle:@"Downloads"
                                       subtitle:@"Queue, history, retry, and cancellation"
                                           icon:SCISettingsIcon(@"download")
                                 viewController:[SCIDownloadHistoryViewController new]],
            [SCISetting menuCellWithTitle:@"Default Photo Quality" icon:SCISettingsIcon(@"photo") menu:SCIMediaPhotoQualityMenu()],
            videoQualitySetting,
            encodingSettings,
            encodingLogs
        ], [NSString stringWithFormat:@"%@\n\nDuplicate detection runs before downloading. Gallery checks are exact. Photos checks cover media SCInsta saved while tracking is enabled.", qualityFooter]),
        SCITopicSection(@"Audio", @[
            [SCISetting switchCellWithTitle:@"Audio Downloads" icon:SCISettingsIcon(@"audio_download") defaultsKey:@"general_audio_download_enabled"],
            [SCISetting switchCellWithTitle:@"Audio Page Button" icon:SCISettingsIcon(@"audio_page") defaultsKey:@"general_audio_page_download" requiresRestart:YES],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Audio Page Default Action" icon:SCISettingsIcon(@"action") menu:[self audioPageDefaultActionMenu]], SCISettingsIcon(@"action"))
        ], @"Adds audio actions for audio pages and media action buttons."),
        SCITopicSection(@"Storage", @[
            clearCacheSetting,
            [SCISetting menuCellWithTitle:@"Auto Clear Cache" icon:SCISettingsIcon(@"clock") menu:SCICacheAutoClearMenu()]
        ], @"Automatic clearing is checked whenever Instagram becomes active."),
        SCITopicSection(@"App", @[
            [self appIconSetting],
            [SCISetting switchCellWithTitle:@"Disable App Haptics" icon:SCISettingsIcon(@"haptics") defaultsKey:@"general_disable_haptics"]
        ], @"Choose an app icon directly from the icons exposed by the installed Instagram bundle. Disable App Haptics turns off haptics and vibrations within the app."),
    ]);
}

@end

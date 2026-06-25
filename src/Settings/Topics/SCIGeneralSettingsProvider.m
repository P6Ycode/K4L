#import "SCIGeneralSettingsProvider.h"

#import "../SCIAppIconCatalog.h"
#import "../SCIAppIconPickerViewController.h"
#import "../SCITopicSettingsSupport.h"
#import "../../Utils.h"
#import "../../Shared/Account/SCIAccountManager.h"
#import "../../Shared/UI/SCIIGAlertPresenter.h"
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

+ (SCISetting *)perAccountSetting {
    SCISetting *setting = [SCISetting switchCellWithTitle:@"Per-Account Settings"
                                                    icon:SCISettingsIcon(@"user_circle")
                                             defaultsKey:kSCIPrefPerAccountSettings];
    // Changes which key namespace every feature reads, and most enabled-state is
    // captured at hook install, so a restart applies it cleanly.
    setting.requiresRestart = YES;
    return setting;
}

+ (SCISetting *)perAccountInfoSetting {
    return [SCISetting buttonCellWithTitle:@"How It Works"
                                  subtitle:nil
                                      icon:SCISettingsIcon(@"info")
                                    action:^{
        NSString *message =
            @"Each logged-in account gets its own SCInsta settings. A newly seen "
            @"account starts from your current settings until you change something.\n\n"
            @"These stay shared across all accounts:\n"
            @"•  App icon\n"
            @"•  Appearance & Liquid Glass\n"
            @"•  Tab bar order & visibility\n"
            @"•  Hide UI on capture\n"
            @"•  Download encoding settings\n"
            @"•  Gallery view, sort & lock\n"
            @"•  Disable All (master switch)\n\n"
            @"Gallery media ownership is controlled separately in Gallery settings.";

        [SCIIGAlertPresenter presentAlertFromViewController:topMostController()
                                                     title:@"Per-Account Settings"
                                                   message:message
                                                   actions:@[ [SCIIGAlertAction actionWithTitle:@"OK" style:SCIIGAlertActionStyleCancel handler:nil] ]];
    }];
}

+ (SCISetting *)rootSetting {
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
        SCITopicSection(@"Comments", @[
            [SCISetting switchCellWithTitle:@"Swipe to Close Comments" icon:SCISettingsIcon(@"left_right") defaultsKey:@"general_comments_swipe_close"],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Swipe Direction" icon:SCISettingsIcon(@"left_right") menu:SCISwipeCloseCommentsDirectionMenu()], SCISettingsIcon(@"left_right")),
            [SCISetting switchCellWithTitle:@"Copy Comment" icon:SCISettingsIcon(@"copy") defaultsKey:@"general_comments_copy_text"],
            [SCISetting switchCellWithTitle:@"Comment Media Actions" icon:SCISettingsIcon(@"media") defaultsKey:@"general_comments_media_actions"],
            [SCISetting switchCellWithTitle:@"Confirm Comment Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"general_comments_confirm_like"],
            [SCISetting switchCellWithTitle:@"Hide Comment Shopping" icon:SCISettingsIcon(@"shopping_bag") defaultsKey:@"general_comments_hide_shopping"],
            [SCISetting switchCellWithTitle:@"Hide Gifts Button" icon:SCISettingsIcon(@"gift") defaultsKey:@"general_comments_hide_gifts_button"]
        ], @"Copy Comment adds a copy action to comment menus. Comment Media Actions adds Photos, Share, Gallery, and link actions for GIF and photo comments. Swipe to Close Comments adds horizontal swipe gestures to comment sheets. Hide Comment Shopping removes commerce carousels in comment threads. Hide Gifts Button removes the gift shortcut from the comment composer."),
        SCITopicSection(@"Accounts", @[
            [self perAccountSetting],
            [self perAccountInfoSetting]
        ], @"Give each logged-in account its own SCInsta settings."),
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

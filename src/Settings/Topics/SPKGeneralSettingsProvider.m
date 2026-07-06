#import "SPKGeneralSettingsProvider.h"

#import "../../AssetUtils.h"
#import "../../Shared/Account/SPKAccountManager.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../Utils.h"
#import "../SPKActionSectionIconPickerViewController.h"
#import "../SPKAppIconCatalog.h"
#import "../SPKAppIconPickerViewController.h"
#import "../SPKTopicSettingsSupport.h"

@implementation SPKGeneralSettingsProvider

+ (SPKSetting *)defaultMenuIconSetting {
    SPKActionSectionIconPickerViewController *controller =
        [[SPKActionSectionIconPickerViewController alloc] initWithSelectedIconName:SPKActionButtonOpenMenuIconName()
                                                                          onSelect:^(NSString *iconName) {
                                                                              SPKPreferenceSetObject(iconName.length > 0 ? iconName : @"action", @"general_action_btn_default_menu_icon");
                                                                              [[NSNotificationCenter defaultCenter] postNotificationName:SPKActionButtonConfigurationDidChangeNotification object:nil];
                                                                          }];
    controller.title = @"Open Menu Icon";

    SPKSetting *setting = [SPKSetting navigationCellWithTitle:@"Open Menu Icon"
                                                     subtitle:@""
                                                         icon:SPKSettingsIcon(@"action")
                                               viewController:controller];
    // The row's icon mirrors the chosen glyph, so the (cryptic) catalog name is
    // redundant as accessory text — let the adaptive icon convey the selection.
    setting.iconProvider = ^UIImage * {
        return SPKSettingsIcon(SPKActionButtonOpenMenuIconName());
    };
    return setting;
}

+ (SPKSetting *)appIconSetting {
    SPKAppIconPickerViewController *controller = [[SPKAppIconPickerViewController alloc] initWithSelectedIdentifier:[SPKAppIconCatalog currentAppIconIdentifier]
                                                                                                           onSelect:nil];
    SPKSetting *setting = [SPKSetting navigationCellWithTitle:@"App Icon"
                                                     subtitle:@""
                                                         icon:SPKSettingsIcon(@"app")
                                               viewController:controller];
    setting.accessoryTextProvider = ^NSString * {
        SPKAppIconItem *currentIcon = [SPKAppIconCatalog currentAppIcon];
        return currentIcon.displayName.length > 0 ? currentIcon.displayName : @"Default";
    };
    return setting;
}

+ (SPKSetting *)perAccountSetting {
    SPKSetting *setting = [SPKSetting switchCellWithTitle:@"Per-Account Settings"
                                                     icon:SPKSettingsIcon(@"user_circle")
                                              defaultsKey:kSPKPrefPerAccountSettings];
    // Changes which key namespace every feature reads, and most enabled-state is
    // captured at hook install, so a restart applies it cleanly.
    setting.requiresRestart = YES;
    return setting;
}

+ (SPKSetting *)perAccountInfoSetting {
    return [SPKSetting buttonCellWithTitle:@"How It Works"
                                  subtitle:nil
                                      icon:SPKSettingsIcon(@"info")
                                    action:^{
                                        NSString *message =
                                            @"Each logged-in account gets its own Sparkle settings. A newly seen "
                                            @"account starts from your current settings until you change something.\n\n"
                                            @"These stay shared across all accounts:\n"
                                            @"•  App icon\n"
                                            @"•  Appearance & Liquid Glass\n"
                                            @"•  Tab bar order & visibility\n"
                                            @"•  Main feed mode (For You / Following)\n"
                                            @"•  Disable video autoplay\n"
                                            @"•  Hide UI on capture\n"
                                            @"•  Download encoding settings\n"
                                            @"•  Gallery view, sort & lock\n"
                                            @"•  Disable All (master switch)\n\n"
                                            @"Gallery media ownership is controlled separately in Gallery settings.";

                                        [SPKIGAlertPresenter presentAlertFromViewController:topMostController()
                                                                                      title:@"Per-Account Settings"
                                                                                    message:message
                                                                                    actions:@[ [SPKIGAlertAction actionWithTitle:@"OK" style:SPKIGAlertActionStyleCancel handler:nil] ]];
                                    }];
}

+ (SPKSetting *)rootSetting {
    SPKSetting *clearCacheSetting = [SPKSetting buttonCellWithTitle:@"Clear Cache"
                                                           subtitle:@""
                                                               icon:SPKSettingsIcon(@"trash")
                                                             action:^(void) {
                                                                 unsigned long long freedBytes = [SPKUtils cleanCacheReturningFreedBytes];
                                                                 NSString *subtitle = freedBytes > 0
                                                                                          ? [NSString stringWithFormat:@"Freed %@", [NSByteCountFormatter stringFromByteCount:(long long)freedBytes countStyle:NSByteCountFormatterCountStyleFile]]
                                                                                          : @"Cache was already empty";
                                                                 SPKNotify(kSPKNotificationSettingsClearCache, @"Cache cleared", subtitle, @"circle_check_filled", SPKNotificationToneForIconResource(@"circle_check_filled"));
                                                             }];
    clearCacheSetting.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearCacheSetting.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearCacheSetting.accessoryTextProvider = ^NSString * {
        return [SPKUtils formattedCacheSize];
    };

    return SPKTopicNavigationSetting(@"General", @"settings", 24.0, @[
        SPKTopicSection(@"Behavior", @[
            [SPKSetting switchCellWithTitle:@"Copy Text"
                                       icon:SPKSettingsIcon(@"text")
                                defaultsKey:@"general_copy_text"],
            [SPKSetting switchCellWithTitle:@"No Recent Searches"
                                       icon:SPKSettingsIcon(@"search")
                                defaultsKey:@"general_no_recent_searches"],
            [SPKSetting switchCellWithTitle:@"Copy Links Without Tracking"
                                       icon:SPKSettingsIcon(@"user_unfollow")
                                defaultsKey:@"general_strip_share_link_tracking"],
            [SPKSetting switchCellWithTitle:@"Hold Send to Copy Link"
                                       icon:SPKSettingsIcon(@"link")
                                defaultsKey:@"general_hold_send_copy_link"],
        ],
                        @"1. Long press on text fields across the app to copy.\n"
                        @"2. Search bars will no longer save recent searches.\n"
                        @"3. Remove the user and tracking identifiers from copied links.\n"
                        @"4. Long press the send/share button to copy the post link."),
        SPKTopicSection(@"Sharing", @[
            [SPKSetting switchCellWithTitle:@"Hide Create Group Button"
                                       icon:SPKSettingsIcon(@"group")
                                defaultsKey:@"general_hide_create_group"],
            [SPKSetting switchCellWithTitle:@"Confirm Create Group"
                                       icon:SPKSettingsIcon(@"group")
                                defaultsKey:@"general_confirm_create_group"],
            [SPKSetting switchCellWithTitle:@"Confirm Sending Post"
                                       icon:SPKSettingsIcon(@"messages")
                                defaultsKey:@"general_confirm_send"],
        ],
                        @"1. Hide the create group button from the Instagram send/share sheet.\n"
                        @"2. Show a confirmation alert when you try to create a group.\n"
                        @"3. Show a confirmation alert when sending a post."),
        SPKTopicSection(@"Recommendations", @[
            [SPKSetting navigationCellWithTitle:@"Ads"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"ads")
                                    navSections:@[
                                        SPKTopicSection(@"Ads", @[
                                            [SPKSetting switchCellWithTitle:@"Hide Feed Ads"
                                                                defaultsKey:@"general_hide_ads_feed"],
                                            [SPKSetting switchCellWithTitle:@"Hide Story Ads"
                                                                defaultsKey:@"general_hide_ads_stories"],
                                            [SPKSetting switchCellWithTitle:@"Hide Reels Ads"
                                                                defaultsKey:@"general_hide_ads_reels"],
                                            [SPKSetting switchCellWithTitle:@"Hide Explore Ads"
                                                                defaultsKey:@"general_hide_ads_explore"],
                                            [SPKSetting switchCellWithTitle:@"Hide Reels Shopping CTA"
                                                                defaultsKey:@"general_hide_reels_shopping_cta"]
                                        ],
                                                        nil)
                                    ]],
            [SPKSetting navigationCellWithTitle:@"Meta AI"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"meta_ai")
                                    navSections:@[
                                        SPKTopicSection(@"", @[
                                            [SPKSetting switchCellWithTitle:@"Hide in Direct"
                                                                defaultsKey:@"general_hide_meta_ai_msgs"],
                                            [SPKSetting switchCellWithTitle:@"Hide in Explore & Search"
                                                                defaultsKey:@"general_hide_meta_ai_explore"],
                                            [SPKSetting switchCellWithTitle:@"Hide in Comments"
                                                                defaultsKey:@"general_hide_meta_ai_comments"],
                                            [SPKSetting switchCellWithTitle:@"Hide in Creation Tools"
                                                                defaultsKey:@"general_hide_meta_ai_creation"],
                                            [SPKSetting switchCellWithTitle:@"Hide Global AI Chrome"
                                                                defaultsKey:@"general_hide_meta_ai_global"]
                                        ],
                                                        @"Direct includes inbox, composer, recipients, themes, and message menus. Global chrome covers generic Meta AI buttons, placeholders, and branded entry points.")
                                    ]],
            [SPKSetting navigationCellWithTitle:@"Suggested Users"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"users")
                                    navSections:@[
                                        SPKTopicSection(@"Suggested Users", @[
                                            [SPKSetting switchCellWithTitle:@"Hide Feed Suggestions"
                                                                defaultsKey:@"general_hide_suggested_users_feed"],
                                            [SPKSetting switchCellWithTitle:@"Hide Reels Suggestions"
                                                                defaultsKey:@"general_hide_suggested_users_reels"],
                                            [SPKSetting switchCellWithTitle:@"Hide Direct Suggestions"
                                                                defaultsKey:@"general_hide_suggested_users_msgs"],
                                            [SPKSetting switchCellWithTitle:@"Hide Search Suggestions"
                                                                defaultsKey:@"general_hide_suggested_users_search"],
                                            [SPKSetting switchCellWithTitle:@"Hide Profile Suggestions"
                                                                defaultsKey:@"general_hide_suggested_users_profile"],
                                            [SPKSetting switchCellWithTitle:@"Hide Activity Suggestions"
                                                                defaultsKey:@"general_hide_suggested_users_activity"],
                                            [SPKSetting switchCellWithTitle:@"Hide Follow-List Suggestions"
                                                                defaultsKey:@"general_hide_suggested_users_follow_lists"],
                                            [SPKSetting switchCellWithTitle:@"Hide Subscription Suggestions"
                                                                defaultsKey:@"general_hide_suggested_users_subscriptions"]
                                        ],
                                                        nil)
                                    ]]
        ],
                        @"Control ads, AI and suggestions visibility by surface."),
        SPKTopicSection(@"Comments", @[
            [SPKSetting switchCellWithTitle:@"Copy Comment"
                                       icon:SPKSettingsIcon(@"copy")
                                defaultsKey:@"general_comments_copy_text"],
            [SPKSetting switchCellWithTitle:@"Comment Media Actions"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:@"general_comments_media_actions"],
            [SPKSetting switchCellWithTitle:@"Upload Photo from Gallery"
                                       icon:SPKSettingsIcon(@"photo")
                                defaultsKey:@"general_comments_gallery_upload"]
        ],
                        @"1. Adds a copy action to comment menus.\n"
                        @"2. Adds Photos, Share, Gallery, and link actions for GIF and photo comments.\n"
                        @"3. Long-press the composer's photo button to attach an image from your Sparkle Gallery."),
        SPKTopicSection(@"", @[
            [SPKSetting switchCellWithTitle:@"Swipe to Close Comments"
                                       icon:SPKSettingsIcon(@"left_right")
                                defaultsKey:@"general_comments_swipe_close"],
            SPKSettingApplySelectedMenuIcon([SPKSetting menuCellWithTitle:@"Swipe Direction" icon:SPKSettingsIcon(@"left_right") menu:SPKSwipeCloseCommentsDirectionMenu()], SPKSettingsIcon(@"left_right")),
        ],
                        @"Adds a horizontal swipe gesture to close comment sheets, in the chosen direction."),
        SPKTopicSection(@"", @[
            [SPKSetting switchCellWithTitle:@"Confirm Comment Like"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"general_comments_confirm_like"],
            [SPKSetting switchCellWithTitle:@"Hide Comment Shopping"
                                       icon:SPKSettingsIcon(@"shopping_bag")
                                defaultsKey:@"general_comments_hide_shopping"],
            [SPKSetting switchCellWithTitle:@"Hide Gifts Button"
                                       icon:SPKSettingsIcon(@"gift")
                                defaultsKey:@"general_comments_hide_gifts_button"],
        ],
                        @"1. Shows a confirmation alert before liking a comment.\n"
                        @"2. Removes commerce carousels in comment threads.\n"
                        @"3. Removes the gift shortcut from the comment composer."),
        SPKTopicSection(@"Accounts", @[
            [self perAccountSetting],
            [self perAccountInfoSetting]
        ],
                        @"Give each logged-in account its own Sparkle settings."),
        SPKTopicSection(@"Storage", @[
            clearCacheSetting,
            [SPKSetting menuCellWithTitle:@"Auto Clear Cache"
                                     icon:SPKSettingsIcon(@"clock")
                                     menu:SPKCacheAutoClearMenu()]
        ],
                        @"Automatic clearing is checked whenever Instagram becomes active."),
        SPKTopicSection(@"App", @[
            [self appIconSetting],
            [self defaultMenuIconSetting],
            [SPKSetting switchCellWithTitle:@"Disable App Haptics"
                                       icon:SPKSettingsIcon(@"haptics")
                                defaultsKey:@"general_disable_haptics"]
        ],
                        @"Choose an app icon directly from the icons exposed by the installed Instagram bundle. Open Menu Icon sets the glyph shown on every action button whose default tap action is Open Menu. Disable App Haptics turns off haptics and vibrations within the app."),
    ]);
}

@end

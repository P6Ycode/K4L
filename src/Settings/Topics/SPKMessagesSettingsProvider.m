#import "SPKMessagesSettingsProvider.h"

#import "../../Features/Messages/DeletedMessagesLog/SPKDeletedMessagesViewController.h"
#import "../../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../../Shared/Messages/SPKDirectSeenContext.h"
#import "../../Utils.h"
#import "../SPKSettingsViewController.h"
#import "../SPKTopicSettingsSupport.h"

static NSString *const kSPKMessagesActionButtonEnabledKey = @"msgs_action_btn";
static NSString *const kSPKMessagesAudioCallConfirmKey = @"msgs_confirm_audio_call";
static NSString *const kSPKMessagesVideoCallConfirmKey = @"msgs_confirm_video_call";

static NSArray *SPKMessagesSettingsSections(void);

// A switch cell that stays visible but is disabled while the "Audio Downloads"
// master toggle is off (keeping its stored value).
static SPKSetting *SPKAudioGatedSwitch(NSString *title, UIImage *icon, NSString *defaultsKey) {
    SPKSetting *setting = [SPKSetting switchCellWithTitle:title icon:icon defaultsKey:defaultsKey];
    setting.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"downloads_audio_enabled"];
    };
    return setting;
}

@interface SPKMessagesSettingsViewController : SPKSettingsViewController
@end

@implementation SPKMessagesSettingsViewController
- (instancetype)init {
    return [super initWithTitle:@"Messages" sections:SPKMessagesSettingsSections() reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self replaceSections:SPKMessagesSettingsSections()];
}

- (void)switchChanged:(UISwitch *)sender {
    SPKSetting *row = [self settingForSender:sender];
    [super switchChanged:sender];
    if ([row.defaultsKey isEqualToString:@"msgs_manual_seen"] ||
        [row.defaultsKey isEqualToString:@"msgs_manual_visual_seen"]) {
        [self replaceSections:SPKMessagesSettingsSections()];
    }
}
@end

static NSArray *SPKMessagesSettingsSections(void) {
    BOOL manualSeen = [SPKUtils getBoolPref:@"msgs_manual_seen"];
    SPKSetting *manualSeenList = [SPKSetting navigationCellWithTitle:SPKDirectManualSeenListTitle(manualSeen)
                                                            subtitle:@""
                                                                icon:SPKSettingsIcon(@"users")
                                                      viewController:SPKDirectManualSeenListViewController()];
    manualSeenList.userInfo = @{@"accessoryText" : [NSString stringWithFormat:@"%lu", (unsigned long)SPKDirectManualSeenThreadCount(manualSeen)]};

    // Auto-seen triggers only act while manual seen is on. Keep their stored value
    // but lock the cells when manual seen is off.
    SPKSetting *seenOnSend = [SPKSetting switchCellWithTitle:@"Mark Seen on Message Send" icon:SPKSettingsIcon(@"messages") defaultsKey:@"msgs_seen_on_send"];
    SPKSetting *seenOnReply = [SPKSetting switchCellWithTitle:@"Mark Seen on Message Reply" icon:SPKSettingsIcon(@"reply") defaultsKey:@"msgs_seen_on_reply"];
    SPKSetting *seenOnReaction = [SPKSetting switchCellWithTitle:@"Mark Seen on Reaction" icon:SPKSettingsIcon(@"reactions") defaultsKey:@"msgs_seen_on_reaction"];
    seenOnSend.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_seen"];
    };
    seenOnReply.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_seen"];
    };
    seenOnReaction.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_seen"];
    };

    // Advancing after a manual seen only applies while visual manual seen is on.
    SPKSetting *advanceVisual = [SPKSetting switchCellWithTitle:@"Advance After Manual Seen" icon:SPKSettingsIcon(@"autoscroll") defaultsKey:@"msgs_advance_visual_on_seen"];
    advanceVisual.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_visual_seen"];
    };

    return @[
        SPKTopicSection(@"Action Button", @[
            [SPKSetting switchCellWithTitle:@"Messages Action Button"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:kSPKMessagesActionButtonEnabledKey],
            SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSourceDirect),
            SPKActionButtonConfigurationNavigationSetting(SPKActionButtonSourceDirect, @"Messages", SPKActionButtonSupportedActionsForSource(SPKActionButtonSourceDirect), SPKActionButtonDefaultSectionsForSource(SPKActionButtonSourceDirect))
        ],
                        @"Choose what tapping the action button does. Long press opens the full menu."),
        SPKTopicSection(@"Messaging", @[
            [SPKSetting switchCellWithTitle:@"Manually Mark Seen"
                                       icon:SPKSettingsIcon(@"eye")
                                defaultsKey:@"msgs_manual_seen"],
            seenOnSend,
            seenOnReply,
            seenOnReaction,
            manualSeenList,
        ],
                        manualSeen ? @"1. Prevents automatic seen receipts and adds an eye button to mark chats as seen.\n"
                                     @"2. Marks a chat as seen when you send a message.\n"
                                     @"3. Marks a chat as seen when you reply.\n"
                                     @"4. Marks a chat as seen when you react.\n\n"
                                     @"Excluded Chats keep Instagram's normal seen behavior. Manage them from the eye button, an inbox long press, or the list above."
                                   : @"1. Prevents automatic seen receipts and adds an eye button to mark chats as seen.\n"
                                     @"2. Marks a chat as seen when you send a message.\n"
                                     @"3. Marks a chat as seen when you reply.\n"
                                     @"4. Marks a chat as seen when you react.\n\n"
                                     @"Included Chats require the eye button or the auto-seen triggers above. Manage them from the eye button, an inbox long press, or the list above."),
        SPKTopicSection(@"Deleted Messages", @[
            [SPKSetting switchCellWithTitle:@"Keep Deleted Messages"
                                       icon:SPKSettingsIcon(@"undo_circle")
                                defaultsKey:@"msgs_keep_deleted"],
            [SPKSetting switchCellWithTitle:@"Confirm Inbox Refresh"
                                       icon:SPKSettingsIcon(@"arrow_cw")
                                defaultsKey:@"msgs_confirm_refresh"],
            [SPKSetting switchCellWithTitle:@"Log Deleted Messages"
                                       icon:SPKSettingsIcon(@"logs")
                                defaultsKey:@"msgs_deleted_log"],
            [SPKSetting switchCellWithTitle:@"Log Removed Reactions"
                                       icon:SPKSettingsIcon(@"reactions")
                                defaultsKey:@"msgs_deleted_log_reactions"],
            [SPKSetting switchCellWithTitle:@"Respect Seen Chat List"
                                       icon:SPKSettingsIcon(@"eye")
                                defaultsKey:@"msgs_deleted_log_respect_seen_list"],
            [SPKSetting navigationCellWithTitle:@"Deleted Messages Logs"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"channels")
                                 viewController:[SPKDeletedMessagesViewController new]],
        ],
                        @"1. Preserves remotely unsent messages in the chat, marked with an undo-circle indicator.\n"
                        @"2. Asks before refreshing the inbox, which reloads threads and drops preserved messages.\n"
                        @"3. Records message content before removal and keeps view-once/view-twice media until cleared.\n"
                        @"4. Also logs reactions that are removed.\n"
                        @"5. Skips log capture and unsent notifications for chats in your manual-seen include/exclude list.\n"
                        @"6. Opens the captured deleted-message logs."),
        SPKTopicSection(@"Interface", @[
            [SPKSetting switchCellWithTitle:@"Hide Typing Status"
                                       icon:SPKSettingsIcon(@"keyboard")
                                defaultsKey:@"msgs_disable_typing"],
            [SPKSetting switchCellWithTitle:@"Hide Reels Blend Button"
                                       icon:SPKSettingsIcon(@"blend")
                                defaultsKey:@"msgs_hide_reels_blend"],
            [SPKSetting switchCellWithTitle:@"Hide Audio Call Button"
                                       icon:SPKSettingsIcon(@"call")
                                defaultsKey:@"msgs_hide_audio_call_btn"],
            [SPKSetting switchCellWithTitle:@"Hide Video Call Button"
                                       icon:SPKSettingsIcon(@"video")
                                defaultsKey:@"msgs_hide_video_call_btn"],
            [SPKSetting switchCellWithTitle:@"No Suggested Chats"
                                       icon:SPKSettingsIcon(@"question")
                                defaultsKey:@"msgs_hide_suggested_chats"],
        ],
                        @"1. Stops sending your typing indicator to others.\n"
                        @"2. Removes the Reels Blend button from the inbox.\n"
                        @"3. Hides the audio call button in the chat header.\n"
                        @"4. Hides the video call button in the chat header.\n"
                        @"5. Removes suggested chats from the inbox."),
        SPKTopicSection(@"Visual Messages", @[
            [SPKSetting switchCellWithTitle:@"Manually Mark Seen"
                                       icon:SPKSettingsIcon(@"eye")
                                defaultsKey:@"msgs_manual_visual_seen"],
            advanceVisual,
            [SPKSetting switchCellWithTitle:@"Stop Auto Advance"
                                       icon:SPKSettingsIcon(@"autoscroll")
                                defaultsKey:@"msgs_stop_visual_auto_advance"],
            [SPKSetting switchCellWithTitle:@"Disable View-Once Limitations"
                                       icon:SPKSettingsIcon(@"view_once")
                                defaultsKey:@"msgs_disable_view_once"],
            [SPKSetting switchCellWithTitle:@"Disable Screenshot Detection"
                                       icon:SPKSettingsIcon(@"warning")
                                defaultsKey:@"msgs_disable_screenshot_detection"]
        ],
                        @"1. Prevents automatic seen receipts and adds a button to mark the chat as seen.\n"
                        @"2. Moves to the next visual item when available or dismisses.\n"
                        @"3. Keeps the current visual message on screen instead of auto-advancing when it ends.\n"
                        @"4. View-once messages behave like normal visual messages.\n"
                        @"5. Allows screen capture of visual messages."),
        SPKTopicSection(@"Vanish Mode", @[
            [SPKSetting switchCellWithTitle:@"Disable Swipe-Up Gesture"
                                       icon:SPKSettingsIcon(@"arrow_up")
                                defaultsKey:@"msgs_disable_vanish_swipe_up"],
            [SPKSetting switchCellWithTitle:@"Disable Screenshot Detection"
                                       icon:SPKSettingsIcon(@"warning")
                                defaultsKey:@"msgs_hide_vanish_screenshot"],
        ],
                        @"1. Disable the gesture that enables vanish mode.\n"
                        @"2. Allows screen capture while vanish mode is active."),
        SPKTopicSection(@"Notes", @[
            [SPKSetting switchCellWithTitle:@"Hide Notes Tray"
                                       icon:SPKSettingsIcon(@"notes")
                                defaultsKey:@"msgs_hide_notes_tray"],
            [SPKSetting switchCellWithTitle:@"Hide Friends Map"
                                       icon:SPKSettingsIcon(@"map")
                                defaultsKey:@"msgs_hide_friends_map"],
            SPKAudioGatedSwitch(@"Download Notes Audio", SPKSettingsIcon(@"audio"), @"msgs_download_notes_audio"),
            [SPKSetting switchCellWithTitle:@"Copy Note Text"
                                       icon:SPKSettingsIcon(@"copy")
                                defaultsKey:@"msgs_copy_note_text"]
        ],
                        @"Long-press a note in the tray to download its audio or copy its text. Each action only appears when the note has that content."),
        SPKTopicSection(@"Audio", @[
            SPKAudioGatedSwitch(@"Download Voice Messages", SPKSettingsIcon(@"audio_download"), @"msgs_download_audio_messages"),
            [SPKSetting switchCellWithTitle:@"Upload Audio"
                                       icon:SPKSettingsIcon(@"audio_upload")
                                defaultsKey:@"msgs_upload_audio_messages"],
            [SPKSetting switchCellWithTitle:@"Trim Before Sending"
                                       icon:SPKSettingsIcon(@"trim")
                                defaultsKey:@"msgs_audio_upload_trim"]
        ],
                        @"1. Adds audio actions to supported voice/audio message views.\n"
                        @"2. Adds an option to the composer plus (+) menu that sends the selected audio or video as a voice message.\n"
                        @"3. When uploading, offers to trim the audio before sending it."),
        SPKTopicSection(@"Media", @[
            [SPKSetting switchCellWithTitle:@"Upload Photo from Gallery"
                                       icon:SPKSettingsIcon(@"photo")
                                defaultsKey:@"msgs_upload_gallery_media"]
        ],
                        @"Adds an option to the composer plus (+) menu that sends a photo from the Sparkle Gallery into the chat."),
        SPKTopicSection(@"Confirmation", @[
            [SPKSetting switchCellWithTitle:@"Confirm Audio Call"
                                       icon:SPKSettingsIcon(@"call")
                                defaultsKey:kSPKMessagesAudioCallConfirmKey],
            [SPKSetting switchCellWithTitle:@"Confirm Video Call"
                                       icon:SPKSettingsIcon(@"video")
                                defaultsKey:kSPKMessagesVideoCallConfirmKey],
            [SPKSetting switchCellWithTitle:@"Confirm Double Tap"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"msgs_confirm_double_tap"],
            [SPKSetting switchCellWithTitle:@"Confirm Reactions"
                                       icon:SPKSettingsIcon(@"reactions")
                                defaultsKey:@"msgs_confirm_reaction"],
            [SPKSetting switchCellWithTitle:@"Confirm Voice Messages"
                                       icon:SPKSettingsIcon(@"voice")
                                defaultsKey:@"msgs_confirm_voice_msg"],
            [SPKSetting switchCellWithTitle:@"Confirm Follow Requests"
                                       icon:SPKSettingsIcon(@"user_request")
                                defaultsKey:@"msgs_confirm_follow_request"],
            [SPKSetting switchCellWithTitle:@"Confirm Vanish Mode"
                                       icon:SPKSettingsIcon(@"vanish")
                                defaultsKey:@"msgs_confirm_vanish_mode"],
            [SPKSetting switchCellWithTitle:@"Confirm Changing Theme"
                                       icon:SPKSettingsIcon(@"palette")
                                defaultsKey:@"msgs_confirm_theme_change"]
        ],
                        @"Shows confirmation alerts before the selected message actions are sent.")
    ];
}

@implementation SPKMessagesSettingsProvider

+ (SPKSetting *)rootSetting {
    SPKSetting *setting = [SPKSetting navigationCellWithTitle:@"Messages"
                                                     subtitle:@""
                                                         icon:SPKSettingsIcon(@"messages")
                                               viewController:[[SPKMessagesSettingsViewController alloc] init]];
    setting.searchSectionsProvider = ^NSArray * {
        return SPKMessagesSettingsSections();
    };
    return SPKSettingApplyIconTint(setting, [SPKUtils SPKColor_InstagramPrimaryText]);
}

@end

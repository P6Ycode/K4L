#import "SCIMessagesSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../SCISettingsViewController.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../../Shared/Messages/SCIDirectSeenContext.h"
#import "../../Features/Messages/DeletedMessagesLog/SCIDeletedMessagesViewController.h"
#import "../../Utils.h"

static NSString * const kSCIMessagesActionButtonEnabledKey = @"msgs_action_btn";
static NSString * const kSCIMessagesAudioCallConfirmKey = @"msgs_confirm_audio_call";
static NSString * const kSCIMessagesVideoCallConfirmKey = @"msgs_confirm_video_call";

static NSArray *SCIMessagesSettingsSections(void);

@interface SCIMessagesSettingsViewController : SCISettingsViewController
@end

@implementation SCIMessagesSettingsViewController
- (instancetype)init {
    return [super initWithTitle:@"Messages" sections:SCIMessagesSettingsSections() reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self replaceSections:SCIMessagesSettingsSections()];
}

- (void)switchChanged:(UISwitch *)sender {
    SCISetting *row = [self settingForSender:sender];
    [super switchChanged:sender];
    if ([row.defaultsKey isEqualToString:@"msgs_manual_seen"] ||
        [row.defaultsKey isEqualToString:@"msgs_manual_visual_seen"]) {
        [self replaceSections:SCIMessagesSettingsSections()];
    }
}
@end

static NSArray *SCIMessagesSettingsSections(void) {
    BOOL manualSeen = [SCIUtils getBoolPref:@"msgs_manual_seen"];
    SCISetting *manualSeenList = [SCISetting navigationCellWithTitle:SCIDirectManualSeenListTitle(manualSeen)
                                                            subtitle:@""
                                                                icon:SCISettingsIcon(@"users")
                                                      viewController:SCIDirectManualSeenListViewController()];
    manualSeenList.userInfo = @{@"accessoryText": [NSString stringWithFormat:@"%lu", (unsigned long)SCIDirectManualSeenThreadCount(manualSeen)]};

    // Auto-seen triggers only act while manual seen is on. Keep their stored value
    // but lock the cells when manual seen is off.
    SCISetting *seenOnSend = [SCISetting switchCellWithTitle:@"Mark Seen on Message Send" icon:SCISettingsIcon(@"messages") defaultsKey:@"msgs_seen_on_send"];
    SCISetting *seenOnReply = [SCISetting switchCellWithTitle:@"Mark Seen on Message Reply" icon:SCISettingsIcon(@"reply") defaultsKey:@"msgs_seen_on_reply"];
    SCISetting *seenOnReaction = [SCISetting switchCellWithTitle:@"Mark Seen on Reaction" icon:SCISettingsIcon(@"reactions") defaultsKey:@"msgs_seen_on_reaction"];
    seenOnSend.enabledProvider = ^BOOL{ return [SCIUtils getBoolPref:@"msgs_manual_seen"]; };
    seenOnReply.enabledProvider = ^BOOL{ return [SCIUtils getBoolPref:@"msgs_manual_seen"]; };
    seenOnReaction.enabledProvider = ^BOOL{ return [SCIUtils getBoolPref:@"msgs_manual_seen"]; };

    // Advancing after a manual seen only applies while visual manual seen is on.
    SCISetting *advanceVisual = [SCISetting switchCellWithTitle:@"Advance After Manual Seen" icon:SCISettingsIcon(@"autoscroll") defaultsKey:@"msgs_advance_visual_on_seen"];
    advanceVisual.enabledProvider = ^BOOL{ return [SCIUtils getBoolPref:@"msgs_manual_visual_seen"]; };

    return @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Messages Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIMessagesActionButtonEnabledKey],
            SCIActionButtonDefaultActionNavigationSetting(SCIActionButtonSourceDirect),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceDirect, @"Messages", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceDirect), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceDirect))
        ], @"Choose what tapping the action button does. Long press opens the full menu."),
        SCITopicSection(@"Messaging", @[
            [SCISetting switchCellWithTitle:@"Manually Mark Seen" icon:SCISettingsIcon(@"eye") defaultsKey:@"msgs_manual_seen"],
            seenOnSend,
            seenOnReply,
            seenOnReaction,
            manualSeenList,
        ], manualSeen
           ? @"1. Prevents automatic seen receipts and adds an eye button to mark chats as seen.\n"
             @"2. Marks a chat as seen when you send a message.\n"
             @"3. Marks a chat as seen when you reply.\n"
             @"4. Marks a chat as seen when you react.\n\n"
             @"Excluded Chats keep Instagram's normal seen behavior. Manage them from the eye button, an inbox long press, or the list above."
           : @"1. Prevents automatic seen receipts and adds an eye button to mark chats as seen.\n"
             @"2. Marks a chat as seen when you send a message.\n"
             @"3. Marks a chat as seen when you reply.\n"
             @"4. Marks a chat as seen when you react.\n\n"
             @"Included Chats require the eye button or the auto-seen triggers above. Manage them from the eye button, an inbox long press, or the list above."),
        SCITopicSection(@"Deleted Messages", @[
            [SCISetting switchCellWithTitle:@"Keep Deleted Messages" icon:SCISettingsIcon(@"undo_circle") defaultsKey:@"msgs_keep_deleted"],
            [SCISetting switchCellWithTitle:@"Confirm Inbox Refresh" icon:SCISettingsIcon(@"arrow_cw") defaultsKey:@"msgs_confirm_refresh"],
            [SCISetting switchCellWithTitle:@"Log Deleted Messages" icon:SCISettingsIcon(@"logs") defaultsKey:@"msgs_deleted_log"],
            [SCISetting switchCellWithTitle:@"Log Removed Reactions" icon:SCISettingsIcon(@"reactions") defaultsKey:@"msgs_deleted_log_reactions"],
            [SCISetting switchCellWithTitle:@"Respect Seen Chat List" icon:SCISettingsIcon(@"eye") defaultsKey:@"msgs_deleted_log_respect_seen_list"],
            [SCISetting navigationCellWithTitle:@"Deleted Messages Logs"
                                       subtitle:@""
                                           icon:SCISettingsIcon(@"channels")
                                 viewController:[SCIDeletedMessagesViewController new]],
        ], @"1. Preserves remotely unsent messages in the chat, marked with an undo-circle indicator.\n"
           @"2. Asks before refreshing the inbox, which reloads threads and drops preserved messages.\n"
           @"3. Records message content before removal and keeps view-once/view-twice media until cleared.\n"
           @"4. Also logs reactions that are removed.\n"
           @"5. Skips log capture and unsent notifications for chats in your manual-seen include/exclude list.\n"
           @"6. Opens the captured deleted-message logs."),
        SCITopicSection(@"Interface", @[
            [SCISetting switchCellWithTitle:@"Hide Typing Status" icon:SCISettingsIcon(@"keyboard") defaultsKey:@"msgs_disable_typing"],
            [SCISetting switchCellWithTitle:@"Hide Reels Blend Button" icon:SCISettingsIcon(@"blend") defaultsKey:@"msgs_hide_reels_blend"],
            [SCISetting switchCellWithTitle:@"Hide Audio Call Button" icon:SCISettingsIcon(@"call") defaultsKey:@"msgs_hide_audio_call_btn"],
            [SCISetting switchCellWithTitle:@"Hide Video Call Button" icon:SCISettingsIcon(@"video") defaultsKey:@"msgs_hide_video_call_btn"],
            [SCISetting switchCellWithTitle:@"No Suggested Chats" icon:SCISettingsIcon(@"question") defaultsKey:@"msgs_hide_suggested_chats"],
        ], @"1. Stops sending your typing indicator to others.\n"
           @"2. Removes the Reels Blend button from the inbox.\n"
           @"3. Hides the audio call button in the chat header.\n"
           @"4. Hides the video call button in the chat header.\n"
           @"5. Removes suggested chats from the inbox."),
        SCITopicSection(@"Visual Messages", @[
            [SCISetting switchCellWithTitle:@"Manually Mark Seen" icon:SCISettingsIcon(@"eye") defaultsKey:@"msgs_manual_visual_seen"],
            advanceVisual,
            [SCISetting switchCellWithTitle:@"Disable View-Once Limitations" icon:SCISettingsIcon(@"view_once") defaultsKey:@"msgs_disable_view_once"],
            [SCISetting switchCellWithTitle:@"Disable Screenshot Detection" icon:SCISettingsIcon(@"warning") defaultsKey:@"msgs_disable_screenshot_detection"]
        ], @"1. Prevents automatic seen receipts and adds a button to mark the chat as seen.\n"
           @"2. Moves to the next visual item when available or dismisses.\n"
           @"3. View-once messages behave like normal visual messages.\n"
           @"4. Allows screen capture of visual messages."),
        SCITopicSection(@"Vanish Mode", @[
            [SCISetting switchCellWithTitle:@"Disable Swipe-Up Gesture" icon:SCISettingsIcon(@"arrow_up") defaultsKey:@"msgs_disable_vanish_swipe_up"],
            [SCISetting switchCellWithTitle:@"Disable Screenshot Detection" icon:SCISettingsIcon(@"warning") defaultsKey:@"msgs_hide_vanish_screenshot"],
        ], @"1. Disable the gesture that enables vanish mode.\n"
           @"2. Allows screen capture while vanish mode is active."),
        SCITopicSection(@"Notes", @[
            [SCISetting switchCellWithTitle:@"Hide Notes Tray" icon:SCISettingsIcon(@"notes") defaultsKey:@"msgs_hide_notes_tray"],
            [SCISetting switchCellWithTitle:@"Hide Friends Map" icon:SCISettingsIcon(@"map") defaultsKey:@"msgs_hide_friends_map"],
            [SCISetting switchCellWithTitle:@"Note Theming" icon:SCISettingsIcon(@"palette") defaultsKey:@"msgs_notes_customization"],
            [SCISetting switchCellWithTitle:@"Custom Note Themes" icon:SCISettingsIcon(@"eyedropper") defaultsKey:@"msgs_custom_note_themes"],
            [SCISetting switchCellWithTitle:@"Download Notes Audio" icon:SCISettingsIcon(@"audio") defaultsKey:@"msgs_download_notes_audio" requiresRestart:YES]
        ], @"Note Theming enables Instagram's note theme picker. Custom Note Themes add custom emoji, background, and text color options."),
        SCITopicSection(@"Audio", @[
            [SCISetting switchCellWithTitle:@"Download Voice Messages" icon:SCISettingsIcon(@"audio_download") defaultsKey:@"msgs_download_audio_messages" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Upload Audio" icon:SCISettingsIcon(@"audio_upload") defaultsKey:@"msgs_upload_audio_messages" requiresRestart:YES]
        ], @"1. Adds audio actions to supported voice/audio message views.\n"
           @"2. Adds an option to the composer plus (+) menu that sends the selected audio or video as a voice message."),
        SCITopicSection(@"Media", @[
            [SCISetting switchCellWithTitle:@"Upload Photo from Gallery" icon:SCISettingsIcon(@"photo") defaultsKey:@"msgs_upload_gallery_media" requiresRestart:YES]
        ], @"Adds an option to the composer plus (+) menu that sends a photo from the SCInsta Gallery into the chat."),
        SCITopicSection(@"Confirmation", @[
            [SCISetting switchCellWithTitle:@"Confirm Audio Call" icon:SCISettingsIcon(@"call") defaultsKey:kSCIMessagesAudioCallConfirmKey],
            [SCISetting switchCellWithTitle:@"Confirm Video Call" icon:SCISettingsIcon(@"video") defaultsKey:kSCIMessagesVideoCallConfirmKey],
            [SCISetting switchCellWithTitle:@"Confirm Double Tap" icon:SCISettingsIcon(@"heart") defaultsKey:@"msgs_confirm_double_tap"],
            [SCISetting switchCellWithTitle:@"Confirm Reactions" icon:SCISettingsIcon(@"reactions") defaultsKey:@"msgs_confirm_reaction"],
            [SCISetting switchCellWithTitle:@"Confirm Voice Messages" icon:SCISettingsIcon(@"voice") defaultsKey:@"msgs_confirm_voice_msg"],
            [SCISetting switchCellWithTitle:@"Confirm Follow Requests" icon:SCISettingsIcon(@"user_request") defaultsKey:@"msgs_confirm_follow_request"],
            [SCISetting switchCellWithTitle:@"Confirm Vanish Mode" icon:SCISettingsIcon(@"vanish") defaultsKey:@"msgs_confirm_vanish_mode"],
            [SCISetting switchCellWithTitle:@"Confirm Changing Theme" icon:SCISettingsIcon(@"palette") defaultsKey:@"msgs_confirm_theme_change"]
        ], @"Shows confirmation alerts before the selected message actions are sent.")
    ];
}

@implementation SCIMessagesSettingsProvider

+ (SCISetting *)rootSetting {
    SCISetting *setting = [SCISetting navigationCellWithTitle:@"Messages"
                                                     subtitle:@""
                                                         icon:SCISettingsIcon(@"messages")
                                               viewController:[[SCIMessagesSettingsViewController alloc] init]];
    setting.searchSectionsProvider = ^NSArray *{
        return SCIMessagesSettingsSections();
    };
    return SCISettingApplyIconTint(setting, [SCIUtils SCIColor_InstagramPrimaryText]);
}

@end

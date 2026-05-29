#import "SCIMessagesSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../SCISettingsViewController.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../../Shared/Messages/SCIDirectSeenContext.h"
#import "../../Utils.h"

static NSString * const kSCIMessagesActionButtonEnabledKey = @"msgs_action_btn";
static NSString * const kSCIMessagesActionButtonDefaultActionKey = @"msgs_action_btn_default_action";
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
    if ([row.defaultsKey isEqualToString:@"msgs_manual_seen"]) {
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

    return @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Messages Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIMessagesActionButtonEnabledKey],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Default Tap Action" icon:SCISettingsIcon(@"action") menu:SCIActionButtonDefaultActionMenu(kSCIMessagesActionButtonDefaultActionKey, @"Messages", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceDirect))], SCISettingsIcon(@"action")),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceDirect, @"Messages", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceDirect), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceDirect))
        ], @"Choose what tapping the action button does. Long press opens the full menu."),
        SCITopicSection(@"Messaging", @[
            [SCISetting switchCellWithTitle:@"Manually Mark Seen" icon:SCISettingsIcon(@"eye") defaultsKey:@"msgs_manual_seen"],
            manualSeenList,
            [SCISetting switchCellWithTitle:@"Mark Seen on Message Send" icon:SCISettingsIcon(@"messages") defaultsKey:@"msgs_seen_on_send"],
            [SCISetting switchCellWithTitle:@"Mark Seen on Message Reply" icon:SCISettingsIcon(@"reply") defaultsKey:@"msgs_seen_on_reply"],
            [SCISetting switchCellWithTitle:@"Mark Seen on Reaction" icon:SCISettingsIcon(@"reactions") defaultsKey:@"msgs_seen_on_reaction"],
            [SCISetting switchCellWithTitle:@"Disable Typing Status" icon:SCISettingsIcon(@"keyboard") defaultsKey:@"msgs_disable_typing"],
            [SCISetting switchCellWithTitle:@"Hide Reels Blend Button" icon:SCISettingsIcon(@"blend") defaultsKey:@"msgs_hide_reels_blend"],
        ], manualSeen
           ? @"1. Prevents automatic seen receipts and adds a button to mark the chat as seen.\n"
             @"2. Excluded Chats use Instagram's normal seen behavior and can be managed from the eye button, inbox long press, or this list.\n"
             @"3. Marks messages as seen automatically when you send a new message.\n"
             @"4. Marks messages as seen automatically when you send a quoted reply.\n"
             @"5. Marks messages as seen automatically when you react to a message.\n"
             @"6. Prevents typing indicators from being shown to others."
           : @"1. Messages use Instagram's normal seen behavior except chats in Included Chats.\n"
             @"2. Included Chats require the eye button or enabled auto seen triggers to mark seen and can be managed from the eye button, inbox long press, or this list.\n"
             @"3. Marks messages as seen automatically when you send a new message.\n"
             @"4. Marks messages as seen automatically when you send a quoted reply.\n"
             @"5. Marks messages as seen automatically when you react to a message.\n"
             @"6. Prevents typing indicators from being shown to others."),
        SCITopicSection(@"", @[
            /// TODO: fix
            [SCISetting switchCellWithTitle:@"Keep Deleted Messages" icon:SCISettingsIcon(@"history") defaultsKey:@"msgs_keep_deleted"],
            [SCISetting switchCellWithTitle:@"No Suggested Chats" icon:SCISettingsIcon(@"question") defaultsKey:@"msgs_hide_suggested_chats"],
            [SCISetting switchCellWithTitle:@"Confirm Inbox Refresh" icon:SCISettingsIcon(@"arrow_cw") defaultsKey:@"msgs_confirm_refresh"]
        ], nil),
        SCITopicSection(@"Visual Messages", @[
            [SCISetting switchCellWithTitle:@"Manually Mark Seen" icon:SCISettingsIcon(@"eye") defaultsKey:@"msgs_manual_visual_seen"],
            [SCISetting switchCellWithTitle:@"Advance After Manual Seen" icon:SCISettingsIcon(@"autoscroll") defaultsKey:@"msgs_advance_visual_on_seen"],
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
            [SCISetting switchCellWithTitle:@"Download Audio Messages" icon:SCISettingsIcon(@"audio_download") defaultsKey:@"msgs_download_audio_messages" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Upload Audio Messages" icon:SCISettingsIcon(@"audio_upload") defaultsKey:@"msgs_upload_audio_messages" requiresRestart:YES]
        ], @"Downloads add audio actions to supported voice/audio message views. Upload converts selected audio or video to M4A when a compatible Instagram sender is available."),
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
    return SCISettingApplyIconTint([SCISetting navigationCellWithTitle:@"Messages"
                                                              subtitle:@""
                                                                  icon:SCISettingsIcon(@"messages")
                                                        viewController:[[SCIMessagesSettingsViewController alloc] init]],
                                   [SCIUtils SCIColor_InstagramPrimaryText]);
}

@end

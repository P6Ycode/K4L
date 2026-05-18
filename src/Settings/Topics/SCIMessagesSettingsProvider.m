#import "SCIMessagesSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../../Utils.h"

static NSString * const kSCIMessagesActionButtonEnabledKey = @"action_button_messages_enabled";
static NSString * const kSCIMessagesActionButtonDefaultActionKey = @"action_button_messages_default_action";
/// TODO: remove
static NSString * const kSCIMessagesLegacyCallConfirmKey = @"call_confirm";
static NSString * const kSCIMessagesAudioCallConfirmKey = @"call_confirm_audio";
static NSString * const kSCIMessagesVideoCallConfirmKey = @"call_confirm_video";

/// TODO: remove
static void SCIMigrateLegacyCallConfirmSettingIfNeeded(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id legacyValue = [defaults objectForKey:kSCIMessagesLegacyCallConfirmKey];
    if (!legacyValue) return;

    BOOL legacyEnabled = [defaults boolForKey:kSCIMessagesLegacyCallConfirmKey];
    if (![defaults objectForKey:kSCIMessagesAudioCallConfirmKey]) {
        [defaults setBool:legacyEnabled forKey:kSCIMessagesAudioCallConfirmKey];
    }
    if (![defaults objectForKey:kSCIMessagesVideoCallConfirmKey]) {
        [defaults setBool:legacyEnabled forKey:kSCIMessagesVideoCallConfirmKey];
    }
}

@implementation SCIMessagesSettingsProvider

+ (SCISetting *)rootSetting {
    /// TODO: remove
    SCIMigrateLegacyCallConfirmSettingIfNeeded();

    return SCITopicNavigationSetting(@"Messages", @"messages", 24.0, @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Messages Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIMessagesActionButtonEnabledKey],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Default Tap Action" icon:SCISettingsIcon(@"action") menu:SCIActionButtonDefaultActionMenu(kSCIMessagesActionButtonDefaultActionKey, @"Messages", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceDirect))], SCISettingsIcon(@"action")),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceDirect, @"Messages", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceDirect), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceDirect))
        ], @"Choose what tapping the action button does. Long press opens the full menu."),
        SCITopicSection(@"Messaging", @[
            [SCISetting switchCellWithTitle:@"Manually Mark Seen" icon:SCISettingsIcon(@"eye") defaultsKey:@"remove_lastseen"],
            [SCISetting switchCellWithTitle:@"Mark Seen on Send" icon:SCISettingsIcon(@"messages") defaultsKey:@"seen_auto_on_send"],
            [SCISetting switchCellWithTitle:@"Disable Typing Status" icon:SCISettingsIcon(@"keyboard") defaultsKey:@"disable_typing_status"],
            [SCISetting switchCellWithTitle:@"Hide Reels Blend Button" icon:SCISettingsIcon(@"blend") defaultsKey:@"hide_reels_blend"],
        ], @"1. Prevents automatic seen receipts and adds a button to mark the chat as seen.\n"
           @"2. Marks messages as seen automatically when you send a message or react.\n"
           @"3. Prevents typing indicators from being shown to others."),
        SCITopicSection(@"", @[
            /// TODO: fix
            [SCISetting switchCellWithTitle:@"Keep Deleted Messages" icon:SCISettingsIcon(@"history") defaultsKey:@"keep_deleted_message"],
            [SCISetting switchCellWithTitle:@"No Suggested Chats" icon:SCISettingsIcon(@"question") defaultsKey:@"no_suggested_chats"]
        ], nil),
        SCITopicSection(@"Visual Messages", @[
            [SCISetting switchCellWithTitle:@"Manually Mark Seen" icon:SCISettingsIcon(@"eye") defaultsKey:@"unlimited_replay"],
            [SCISetting switchCellWithTitle:@"Advance After Manual Seen" icon:SCISettingsIcon(@"autoscroll") defaultsKey:@"advance_direct_visual_when_marking_seen"],
            [SCISetting switchCellWithTitle:@"Disable View-Once Limitations" icon:SCISettingsIcon(@"view_once") defaultsKey:@"disable_view_once_limitations"],
            [SCISetting switchCellWithTitle:@"Disable Screenshot Detection" icon:SCISettingsIcon(@"warning") defaultsKey:@"remove_screenshot_alert"],
            [SCISetting switchCellWithTitle:@"Disable Instants Creation" icon:SCISettingsIcon(@"instants") defaultsKey:@"disable_instants_creation" requiresRestart:YES]
        ], @"1. Prevents automatic seen receipts and adds a button to mark the chat as seen.\n"
           @"2. Moves to the next visual item when available or dismisses.\n"
           @"3. View-once messages behave like normal visual messages.\n"
           @"4. Allows screen capture of visual messages."),
        SCITopicSection(@"Vanish Mode", @[
            [SCISetting switchCellWithTitle:@"Disable Swipe-Up Gesture" icon:SCISettingsIcon(@"arrow_up") defaultsKey:@"disable_disappearing_swipe_up"],
            [SCISetting switchCellWithTitle:@"Disable Screenshot Detection" icon:SCISettingsIcon(@"warning") defaultsKey:@"hide_vanish_screenshot"],
        ], @"1. Disable the gesture that enables vanish mode.\n"
           @"2. Allows screen capture while vanish mode is active."),
        SCITopicSection(@"Notes", @[
            [SCISetting switchCellWithTitle:@"Hide Notes Tray" icon:SCISettingsIcon(@"notes") defaultsKey:@"hide_notes_tray"],
            [SCISetting switchCellWithTitle:@"Hide Friends Map" icon:SCISettingsIcon(@"map") defaultsKey:@"hide_friends_map"],
            [SCISetting switchCellWithTitle:@"Note Theming" icon:SCISettingsIcon(@"palette") defaultsKey:@"enable_notes_customization"],
            [SCISetting switchCellWithTitle:@"Custom Note Themes" icon:SCISettingsIcon(@"eyedropper") defaultsKey:@"custom_note_themes"]
        ], @"Note Theming enables Instagram's note theme picker. Custom Note Themes add custom emoji, background, and text color options."),
        SCITopicSection(@"Confirmation", @[
            [SCISetting switchCellWithTitle:@"Confirm Audio Call" icon:SCISettingsIcon(@"call") defaultsKey:kSCIMessagesAudioCallConfirmKey],
            [SCISetting switchCellWithTitle:@"Confirm Video Call" icon:SCISettingsIcon(@"video") defaultsKey:kSCIMessagesVideoCallConfirmKey],
            [SCISetting switchCellWithTitle:@"Confirm Double Tap" icon:SCISettingsIcon(@"heart") defaultsKey:@"dm_message_double_tap_confirm"],
            [SCISetting switchCellWithTitle:@"Confirm Reactions" icon:SCISettingsIcon(@"reactions") defaultsKey:@"dm_message_reaction_confirm"],
            [SCISetting switchCellWithTitle:@"Confirm Voice Messages" icon:SCISettingsIcon(@"voice") defaultsKey:@"voice_message_confirm"],
            [SCISetting switchCellWithTitle:@"Confirm Follow Requests" icon:SCISettingsIcon(@"user_request") defaultsKey:@"follow_request_confirm"],
            [SCISetting switchCellWithTitle:@"Confirm Vanish Mode" icon:SCISettingsIcon(@"vanish") defaultsKey:@"shh_mode_confirm"],
            [SCISetting switchCellWithTitle:@"Confirm Changing Theme" icon:SCISettingsIcon(@"palette") defaultsKey:@"change_direct_theme_confirm"]
        ], @"Shows confirmation alerts before the selected message actions are sent.")
    ]);
}

@end

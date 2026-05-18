#import "SCIStoriesSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
static NSString * const kSCIStoriesActionButtonEnabledKey = @"action_button_stories_enabled";
static NSString * const kSCIStoriesActionButtonDefaultActionKey = @"action_button_stories_default_action";

@implementation SCIStoriesSettingsProvider

+ (SCISetting *)rootSetting {
    return SCITopicNavigationSetting(@"Stories", @"story", 24.0, @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Stories Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIStoriesActionButtonEnabledKey],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Default Tap Action" icon:SCISettingsIcon(@"action") menu:SCIActionButtonDefaultActionMenu(kSCIStoriesActionButtonDefaultActionKey, @"Stories", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceStories))], SCISettingsIcon(@"action")),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceStories, @"Stories", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceStories), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceStories))
        ], @"1. Add an action button above the bottom story bar.\n"
           @"2. Choose the default action. Long press opens the full menu."),
        SCITopicSection(@"Seen Receipts", @[
            [SCISetting switchCellWithTitle:@"Manually Mark Seen" icon:SCISettingsIcon(@"eye") defaultsKey:@"no_seen_receipt"],
            [SCISetting switchCellWithTitle:@"Mark Seen on Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"story_mark_seen_on_like"],
            [SCISetting switchCellWithTitle:@"Mark Seen on Reply" icon:SCISettingsIcon(@"reply") defaultsKey:@"story_mark_seen_on_reply"],
        ], @"1. Prevent automatic seen receipts and adds a button to mark the current story as seen.\n"
           @"2. Mark the story as seen when you press like.\n"
           @"3. Mark the story as seen when you send a reply."),
        SCITopicSection(@"Story Navigation", @[
            [SCISetting switchCellWithTitle:@"Stop Auto Advance" icon:SCISettingsIcon(@"autoscroll_off") defaultsKey:@"stop_story_auto_advance"],
            [SCISetting switchCellWithTitle:@"Advance on Eye Button" icon:SCISettingsIcon(@"eye") defaultsKey:@"advance_story_when_marking_seen"],
            [SCISetting switchCellWithTitle:@"Advance on Story Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"advance_story_when_like_marked_seen"],
            [SCISetting switchCellWithTitle:@"Advance on Story Reply" icon:SCISettingsIcon(@"reply") defaultsKey:@"advance_story_when_reply_marked_seen"],
        ], @"1. Prevent automatically moving to the next story.\n"
           @"2. Move to the next story when you press the eye button.\n"
           @"3. Move to the next story when you press like.\n"
           @"4. Move to the next story when you reply."),
        SCITopicSection(@"Confirmations", @[
            [SCISetting switchCellWithTitle:@"Confirm Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"like_confirm_stories"],
            [SCISetting switchCellWithTitle:@"Confirm Sticker Interaction" icon:SCISettingsIcon(@"sticker") defaultsKey:@"sticker_interact_confirm"]
        ], @"1. Show a confirmation alert when you try to like a story.\n"
           @"2. Show a confirmation alert when a story has a sticker and you tap on it."),
        SCITopicSection(@"Other", @[
            [SCISetting switchCellWithTitle:@"Show Story Mentions" icon:SCISettingsIcon(@"mention") defaultsKey:@"story_mentions_button"],
            [SCISetting switchCellWithTitle:@"Show Poll Vote Counts" icon:SCISettingsIcon(@"poll") defaultsKey:@"story_poll_vote_counts"],
            [SCISetting switchCellWithTitle:@"Use Detailed Color Picker" icon:SCISettingsIcon(@"eyedropper") defaultsKey:@"detailed_color_picker"]
        ], @"1. Enabling this will add a button above the bottom story bar, where you can see all mentioned users.\n"
           @"2. Display the vote counts for each option the poll has.\n"
           @"3. Long press on the eyedropper tool in stories to customize text color more precisely.")
    ]);
}

@end

#import "SCIStoriesSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../SCISettingsViewController.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../../Shared/Stories/SCIStoryContext.h"
#import "../../Utils.h"
static NSString * const kSCIStoriesActionButtonEnabledKey = @"action_button_stories_enabled";
static NSString * const kSCIStoriesActionButtonDefaultActionKey = @"action_button_stories_default_action";

static NSDictionary *SCIStoriesSeenReceiptsSection(void);
static NSArray *SCIStoriesSettingsSections(void);

@interface SCIStoriesSettingsViewController : SCISettingsViewController
@end

@implementation SCIStoriesSettingsViewController
- (instancetype)init {
    return [super initWithTitle:@"Stories" sections:SCIStoriesSettingsSections() reduceMargin:NO];
}

- (void)switchChanged:(UISwitch *)sender {
    SCISetting *row = [self settingForSender:sender];
    [super switchChanged:sender];
    if ([row.defaultsKey isEqualToString:@"no_seen_receipt"]) {
        [self replaceSections:SCIStoriesSettingsSections()];
    }
}
@end

static NSDictionary *SCIStoriesSeenReceiptsSection(void) {
    BOOL manualSeen = [SCIUtils getBoolPref:@"no_seen_receipt"];
    NSString *footer = manualSeen
        ? @"1. Stories are not marked seen automatically, except users in Excluded Users.\n"
          @"2. Excluded users use Instagram's normal seen behavior and do not need the eye button.\n"
          @"3. Mark the story as seen when you press like.\n"
          @"4. Mark the story as seen when you send a reply."
        : @"1. Stories use Instagram's normal seen behavior, except users in Included Users.\n"
          @"2. Included users require the eye button, story like, or story reply to mark seen.\n"
          @"3. Mark the story as seen when you press like.\n"
          @"4. Mark the story as seen when you send a reply.";
    return SCITopicSection(@"Seen Receipts", @[
        [SCISetting switchCellWithTitle:@"Manually Mark Seen" icon:SCISettingsIcon(@"eye") defaultsKey:@"no_seen_receipt"],
        [SCISetting navigationCellWithTitle:SCIStoryManualSeenListTitle(manualSeen)
                                   subtitle:@""
                                       icon:SCISettingsIcon(@"users")
                             viewController:SCIStoryManualSeenListViewController()],
        [SCISetting switchCellWithTitle:@"Mark Seen on Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"story_mark_seen_on_like"],
        [SCISetting switchCellWithTitle:@"Mark Seen on Reply" icon:SCISettingsIcon(@"reply") defaultsKey:@"story_mark_seen_on_reply"],
    ], footer);
}

static NSArray *SCIStoriesSettingsSections(void) {
    return @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Stories Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIStoriesActionButtonEnabledKey],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Default Tap Action" icon:SCISettingsIcon(@"action") menu:SCIActionButtonDefaultActionMenu(kSCIStoriesActionButtonDefaultActionKey, @"Stories", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceStories))], SCISettingsIcon(@"action")),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceStories, @"Stories", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceStories), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceStories))
        ], @"1. Add an action button above the bottom story bar.\n"
           @"2. Choose the default action. Long press opens the full menu."),
        SCIStoriesSeenReceiptsSection(),
        SCITopicSection(@"Story Navigation", @[
            [SCISetting switchCellWithTitle:@"Stop Auto Advance" icon:SCISettingsIcon(@"autoscroll") defaultsKey:@"stop_story_auto_advance"],
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
    ];
}

@implementation SCIStoriesSettingsProvider

+ (SCISetting *)rootSetting {
    return SCISettingApplyIconTint([SCISetting navigationCellWithTitle:@"Stories"
                                                              subtitle:@""
                                                                  icon:SCISettingsIcon(@"story")
                                                        viewController:[[SCIStoriesSettingsViewController alloc] init]],
                                   [SCIUtils SCIColor_InstagramPrimaryText]);
}

@end

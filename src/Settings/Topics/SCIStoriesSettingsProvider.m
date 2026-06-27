#import "SCIStoriesSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../SCISettingsViewController.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../../Shared/Stories/SCIStoryContext.h"
#import "../../Utils.h"
static NSString * const kSCIStoriesActionButtonEnabledKey = @"stories_action_btn";

static NSDictionary *SCIStoriesSeenReceiptsSection(void);
static NSArray *SCIStoriesSettingsSections(void);

@interface SCIStoriesSettingsViewController : SCISettingsViewController
@end

@implementation SCIStoriesSettingsViewController
- (instancetype)init {
    return [super initWithTitle:@"Stories" sections:SCIStoriesSettingsSections() reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self replaceSections:SCIStoriesSettingsSections()];
}

- (void)switchChanged:(UISwitch *)sender {
    SCISetting *row = [self settingForSender:sender];
    [super switchChanged:sender];
    if ([row.defaultsKey isEqualToString:@"stories_manual_seen"]) {
        [self replaceSections:SCIStoriesSettingsSections()];
    }
}
@end

static NSDictionary *SCIStoriesSeenReceiptsSection(void) {
    BOOL manualSeen = [SCIUtils getBoolPref:@"stories_manual_seen"];
    NSString *footer = manualSeen
        ? @"1. Stories are not marked seen automatically, except users in Excluded Users.\n"
          @"2. Mark the story as seen when you press like.\n"
          @"3. Mark the story as seen when you send a reply.\n"
          @"4. Excluded Users use Instagram's normal seen behavior and do not need the eye button."
        : @"1. Stories use Instagram's normal seen behavior, except users in Included Users.\n"
          @"2. Mark the story as seen when you press like.\n"
          @"3. Mark the story as seen when you send a reply.\n"
          @"4. Included Users require the eye button, story like, or story reply to mark seen.";
    SCISetting *manualSeenList = [SCISetting navigationCellWithTitle:SCIStoryManualSeenListTitle(manualSeen)
                                                            subtitle:@""
                                                                icon:SCISettingsIcon(@"users")
                                                      viewController:SCIStoryManualSeenListViewController()];
    manualSeenList.userInfo = @{@"accessoryText": [NSString stringWithFormat:@"%lu", (unsigned long)SCIStoryManualSeenUserList(manualSeen).count]};

    // The auto-seen triggers only do anything while manual seen is on. Keep their
    // stored value but lock the cells when manual seen is off.
    SCISetting *markSeenOnLike = [SCISetting switchCellWithTitle:@"Mark Seen on Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"stories_mark_seen_on_like"];
    SCISetting *markSeenOnReply = [SCISetting switchCellWithTitle:@"Mark Seen on Reply" icon:SCISettingsIcon(@"reply") defaultsKey:@"stories_mark_seen_on_reply"];
    markSeenOnLike.enabledProvider = ^BOOL{ return [SCIUtils getBoolPref:@"stories_manual_seen"]; };
    markSeenOnReply.enabledProvider = ^BOOL{ return [SCIUtils getBoolPref:@"stories_manual_seen"]; };

    return SCITopicSection(@"Seen Receipts", @[
        [SCISetting switchCellWithTitle:@"Manually Mark Seen" icon:SCISettingsIcon(@"eye") defaultsKey:@"stories_manual_seen"],
        markSeenOnLike,
        markSeenOnReply,
        manualSeenList,
    ], footer);
}

static NSArray *SCIStoriesSettingsSections(void) {
    return @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Stories Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIStoriesActionButtonEnabledKey],
            SCIActionButtonDefaultActionNavigationSetting(SCIActionButtonSourceStories),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceStories, @"Stories", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceStories), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceStories))
        ], @"1. Add an action button above the bottom story bar.\n"
           @"2. Choose the default action. Long press opens the full menu."),
        SCIStoriesSeenReceiptsSection(),
        SCITopicSection(@"Story Navigation", @[
            [SCISetting switchCellWithTitle:@"Stop Auto Advance" icon:SCISettingsIcon(@"autoscroll") defaultsKey:@"stories_stop_auto_advance"],
            [SCISetting switchCellWithTitle:@"Advance on Eye Button" icon:SCISettingsIcon(@"eye") defaultsKey:@"stories_advance_on_manual_seen"],
            [SCISetting switchCellWithTitle:@"Advance on Story Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"stories_advance_on_like_seen"],
            [SCISetting switchCellWithTitle:@"Advance on Story Reply" icon:SCISettingsIcon(@"reply") defaultsKey:@"stories_advance_on_reply_seen"],
        ], @"1. Prevent automatically moving to the next story.\n"
           @"2. Move to the next story when you press the eye button.\n"
           @"3. Move to the next story when you press like.\n"
           @"4. Move to the next story when you reply."),
        SCITopicSection(@"Confirmations", @[
            [SCISetting switchCellWithTitle:@"Confirm Like" icon:SCISettingsIcon(@"heart") defaultsKey:@"stories_confirm_like"],
            [SCISetting switchCellWithTitle:@"Confirm Quick Reaction" icon:SCISettingsIcon(@"reactions") defaultsKey:@"stories_confirm_quick_reaction"],
            [SCISetting switchCellWithTitle:@"Confirm Sticker Interaction" icon:SCISettingsIcon(@"sticker") defaultsKey:@"stories_confirm_sticker"]
        ], @"1. Show a confirmation alert when you try to like a story.\n"
           @"2. Show a confirmation alert when you tap a quick reaction emoji.\n"
           @"3. Show a confirmation alert when a story has a sticker and you tap on it."),
        SCITopicSection(@"Other", @[
            [SCISetting switchCellWithTitle:@"Show Story Mentions" icon:SCISettingsIcon(@"mention") defaultsKey:@"stories_mentions_btn"],
            [SCISetting switchCellWithTitle:@"Show Poll Vote Counts" icon:SCISettingsIcon(@"poll") defaultsKey:@"stories_poll_vote_counts"],
            [SCISetting switchCellWithTitle:@"Use Detailed Color Picker" icon:SCISettingsIcon(@"eyedropper") defaultsKey:@"stories_detailed_color_picker"]
        ], @"1. Enabling this will add a button above the bottom story bar, where you can see all mentioned users.\n"
           @"2. Display the vote counts for each option the poll has.\n"
           @"3. Long press on the eyedropper tool in stories to customize text color more precisely.")
    ];
}

@implementation SCIStoriesSettingsProvider

+ (SCISetting *)rootSetting {
    SCISetting *setting = [SCISetting navigationCellWithTitle:@"Stories"
                                                     subtitle:@""
                                                         icon:SCISettingsIcon(@"story")
                                               viewController:[[SCIStoriesSettingsViewController alloc] init]];
    setting.searchSectionsProvider = ^NSArray *{
        return SCIStoriesSettingsSections();
    };
    return SCISettingApplyIconTint(setting, [SCIUtils SCIColor_InstagramPrimaryText]);
}

@end

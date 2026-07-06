#import "SPKStoriesSettingsProvider.h"

#import "../../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../../Shared/Stories/SPKStoryContext.h"
#import "../../Utils.h"
#import "../SPKSettingsViewController.h"
#import "../SPKTopicSettingsSupport.h"
static NSString *const kSPKStoriesActionButtonEnabledKey = @"stories_action_btn";

static NSDictionary *SPKStoriesSeenReceiptsSection(void);
static NSArray *SPKStoriesSettingsSections(void);

@interface SPKStoriesSettingsViewController : SPKSettingsViewController
@end

@implementation SPKStoriesSettingsViewController
- (instancetype)init {
    return [super initWithTitle:@"Stories" sections:SPKStoriesSettingsSections() reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self replaceSections:SPKStoriesSettingsSections()];
}

- (void)switchChanged:(UISwitch *)sender {
    SPKSetting *row = [self settingForSender:sender];
    [super switchChanged:sender];
    if ([row.defaultsKey isEqualToString:@"stories_manual_seen"]) {
        [self replaceSections:SPKStoriesSettingsSections()];
    }
}
@end

static NSDictionary *SPKStoriesSeenReceiptsSection(void) {
    BOOL manualSeen = [SPKUtils getBoolPref:@"stories_manual_seen"];
    NSString *footer = manualSeen
                           ? @"1. Stories are not marked seen automatically, except users in Excluded Users.\n"
                             @"2. Mark the story as seen when you press like.\n"
                             @"3. Mark the story as seen when you send a reply.\n"
                             @"4. Excluded Users use Instagram's normal seen behavior and do not need the eye button."
                           : @"1. Stories use Instagram's normal seen behavior, except users in Included Users.\n"
                             @"2. Mark the story as seen when you press like.\n"
                             @"3. Mark the story as seen when you send a reply.\n"
                             @"4. Included Users require the eye button, story like, or story reply to mark seen.";
    SPKSetting *manualSeenList = [SPKSetting navigationCellWithTitle:SPKStoryManualSeenListTitle(manualSeen)
                                                            subtitle:@""
                                                                icon:SPKSettingsIcon(@"users")
                                                      viewController:SPKStoryManualSeenListViewController()];
    manualSeenList.userInfo = @{@"accessoryText" : [NSString stringWithFormat:@"%lu", (unsigned long)SPKStoryManualSeenUserList(manualSeen).count]};

    // The auto-seen triggers only do anything while manual seen is on. Keep their
    // stored value but lock the cells when manual seen is off.
    SPKSetting *markSeenOnLike = [SPKSetting switchCellWithTitle:@"Mark Seen on Like" icon:SPKSettingsIcon(@"heart") defaultsKey:@"stories_mark_seen_on_like"];
    SPKSetting *markSeenOnReply = [SPKSetting switchCellWithTitle:@"Mark Seen on Reply" icon:SPKSettingsIcon(@"reply") defaultsKey:@"stories_mark_seen_on_reply"];
    markSeenOnLike.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"stories_manual_seen"];
    };
    markSeenOnReply.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"stories_manual_seen"];
    };

    return SPKTopicSection(@"Seen Receipts", @[
        [SPKSetting switchCellWithTitle:@"Manually Mark Seen"
                                   icon:SPKSettingsIcon(@"eye")
                            defaultsKey:@"stories_manual_seen"],
        markSeenOnLike,
        markSeenOnReply,
        manualSeenList,
    ],
                           footer);
}

static NSArray *SPKStoriesSettingsSections(void) {
    return @[
        SPKTopicSection(@"Action Button", @[
            [SPKSetting switchCellWithTitle:@"Stories Action Button"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:kSPKStoriesActionButtonEnabledKey],
            SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSourceStories),
            SPKActionButtonConfigurationNavigationSetting(SPKActionButtonSourceStories, @"Stories", SPKActionButtonSupportedActionsForSource(SPKActionButtonSourceStories), SPKActionButtonDefaultSectionsForSource(SPKActionButtonSourceStories))
        ],
                        @"1. Add an action button above the bottom story bar.\n"
                        @"2. Choose the default action. Long press opens the full menu."),
        SPKStoriesSeenReceiptsSection(), SPKTopicSection(@"Story Navigation", @[
            [SPKSetting switchCellWithTitle:@"Stop Auto Advance"
                                       icon:SPKSettingsIcon(@"autoscroll")
                                defaultsKey:@"stories_stop_auto_advance"],
            [SPKSetting switchCellWithTitle:@"Advance on Eye Button"
                                       icon:SPKSettingsIcon(@"eye")
                                defaultsKey:@"stories_advance_on_manual_seen"],
            [SPKSetting switchCellWithTitle:@"Advance on Story Like"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"stories_advance_on_like_seen"],
            [SPKSetting switchCellWithTitle:@"Advance on Story Reply"
                                       icon:SPKSettingsIcon(@"reply")
                                defaultsKey:@"stories_advance_on_reply_seen"],
        ],
                                                         @"1. Prevent automatically moving to the next story.\n"
                                                         @"2. Move to the next story when you press the eye button.\n"
                                                         @"3. Move to the next story when you press like.\n"
                                                         @"4. Move to the next story when you reply."),
        SPKTopicSection(@"Confirmations", @[
            [SPKSetting switchCellWithTitle:@"Confirm Like"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"stories_confirm_like"],
            [SPKSetting switchCellWithTitle:@"Confirm Quick Reaction"
                                       icon:SPKSettingsIcon(@"reactions")
                                defaultsKey:@"stories_confirm_quick_reaction"],
            [SPKSetting switchCellWithTitle:@"Confirm Sticker Interaction"
                                       icon:SPKSettingsIcon(@"sticker")
                                defaultsKey:@"stories_confirm_sticker"]
        ],
                        @"1. Show a confirmation alert when you try to like a story.\n"
                        @"2. Show a confirmation alert when you tap a quick reaction emoji.\n"
                        @"3. Show a confirmation alert when a story has a sticker and you tap on it."),
        SPKTopicSection(@"Other", @[
            [SPKSetting switchCellWithTitle:@"Hide Join Trending"
                                       icon:SPKSettingsIcon(@"arrow_up_right")
                                defaultsKey:@"stories_hide_join_trending"],
            [SPKSetting switchCellWithTitle:@"Show Story Mentions"
                                       icon:SPKSettingsIcon(@"mention")
                                defaultsKey:@"stories_mentions_btn"],
            [SPKSetting switchCellWithTitle:@"Show Poll Vote Counts"
                                       icon:SPKSettingsIcon(@"poll")
                                defaultsKey:@"stories_poll_vote_counts"],
            [SPKSetting switchCellWithTitle:@"Use Detailed Color Picker"
                                       icon:SPKSettingsIcon(@"eyedropper")
                                defaultsKey:@"stories_detailed_color_picker"]
        ],
                        @"1. Enabling this will add a button above the bottom story bar, where you can see all mentioned users.\n"
                        @"2. Display the vote counts for each option the poll has.\n"
                        @"3. Long press on the eyedropper tool in stories to customize text color more precisely.")
    ];
}

@implementation SPKStoriesSettingsProvider

+ (SPKSetting *)rootSetting {
    SPKSetting *setting = [SPKSetting navigationCellWithTitle:@"Stories"
                                                     subtitle:@""
                                                         icon:SPKSettingsIcon(@"story")
                                               viewController:[[SPKStoriesSettingsViewController alloc] init]];
    setting.searchSectionsProvider = ^NSArray * {
        return SPKStoriesSettingsSections();
    };
    return SPKSettingApplyIconTint(setting, [SPKUtils SPKColor_InstagramPrimaryText]);
}

@end

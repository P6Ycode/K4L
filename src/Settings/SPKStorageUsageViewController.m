#import "SPKStorageUsageViewController.h"

#import "../Shared/Avatars/SPKAvatarCache.h"
#import "../Shared/SPKStoragePaths.h"
#import "../Shared/UI/SPKIGAlertPresenter.h"
#import "../Utils.h"
#import "SPKTopicSettingsSupport.h"

@interface SPKStorageUsageViewController ()
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *breakdown;
@end

@implementation SPKStorageUsageViewController

- (instancetype)init {
    return [super initWithTitle:@"Storage" sections:@[] reduceMargin:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadStatsAndRebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadStatsAndRebuild];
}

- (void)reloadStatsAndRebuild {
    self.breakdown = [SPKStoragePaths storageBreakdown];
    [self rebuildSections];
}

- (NSString *)formattedKey:(NSString *)key {
    unsigned long long bytes = [self.breakdown[key] unsignedLongLongValue];
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)rebuildSections {
    NSMutableArray *sections = [NSMutableArray array];

    [sections addObject:SPKTopicSection(@"Overview", @[
                  [SPKSetting valueCellWithTitle:@"Total"
                                        subtitle:[self formattedKey:@"total"]
                                            icon:SPKSettingsIcon(@"info")],
              ],
                                        @"On-device storage used by all Sparkle data. Instagram's own cache is not included.")];

    [sections addObject:SPKTopicSection(@"Breakdown", @[
                  [SPKSetting valueCellWithTitle:@"Gallery"
                                        subtitle:[self formattedKey:@"gallery"]
                                            icon:SPKSettingsIcon(@"sparkle_gallery")],
                  [SPKSetting valueCellWithTitle:@"Downloads"
                                        subtitle:[self formattedKey:@"downloads"]
                                            icon:SPKSettingsIcon(@"download")],
                  [SPKSetting valueCellWithTitle:@"Deleted Messages"
                                        subtitle:[self formattedKey:@"deletedMessages"]
                                            icon:SPKSettingsIcon(@"messages")],
                  [SPKSetting valueCellWithTitle:@"Profile Analyzer"
                                        subtitle:[self formattedKey:@"profileAnalyzer"]
                                            icon:SPKSettingsIcon(@"profile_analyzer")],
                  [SPKSetting valueCellWithTitle:@"Profile Pictures"
                                        subtitle:[self formattedKey:@"avatars"]
                                            icon:SPKSettingsIcon(@"user_circle")],
              ],
                                        nil)];

    SPKSetting *clearAvatars = [SPKSetting buttonCellWithTitle:@"Clear Cached Profile Pictures"
                                                      subtitle:nil
                                                          icon:SPKSettingsIcon(@"user_circle")
                                                        action:^{
                                                            [self confirmClearAvatars];
                                                        }];
    clearAvatars.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearAvatars.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    [sections addObject:SPKTopicSection(@"Profile Pictures", @[ clearAvatars ],
                                        @"Profile pictures are a shared cache reused across Sparkle. Clearing them frees space; they re-download as needed.")];

    [self replaceSections:sections];
}

- (void)confirmClearAvatars {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Clear cached profile pictures?"
                                                message:@"This removes all on-device profile pictures. They will re-download when next shown."
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"Cancel"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:nil],
                                                    [SPKIGAlertAction actionWithTitle:@"Clear"
                                                                                style:SPKIGAlertActionStyleDestructive
                                                                              handler:^{
                                                                                  [[SPKAvatarCache shared] purge];
                                                                                  [self reloadStatsAndRebuild];
                                                                              }],
                                                ]];
}

@end

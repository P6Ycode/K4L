#import "SPKProfileAnalyzerViewController.h"
#import "SPKProfileAnalyzerModels.h"
#import "SPKProfileAnalyzerStorage.h"
#import "SPKProfileAnalyzerService.h"
#import "SPKProfileAnalyzerListViewController.h"
#import "SPKProfileAnalyzerAvatarView.h"
#import "SPKProfileAnalyzerAvatarCache.h"
#import "../../../Utils.h"
#import "../../../AssetUtils.h"
#import "../../../Shared/UI/SPKNotificationCenter.h"
#import "../../../Shared/UI/SPKMediaChrome.h"
#import "../../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../../Shared/UI/SPKSwitch.h"

#pragma mark - Category descriptor

typedef NS_ENUM(NSInteger, SPKPACategory) {
    SPKPACategoryMutual,
    SPKPACategoryNotFollowingBack,
    SPKPACategoryDontFollowBack,
    SPKPACategoryNewFollowers,
    SPKPACategoryLostFollowers,
    SPKPACategoryYouStartedFollowing,
    SPKPACategoryYouUnfollowed,
    SPKPACategoryProfileUpdates,
};

@interface SPKPACategoryRow : NSObject
@property (nonatomic, assign) SPKPACategory category;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, assign) NSInteger count;
@end
@implementation SPKPACategoryRow @end

#pragma mark - Scan pill button (progress fills inside the pill)

@interface SPKPAScanButton : UIControl
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) CALayer *fillLayer;
@property (nonatomic, assign) double progress;   // 0..1
@property (nonatomic, assign, getter=isScanning) BOOL scanning;
- (void)setProgress:(double)progress animated:(BOOL)animated;
@end

@implementation SPKPAScanButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    self.clipsToBounds = YES;

    _fillLayer = [CALayer layer];
    _fillLayer.anchorPoint = CGPointMake(0, 0);
    [self.layer addSublayer:_fillLayer];

    _label = [UILabel new];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    _label.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_label];
    [NSLayoutConstraint activateConstraints:@[
        [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_label.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:16.0],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16.0],
    ]];

    [self applyColors];
    return self;
}

// "Light in dark mode and vice versa": the pill fill tracks the primary-text
// color (white-ish in dark, black-ish in light); the title is the inverse. The
// progress fill is the same hue at full opacity over a dimmed track, so the pill
// visually "fills up" while scanning without a contrast-breaking accent color.
- (void)applyColors {
    UIColor *base = [SPKUtils SPKColor_InstagramPrimaryText];
    UIColor *text = [SPKUtils SPKColor_InstagramBackground];
    self.label.textColor = text;
    if (self.scanning) {
        self.backgroundColor = [base colorWithAlphaComponent:0.30];
        self.fillLayer.backgroundColor = base.CGColor;
        self.fillLayer.hidden = NO;
    } else {
        self.backgroundColor = base;
        self.fillLayer.hidden = YES;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2.0;   // pill
    [self updateFillFrameAnimated:NO];
    [self applyColors];   // re-resolve CGColor for the current trait collection
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self applyColors];
}

- (void)updateFillFrameAnimated:(BOOL)animated {
    CGFloat w = self.bounds.size.width * MAX(0.0, MIN(1.0, self.progress));
    CGRect target = CGRectMake(0, 0, w, self.bounds.size.height);
    if (!animated) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.fillLayer.frame = target;
        [CATransaction commit];
    } else {
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.25];
        self.fillLayer.frame = target;
        [CATransaction commit];
    }
}

- (void)setScanning:(BOOL)scanning {
    _scanning = scanning;
    if (!scanning) { _progress = 0; }
    [self applyColors];
    [self updateFillFrameAnimated:NO];
}

- (void)setProgress:(double)progress animated:(BOOL)animated {
    _progress = MAX(0.0, MIN(1.0, progress));
    [self updateFillFrameAnimated:animated];
}

- (void)setText:(NSString *)text { self.label.text = text; }

@end

#pragma mark - Identity header

@interface SPKPAIdentityHeader : UIView
@property (nonatomic, strong) SPKProfileAnalyzerAvatarView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIStackView *statsRow;
@property (nonatomic, strong) UILabel *scanDateLabel;
@property (nonatomic, strong) SPKPAScanButton *scanButton;
@end

@implementation SPKPAIdentityHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    self.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];

    _avatarView = [[SPKProfileAnalyzerAvatarView alloc] initWithFrame:CGRectZero];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_avatarView];

    _nameLabel = [UILabel new];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    _nameLabel.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    _nameLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_nameLabel];

    _usernameLabel = [UILabel new];
    _usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _usernameLabel.font = [UIFont systemFontOfSize:14.0];
    _usernameLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    _usernameLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_usernameLabel];

    _statsRow = [[UIStackView alloc] init];
    _statsRow.translatesAutoresizingMaskIntoConstraints = NO;
    _statsRow.axis = UILayoutConstraintAxisHorizontal;
    _statsRow.distribution = UIStackViewDistributionFillEqually;
    _statsRow.alignment = UIStackViewAlignmentCenter;
    [self addSubview:_statsRow];

    _scanDateLabel = [UILabel new];
    _scanDateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _scanDateLabel.font = [UIFont systemFontOfSize:12.0];
    _scanDateLabel.textColor = [SPKUtils SPKColor_InstagramTertiaryText];
    _scanDateLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_scanDateLabel];

    _scanButton = [[SPKPAScanButton alloc] initWithFrame:CGRectZero];
    _scanButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_scanButton];

    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.topAnchor constraintEqualToAnchor:self.topAnchor constant:20.0],
        [_avatarView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_avatarView.widthAnchor constraintEqualToConstant:88.0],
        [_avatarView.heightAnchor constraintEqualToConstant:88.0],

        [_nameLabel.topAnchor constraintEqualToAnchor:_avatarView.bottomAnchor constant:10.0],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],

        [_usernameLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2.0],
        [_usernameLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_usernameLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],

        [_statsRow.topAnchor constraintEqualToAnchor:_usernameLabel.bottomAnchor constant:16.0],
        [_statsRow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24.0],
        [_statsRow.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24.0],
        [_statsRow.heightAnchor constraintEqualToConstant:44.0],

        [_scanButton.topAnchor constraintEqualToAnchor:_statsRow.bottomAnchor constant:16.0],
        [_scanButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [_scanButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
        [_scanButton.heightAnchor constraintEqualToConstant:48.0],

        [_scanDateLabel.topAnchor constraintEqualToAnchor:_scanButton.bottomAnchor constant:10.0],
        [_scanDateLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24.0],
        [_scanDateLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24.0],
        [_scanDateLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-20.0],
    ]];
    return self;
}

- (UIView *)statColumnValue:(NSString *)value caption:(NSString *)caption {
    UIStackView *col = [[UIStackView alloc] init];
    col.axis = UILayoutConstraintAxisVertical;
    col.alignment = UIStackViewAlignmentCenter;
    col.distribution = UIStackViewDistributionFill;
    col.spacing = 1.0;

    UILabel *v = [UILabel new];
    v.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    v.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    v.textAlignment = NSTextAlignmentCenter;
    v.text = value;
    [col addArrangedSubview:v];

    UILabel *c = [UILabel new];
    c.font = [UIFont systemFontOfSize:12.0];
    c.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    c.textAlignment = NSTextAlignmentCenter;
    c.text = caption;
    [col addArrangedSubview:c];

    return col;
}

- (void)setStatsPosts:(NSString *)posts followers:(NSString *)followers following:(NSString *)following {
    for (UIView *v in self.statsRow.arrangedSubviews) { [self.statsRow removeArrangedSubview:v]; [v removeFromSuperview]; }
    [self.statsRow addArrangedSubview:[self statColumnValue:posts caption:@"Posts"]];
    [self.statsRow addArrangedSubview:[self statColumnValue:followers caption:@"Followers"]];
    [self.statsRow addArrangedSubview:[self statColumnValue:following caption:@"Following"]];
}

@end

#pragma mark - Main VC

@interface SPKProfileAnalyzerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) SPKPAIdentityHeader *header;
@property (nonatomic, strong) SPKProfileAnalyzerReport *report;
@property (nonatomic, strong) NSArray<SPKProfileAnalyzerVisit *> *visits;
@property (nonatomic, copy) NSArray<SPKPACategoryRow *> *currentRows;   // section: current snapshot
@property (nonatomic, copy) NSArray<SPKPACategoryRow *> *changeRows;    // section: changes vs previous
@property (nonatomic, copy) NSString *selfPK;
@property (nonatomic, assign) BOOL trackVisits;
@end

@implementation SPKProfileAnalyzerViewController

+ (void)presentFromTop {
    UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    // Don't stack a second analyzer if one is already on screen.
    UIViewController *probe = root;
    while (probe) {
        if ([probe isKindOfClass:[SPKProfileAnalyzerViewController class]]) return;
        if ([probe isKindOfClass:[UINavigationController class]]) {
            for (UIViewController *vc in ((UINavigationController *)probe).viewControllers) {
                if ([vc isKindOfClass:[SPKProfileAnalyzerViewController class]]) return;
            }
        }
        probe = probe.presentingViewController;
    }
    SPKProfileAnalyzerViewController *analyzer = [SPKProfileAnalyzerViewController new];
    UINavigationController *nav = [[SPKChromeNavigationController alloc] initWithRootViewController:analyzer];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [root presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Profile Analyzer";
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.selfPK = [SPKUtils currentUserPK];

    if (self.navigationController.viewControllers.firstObject == self) {
        SPKMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ SPKMediaChromeTopBarButtonItem(@"xmark", self, @selector(closeTapped)) ]);
    }

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SPKUtils SPKColor_InstagramSeparator];
    self.tableView.tintColor = [SPKUtils SPKColor_InstagramBlue];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56.0;
    self.tableView.sectionHeaderTopPadding = 0;
    [self.view addSubview:self.tableView];

    [self buildTableHeader];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataChanged:) name:SPKProfileAnalyzerDataDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(progressChanged:) name:SPKProfileAnalyzerProgressDidChangeNotification object:nil];

    [self loadCachedData];
    [self paintHeaderIdentity];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // Intentionally NOT cancelling the service — scans run in the background and
    // report completion via the notification pill.
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.trackVisits = [SPKUtils getBoolPref:@"profile_analyzer_track_visits"];
    [self loadCachedData];
    [self paintHeaderIdentity];
    [self syncRunningState];
}

#pragma mark - Header

- (void)buildTableHeader {
    self.headerContainer = [UIView new];
    self.header = [[SPKPAIdentityHeader alloc] init];
    self.header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerContainer addSubview:self.header];
    [self.header.scanButton addTarget:self action:@selector(scanTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.header.scanButton setText:@"Run Analysis"];

    [NSLayoutConstraint activateConstraints:@[
        [self.header.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor],
        [self.header.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor],
        [self.header.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor],
        [self.header.bottomAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor],
    ]];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGFloat w = self.tableView.bounds.size.width;
    if (w < 1) return;
    self.headerContainer.frame = CGRectMake(0, 0, w, 1);
    [self.headerContainer setNeedsLayout];
    [self.headerContainer layoutIfNeeded];
    CGFloat h = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height)
                                   withHorizontalFittingPriority:UILayoutPriorityRequired
                                         verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGRect target = CGRectMake(0, 0, w, h);
    if (!CGRectEqualToRect(self.headerContainer.frame, target) || self.tableView.tableHeaderView != self.headerContainer) {
        self.headerContainer.frame = target;
        self.tableView.tableHeaderView = self.headerContainer;
    }
}

static NSString *SPKPACompact(NSInteger n) {
    if (n >= 1000000) return [NSString stringWithFormat:@"%.1fM", n / 1000000.0];
    if (n >= 10000)   return [NSString stringWithFormat:@"%.0fK", n / 1000.0];
    if (n >= 1000)    return [NSString stringWithFormat:@"%.1fK", n / 1000.0];
    return [NSString stringWithFormat:@"%ld", (long)n];
}

- (void)paintHeaderIdentity {
    NSDictionary *cached = [SPKProfileAnalyzerStorage headerInfoForUserPK:self.selfPK];
    SPKProfileAnalyzerSnapshot *cur = self.report.current;

    NSString *username = cached[@"username"] ?: cur.selfUsername;
    NSString *fullName = cached[@"full_name"] ?: cur.selfFullName;
    BOOL haveData = (cached != nil) || (cur != nil);
    NSInteger followers = cached[@"follower_count"] ? [cached[@"follower_count"] integerValue] : cur.followerCount;
    NSInteger following = cached[@"following_count"] ? [cached[@"following_count"] integerValue] : cur.followingCount;
    NSInteger posts = cached[@"media_count"] ? [cached[@"media_count"] integerValue] : cur.mediaCount;
    NSString *picURL = cached[@"profile_pic_url"] ?: cur.selfProfilePicURL;

    self.header.nameLabel.text = fullName.length ? fullName : (username.length ? username : @"Profile Analyzer");
    self.header.usernameLabel.text = username.length ? [NSString stringWithFormat:@"@%@", username] : @"";
    [self.header setStatsPosts:haveData ? SPKPACompact(posts) : @"—"
                     followers:haveData ? SPKPACompact(followers) : @"—"
                     following:haveData ? SPKPACompact(following) : @"—"];

    if (cur.scanDate) {
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateStyle = NSDateFormatterMediumStyle;
        df.timeStyle = NSDateFormatterShortStyle;
        df.doesRelativeDateFormatting = YES;
        self.header.scanDateLabel.text = [NSString stringWithFormat:@"Last analyzed %@", [df stringFromDate:cur.scanDate]];
    } else {
        self.header.scanDateLabel.text = @"Not analyzed yet";
    }

    if (picURL.length && self.selfPK.length) {
        [self.header.avatarView configureWithPK:self.selfPK urlString:picURL];
    }

    if (!self.header.scanButton.isScanning) {
        [self.header.scanButton setText:(self.report.current ? @"Re-run Analysis" : @"Run Analysis")];
    }
    [self.view setNeedsLayout];
}

#pragma mark - Data

- (void)dataChanged:(NSNotification *)note {
    NSString *pk = note.userInfo[@"user_pk"];
    if (pk.length && self.selfPK.length && ![pk isEqualToString:self.selfPK]) return;
    [self loadCachedData];
    [self paintHeaderIdentity];
}

- (void)loadCachedData {
    if (!self.selfPK.length) self.selfPK = [SPKUtils currentUserPK];
    SPKProfileAnalyzerSnapshot *cur = [SPKProfileAnalyzerStorage currentSnapshotForUserPK:self.selfPK];
    SPKProfileAnalyzerSnapshot *prev = [SPKProfileAnalyzerStorage previousSnapshotForUserPK:self.selfPK];
    self.report = [SPKProfileAnalyzerReport reportFromCurrent:cur previous:prev];
    self.visits = [SPKProfileAnalyzerStorage visitedProfilesForUserPK:self.selfPK];
    [self rebuildRows];
    [self.tableView reloadData];
}

- (SPKPACategoryRow *)row:(SPKPACategory)cat title:(NSString *)title icon:(NSString *)icon count:(NSInteger)count {
    SPKPACategoryRow *r = [SPKPACategoryRow new];
    r.category = cat; r.title = title; r.iconName = icon; r.count = count;
    return r;
}

- (void)rebuildRows {
    SPKProfileAnalyzerReport *rep = self.report;
    NSMutableArray *current = [NSMutableArray array];
    NSMutableArray *changes = [NSMutableArray array];
    if (rep.current) {
        [current addObject:[self row:SPKPACategoryMutual title:@"Mutual Followers" icon:@"user_check" count:rep.mutualFollowers.count]];
        [current addObject:[self row:SPKPACategoryNotFollowingBack title:@"Not Following You Back" icon:@"user_unfollow" count:rep.notFollowingYouBack.count]];
        [current addObject:[self row:SPKPACategoryDontFollowBack title:@"You Don't Follow Back" icon:@"user_follow" count:rep.youDontFollowBack.count]];
    }
    if (rep.previous) {
        [changes addObject:[self row:SPKPACategoryNewFollowers title:@"New Followers" icon:@"face_happy" count:rep.recentFollowers.count]];
        [changes addObject:[self row:SPKPACategoryLostFollowers title:@"Lost Followers" icon:@"face_sad" count:rep.lostFollowers.count]];
        [changes addObject:[self row:SPKPACategoryYouStartedFollowing title:@"You Started Following" icon:@"user_follow" count:rep.youStartedFollowing.count]];
        [changes addObject:[self row:SPKPACategoryYouUnfollowed title:@"You Unfollowed" icon:@"user_unfollow" count:rep.youUnfollowed.count]];
        [changes addObject:[self row:SPKPACategoryProfileUpdates title:@"Profile Updates" icon:@"edit" count:rep.profileUpdates.count]];
    }
    self.currentRows = current;
    self.changeRows = changes;
}

#pragma mark - Scan

- (void)scanTapped {
    SPKProfileAnalyzerService *svc = [SPKProfileAnalyzerService sharedService];
    if (svc.isRunning) return;
    if (!self.selfPK.length) self.selfPK = [SPKUtils currentUserPK];

    [self setScanning:YES];

    SPKNotificationPillView *pill = nil;
    if (SPKNotificationIsEnabled(kSPKNotificationProfileAnalyzerComplete)) {
        pill = SPKNotifyProgress(kSPKNotificationProfileAnalyzerComplete, @"Analyzing profile...", ^{
            [[SPKProfileAnalyzerService sharedService] cancel];
        });
        [pill setProgress:0.02f animated:NO];
        // Tapping the pill (during the scan or after it completes) jumps into
        // the analyzer.
        pill.onTapWhenProgress = ^{ [SPKProfileAnalyzerViewController presentFromTop]; };
    }

    __weak typeof(self) weakSelf = self;
    [svc runForSelfWithHeaderInfo:^(NSDictionary *userInfo) {
        [weakSelf paintHeaderIdentity];
    } progress:^(NSString *status, double fraction) {
        [pill updateProgressTitle:@"Analyzing profile..." subtitle:status];
        [pill setProgress:(float)fraction animated:YES];
    } completion:^(SPKProfileAnalyzerSnapshot *snapshot, NSError *error) {
        [weakSelf setScanning:NO];
        if (error) {
            if (error.code == SPKProfileAnalyzerErrorCancelled) {
                [pill dismiss];
            } else {
                [pill showErrorWithTitle:@"Analysis failed" subtitle:error.localizedDescription icon:nil];
                SPKNotificationTriggerHaptic(kSPKNotificationProfileAnalyzerComplete, SPKNotificationToneError);
            }
            return;
        }
        [pill setProgress:1.0f animated:YES];
        [pill showSuccessWithTitle:@"Analysis complete" subtitle:@"Tap to view results" icon:nil];
        pill.onTapWhenCompleted = ^{ [SPKProfileAnalyzerViewController presentFromTop]; };
        SPKNotificationTriggerHaptic(kSPKNotificationProfileAnalyzerComplete, SPKNotificationToneSuccess);
        // Auto-dismiss after the configured pill duration (progress pills don't
        // self-dismiss on completion, so schedule it explicitly).
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SPKNotificationPillDuration() * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (pill.superview) [pill dismiss];
        });
        [weakSelf loadCachedData];
        [weakSelf paintHeaderIdentity];
    }];
}

- (void)setScanning:(BOOL)scanning {
    self.header.scanButton.scanning = scanning;
    if (scanning) {
        [self.header.scanButton setText:@"Analyzing..."];
        [self.header.scanButton setProgress:MAX(0.02, [SPKProfileAnalyzerService sharedService].currentFraction) animated:NO];
    } else {
        [self.header.scanButton setText:(self.report.current ? @"Re-run Analysis" : @"Run Analysis")];
    }
}

- (void)syncRunningState {
    SPKProfileAnalyzerService *svc = [SPKProfileAnalyzerService sharedService];
    if (svc.isRunning) {
        [self setScanning:YES];
        [self.header.scanButton setProgress:svc.currentFraction animated:NO];
        if (svc.currentStatus.length) [self.header.scanButton setText:svc.currentStatus];
    } else {
        [self setScanning:NO];
    }
}

- (void)progressChanged:(NSNotification *)note {
    if (![note.userInfo[@"running"] boolValue]) { [self setScanning:NO]; return; }
    if (!self.header.scanButton.isScanning) [self setScanning:YES];
    [self.header.scanButton setProgress:[note.userInfo[@"fraction"] doubleValue] animated:YES];
    NSString *status = note.userInfo[@"status"];
    if (status.length) [self.header.scanButton setText:status];
}

#pragma mark - Section model

// Row identifiers for the non-category list rows.
typedef NS_ENUM(NSInteger, SPKPAOptionRow) {
    SPKPAOptionTrackVisits,
    SPKPAOptionVisitedProfiles,
    SPKPAOptionAbout,
};

typedef NS_ENUM(NSInteger, SPKPASectionKind) {
    SPKPASectionEmpty,     // no scan yet — single explanatory row
    SPKPASectionCurrent,   // mutuals / not-following-back / don't-follow-back
    SPKPASectionChanges,   // new/lost/started/unfollowed/updates (needs 2 scans)
    SPKPASectionOptions,   // track visits + visited profiles + about
    SPKPASectionReset,     // reset data (destructive)
};

- (NSArray<NSNumber *> *)activeSections {
    NSMutableArray *s = [NSMutableArray array];
    if (!self.report.current) {
        [s addObject:@(SPKPASectionEmpty)];
    } else {
        [s addObject:@(SPKPASectionCurrent)];
        if (self.changeRows.count > 0) [s addObject:@(SPKPASectionChanges)];
    }
    [s addObject:@(SPKPASectionOptions)];
    [s addObject:@(SPKPASectionReset)];
    return s;
}

// The option rows present in the Options section (Visited Profiles only shows
// when tracking is enabled).
- (NSArray<NSNumber *> *)optionRows {
    NSMutableArray *rows = [NSMutableArray arrayWithObject:@(SPKPAOptionTrackVisits)];
    if (self.trackVisits) [rows addObject:@(SPKPAOptionVisitedProfiles)];
    [rows addObject:@(SPKPAOptionAbout)];
    return rows;
}

- (SPKPASectionKind)kindForSection:(NSInteger)section {
    return (SPKPASectionKind)[[self activeSections][section] integerValue];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self activeSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self kindForSection:section]) {
        case SPKPASectionEmpty:    return 1;
        case SPKPASectionCurrent:  return self.currentRows.count;
        case SPKPASectionChanges:  return self.changeRows.count;
        case SPKPASectionOptions:  return [self optionRows].count;
        case SPKPASectionReset:    return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self kindForSection:section]) {
        case SPKPASectionEmpty:    return nil;
        case SPKPASectionCurrent:  return @"This Scan";
        case SPKPASectionChanges:  return @"Since Last Scan";
        case SPKPASectionOptions:  return @"Options";
        case SPKPASectionReset:    return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPKPASectionKind kind = [self kindForSection:indexPath.section];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    cell.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];
    cell.tintColor = [SPKUtils SPKColor_InstagramBlue];
    UIView *selected = [UIView new];
    selected.backgroundColor = [SPKUtils SPKColor_InstagramPressedBackground];
    cell.selectedBackgroundView = selected;
    content.textProperties.color = [SPKUtils SPKColor_InstagramPrimaryText];
    content.secondaryTextProperties.color = [SPKUtils SPKColor_InstagramSecondaryText];

    if (kind == SPKPASectionEmpty) {
        content.text = @"No analysis yet";
        content.secondaryText = @"Tap Run Analysis to fetch your followers and following.";
        content.secondaryTextProperties.numberOfLines = 0;
        content.textToSecondaryTextVerticalPadding = 4.5;
        content.image = [SPKAssetUtils instagramIconNamed:@"profile_analyzer" pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        content.imageProperties.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.contentConfiguration = content;
        return cell;
    }

    if (kind == SPKPASectionReset) {
        content.text = @"Reset Profile Analyzer Data";
        content.textProperties.color = [SPKUtils SPKColor_InstagramDestructive];
        content.image = [SPKAssetUtils instagramIconNamed:@"trash" pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        content.imageProperties.tintColor = [SPKUtils SPKColor_InstagramDestructive];
        cell.contentConfiguration = content;
        return cell;
    }

    if (kind == SPKPASectionOptions) {
        SPKPAOptionRow opt = (SPKPAOptionRow)[[self optionRows][indexPath.row] integerValue];
        if (opt == SPKPAOptionTrackVisits) {
            content.text = @"Track Visited Profiles";
            content.image = [SPKAssetUtils instagramIconNamed:@"eye" pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
            content.imageProperties.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
            SPKSwitch *toggle = [SPKSwitch new];
            toggle.on = self.trackVisits;
            [toggle addTarget:self action:@selector(trackVisitsToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (opt == SPKPAOptionVisitedProfiles) {
            content.text = @"Visited Profiles";
            content.image = [SPKAssetUtils instagramIconNamed:@"history" pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
            content.imageProperties.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
            content.secondaryText = [NSString stringWithFormat:@"%lu", (unsigned long)self.visits.count];
            content.prefersSideBySideTextAndSecondaryText = YES;
            content.secondaryTextProperties.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightMedium];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else { // About
            content.text = @"About Profile Analyzer";
            content.image = [SPKAssetUtils instagramIconNamed:@"info" pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
            content.imageProperties.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        cell.contentConfiguration = content;
        return cell;
    }

    SPKPACategoryRow *r = (kind == SPKPASectionCurrent) ? self.currentRows[indexPath.row] : self.changeRows[indexPath.row];
    content.text = r.title;
    content.image = [SPKAssetUtils instagramIconNamed:r.iconName pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    content.imageProperties.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];

    // Count shown as a side-by-side secondary value, matching settings' accessory text.
    content.secondaryText = [NSString stringWithFormat:@"%ld", (long)r.count];
    content.prefersSideBySideTextAndSecondaryText = YES;
    content.secondaryTextProperties.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightMedium];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SPKPASectionKind kind = [self kindForSection:indexPath.section];

    if (kind == SPKPASectionEmpty) return;

    if (kind == SPKPASectionReset) {
        [self confirmReset];
        return;
    }

    if (kind == SPKPASectionOptions) {
        SPKPAOptionRow opt = (SPKPAOptionRow)[[self optionRows][indexPath.row] integerValue];
        if (opt == SPKPAOptionVisitedProfiles) [self openVisitedList];
        else if (opt == SPKPAOptionAbout) [self showAbout];
        return;
    }

    SPKPACategoryRow *r = (kind == SPKPASectionCurrent) ? self.currentRows[indexPath.row] : self.changeRows[indexPath.row];
    [self openCategory:r.category title:r.title];
}

#pragma mark - Options actions

- (void)trackVisitsToggled:(SPKSwitch *)toggle {
    SPKPreferenceSetObject(@(toggle.isOn), @"profile_analyzer_track_visits");
    self.trackVisits = toggle.isOn;
    NSInteger optionsIndex = [[self activeSections] indexOfObject:@(SPKPASectionOptions)];
    if (optionsIndex != NSNotFound) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:optionsIndex] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)showAbout {
    NSString *message =
        @"Profile Analyzer fetches your full followers and following lists and stores them on-device. "
        @"Each analysis is compared to the previous one to surface new and lost followers, who you started "
        @"following or unfollowed, and profile changes.\n\n"
        @"Because Instagram limits how many requests can be made in a short window, accounts with more than "
        @"13,000 total connections (followers + following) can't be analyzed. Analysis runs in the background — "
        @"you'll get a notification when it finishes.\n\n"
        @"All data stays on your device and is never uploaded.";
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"About Profile Analyzer"
                                                message:message
                                                actions:@[
        [SPKIGAlertAction actionWithTitle:@"OK" style:SPKIGAlertActionStyleCancel handler:nil],
    ]];
}

- (void)confirmReset {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Reset Profile Analyzer"
                                                message:@"This deletes all stored snapshots, visited-profile history and cached avatars. This cannot be undone."
                                                actions:@[
        [SPKIGAlertAction actionWithTitle:@"Cancel" style:SPKIGAlertActionStyleCancel handler:nil],
        [SPKIGAlertAction actionWithTitle:@"Reset" style:SPKIGAlertActionStyleDestructive handler:^{
            [SPKProfileAnalyzerStorage resetAll];
            [[SPKProfileAnalyzerAvatarCache shared] purge];
            [self loadCachedData];
            [self paintHeaderIdentity];
        }],
    ]];
}

- (void)openVisitedList {
    SPKProfileAnalyzerListViewController *vc =
        [[SPKProfileAnalyzerListViewController alloc] initVisitedListWithTitle:@"Visited Profiles" visits:self.visits];
    NSString *owner = self.selfPK;
    vc.onRemoveVisit = ^(SPKProfileAnalyzerVisit *visit) {
        [SPKProfileAnalyzerStorage removeVisitForUserPK:owner visitedPK:visit.user.pk];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openCategory:(SPKPACategory)cat title:(NSString *)title {
    SPKProfileAnalyzerReport *r = self.report;
    NSArray<SPKProfileAnalyzerUser *> *users = nil;
    SPKPAListKind kind = SPKPAListKindPlain;

    switch (cat) {
        case SPKPACategoryMutual:              users = r.mutualFollowers;      kind = SPKPAListKindUnfollow; break;
        case SPKPACategoryNotFollowingBack:    users = r.notFollowingYouBack;  kind = SPKPAListKindUnfollow; break;
        case SPKPACategoryDontFollowBack:      users = r.youDontFollowBack;    kind = SPKPAListKindFollow;   break;
        case SPKPACategoryNewFollowers:        users = r.recentFollowers;      kind = SPKPAListKindFollow;   break;
        case SPKPACategoryLostFollowers:       users = r.lostFollowers;        kind = SPKPAListKindPlain;    break;
        case SPKPACategoryYouStartedFollowing: users = r.youStartedFollowing;  kind = SPKPAListKindUnfollow; break;
        case SPKPACategoryYouUnfollowed:       users = r.youUnfollowed;        kind = SPKPAListKindFollow;   break;
        case SPKPACategoryProfileUpdates: {
            SPKProfileAnalyzerListViewController *vc =
                [[SPKProfileAnalyzerListViewController alloc] initWithTitle:title profileUpdates:r.profileUpdates];
            [self.navigationController pushViewController:vc animated:YES];
            return;
        }
    }

    SPKProfileAnalyzerListViewController *vc =
        [[SPKProfileAnalyzerListViewController alloc] initWithTitle:title users:users kind:kind];
    [self.navigationController pushViewController:vc animated:YES];
}

@end

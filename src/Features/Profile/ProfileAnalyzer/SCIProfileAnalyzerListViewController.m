#import "SCIProfileAnalyzerListViewController.h"
#import "SCIProfileAnalyzerAvatarView.h"
#import "../../../Networking/SCIInstagramAPI.h"
#import "../../../Utils.h"
#import "../../../AssetUtils.h"
#import "../../../Shared/UI/SCIMediaChrome.h"

// IG throttles /friendships/ — batch follow-state lookups (50/request) with a
// short cushion stays inside the limit.
static const NSInteger kSCIPABatchCap = 50;
static const NSTimeInterval kSCIPAFriendshipTTL = 10 * 60;
static CGFloat const kSCIPAAvatarSize = 52.0;

typedef NS_ENUM(NSInteger, SCIPASortMode) {
    SCIPASortModeDefault,
    SCIPASortModeAZ,
    SCIPASortModeZA,
    SCIPASortModeRecent,       // visited only
    SCIPASortModeMostVisited,  // visited only
};

#pragma mark - Follow-state memory cache (process-wide, TTL'd)

@interface SCIPAFollowCache : NSObject
+ (NSNumber *)followingForPK:(NSString *)pk;
+ (void)setFollowing:(BOOL)following forPK:(NSString *)pk;
@end

@implementation SCIPAFollowCache
+ (NSMutableDictionary *)store {
    static NSMutableDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [NSMutableDictionary dictionary]; });
    return m;
}
+ (NSNumber *)followingForPK:(NSString *)pk {
    if (!pk.length) return nil;
    NSDictionary *e = [self store][pk];
    if (!e) return nil;
    if (-[e[@"ts"] timeIntervalSinceNow] > kSCIPAFriendshipTTL) {
        [[self store] removeObjectForKey:pk];
        return nil;
    }
    return e[@"following"];
}
+ (void)setFollowing:(BOOL)following forPK:(NSString *)pk {
    if (!pk.length) return;
    [self store][pk] = @{ @"following": @(following), @"ts": [NSDate date] };
}
@end

#pragma mark - Cell

@interface SCIPAUserCell : UITableViewCell
@property (nonatomic, strong) SCIProfileAnalyzerAvatarView *avatarView;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIImageView *verifiedBadge;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIActivityIndicatorView *actionSpinner;
@property (nonatomic, strong) NSLayoutConstraint *nameTrailingToButton;
@property (nonatomic, strong) NSLayoutConstraint *nameTrailingToEdge;
@property (nonatomic, copy) NSString *boundPK;
@property (nonatomic, copy) void(^onActionTap)(SCIPAUserCell *);
@end

@implementation SCIPAUserCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return self;
    self.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.selectedBackgroundView = [UIView new];
    self.selectedBackgroundView.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];

    _avatarView = [[SCIProfileAnalyzerAvatarView alloc] initWithFrame:CGRectZero];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_avatarView];

    _usernameLabel = [UILabel new];
    _usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _usernameLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    _usernameLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    [_usernameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    _verifiedBadge = [UIImageView new];
    _verifiedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _verifiedBadge.contentMode = UIViewContentModeScaleAspectFit;
    _verifiedBadge.image = [SCIAssetUtils instagramIconNamed:@"verified" pointSize:13.0];
    _verifiedBadge.hidden = YES;
    [_verifiedBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[_usernameLabel, _verifiedBadge]];
    nameRow.translatesAutoresizingMaskIntoConstraints = NO;
    nameRow.axis = UILayoutConstraintAxisHorizontal;
    nameRow.alignment = UIStackViewAlignmentCenter;
    nameRow.spacing = 4.0;
    [self.contentView addSubview:nameRow];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    _subtitleLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    _subtitleLabel.numberOfLines = 1;
    [self.contentView addSubview:_subtitleLabel];

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    _actionButton.layer.cornerRadius = 8.0;
    _actionButton.contentEdgeInsets = UIEdgeInsetsMake(6, 14, 6, 14);
    _actionButton.hidden = YES;
    [_actionButton addTarget:self action:@selector(onAction) forControlEvents:UIControlEventTouchUpInside];
    [_actionButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_actionButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_actionButton];

    _actionSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _actionSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _actionSpinner.color = [SCIUtils SCIColor_InstagramSecondaryText];
    _actionSpinner.hidesWhenStopped = YES;
    [self.contentView addSubview:_actionSpinner];

    _nameTrailingToButton = [nameRow.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-10.0];
    _nameTrailingToEdge = [nameRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16.0];

    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_avatarView.widthAnchor constraintEqualToConstant:kSCIPAAvatarSize],
        [_avatarView.heightAnchor constraintEqualToConstant:kSCIPAAvatarSize],

        [nameRow.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12.0],
        [nameRow.topAnchor constraintEqualToAnchor:_avatarView.topAnchor constant:4.0],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:nameRow.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:nameRow.bottomAnchor constant:3.0],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-10.0],

        [_actionButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        [_actionButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

        [_actionSpinner.centerXAnchor constraintEqualToAnchor:_actionButton.centerXAnchor],
        [_actionSpinner.centerYAnchor constraintEqualToAnchor:_actionButton.centerYAnchor],
    ]];
    _nameTrailingToButton.active = YES;
    return self;
}

- (void)setActionButtonVisible:(BOOL)visible {
    self.actionButton.hidden = !visible;
    self.nameTrailingToButton.active = visible;
    self.nameTrailingToEdge.active = !visible;
}

- (void)onAction { if (self.onActionTap) self.onActionTap(self); }

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.avatarView prepareForReuse];
    self.boundPK = nil;
    self.verifiedBadge.hidden = YES;
    self.onActionTap = nil;
    [self.actionSpinner stopAnimating];
    self.actionButton.hidden = YES;
}

@end

#pragma mark - List VC

@interface SCIProfileAnalyzerListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, assign) SCIPAListKind kind;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerUser *> *allUsers;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerProfileChange *> *allUpdates;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerVisit *> *allVisits;

@property (nonatomic, copy) NSArray<SCIProfileAnalyzerUser *> *shownUsers;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerProfileChange *> *shownUpdates;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerVisit *> *shownVisits;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyStateIcon;
@property (nonatomic, strong) UILabel *emptyStateTitle;
@property (nonatomic, strong) UILabel *emptyStateSubtitle;
@property (nonatomic, assign) SCIPASortMode sortMode;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) NSMutableSet<NSString *> *requestedFollowPKs;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingFollowPKs;
@property (nonatomic, assign) BOOL followFlushScheduled;
@end

@implementation SCIProfileAnalyzerListViewController

- (instancetype)initWithTitle:(NSString *)title users:(NSArray<SCIProfileAnalyzerUser *> *)users kind:(SCIPAListKind)kind {
    if ((self = [super init])) {
        self.title = title;
        _kind = kind;
        _allUsers = [users copy] ?: @[];
        _sortMode = SCIPASortModeDefault;
    }
    return self;
}

- (instancetype)initWithTitle:(NSString *)title profileUpdates:(NSArray<SCIProfileAnalyzerProfileChange *> *)updates {
    if ((self = [super init])) {
        self.title = title;
        _kind = SCIPAListKindProfileUpdate;
        _allUpdates = [updates copy] ?: @[];
        _sortMode = SCIPASortModeDefault;
    }
    return self;
}

- (instancetype)initVisitedListWithTitle:(NSString *)title visits:(NSArray<SCIProfileAnalyzerVisit *> *)visits {
    if ((self = [super init])) {
        self.title = title;
        _kind = SCIPAListKindVisited;
        _allVisits = [visits copy] ?: @[];
        _sortMode = SCIPASortModeRecent;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.requestedFollowPKs = [NSMutableSet set];
    self.pendingFollowPKs = [NSMutableSet set];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 80.0, 0.0, 0.0);
    self.tableView.rowHeight = 72.0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:[SCIPAUserCell class] forCellReuseIdentifier:@"u"];
    [self.view addSubview:self.tableView];

    [self setupEmptyState];

    if (self.kind != SCIPAListKindProfileUpdate) {
        self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
        self.searchController.searchResultsUpdater = self;
        self.searchController.obscuresBackgroundDuringPresentation = NO;
        self.searchController.searchBar.placeholder = @"Search";
        [self.searchController.searchBar setImage:[SCIAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                                 forSearchBarIcon:UISearchBarIconSearch
                                            state:UIControlStateNormal];
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
        [self installSortItem];
    }

    [self applyFilterAndSort];
}

- (void)setupEmptyState {
    self.emptyStateView = [UIView new];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateView.hidden = YES;
    [self.view addSubview:self.emptyStateView];

    self.emptyStateIcon = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"promote_empty" pointSize:72.0 renderingMode:UIImageRenderingModeAlwaysTemplate]];
    self.emptyStateIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.emptyStateIcon.tintColor = [SCIUtils SCIColor_InstagramTertiaryText];
    [self.emptyStateView addSubview:self.emptyStateIcon];

    self.emptyStateTitle = [UILabel new];
    self.emptyStateTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateTitle.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    self.emptyStateTitle.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    self.emptyStateTitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateTitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateTitle];

    self.emptyStateSubtitle = [UILabel new];
    self.emptyStateSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateSubtitle.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.emptyStateSubtitle.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    self.emptyStateSubtitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateSubtitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateSubtitle];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30.0],
        [self.emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40.0],
        [self.emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40.0],

        [self.emptyStateIcon.topAnchor constraintEqualToAnchor:self.emptyStateView.topAnchor],
        [self.emptyStateIcon.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
        [self.emptyStateIcon.widthAnchor constraintEqualToConstant:72.0],
        [self.emptyStateIcon.heightAnchor constraintEqualToConstant:72.0],

        [self.emptyStateTitle.topAnchor constraintEqualToAnchor:self.emptyStateIcon.bottomAnchor constant:18.0],
        [self.emptyStateTitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateTitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],

        [self.emptyStateSubtitle.topAnchor constraintEqualToAnchor:self.emptyStateTitle.bottomAnchor constant:6.0],
        [self.emptyStateSubtitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateSubtitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],
        [self.emptyStateSubtitle.bottomAnchor constraintEqualToAnchor:self.emptyStateView.bottomAnchor],
    ]];
}

#pragma mark - Sort

- (void)installSortItem {
    UIBarButtonItem *sortItem = SCIMediaChromeTopBarMenuButtonItem(@"sort", [self sortMenu], @"Sort");
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[sortItem]);
}

- (UIMenu *)sortMenu {
    __weak typeof(self) weakSelf = self;
    UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion([weakSelf sortMenuElements]);
    }];
    return [UIMenu menuWithTitle:@"" children:@[deferred]];
}

- (NSArray<UIMenuElement *> *)sortMenuElements {
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    void (^add)(NSString *, SCIPASortMode) = ^(NSString *titleStr, SCIPASortMode mode) {
        UIAction *a = [UIAction actionWithTitle:titleStr image:nil identifier:nil handler:^(__unused UIAction *action) {
            weakSelf.sortMode = mode;
            [weakSelf applyFilterAndSort];
        }];
        if (weakSelf.sortMode == mode) a.state = UIMenuElementStateOn;
        [actions addObject:a];
    };
    if (self.kind == SCIPAListKindVisited) {
        add(@"Most Recent", SCIPASortModeRecent);
        add(@"Most Visited", SCIPASortModeMostVisited);
        add(@"A–Z", SCIPASortModeAZ);
        add(@"Z–A", SCIPASortModeZA);
    } else {
        add(@"Default", SCIPASortModeDefault);
        add(@"A–Z", SCIPASortModeAZ);
        add(@"Z–A", SCIPASortModeZA);
    }
    return @[[UIMenu menuWithTitle:@"Sort" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:actions]];
}

#pragma mark - Filter + sort

- (NSString *)haystackForUser:(SCIProfileAnalyzerUser *)u {
    return [NSString stringWithFormat:@"%@ %@", u.username ?: @"", u.fullName ?: @""].lowercaseString;
}

- (NSArray *)sortUsers:(NSArray<SCIProfileAnalyzerUser *> *)users {
    if (self.sortMode == SCIPASortModeAZ) {
        return [users sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerUser *a, SCIProfileAnalyzerUser *b) {
            return [(a.username ?: @"") caseInsensitiveCompare:(b.username ?: @"")];
        }];
    }
    if (self.sortMode == SCIPASortModeZA) {
        return [users sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerUser *a, SCIProfileAnalyzerUser *b) {
            return [(b.username ?: @"") caseInsensitiveCompare:(a.username ?: @"")];
        }];
    }
    return users;
}

- (NSArray *)sortVisits:(NSArray<SCIProfileAnalyzerVisit *> *)visits {
    switch (self.sortMode) {
        case SCIPASortModeMostVisited:
            return [visits sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerVisit *a, SCIProfileAnalyzerVisit *b) {
                if (a.visitCount != b.visitCount) return a.visitCount > b.visitCount ? NSOrderedAscending : NSOrderedDescending;
                return [b.lastSeen compare:a.lastSeen];
            }];
        case SCIPASortModeAZ:
            return [visits sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerVisit *a, SCIProfileAnalyzerVisit *b) {
                return [(a.user.username ?: @"") caseInsensitiveCompare:(b.user.username ?: @"")];
            }];
        case SCIPASortModeZA:
            return [visits sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerVisit *a, SCIProfileAnalyzerVisit *b) {
                return [(b.user.username ?: @"") caseInsensitiveCompare:(a.user.username ?: @"")];
            }];
        default:
            return [visits sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerVisit *a, SCIProfileAnalyzerVisit *b) {
                return [b.lastSeen compare:a.lastSeen];
            }];
    }
}

- (void)applyFilterAndSort {
    NSString *q = self.searchText.lowercaseString;
    BOOL hasQuery = q.length > 0;

    if (self.kind == SCIPAListKindProfileUpdate) {
        self.shownUpdates = self.allUpdates;
    } else if (self.kind == SCIPAListKindVisited) {
        NSArray *visits = self.allVisits;
        if (hasQuery) {
            NSMutableArray *out = [NSMutableArray array];
            for (SCIProfileAnalyzerVisit *v in visits) if ([[self haystackForUser:v.user] containsString:q]) [out addObject:v];
            visits = out;
        }
        self.shownVisits = [self sortVisits:visits];
    } else {
        NSArray *users = self.allUsers;
        if (hasQuery) {
            NSMutableArray *out = [NSMutableArray array];
            for (SCIProfileAnalyzerUser *u in users) if ([[self haystackForUser:u] containsString:q]) [out addObject:u];
            users = out;
        }
        self.shownUsers = [self sortUsers:users];
    }

    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    NSInteger count = [self.tableView numberOfRowsInSection:0];
    BOOL isEmpty = count == 0;
    self.emptyStateView.hidden = !isEmpty;
    self.tableView.hidden = isEmpty;
    if (!isEmpty) return;
    if (self.searchText.length) {
        self.emptyStateIcon.image = [SCIAssetUtils instagramIconNamed:@"promote_empty" pointSize:72.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        self.emptyStateTitle.text = @"No matches";
        self.emptyStateSubtitle.text = @"No accounts match your search.";
    } else {
        self.emptyStateIcon.image = [SCIAssetUtils instagramIconNamed:@"promote_empty" pointSize:72.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        self.emptyStateTitle.text = @"Nothing here";
        self.emptyStateSubtitle.text = @"There are no accounts in this list.";
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchText = searchController.searchBar.text;
    [self applyFilterAndSort];
}

#pragma mark - Helpers

static NSString *SCIPARelativeDate(NSDate *date) {
    if (!date) return @"";
    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateStyle = NSDateFormatterMediumStyle;
        df.timeStyle = NSDateFormatterShortStyle;
        df.doesRelativeDateFormatting = YES;
    });
    return [df stringFromDate:date];
}

- (SCIProfileAnalyzerUser *)userAtIndexPath:(NSIndexPath *)indexPath {
    switch (self.kind) {
        case SCIPAListKindVisited:
            return indexPath.row < (NSInteger)self.shownVisits.count ? self.shownVisits[indexPath.row].user : nil;
        case SCIPAListKindProfileUpdate:
            return indexPath.row < (NSInteger)self.shownUpdates.count ? self.shownUpdates[indexPath.row].current : nil;
        default:
            return indexPath.row < (NSInteger)self.shownUsers.count ? self.shownUsers[indexPath.row] : nil;
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.kind) {
        case SCIPAListKindVisited:        return self.shownVisits.count;
        case SCIPAListKindProfileUpdate:  return self.shownUpdates.count;
        default:                          return self.shownUsers.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIPAUserCell *cell = [tableView dequeueReusableCellWithIdentifier:@"u" forIndexPath:indexPath];

    SCIProfileAnalyzerUser *user = [self userAtIndexPath:indexPath];
    cell.boundPK = user.pk;
    cell.usernameLabel.text = user.username.length ? [@"@" stringByAppendingString:user.username] : @"Unknown user";
    cell.verifiedBadge.hidden = !user.isVerified;

    if (self.kind == SCIPAListKindVisited && indexPath.row < (NSInteger)self.shownVisits.count) {
        SCIProfileAnalyzerVisit *v = self.shownVisits[indexPath.row];
        NSString *count = v.visitCount > 1 ? [NSString stringWithFormat:@"  ·  %ld visits", (long)v.visitCount] : @"";
        cell.subtitleLabel.text = [NSString stringWithFormat:@"%@%@", SCIPARelativeDate(v.lastSeen), count];
    } else if (self.kind == SCIPAListKindProfileUpdate && indexPath.row < (NSInteger)self.shownUpdates.count) {
        cell.subtitleLabel.text = [self changeSummaryForUpdate:self.shownUpdates[indexPath.row]];
    } else {
        cell.subtitleLabel.text = user.fullName.length ? user.fullName : @"";
    }

    BOOL wantsButton = (self.kind == SCIPAListKindFollow || self.kind == SCIPAListKindUnfollow);
    [cell setActionButtonVisible:wantsButton];
    if (wantsButton) {
        BOOL following = (self.kind == SCIPAListKindUnfollow);
        NSNumber *cached = [SCIPAFollowCache followingForPK:user.pk];
        if (cached) following = cached.boolValue;
        [self styleButton:cell.actionButton following:following];
        __weak typeof(self) weakSelf = self;
        cell.onActionTap = ^(SCIPAUserCell *c) { [weakSelf toggleFollowForCell:c]; };
    }

    [cell.avatarView configureWithPK:user.pk urlString:user.profilePicURL];
    return cell;
}

- (NSString *)changeSummaryForUpdate:(SCIProfileAnalyzerProfileChange *)ch {
    NSMutableArray *parts = [NSMutableArray array];
    if (ch.usernameChanged)   [parts addObject:[NSString stringWithFormat:@"@%@ → @%@", ch.previous.username ?: @"", ch.current.username ?: @""]];
    if (ch.fullNameChanged)   [parts addObject:[NSString stringWithFormat:@"name: %@ → %@", ch.previous.fullName ?: @"—", ch.current.fullName ?: @"—"]];
    if (ch.profilePicChanged) [parts addObject:@"changed profile picture"];
    return [parts componentsJoinedByString:@"  ·  "];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCIProfileAnalyzerUser *user = [self userAtIndexPath:indexPath];
    if (user.username.length) [SCIUtils openInstagramProfileForUsername:user.username];
}

#pragma mark - Live follow-state resolution (batched)

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.kind != SCIPAListKindFollow && self.kind != SCIPAListKindUnfollow) return;
    SCIProfileAnalyzerUser *user = [self userAtIndexPath:indexPath];
    NSString *pk = user.pk;
    if (!pk.length) return;
    if ([SCIPAFollowCache followingForPK:pk]) return;
    if ([self.requestedFollowPKs containsObject:pk]) return;
    [self.requestedFollowPKs addObject:pk];
    [self.pendingFollowPKs addObject:pk];
    [self scheduleFollowBatchFlush];
}

- (void)scheduleFollowBatchFlush {
    if (self.followFlushScheduled) return;
    self.followFlushScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        weakSelf.followFlushScheduled = NO;
        [weakSelf flushFollowBatch];
    });
}

- (void)flushFollowBatch {
    if (!self.pendingFollowPKs.count) return;
    NSArray *batch = [self.pendingFollowPKs.allObjects subarrayWithRange:NSMakeRange(0, MIN(kSCIPABatchCap, self.pendingFollowPKs.count))];
    [self.pendingFollowPKs minusSet:[NSSet setWithArray:batch]];

    __weak typeof(self) weakSelf = self;
    [SCIInstagramAPI fetchFriendshipStatusesForPKs:batch completion:^(NSDictionary *statuses, NSError *error) {
        if (!error && statuses.count) {
            for (NSString *pk in statuses) {
                id s = statuses[pk];
                if ([s isKindOfClass:[NSDictionary class]]) [SCIPAFollowCache setFollowing:[s[@"following"] boolValue] forPK:pk];
            }
            [weakSelf refreshVisibleFollowButtons];
        }
        if (weakSelf.pendingFollowPKs.count) [weakSelf scheduleFollowBatchFlush];
    }];
}

- (void)refreshVisibleFollowButtons {
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        SCIPAUserCell *cell = (SCIPAUserCell *)[self.tableView cellForRowAtIndexPath:ip];
        if (![cell isKindOfClass:[SCIPAUserCell class]]) continue;
        NSNumber *cached = [SCIPAFollowCache followingForPK:cell.boundPK];
        if (cached && !cell.actionButton.hidden) [self styleButton:cell.actionButton following:cached.boolValue];
    }
}

#pragma mark - Swipe to delete (visited list only)

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.kind != SCIPAListKindVisited) return nil;
    if (indexPath.row >= (NSInteger)self.shownVisits.count) return nil;

    __weak typeof(self) weakSelf = self;
    SCIProfileAnalyzerVisit *visit = self.shownVisits[indexPath.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil
                                                                    handler:^(UIContextualAction *action, UIView *sourceView, void (^done)(BOOL)) {
        [weakSelf removeVisit:visit];
        done(YES);
    }];
    del.image = [SCIAssetUtils instagramIconNamed:@"trash" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    del.backgroundColor = [SCIUtils SCIColor_InstagramDestructive];
    del.accessibilityLabel = @"Remove";
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (void)removeVisit:(SCIProfileAnalyzerVisit *)visit {
    NSMutableArray *all = [self.allVisits mutableCopy];
    [all removeObject:visit];
    self.allVisits = all;
    if (self.onRemoveVisit) self.onRemoveVisit(visit);
    [self applyFilterAndSort];
}

#pragma mark - Follow / unfollow

- (void)styleButton:(UIButton *)button following:(BOOL)following {
    if (following) {
        [button setTitle:@"Following" forState:UIControlStateNormal];
        [button setTitleColor:[SCIUtils SCIColor_InstagramPrimaryText] forState:UIControlStateNormal];
        button.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = [SCIUtils SCIColor_InstagramSeparator].CGColor;
    } else {
        [button setTitle:@"Follow" forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.backgroundColor = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];
        button.layer.borderWidth = 0.0;
    }
}

- (void)toggleFollowForCell:(SCIPAUserCell *)cell {
    NSString *pk = cell.boundPK;
    if (!pk.length) return;

    NSNumber *cached = [SCIPAFollowCache followingForPK:pk];
    BOOL currentlyFollowing = cached ? cached.boolValue : (self.kind == SCIPAListKindUnfollow);

    cell.actionButton.hidden = YES;
    [cell.actionSpinner startAnimating];

    void (^finish)(BOOL) = ^(BOOL nowFollowing) {
        [SCIPAFollowCache setFollowing:nowFollowing forPK:pk];
        [cell.actionSpinner stopAnimating];
        if ([cell.boundPK isEqualToString:pk]) {
            cell.actionButton.hidden = NO;
            [self styleButton:cell.actionButton following:nowFollowing];
        }
    };

    if (currentlyFollowing) {
        [SCIInstagramAPI unfollowUserPK:pk completion:^(NSDictionary *resp, NSError *error) { finish(error ? currentlyFollowing : NO); }];
    } else {
        [SCIInstagramAPI followUserPK:pk completion:^(NSDictionary *resp, NSError *error) { finish(error ? currentlyFollowing : YES); }];
    }
}

@end

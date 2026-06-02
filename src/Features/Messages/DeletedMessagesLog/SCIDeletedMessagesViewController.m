#import "SCIDeletedMessagesViewController.h"

#import "SCIDeletedMessagesAvatarCache.h"
#import "SCIDeletedMessagesChipBar.h"
#import "SCIDeletedMessagesDate.h"
#import "SCIDeletedMessagesFilter.h"
#import "SCIDeletedMessagesSenderCell.h"
#import "SCIDeletedMessagesStorage.h"
#import "SCIDeletedMessagesStorageViewController.h"
#import "SCIDeletedMessagesUserDetailViewController.h"
#import "../../../Utils.h"
#import "../../../AssetUtils.h"
#import "../../../Shared/UI/SCIMediaChrome.h"
#import "../../../Shared/UI/SCIIGAlertPresenter.h"

#import <objc/runtime.h>

static NSString *SCIDMCurrentUserPK(void) {
    @try {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            id session = nil;
            @try { session = [window valueForKey:@"userSession"]; } @catch (__unused id e) {}
            id user = nil;
            @try { user = [session valueForKey:@"user"]; } @catch (__unused id e) {}
            for (NSString *key in @[@"pk", @"instagramUserID", @"instagramUserId", @"userID", @"userId"]) {
                id value = nil;
                @try { value = [user valueForKey:key]; } @catch (__unused id e) {}
                if ([value isKindOfClass:NSString.class] && [value length]) return value;
                if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
            }
        }
    } @catch (__unused id e) {}
    NSArray<NSString *> *owners = [SCIDeletedMessagesStorage allOwnerPKs];
    return owners.firstObject ?: @"anon";
}

@interface SCIDeletedMessagesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, SCIDeletedMessagesChipBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) SCIDeletedMessagesChipBar *chipBar;
@property (nonatomic, strong) NSLayoutConstraint *chipBarHeight;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyStateIcon;
@property (nonatomic, strong) UILabel *emptyStateTitle;
@property (nonatomic, strong) UILabel *emptyStateSubtitle;
@property (nonatomic, strong) SCIDeletedMessagesFilter *filter;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, copy) NSArray<SCIDeletedMessageGroup *> *groups;
@property (nonatomic, copy) NSArray<SCIDeletedMessageGroup *> *visibleGroups;
@end

@implementation SCIDeletedMessagesViewController

// Chip filter columns. Multi-select; an empty selection means "show all", so
// there's no dedicated "All" chip. Index maps to an explicit kind so chip order
// is decoupled from the enum's numeric values.
static NSArray<NSString *> *SCIDMChipTitles(void) {
    return @[@"Text", @"Photo", @"Video", @"Voice", @"GIF", @"Sticker", @"Share", @"Link", @"Reaction"];
}
static NSArray<NSString *> *SCIDMChipSymbols(void) {
    return @[@"message", @"photo", @"video", @"voice", @"gif", @"sticker", @"share", @"link", @"reactions"];
}
// Filled variants used when a chip is selected.
static NSArray<NSString *> *SCIDMChipSelectedSymbols(void) {
    return @[@"message", @"photo_filled", @"video_filled", @"voice_filled", @"gif_filled", @"sticker_filled", @"share", @"link", @"reactions"];
}
static SCIDeletedMessageKind SCIDMChipKindForIndex(NSInteger index) {
    switch (index) {
        case 0: return SCIDeletedMessageKindText;
        case 1: return SCIDeletedMessageKindPhoto;
        case 2: return SCIDeletedMessageKindVideo;
        case 3: return SCIDeletedMessageKindVoice;
        case 4: return SCIDeletedMessageKindGif;
        case 5: return SCIDeletedMessageKindSticker;
        case 6: return SCIDeletedMessageKindShare;
        case 7: return SCIDeletedMessageKindLink;
        case 8: return SCIDeletedMessageKindReaction;
        default: return SCIDeletedMessageKindUnknown;
    }
}

+ (void)presentFromViewController:(UIViewController *)presenter {
    UIViewController *root = presenter ?: UIApplication.sharedApplication.keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[SCIDeletedMessagesViewController new]];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [root presentViewController:nav animated:YES completion:nil];
}

+ (void)presentForThreadId:(NSString *)threadId
                  senderPK:(NSString *)senderPK
                senderName:(NSString *)senderName
        fromViewController:(UIViewController *)presenter {
    UIViewController *root = presenter ?: UIApplication.sharedApplication.keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;

    SCIDeletedMessagesViewController *list = [SCIDeletedMessagesViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;

    // Prefer threadId (reliable from an open chat); fall back to senderPK.
    NSString *ownerPK = SCIDMCurrentUserPK();
    SCIDeletedMessageGroup *group = nil;
    if (threadId.length) {
        group = [SCIDeletedMessagesStorage groupForThreadId:threadId ownerPK:ownerPK];
    }
    if (!group && senderPK.length) {
        group = [SCIDeletedMessagesStorage groupForSenderPK:senderPK ownerPK:ownerPK];
    }

    UIViewController *detail = nil;
    if (group) {
        detail = [[SCIDeletedMessagesUserDetailViewController alloc] initWithGroup:group ownerPK:ownerPK];
    }

    [root presentViewController:nav animated:YES completion:^{
        if (detail) {
            [list.navigationController pushViewController:detail animated:YES];
        }
    }];
}

- (instancetype)init {
    if ((self = [super init])) {
        _filter = [SCIDeletedMessagesFilter new];
        _ownerPK = SCIDMCurrentUserPK();
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Deleted Messages";
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];

    UIBarButtonItem *moreItem = SCIMediaChromeTopBarMenuButtonItem(@"more", [self moreMenu], @"More");
    UIBarButtonItem *sortItem = SCIMediaChromeTopBarMenuButtonItem(@"sort", [self sortMenu], @"Sort and Filter");
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[moreItem, sortItem]);
    if (self.navigationController.viewControllers.firstObject == self) {
        SCIMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ SCIMediaChromeTopBarButtonItem(@"xmark", self, @selector(close)) ]);
    }

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Deleted Messages";
    [self.searchController.searchBar setImage:[SCIAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                            forSearchBarIcon:UISearchBarIconSearch
                                       state:UIControlStateNormal];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.chipBar = [[SCIDeletedMessagesChipBar alloc] initWithFrame:CGRectZero];
    self.chipBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipBar.delegate = self;
    [self.chipBar setItems:SCIDMChipTitles() symbols:SCIDMChipSymbols() selectedSymbols:SCIDMChipSelectedSymbols()];
    [self.view addSubview:self.chipBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 80.0, 0.0, 0.0);
    self.tableView.rowHeight = 72.0;
    [self.tableView registerClass:[SCIDeletedMessagesSenderCell class] forCellReuseIdentifier:SCIDeletedMessagesSenderCellReuseID];
    [self.view addSubview:self.tableView];

    [self setupEmptyState];

    self.chipBarHeight = [self.chipBar.heightAnchor constraintEqualToConstant:50.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.chipBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.chipBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.chipBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        self.chipBarHeight,
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.chipBar.bottomAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:SCIDeletedMessagesDidChangeNotification object:nil];
    [self reloadData];
}

- (void)setupEmptyState {
    self.emptyStateView = [UIView new];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateView.hidden = YES;
    [self.view addSubview:self.emptyStateView];

    self.emptyStateIcon = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"messages_empty" pointSize:96.0 renderingMode:UIImageRenderingModeAlwaysTemplate]];
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)reloadData {
    self.ownerPK = SCIDMCurrentUserPK();
    self.groups = [SCIDeletedMessagesStorage groupedBySenderForOwnerPK:self.ownerPK];
    [self applyFilter];
    [self rebuildMenus];
}

- (void)applyFilter {
    self.visibleGroups = [self.filter applyToGroups:self.groups ?: @[]];
    [self updateChipBarVisibility];
    [self updateEmptyState];
    [self.tableView reloadData];
}

// Distinct message kinds present across all unfiltered groups. Drives whether
// the kind chip bar is worth showing at all.
- (NSUInteger)distinctKindCount {
    NSMutableSet<NSNumber *> *kinds = [NSMutableSet set];
    for (SCIDeletedMessageGroup *group in self.groups) {
        for (SCIDeletedMessage *message in group.messages) {
            [kinds addObject:@(message.kind)];
        }
    }
    return kinds.count;
}

- (void)updateChipBarVisibility {
    // Show when there's something to filter (2+ kinds), OR when a filter is
    // currently active / hiding everything so the user can change it.
    BOOL hasActiveKindFilter = [self.filter hasKindFilter];
    BOOL show = ([self distinctKindCount] >= 2) || hasActiveKindFilter;
    BOOL hidden = !show;
    if (self.chipBar.hidden != hidden) {
        self.chipBar.hidden = hidden;
        self.chipBarHeight.constant = hidden ? 0.0 : 50.0;
    }
}

- (void)updateEmptyState {
    BOOL loggingEnabled = [SCIUtils getBoolPref:@"msgs_deleted_log"];
    BOOL hasAnyData = (self.groups.count > 0);
    BOOL hasFiltersActive = ![self.filter isEmpty];
    BOOL isEmpty = (self.visibleGroups.count == 0);

    self.emptyStateView.hidden = !isEmpty;
    self.tableView.hidden = isEmpty;

    if (!isEmpty) return;

    if (!loggingEnabled && !hasAnyData) {
        self.emptyStateIcon.image = [SCIAssetUtils instagramIconNamed:@"messages_empty" pointSize:96.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        self.emptyStateTitle.text = @"Logging is off";
        self.emptyStateSubtitle.text = @"Turn on Log Deleted Messages in Settings to start capturing unsent messages.";
    } else if (hasAnyData && hasFiltersActive) {
        self.emptyStateTitle.text = @"No matches";
        self.emptyStateSubtitle.text = @"No deleted messages match the current filters.";
    } else {
        self.emptyStateTitle.text = @"Nothing here yet";
        self.emptyStateSubtitle.text = @"Messages that other people unsend will show up here.";
    }
}

- (void)rebuildMenus {
    // Menus are deferred (self-refreshing), so nothing to reassign here.
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.filter.searchText = searchController.searchBar.text;
    [self applyFilter];
}

#pragma mark - Chip Bar

- (void)chipBar:(SCIDeletedMessagesChipBar *)bar didChangeSelection:(NSSet<NSNumber *> *)selectedIndices {
    [self.filter clearKinds];
    for (NSNumber *index in selectedIndices) {
        SCIDeletedMessageKind kind = SCIDMChipKindForIndex(index.integerValue);
        if (kind != SCIDeletedMessageKindUnknown) [self.filter toggleKind:kind];
    }
    [self applyFilter];
}

#pragma mark - Menus

// Both top-bar menus resolve their children fresh each open (via a deferred
// element), so checkmarks / titles always reflect current state without
// reassigning the button's menu.
- (UIMenu *)sortMenu {
    __weak typeof(self) weakSelf = self;
    UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion([weakSelf sortMenuElements]);
    }];
    return [UIMenu menuWithTitle:@"" children:@[deferred]];
}

- (NSArray<UIMenuElement *> *)sortMenuElements {
    __weak typeof(self) weakSelf = self;
    NSArray *items = @[
        @[@"Recent", @(SCIDMSortRecent)],
        @[@"Oldest", @(SCIDMSortOldest)],
        @[@"Most Messages", @(SCIDMSortCountDesc)]
    ];
    NSMutableArray<UIAction *> *sortActions = [NSMutableArray array];
    for (NSArray *item in items) {
        SCIDMSort sort = [item[1] integerValue];
        UIAction *action = [UIAction actionWithTitle:item[0]
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction *a) {
            weakSelf.filter.sort = sort;
            [weakSelf applyFilter];
        }];
        if (self.filter.sort == sort) action.state = UIMenuElementStateOn;
        [sortActions addObject:action];
    }
    UIMenu *sortSection = [UIMenu menuWithTitle:@"Sort" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:sortActions];

    NSMutableArray<UIAction *> *dateActions = [NSMutableArray array];
    NSArray *dateItems = @[
        @[@"All Time", @(SCIDMDateRangeAll)],
        @[@"Today", @(SCIDMDateRangeToday)],
        @[@"Last 7 Days", @(SCIDMDateRangeWeek)],
        @[@"Last 30 Days", @(SCIDMDateRangeMonth)]
    ];
    for (NSArray *item in dateItems) {
        SCIDMDateRange range = [item[1] integerValue];
        UIAction *action = [UIAction actionWithTitle:item[0]
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction *a) {
            weakSelf.filter.dateRange = range;
            [weakSelf applyFilter];
        }];
        if (self.filter.dateRange == range) action.state = UIMenuElementStateOn;
        [dateActions addObject:action];
    }
    UIMenu *dateSection = [UIMenu menuWithTitle:@"Date Range" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:dateActions];

    return @[sortSection, dateSection];
}

- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;
    UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion([weakSelf moreMenuElements]);
    }];
    return [UIMenu menuWithTitle:@"" children:@[deferred]];
}

- (NSArray<UIMenuElement *> *)moreMenuElements {
    __weak typeof(self) weakSelf = self;

    UIAction *storageAction = [UIAction actionWithTitle:@"Storage"
                                                 image:[SCIAssetUtils instagramIconNamed:@"info" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                            identifier:nil
                                               handler:^(__unused UIAction *a) {
        [weakSelf.navigationController pushViewController:[SCIDeletedMessagesStorageViewController new] animated:YES];
    }];

    UIAction *clearFiltersAction = [UIAction actionWithTitle:@"Clear Filters"
                                                      image:[SCIAssetUtils instagramIconNamed:@"filter" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                                 identifier:nil
                                                    handler:^(__unused UIAction *a) {
        weakSelf.filter = [SCIDeletedMessagesFilter new];
        weakSelf.searchController.searchBar.text = nil;
        [weakSelf.chipBar clearSelection];
        [weakSelf applyFilter];
    }];

    UIAction *clearAllAction = [UIAction actionWithTitle:@"Clear All Messages"
                                                   image:[SCIAssetUtils instagramIconNamed:@"trash" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                              identifier:nil
                                                 handler:^(__unused UIAction *a) {
        [weakSelf confirmClearAll];
    }];
    /// TODO: investigate whether native UIMenu destructive tint can be customized. UIMenuElement exposes no supported color API.
    clearAllAction.attributes = UIMenuElementAttributesDestructive;

    UIMenu *destructiveSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[clearAllAction]];

    return @[storageAction, clearFiltersAction, destructiveSection];
}

- (void)confirmClearAll {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Clear deleted messages?"
                                                message:@"This removes the log and captured media for the current account."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Clear" style:SCIIGAlertActionStyleDestructive handler:^{
            [SCIDeletedMessagesStorage resetForOwnerPK:self.ownerPK];
            [[SCIDeletedMessagesAvatarCache shared] purge];
        }],
    ]];
}

- (void)confirmDeleteGroup:(SCIDeletedMessageGroup *)group {
    if (!group.senderPk.length) return;
    NSString *sender = group.senderUsername.length ? [@"@" stringByAppendingString:group.senderUsername] : @"this sender";
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Delete sender log?"
                                                message:[NSString stringWithFormat:@"This removes all logged messages from %@.", sender]
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Delete" style:SCIIGAlertActionStyleDestructive handler:^{
            [SCIDeletedMessagesStorage deleteMessagesForSenderPK:group.senderPk ownerPK:self.ownerPK];
        }],
    ]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleGroups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIDeletedMessagesSenderCell *cell = [tableView dequeueReusableCellWithIdentifier:SCIDeletedMessagesSenderCellReuseID forIndexPath:indexPath];
    [cell configureWithGroup:self.visibleGroups[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCIDeletedMessageGroup *group = self.visibleGroups[indexPath.row];
    [self.navigationController pushViewController:[[SCIDeletedMessagesUserDetailViewController alloc] initWithGroup:group ownerPK:self.ownerPK] animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIDeletedMessageGroup *group = self.visibleGroups[indexPath.row];
    UIContextualAction *pinAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [SCIDeletedMessagesStorage setSenderPinned:!group.isPinned senderPK:group.senderPk ownerPK:self.ownerPK];
        completionHandler(YES);
    }];
    pinAction.image = [SCIAssetUtils instagramIconNamed:(group.isPinned ? @"pin_filled" : @"pin") pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    pinAction.backgroundColor = [SCIUtils SCIColor_Primary];
    pinAction.accessibilityLabel = group.isPinned ? @"Unpin" : @"Pin";
    UIContextualAction *blockAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [SCIDeletedMessagesStorage setSenderBlocked:!group.isBlocked senderPK:group.senderPk ownerPK:self.ownerPK];
        completionHandler(YES);
    }];
    blockAction.image = [SCIAssetUtils instagramIconNamed:(group.isBlocked ? @"circle" : @"circle_off") pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    blockAction.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryText];
    blockAction.accessibilityLabel = group.isBlocked ? @"Unblock" : @"Block";
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self confirmDeleteGroup:group];
        completionHandler(NO);
    }];
    deleteAction.image = [SCIAssetUtils instagramIconNamed:@"trash" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    deleteAction.backgroundColor = [SCIUtils SCIColor_InstagramDestructive];
    deleteAction.accessibilityLabel = @"Delete";
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, blockAction, pinAction]];
}

@end

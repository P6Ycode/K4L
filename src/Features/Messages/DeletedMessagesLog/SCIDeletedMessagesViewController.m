#import "SCIDeletedMessagesViewController.h"

#import "SCIDeletedMessagesChipBar.h"
#import "SCIDeletedMessagesDate.h"
#import "SCIDeletedMessagesFilter.h"
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
@property (nonatomic, strong) SCIDeletedMessagesFilter *filter;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, copy) NSArray<SCIDeletedMessageGroup *> *groups;
@property (nonatomic, copy) NSArray<SCIDeletedMessageGroup *> *visibleGroups;
@end

@implementation SCIDeletedMessagesViewController

+ (void)presentFromViewController:(UIViewController *)presenter {
    UIViewController *root = presenter ?: UIApplication.sharedApplication.keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[SCIDeletedMessagesViewController new]];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [root presentViewController:nav animated:YES completion:nil];
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

    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithImage:SCIMediaChromeTopBarIcon(@"more")
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:nil
                                                                 action:nil];
    moreItem.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    moreItem.menu = [self moreMenu];
    UIBarButtonItem *sortItem = [[UIBarButtonItem alloc] initWithImage:SCIMediaChromeTopBarIcon(@"sort")
                                                                style:UIBarButtonItemStylePlain
                                                               target:nil
                                                               action:nil];
    sortItem.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    sortItem.menu = [self sortMenu];
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[moreItem, sortItem]);
    if (self.navigationController.viewControllers.firstObject == self) {
        SCIMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ SCIMediaChromeTopBarButtonItem(@"xmark", self, @selector(close)) ]);
    }

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search deleted messages";
    [self.searchController.searchBar setImage:[SCIAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                            forSearchBarIcon:UISearchBarIconSearch
                                       state:UIControlStateNormal];
    self.navigationItem.searchController = self.searchController;

    self.chipBar = [[SCIDeletedMessagesChipBar alloc] initWithFrame:CGRectZero];
    self.chipBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipBar.delegate = self;
    [self.chipBar setItems:@[@"All", @"Text", @"Photo", @"Video", @"Voice", @"GIF", @"Sticker", @"Share", @"Link"]
                   symbols:@[@"grid", @"text", @"photo", @"video", @"microphone", @"gif", @"sticker", @"share", @"link"]];
    [self.view addSubview:self.chipBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    self.tableView.rowHeight = 64.0;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.chipBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.chipBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.chipBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.chipBar.bottomAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:SCIDeletedMessagesDidChangeNotification object:nil];
    [self reloadData];
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
    [self.tableView reloadData];
}

- (void)rebuildMenus {
    NSArray<UIBarButtonItem *> *items = self.navigationItem.rightBarButtonItems;
    if (items.count >= 2) {
        items[0].menu = [self moreMenu];
        items[1].menu = [self sortMenu];
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.filter.searchText = searchController.searchBar.text;
    [self applyFilter];
}

#pragma mark - Chip Bar

- (void)chipBar:(SCIDeletedMessagesChipBar *)bar didSelectIndex:(NSInteger)index {
    [self.filter clearKinds];
    if (index > 0) {
        // Map chip index to kind: 1=Text, 2=Photo, 3=Video, 4=Voice, 5=GIF, 6=Sticker, 7=Share, 8=Link
        [self.filter toggleKind:(SCIDeletedMessageKind)index];
    }
    [self applyFilter];
}

#pragma mark - Menus

- (UIMenu *)sortMenu {
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
            [weakSelf rebuildMenus];
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
            [weakSelf rebuildMenus];
        }];
        if (self.filter.dateRange == range) action.state = UIMenuElementStateOn;
        [dateActions addObject:action];
    }
    UIMenu *dateSection = [UIMenu menuWithTitle:@"Date Range" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:dateActions];

    return [UIMenu menuWithTitle:@"" children:@[sortSection, dateSection]];
}

- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;

    UIAction *storageAction = [UIAction actionWithTitle:@"Storage"
                                                 image:[SCIAssetUtils instagramIconNamed:@"storage" pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                            identifier:nil
                                               handler:^(__unused UIAction *a) {
        [weakSelf.navigationController pushViewController:[SCIDeletedMessagesStorageViewController new] animated:YES];
    }];

    UIAction *clearFiltersAction = [UIAction actionWithTitle:@"Clear Filters"
                                                      image:[SCIAssetUtils instagramIconNamed:@"filter" pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                                 identifier:nil
                                                    handler:^(__unused UIAction *a) {
        weakSelf.filter = [SCIDeletedMessagesFilter new];
        weakSelf.searchController.searchBar.text = nil;
        weakSelf.chipBar.selectedIndex = 0;
        [weakSelf applyFilter];
        [weakSelf rebuildMenus];
    }];

    UIAction *clearAllAction = [UIAction actionWithTitle:@"Clear All Messages"
                                                   image:[SCIAssetUtils instagramIconNamed:@"trash" pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                              identifier:nil
                                                 handler:^(__unused UIAction *a) {
        [weakSelf confirmClearAll];
    }];
    clearAllAction.attributes = UIMenuElementAttributesDestructive;

    UIMenu *destructiveSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[clearAllAction]];

    return [UIMenu menuWithTitle:@"" children:@[storageAction, clearFiltersAction, destructiveSection]];
}

- (void)confirmClearAll {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Clear deleted messages?"
                                                message:@"This removes the log and captured media for the current account."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Clear" style:SCIIGAlertActionStyleDestructive handler:^{
            [SCIDeletedMessagesStorage resetForOwnerPK:self.ownerPK];
        }],
    ]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleGroups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sender"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"sender"];
    SCIDeletedMessageGroup *group = self.visibleGroups[indexPath.row];
    NSString *name = group.senderUsername.length ? [@"@" stringByAppendingString:group.senderUsername] : (group.senderFullName ?: @"Unknown user");
    cell.textLabel.text = name;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (group.isPinned) [parts addObject:@"Pinned"];
    if (group.isBlocked) [parts addObject:@"Blocked"];
    [parts addObject:[NSString stringWithFormat:@"%lu message%@", (unsigned long)group.count, group.count == 1 ? @"" : @"s"]];
    [parts addObject:[SCIDeletedMessagesDate stringForDate:group.lastDeletedAt]];
    cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    cell.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    cell.selectedBackgroundView = [UIView new];
    cell.selectedBackgroundView.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
    cell.textLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    cell.detailTextLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    cell.imageView.image = [SCIAssetUtils instagramIconNamed:@"user_circle" pointSize:34.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCIDeletedMessageGroup *group = self.visibleGroups[indexPath.row];
    [self.navigationController pushViewController:[[SCIDeletedMessagesUserDetailViewController alloc] initWithGroup:group ownerPK:self.ownerPK] animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIDeletedMessageGroup *group = self.visibleGroups[indexPath.row];
    UIContextualAction *pinAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:(group.isPinned ? @"Unpin" : @"Pin") handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [SCIDeletedMessagesStorage setSenderPinned:!group.isPinned senderPK:group.senderPk ownerPK:self.ownerPK];
        completionHandler(YES);
    }];
    pinAction.backgroundColor = [SCIUtils SCIColor_Primary];
    UIContextualAction *blockAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:(group.isBlocked ? @"Unblock" : @"Block") handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [SCIDeletedMessagesStorage setSenderBlocked:!group.isBlocked senderPK:group.senderPk ownerPK:self.ownerPK];
        completionHandler(YES);
    }];
    blockAction.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryText];
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [SCIDeletedMessagesStorage deleteMessagesForSenderPK:group.senderPk ownerPK:self.ownerPK];
        completionHandler(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, blockAction, pinAction]];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.visibleGroups.count > 0) return nil;
    return [SCIUtils getBoolPref:@"msgs_deleted_log"] ? @"No deleted messages have been logged for this account." : @"Deleted message logging is disabled.";
}

@end

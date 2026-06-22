#import "SCIGalleryViewController.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryFileDetailsViewController.h"
#import "SCIGalleryGridCell.h"
#import "SCIGalleryGridDensity.h"
#import "SCIGalleryFolderChipBar.h"
#import "SCIGalleryListCollectionCell.h"
#import "SCIGalleryFolderCell.h"
#import "SCIGalleryCoreDataStack.h"
#import "SCIGalleryManager.h"
#import "SCIGalleryLockViewController.h"
#import "SCIGallerySortViewController.h"
#import "SCIGalleryFilterViewController.h"
#import "SCIGallerySettingsViewController.h"
#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryOriginController.h"
#import "SCIGalleryHiddenSources.h"
#import "../MediaPreview/SCIFullScreenMediaPlayer.h"
#import "../MediaTrim/SCITrimConfiguration.h"
#import "../MediaTrim/SCITrimResult.h"
#import "../MediaTrim/SCITrimEditorViewController.h"
#import "../MediaTrim/SCITrimSaveCoordinator.h"
#import "../UI/SCIMediaChrome.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../../InstagramHeaders.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import <CoreData/CoreData.h>

static NSString * const kGridCellID = @"SCIGalleryGridCell";
static NSString * const kListCellID = @"SCIGalleryListCell";
static NSString * const kFolderCellID = @"SCIGalleryFolderCell";
static NSString * const kFolderChipHeaderID = @"SCIGalleryFolderChipHeader";

static NSString * const kSortModeKey    = @"gallery_sort_mode";
static NSString * const kSortGroupByTypeKey = @"gallery_sort_group_by_type";
static NSString * const kViewModeKey    = @"gallery_view_mode"; // 0 = grid, 1 = list
static NSString * const kFavoritesAtTopKey = @"gallery_show_favorites_top";

static CGFloat const kGridSpacing = 2.0;
static CGFloat const kGalleryMenuIconPointSize = 22.0;
static NSInteger const kSCIUINavigationItemSearchBarPlacementIntegratedButton = 4;

static UIImage *SCIGalleryMenuActionIcon(NSString *resourceName) {
    return [SCIAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
                                   pointSize:kGalleryMenuIconPointSize];
}

static UIBarButtonItem *SCIGalleryTextBarButtonItem(NSString *title, id target, SEL action) {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:title
                                                             style:UIBarButtonItemStylePlain
                                                            target:target
                                                            action:action];
    item.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    return item;
}

static NSInteger SCIGalleryItemCountForFolderPath(NSManagedObjectContext *context, NSString *folderPath) {
    if (folderPath.length == 0) return 0;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    NSPredicate *folder = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@",
                           folderPath, [folderPath stringByAppendingString:@"/"]];
    NSPredicate *visible = SCIGalleryVisibleSourcesPredicate();
    request.predicate = visible ? [NSCompoundPredicate andPredicateWithSubpredicates:@[folder, visible]] : folder;
    return [context countForFetchRequest:request error:nil];
}

typedef NS_ENUM(NSInteger, SCIGalleryViewMode) {
    SCIGalleryViewModeGrid = 0,
    SCIGalleryViewModeList = 1,
};

@interface SCIGalleryViewController () <UICollectionViewDataSource,
                                       UICollectionViewDelegate,
                                       UICollectionViewDelegateFlowLayout,
                                       NSFetchedResultsControllerDelegate,
                                       SCIGallerySortViewControllerDelegate,
                                       SCIGalleryFilterViewControllerDelegate,
                                       UIAdaptivePresentationControllerDelegate,
                                       UISearchResultsUpdating,
                                       UISearchControllerDelegate,
                                       UISearchBarDelegate>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UILabel *emptyStateLabel;
// Bottom toolbar is the hosting navigation controller's native UIToolbar.
// iOS 26 renders it as a Liquid Glass pill; earlier systems show a standard bar.

// Folder navigation. Folders are browsed in place (one shared-chrome view
// controller) rather than by pushing a new view controller per folder, so the
// nav bar / search / toolbar are never recreated or cross-faded — which is what
// produced the Liquid Glass transition flashes. `folderTrail` is the stack of
// folder paths from root to the current folder (empty at root); `folderScrollOffsets`
// holds the parallel grid scroll position to restore when navigating back.
@property (nonatomic, copy, nullable) NSString *currentFolderPath;
@property (nonatomic, strong) NSMutableArray<NSString *> *folderTrail;
@property (nonatomic, strong) NSMutableArray<NSValue *> *folderScrollOffsets;
@property (nonatomic, strong) NSArray<NSString *> *subfolders;

// View mode
@property (nonatomic, assign) SCIGalleryViewMode viewMode;
/// Number of columns in grid mode (clamped to kGridColumnsMin...kGridColumnsMax).
@property (nonatomic, assign) NSInteger gridColumns;

// Sort
@property (nonatomic, assign) SCIGallerySortMode sortMode;
@property (nonatomic, assign) BOOL sortGroupByMediaType;

// Filter
@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterTypes;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterSources;
@property (nonatomic, assign) BOOL filterFavoritesOnly;
@property (nonatomic, strong) NSMutableSet<NSString *> *filterUsernames;
@property (nonatomic, assign) BOOL selectionMode;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedFileIDs;
// Signatures of the last-applied nav bar items, tracked separately for the
// leading and trailing groups. The leading button changes as you browse folders
// (close ⇄ back), but the trailing group does not — so reassigning trailing on
// every folder change just re-lays-out its Liquid Glass pill (a visible jump).
@property (nonatomic, copy) NSString *lastLeadingNavSignature;
@property (nonatomic, copy) NSString *lastTrailingNavSignature;
@property (nonatomic, strong) UISearchController *searchController;
// The iOS 26 integrated search button, vended and cached once at load so the
// bottom toolbar always installs the same fully-materialized instance. If we let
// each refresh re-vend it lazily, the nav bar wins the first transition layout
// and briefly renders it in its top-right home (the flash) before we relocate it.
@property (nonatomic, strong) UIBarButtonItem *cachedSearchToolbarItem;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, assign) BOOL preservingSearchQuery;
// When YES (and a query is active), search ignores the folder scope and matches
// across all folders; the search bar scope buttons toggle it.
@property (nonatomic, assign) BOOL searchAllFolders;

@end

@implementation SCIGalleryViewController

#pragma mark - Presentation

+ (void)presentGallery {
    UIViewController *presenter = topMostController();
    SCIGalleryManager *mgr = [SCIGalleryManager sharedManager];

    void (^presentGalleryNav)(void) = ^{
        SCIGalleryViewController *vc = [[SCIGalleryViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [presenter presentViewController:nav animated:YES completion:nil];
    };

    // Authenticate on the presenter (Instagram / settings) before any gallery UI is shown,
    // so Face ID / passcode runs first with no flash of gallery content.
    if (mgr.isLockEnabled && !mgr.isUnlocked) {
        [SCIGalleryLockViewController presentUnlockFromViewController:presenter
                                                           completion:^(BOOL success) {
            if (!success) return;
            presentGalleryNav();
        }];
    } else {
        presentGalleryNav();
    }
}

#pragma mark - Init

- (instancetype)init {
    return [self initWithFolderPath:nil];
}

- (instancetype)initWithFolderPath:(NSString *)folderPath {
    if ((self = [super init])) {
        _currentFolderPath = [folderPath copy];
        _folderTrail = [NSMutableArray array];
        _folderScrollOffsets = [NSMutableArray array];
        // Seed the trail if we were opened directly inside a folder (root is empty).
        if (_currentFolderPath.length > 0) {
            [_folderTrail addObject:_currentFolderPath];
        }
        _filterTypes = [NSMutableSet set];
        _filterSources = [NSMutableSet set];
        _filterUsernames = [NSMutableSet set];
        _filterFavoritesOnly = NO;
        _selectedFileIDs = [NSMutableSet set];

        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _sortMode = (SCIGallerySortMode)[d integerForKey:kSortModeKey];
        _sortGroupByMediaType = [d boolForKey:kSortGroupByTypeKey];
        if (_sortMode == SCIGallerySortModeTypeAsc || _sortMode == SCIGallerySortModeTypeDesc) {
            _sortMode = SCIGallerySortModeDateAddedDesc;
            _sortGroupByMediaType = YES;
            [d setInteger:_sortMode forKey:kSortModeKey];
            [d setBool:_sortGroupByMediaType forKey:kSortGroupByTypeKey];
        }
        _viewMode = (SCIGalleryViewMode)[d integerForKey:kViewModeKey];
        _gridColumns = SCIGalleryGridColumns();
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleGalleryPreferencesChanged:)
                                                 name:@"SCIGalleryFavoritesSortPreferenceChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleGridControlsPreferenceChanged:)
                                                 name:kSCIGalleryGridControlsChangedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleGalleryPreferencesChanged:)
                                                 name:SCIGalleryHiddenSourcesDidChangeNotification
                                               object:nil];

    [self setupCenteredTitle];
    [self setupNavigationItems];
    [self setupSearchController];
    [self setupBottomToolbar];
    [self setupCollectionView];
    [self setupEmptyState];
    [self setupFolderBackGesture];
    [self setupFetchedResultsController];
    [self reloadSubfolders];
    [self updateEmptyState];

    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationController.presentationController.delegate = self;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyGalleryNavigationChrome];
    [self refreshNavigationItems];
    [self refreshBottomToolbarItems];
    [self.navigationController setToolbarHidden:NO animated:animated];
    [self updateCollectionInsets];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Hide the shared toolbar when navigating to a child that shouldn't show it
    // (e.g. settings). Keep it visible when pushing another gallery screen so it
    // doesn't flicker during the push animation; that screen manages its own.
    UIViewController *incoming = self.navigationController.topViewController;
    if (incoming && incoming != self && ![incoming isKindOfClass:[SCIGalleryViewController class]]) {
        [self.navigationController setToolbarHidden:YES animated:animated];
    }
    if (self.navigationController.viewControllers.firstObject != self) return;
    if (self.isMovingFromParentViewController) return;
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed) {
        if ([SCIGalleryManager sharedManager].isLockEnabled) {
            [[SCIGalleryManager sharedManager] lockGallery];
        }
    }
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if ([SCIGalleryManager sharedManager].isLockEnabled) {
        [[SCIGalleryManager sharedManager] lockGallery];
    }
}

- (void)dismissSelf {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Navigation & chrome

/// Shared neutral chrome matching the Instagram-inspired custom palette.
- (void)applyGalleryNavigationChrome {
    UINavigationController *nav = self.navigationController;
    if (!nav) {
        return;
    }
    nav.navigationBar.prefersLargeTitles = NO;
    SCIApplyMediaChromeNavigationBar(nav.navigationBar);
}

- (void)setupCenteredTitle {
    NSString *text = nil;
    if (self.selectionMode) {
        text = self.selectedFileIDs.count > 0
            ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedFileIDs.count]
            : @"Select Files";
    } else {
        text = self.currentFolderPath.length > 0 ? [self.currentFolderPath lastPathComponent] : @"Gallery";
    }
    self.navigationItem.titleView = nil;
    self.title = text;
}

- (void)setupNavigationItems {
    [self refreshNavigationItems];
}

- (void)setupSearchController {
    UISearchController *controller = [[UISearchController alloc] initWithSearchResultsController:nil];
    controller.obscuresBackgroundDuringPresentation = NO;
    controller.hidesNavigationBarDuringPresentation = NO;
    controller.searchResultsUpdater = self;
    controller.delegate = self;
    controller.searchBar.delegate = self;
    [controller.searchBar setImage:[SCIAssetUtils instagramIconNamed:@"search" pointSize:18.0] 
                         forSearchBarIcon:UISearchBarIconSearch 
                                    state:UIControlStateNormal];
    controller.searchBar.placeholder = @"Search...";
    // Scope toggle: search the current folder, or across all folders. Let the
    // search controller manage the scope bar's visibility (shown while searching).
    controller.searchBar.scopeButtonTitles = @[@"This Folder", @"All Folders"];
    controller.automaticallyShowsScopeBar = YES;
    self.searchController = controller;
    self.navigationItem.searchController = controller;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    // iOS 26 integrated search button: collapses search into a single button (the
    // vended `searchBarPlacementBarButtonItem`) instead of an always-visible bar.
    // That item is toolbar-only, so it lives in the bottom toolbar.
    if (@available(iOS 26.0, *)) {
        @try {
            [self.navigationItem setValue:@(kSCIUINavigationItemSearchBarPlacementIntegratedButton) forKey:@"preferredSearchBarPlacement"];
            // Force the integrated button to fully materialize now (and cache it), so
            // the bottom toolbar claims a ready instance on its very first build. If
            // it's vended lazily later, the nav bar renders it in its top-right home
            // for a frame during the first transition — the flash the user sees, which
            // only stops once search has been activated (which forces this same
            // materialization). Loading the controller's view commits that state up
            // front, the way a real activation does.
            [self.searchController loadViewIfNeeded];
            UIBarButtonItem *vended = [self.navigationItem valueForKey:@"searchBarPlacementBarButtonItem"];
            if ([vended isKindOfClass:[UIBarButtonItem class]]) {
                self.cachedSearchToolbarItem = vended;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    self.definesPresentationContext = YES;
}

- (void)refreshNavigationItems {
    // Selection-mode select-all icon reflects current selection.
    NSString *selectionIcon = @"circle";
    NSString *selectionAccessibilityLabel = @"Select all";
    if (self.selectionMode) {
        NSArray<SCIGalleryFile *> *files = [self visibleGalleryFiles];
        BOOL allSelected = files.count > 0 && self.selectedFileIDs.count == files.count;
        if (allSelected) {
            selectionIcon = @"circle_check_filled";
            selectionAccessibilityLabel = @"Deselect all";
        } else if (self.selectedFileIDs.count > 0) {
            selectionIcon = @"circle_check";
            selectionAccessibilityLabel = @"Select all";
        }
    }

    // Leading group changes as you browse (close ⇄ back) or enter selection
    // (Cancel). Apply only when it actually changes.
    NSString *leadingSignature = self.selectionMode ? @"cancel"
        : ([self canNavigateBackInFolders] ? @"back" : @"close");
    if (![leadingSignature isEqualToString:self.lastLeadingNavSignature]) {
        self.lastLeadingNavSignature = leadingSignature;
        UIBarButtonItem *leadingItem;
        if (self.selectionMode) {
            leadingItem = SCIMediaChromeTopBarButtonItem(@"xmark", self, @selector(exitSelectionMode));
            leadingItem.accessibilityLabel = @"Cancel";
        } else if ([self canNavigateBackInFolders]) {
            leadingItem = SCIMediaChromeTopBarButtonItem(@"chevron_left", self, @selector(navigateBackInFolders));
        } else {
            leadingItem = SCIMediaChromeTopBarButtonItem(@"xmark", self, @selector(dismissSelf));
        }
        SCIMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ leadingItem ]);
    }

    // Trailing group only changes between browse (Select + Settings) and selection
    // (Select-all, whose icon tracks the count) — never on folder navigation. Apply
    // only on change so the Liquid Glass pill doesn't re-lay-out (a visible jump).
    NSString *trailingSignature = self.selectionMode
        ? [@"selectAll:" stringByAppendingString:selectionIcon]
        : @"browse";
    if (![trailingSignature isEqualToString:self.lastTrailingNavSignature]) {
        self.lastTrailingNavSignature = trailingSignature;
        if (self.selectionMode) {
            UIBarButtonItem *selectAllItem = SCIMediaChromeTopBarButtonItem(selectionIcon, self, @selector(selectAllVisibleFiles));
            selectAllItem.accessibilityLabel = selectionAccessibilityLabel;
            SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ selectAllItem ]);
        } else {
            // Search is the native iOS 26 integrated button (toolbar-only), so it
            // lives in the bottom toolbar, not here.
            NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];
            [items addObject:SCIMediaChromeTopBarButtonItem(@"circle_check", self, @selector(enterSelectionMode))];
            [items addObject:SCIMediaChromeTopBarButtonItem(@"settings", self, @selector(pushSettings))];
            SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, items);
        }
    }
}

- (void)setupBottomToolbar {
    [self refreshBottomToolbarItems];
}

- (UIBarButtonItem *)galleryBottomBarItemWithResource:(NSString *)resourceName accessibility:(NSString *)label action:(SEL)action {
    return SCIMediaChromeBottomBarButtonItem(resourceName, label, self, action);
}

- (void)refreshBottomToolbarItems {
    SCIMediaChromeConfigureBottomToolbar(self.navigationController.toolbar);

    NSArray<UIBarButtonItem *> *primary;
    if (self.selectionMode) {
        UIBarButtonItem *shareItem = [self galleryBottomBarItemWithResource:@"share" accessibility:@"Share selected" action:@selector(shareSelectedFiles)];
        UIBarButtonItem *moveItem = [self galleryBottomBarItemWithResource:@"folder_move" accessibility:@"Move selected" action:@selector(moveSelectedFiles)];
        UIBarButtonItem *favoriteItem = [self galleryBottomBarItemWithResource:@"heart" accessibility:@"Favorite selected" action:@selector(toggleFavoriteForSelectedFiles)];
        UIBarButtonItem *deleteItem = [self galleryBottomBarItemWithResource:@"trash" accessibility:@"Delete selected" action:@selector(deleteSelectedFiles)];
        deleteItem.tintColor = [SCIUtils SCIColor_InstagramDestructive];

        primary = @[shareItem, moveItem, favoriteItem, deleteItem];
    } else {
        UIBarButtonItem *filterItem = [self galleryBottomBarItemWithResource:@"filter" accessibility:@"Filter" action:@selector(presentFilter)];
        UIBarButtonItem *sortItem = [self galleryBottomBarItemWithResource:@"sort" accessibility:@"Sort" action:@selector(presentSort)];

        NSString *toggleResource = self.viewMode == SCIGalleryViewModeGrid ? @"list" : @"grid";
        NSString *toggleAX = self.viewMode == SCIGalleryViewModeGrid ? @"List view" : @"Grid view";
        UIBarButtonItem *toggleItem = [self galleryBottomBarItemWithResource:toggleResource accessibility:toggleAX action:@selector(toggleViewMode)];

        UIBarButtonItem *folderItem = [self galleryBottomBarItemWithResource:@"folder" accessibility:@"New folder" action:@selector(presentCreateFolder)];

        primary = @[toggleItem, sortItem, filterItem, folderItem];
    }

    // Search lives in its own trailing capsule in both browse and selection modes
    // (you can search to find more items to select).
    self.toolbarItems = SCIMediaChromeBottomToolbarItemsWithTrailingGroup(primary, @[ [self bottomToolbarSearchItem] ]);
}

// The bottom toolbar's search item: the native iOS 26 integrated search button
// (toolbar-only, materialized + cached at load), falling back to a custom button
// that reveals the nav bar search on older systems.
- (UIBarButtonItem *)bottomToolbarSearchItem {
    UIBarButtonItem *searchItem = self.cachedSearchToolbarItem;
    if (!searchItem) {
        if (@available(iOS 26.0, *)) {
            @try {
                UIBarButtonItem *vended = [self.navigationItem valueForKey:@"searchBarPlacementBarButtonItem"];
                if ([vended isKindOfClass:[UIBarButtonItem class]]) {
                    searchItem = vended;
                    self.cachedSearchToolbarItem = vended;
                }
            } @catch (__unused NSException *exception) {
            }
        }
    }
    if (!searchItem) {
        searchItem = [self galleryBottomBarItemWithResource:@"search" accessibility:@"Search" action:@selector(activateSearch)];
    }
    return searchItem;
}

#pragma mark - Collection View

- (void)setupCollectionView {
    UICollectionViewLayout *layout = [self layoutForViewMode:self.viewMode];

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.alwaysBounceVertical = YES;
    _collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_collectionView registerClass:[SCIGalleryGridCell class] forCellWithReuseIdentifier:kGridCellID];
    [_collectionView registerClass:[SCIGalleryListCollectionCell class] forCellWithReuseIdentifier:kListCellID];
    [_collectionView registerClass:[SCIGalleryFolderCell class] forCellWithReuseIdentifier:kFolderCellID];
    [_collectionView registerClass:[SCIGalleryFolderChipBar class]
         forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                withReuseIdentifier:kFolderChipHeaderID];
    [self.view addSubview:_collectionView];

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleGridPinch:)];
    [_collectionView addGestureRecognizer:pinch];

    [NSLayoutConstraint activateConstraints:@[
        [_collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateCollectionInsets];
}

- (void)updateCollectionInsets {
    // The hosting navigation controller folds the visible bottom toolbar into
    // this view controller's safe area, and the collection view's automatic
    // content-inset adjustment already accounts for it. Keep our manual bottom
    // inset at zero so we don't double-count the toolbar height.
    UIEdgeInsets contentInsets = self.collectionView.contentInset;
    contentInsets.bottom = 0.0;
    self.collectionView.contentInset = contentInsets;

    UIEdgeInsets indicatorInsets = self.collectionView.scrollIndicatorInsets;
    indicatorInsets.bottom = 0.0;
    self.collectionView.scrollIndicatorInsets = indicatorInsets;
}

- (UICollectionViewLayout *)layoutForViewMode:(SCIGalleryViewMode)mode {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    if (mode == SCIGalleryViewModeGrid) {
        layout.minimumInteritemSpacing = kGridSpacing;
        layout.minimumLineSpacing = kGridSpacing;
    } else {
        layout.minimumInteritemSpacing = 0;
        layout.minimumLineSpacing = 0;
    }
    layout.sectionHeadersPinToVisibleBounds = SCIGalleryFolderBarPinned();
    return layout;
}

- (void)toggleViewMode {
    if (self.selectionMode) {
        [self exitSelectionMode];
    }
    self.viewMode = self.viewMode == SCIGalleryViewModeGrid ? SCIGalleryViewModeList : SCIGalleryViewModeGrid;
    [[NSUserDefaults standardUserDefaults] setInteger:self.viewMode forKey:kViewModeKey];

    UICollectionViewLayout *newLayout = [self layoutForViewMode:self.viewMode];
    [self.collectionView setCollectionViewLayout:newLayout animated:NO];
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
    [self updateEmptyState];
    [self refreshBottomToolbarItems];
}

#pragma mark - Grid Density

- (void)setGridColumns:(NSInteger)gridColumns {
    NSInteger clamped = MAX(kSCIGalleryGridColumnsMin, MIN(kSCIGalleryGridColumnsMax, gridColumns));
    if (clamped == _gridColumns) return;
    _gridColumns = clamped;
    SCIGalleryGridSetColumns(clamped);
}

/// Applies a new column count with a smooth relayout. No-op outside grid mode.
- (void)applyGridColumns:(NSInteger)columns animated:(BOOL)animated {
    if (self.viewMode != SCIGalleryViewModeGrid) return;
    NSInteger clamped = MAX(kSCIGalleryGridColumnsMin, MIN(kSCIGalleryGridColumnsMax, columns));
    if (clamped == self.gridColumns) return;

    self.gridColumns = clamped;

    if (animated) {
        [UIView animateWithDuration:0.25
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            [self.collectionView.collectionViewLayout invalidateLayout];
            [self.collectionView layoutIfNeeded];
        } completion:^(__unused BOOL finished) {
            // Username overlay visibility depends on density; refresh cells.
            [self reconfigureVisibleGridCells];
        }];
    } else {
        [self.collectionView.collectionViewLayout invalidateLayout];
        [self reconfigureVisibleGridCells];
    }
    [self refreshBottomToolbarItems];
}

/// Re-runs grid cell configuration for visible items (e.g. after a density
/// change that toggles the username overlay) without a full reload.
- (void)reconfigureVisibleGridCells {
    if (self.viewMode != SCIGalleryViewModeGrid) return;
    BOOL showsMeta = ![[NSUserDefaults standardUserDefaults] boolForKey:kSCIGalleryGridShowSourceUsernameDisabledKey];
    BOOL showsUsername = showsMeta && self.gridColumns <= 3;
    for (NSIndexPath *indexPath in self.collectionView.indexPathsForVisibleItems) {
        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
        if (![cell isKindOfClass:[SCIGalleryGridCell class]]) continue;
        SCIGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];
        if (!file) continue;
        [(SCIGalleryGridCell *)cell configureWithGalleryFile:file
                                               selectionMode:self.selectionMode
                                                    selected:[self.selectedFileIDs containsObject:file.identifier]
                                                 showsSource:showsMeta
                                               showsUsername:showsUsername];
    }
}

- (void)handleGridPinch:(UIPinchGestureRecognizer *)pinch {
    if (self.viewMode != SCIGalleryViewModeGrid) return;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSCIGalleryGridPinchDisabledKey]) return;
    if (pinch.state != UIGestureRecognizerStateChanged) return;
    // Pinch out (scale > 1) -> fewer columns (bigger cells); pinch in -> more.
    CGFloat threshold = 0.30;
    if (pinch.scale > 1.0 + threshold && self.gridColumns > kSCIGalleryGridColumnsMin) {
        [self applyGridColumns:SCIGalleryGridColumnsAdjacent(self.gridColumns, YES) animated:YES];
        pinch.scale = 1.0;
    } else if (pinch.scale < 1.0 - threshold && self.gridColumns < kSCIGalleryGridColumnsMax) {
        [self applyGridColumns:SCIGalleryGridColumnsAdjacent(self.gridColumns, NO) animated:YES];
        pinch.scale = 1.0;
    }
}

#pragma mark - Empty State

- (void)setupEmptyState {
    _emptyStateView = [[UIView alloc] initWithFrame:CGRectZero];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.hidden = YES;
    [self.view addSubview:_emptyStateView];

    UIImage *emptyIconImage = [SCIAssetUtils instagramIconNamed:@"media_empty"
                                                      pointSize:96.0];
    UIImageView *icon = [[UIImageView alloc] initWithImage:emptyIconImage];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = [SCIUtils SCIColor_InstagramTertiaryText];
    [_emptyStateView addSubview:icon];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = @"No files in Gallery";
    label.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    [_emptyStateView addSubview:label];
    _emptyStateLabel = label;

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectZero];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Save media from the preview screen\nto see it here.";
    subtitle.textColor = [SCIUtils SCIColor_InstagramTertiaryText];
    subtitle.font = [UIFont systemFontOfSize:14];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 0;
    [_emptyStateView addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
        [_emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40],
        [_emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40],

        [icon.topAnchor constraintEqualToAnchor:_emptyStateView.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:64],
        [icon.heightAnchor constraintEqualToConstant:64],

        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:20],
        [label.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],

        [subtitle.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8],
        [subtitle.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],
        [subtitle.bottomAnchor constraintEqualToAnchor:_emptyStateView.bottomAnchor],
    ]];
}

- (void)updateEmptyState {
    NSInteger files = self.fetchedResultsController.fetchedObjects.count;
    NSInteger folders = [self showsFolderChips] ? self.subfolders.count : 0;
    BOOL hasFilters = self.filterTypes.count > 0 || self.filterSources.count > 0 || self.filterFavoritesOnly;

    BOOL isEmpty = (files == 0 && folders == 0);
    self.emptyStateView.hidden = !isEmpty;
    self.collectionView.hidden = isEmpty;

    if (isEmpty && hasFilters) {
        self.emptyStateLabel.text = @"No matching files";
    } else {
        self.emptyStateLabel.text = @"No files in Gallery";
    }
}

#pragma mark - Fetched Results Controller

- (void)setupFetchedResultsController {
    NSFetchRequest *request = [self currentFetchRequest];

    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    _fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
                                                                    managedObjectContext:ctx
                                                                      sectionNameKeyPath:nil
                                                                               cacheName:nil];
    _fetchedResultsController.delegate = self;

    NSError *error;
    if (![_fetchedResultsController performFetch:&error]) {
        SCILog(@"General", @"[SCInsta Gallery] Fetch failed: %@", error);
    }
}

- (NSFetchRequest *)currentFetchRequest {
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    NSMutableArray<NSSortDescriptor *> *sortDescriptors = [[SCIGallerySortViewController sortDescriptorsForMode:self.sortMode groupByMediaType:self.sortGroupByMediaType] mutableCopy];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kFavoritesAtTopKey] && !self.filterFavoritesOnly) {
        [sortDescriptors insertObject:[NSSortDescriptor sortDescriptorWithKey:@"isFavorite" ascending:NO] atIndex:0];
    }
    request.sortDescriptors = sortDescriptors;
    NSString *query = [self.searchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // "Search all folders" only applies while actually searching; otherwise stay
    // scoped to the current folder.
    BOOL searchingAllFolders = self.searchAllFolders && query.length > 0;
    NSPredicate *basePredicate = [SCIGalleryFilterViewController predicateForTypes:self.filterTypes
                                                                         sources:self.filterSources
                                                                   favoritesOnly:self.filterFavoritesOnly
                                                                       usernames:self.filterUsernames
                                                                      folderPath:self.currentFolderPath
                                                                   scopeToFolder:!searchingAllFolders];
    NSPredicate *visibleSources = SCIGalleryVisibleSourcesPredicate();
    if (visibleSources) {
        basePredicate = basePredicate
            ? [NSCompoundPredicate andPredicateWithSubpredicates:@[basePredicate, visibleSources]]
            : visibleSources;
    }
    if (query.length == 0) {
        request.predicate = basePredicate;
        return request;
    }

    NSPredicate *searchPredicate = [NSPredicate predicateWithFormat:@"(sourceUsername CONTAINS[cd] %@) OR (customName CONTAINS[cd] %@) OR (relativePath CONTAINS[cd] %@)",
                                    query, query, query];
    // basePredicate can be nil when searching all folders with no other filters
    // active (no folder scope, no filters) — don't put nil into the AND array.
    request.predicate = basePredicate
        ? [NSCompoundPredicate andPredicateWithSubpredicates:@[basePredicate, searchPredicate]]
        : searchPredicate;
    return request;
}

- (void)refetch {
    if (self.selectionMode) {
        [self.selectedFileIDs removeAllObjects];
    }
    NSFetchRequest *request = [self currentFetchRequest];
    _fetchedResultsController.fetchRequest.sortDescriptors = request.sortDescriptors;
    _fetchedResultsController.fetchRequest.predicate = request.predicate;

    NSError *error;
    if (![_fetchedResultsController performFetch:&error]) {
        SCILog(@"General", @"[SCInsta Gallery] Refetch failed: %@", error);
    }
    [self reloadSubfolders];
    [self.collectionView reloadData];
    [self updateEmptyState];
    [self setupCenteredTitle];
    [self refreshNavigationItems];
}

#pragma mark - Subfolders

- (void)reloadSubfolders {
    if (self.searchQuery.length > 0) {
        self.subfolders = @[];
        return;
    }
    // Subfolders are derived from distinct `folderPath` values on files whose path
    // is a descendant of the current path.
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.resultType = NSDictionaryResultType;
    req.propertiesToFetch = @[@"folderPath"];
    req.returnsDistinctResults = YES;

    NSString *base = self.currentFolderPath ?: @"";
    NSString *prefix = base.length == 0 ? @"/" : [base stringByAppendingString:@"/"];
    NSPredicate *folderPredicate = [NSPredicate predicateWithFormat:@"folderPath BEGINSWITH %@", prefix];
    NSPredicate *visibleSources = SCIGalleryVisibleSourcesPredicate();
    req.predicate = visibleSources
        ? [NSCompoundPredicate andPredicateWithSubpredicates:@[folderPredicate, visibleSources]]
        : folderPredicate;

    NSArray<NSDictionary *> *results = [ctx executeFetchRequest:req error:nil];
    NSMutableSet<NSString *> *immediate = [NSMutableSet set];

    for (NSDictionary *row in results) {
        NSString *p = row[@"folderPath"];
        if (p.length <= prefix.length) continue;
        NSString *rest = [p substringFromIndex:prefix.length];
        NSRange slash = [rest rangeOfString:@"/"];
        NSString *folderName = slash.location == NSNotFound ? rest : [rest substringToIndex:slash.location];
        if (folderName.length == 0) continue;
        [immediate addObject:[prefix stringByAppendingString:folderName]];
    }

    self.subfolders = [[immediate allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    [self mergePlaceholderSubfolders];
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    // If the last media from a filtered user was removed, drop that username from
    // the active filter so the user isn't left staring at an empty filtered view.
    if ([self pruneStaleUsernameFilters]) {
        [self refetch];
        return;
    }
    [self reloadSubfolders];
    [self.collectionView reloadData];
    [self updateEmptyState];
    [self refreshNavigationItems];
}

#pragma mark - UICollectionViewDataSource

- (BOOL)showsFolderSection {
    // Folders are now presented as a horizontal chip strip in the section
    // header (see showsFolderChips), not as full-width rows. Retiring the row
    // section collapses the layout to a single files section in both modes.
    return NO;
}

/// Folder chips show above the media in both grid and list modes, whenever the
/// current folder has subfolders and the user isn't searching or selecting.
- (BOOL)showsFolderChips {
    return self.subfolders.count > 0 && self.searchQuery.length == 0 && !self.selectionMode;
}

- (BOOL)isFolderIndexPath:(NSIndexPath *)indexPath {
    return [self showsFolderSection] && indexPath.section == 0;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)cv {
    return [self showsFolderSection] ? 2 : 1;
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    if ([self showsFolderSection] && section == 0) return self.subfolders.count;
    NSArray *sections = self.fetchedResultsController.sections;
    if (sections.count == 0) return 0;
    return ((id<NSFetchedResultsSectionInfo>)sections[0]).numberOfObjects;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv
                            cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isFolderIndexPath:indexPath]) {
        SCIGalleryFolderCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kFolderCellID forIndexPath:indexPath];
        NSString *path = self.subfolders[indexPath.item];
        NSInteger itemCount = SCIGalleryItemCountForFolderPath([SCIGalleryCoreDataStack shared].viewContext, path);
        [cell configureWithFolderName:[path lastPathComponent] itemCount:itemCount];
        return cell;
    }

    NSIndexPath *filePath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    SCIGalleryFile *file = [self.fetchedResultsController objectAtIndexPath:filePath];

    if (self.viewMode == SCIGalleryViewModeGrid) {
        SCIGalleryGridCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kGridCellID forIndexPath:indexPath];
        BOOL showsMeta = ![[NSUserDefaults standardUserDefaults] boolForKey:kSCIGalleryGridShowSourceUsernameDisabledKey];
        // Username caption only fits at roomy densities (2-3 columns).
        BOOL showsUsername = showsMeta && self.gridColumns <= 3;
        [cell configureWithGalleryFile:file
                       selectionMode:self.selectionMode
                            selected:[self.selectedFileIDs containsObject:file.identifier]
                         showsSource:showsMeta
                       showsUsername:showsUsername];
        return cell;
    }

    SCIGalleryListCollectionCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kListCellID forIndexPath:indexPath];
    [cell configureWithGalleryFile:file
                   selectionMode:self.selectionMode
                        selected:[self.selectedFileIDs containsObject:file.identifier]];
    [cell setFolderContextName:[self searchResultFolderNameForFile:file]];
    [cell setMoreActionsMenu:self.selectionMode ? nil : [self fileActionsMenuForFile:file]];
    return cell;
}

// The folder a search result lives in, shown on the cell only while searching
// across all folders and when the file is in a different, non-root folder.
- (NSString *)searchResultFolderNameForFile:(SCIGalleryFile *)file {
    if (!self.searchAllFolders || self.searchQuery.length == 0) {
        return nil;
    }
    NSString *folderPath = file.folderPath;
    if (folderPath.length == 0) {
        return nil; // root
    }
    if ([folderPath isEqualToString:self.currentFolderPath ?: @""]) {
        return nil; // already the folder we're in
    }
    return [folderPath lastPathComponent];
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)cv
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if (![kind isEqualToString:UICollectionElementKindSectionHeader]) {
        return [[UICollectionReusableView alloc] init];
    }

    SCIGalleryFolderChipBar *header =
        [cv dequeueReusableSupplementaryViewOfKind:kind
                               withReuseIdentifier:kFolderChipHeaderID
                                      forIndexPath:indexPath];

    if (![self showsFolderChips]) {
        return header;
    }

    NSArray<NSString *> *folders = self.subfolders;
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:folders.count];
    NSMutableArray<NSNumber *> *counts = [NSMutableArray arrayWithCapacity:folders.count];
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    for (NSString *path in folders) {
        [names addObject:[path lastPathComponent]];
        [counts addObject:@(SCIGalleryItemCountForFolderPath(ctx, path))];
    }

    __weak typeof(self) weakSelf = self;
    [header configureWithFolderNames:names
                              counts:counts
                            onSelect:^(NSInteger index) {
        [weakSelf openSubfolderAtIndex:index];
    }
                        menuProvider:^UIMenu * _Nullable(NSInteger index) {
        return [weakSelf folderChipMenuForIndex:index];
    }];
    return header;
}

/// Opens the subfolder at `index` in place (no pushed view controller).
- (void)openSubfolderAtIndex:(NSInteger)index {
    if (self.selectionMode) return;
    if (index < 0 || index >= (NSInteger)self.subfolders.count) return;
    [self navigateIntoFolder:self.subfolders[index]];
}

#pragma mark - In-place folder navigation

// Left-edge swipe to go up a folder, mirroring the native pop gesture (we no
// longer push view controllers, so the system one doesn't apply).
- (void)setupFolderBackGesture {
    UIScreenEdgePanGestureRecognizer *edgePan = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFolderBackEdgePan:)];
    edgePan.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edgePan];
}

- (void)handleFolderBackEdgePan:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan && [self canNavigateBackInFolders]) {
        [self navigateBackInFolders];
    }
}

- (BOOL)canNavigateBackInFolders {
    return self.folderTrail.count > 0;
}

/// Descends into `subfolderPath` by re-scoping the current screen's data, instead
/// of pushing a new view controller — keeping the shared chrome intact.
- (void)navigateIntoFolder:(NSString *)subfolderPath {
    if (subfolderPath.length == 0) {
        return;
    }
    // Remember where we were so returning restores the grid position.
    [self.folderScrollOffsets addObject:[NSValue valueWithCGPoint:self.collectionView.contentOffset]];
    [self.folderTrail addObject:subfolderPath];
    self.currentFolderPath = subfolderPath;

    [self prepareForFolderChange];
    __weak typeof(self) weakSelf = self;
    [self replaceGridContentWithCrossfade:^{
        [weakSelf refetch];
        [weakSelf scrollGridToTop];
    }];
    [self setupCenteredTitle];
    [self refreshNavigationItems];
}

/// Returns to the parent folder, restoring its previous scroll position.
- (void)navigateBackInFolders {
    if (![self canNavigateBackInFolders]) {
        return;
    }
    [self.folderTrail removeLastObject];
    self.currentFolderPath = self.folderTrail.lastObject; // nil at root

    CGPoint restoreOffset = CGPointZero;
    BOOL hasRestoreOffset = NO;
    if (self.folderScrollOffsets.count > 0) {
        restoreOffset = [self.folderScrollOffsets.lastObject CGPointValue];
        [self.folderScrollOffsets removeLastObject];
        hasRestoreOffset = YES;
    }

    [self prepareForFolderChange];
    __weak typeof(self) weakSelf = self;
    [self replaceGridContentWithCrossfade:^{
        [weakSelf refetch];
        if (hasRestoreOffset) {
            [weakSelf.collectionView setContentOffset:restoreOffset animated:NO];
        } else {
            [weakSelf scrollGridToTop];
        }
    }];
    [self setupCenteredTitle];
    [self refreshNavigationItems];
}

/// Shared cleanup when changing folders: exit selection and clear any active search
/// so each folder opens in a clean browse state.
- (void)prepareForFolderChange {
    if (self.selectionMode) {
        [self exitSelectionMode];
    }
    if (self.searchController.active) {
        self.searchController.active = NO;
    }
    self.searchQuery = nil;
    self.searchController.searchBar.text = nil;
    self.searchAllFolders = NO;
    self.searchController.searchBar.selectedScopeButtonIndex = 0;
}

- (void)scrollGridToTop {
    CGFloat topY = -self.collectionView.adjustedContentInset.top;
    [self.collectionView setContentOffset:CGPointMake(0.0, topY) animated:NO];
}

/// Smoothly swaps the grid's contents with a cross-dissolve (no positional slide,
/// so no layout jank). `contentUpdate` should apply the new data/scroll; the
/// transition dissolves the old contents into the new.
- (void)replaceGridContentWithCrossfade:(void (^)(void))contentUpdate {
    if (!contentUpdate) {
        return;
    }
    [UIView transitionWithView:self.collectionView
                      duration:0.22
                       options:(UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction)
                    animations:contentUpdate
                    completion:nil];
}

/// Context menu (rename/delete/etc.) for the folder chip at `index`, reusing the
/// same actions as the legacy folder rows.
- (UIMenu *)folderChipMenuForIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.subfolders.count) return nil;
    NSString *folderPath = self.subfolders[index];
    return [self folderActionsMenuForFolderPath:folderPath];
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)cv
                  layout:(UICollectionViewLayout *)layout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = cv.bounds.size.width;
    if ([self isFolderIndexPath:indexPath]) {
        return CGSizeMake(width, 88);
    }
    if (self.viewMode == SCIGalleryViewModeGrid) {
        NSInteger columns = MAX(kSCIGalleryGridColumnsMin, MIN(kSCIGalleryGridColumnsMax, self.gridColumns));
        CGFloat totalSpacing = kGridSpacing * (columns - 1);
        CGFloat side = floor((width - totalSpacing) / columns);
        return CGSizeMake(side, side);
    }
    return CGSizeMake(width, 72);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)cv
                        layout:(UICollectionViewLayout *)layout
        insetForSectionAtIndex:(NSInteger)section {
    if ([self showsFolderSection] && section == 0 && self.subfolders.count > 0) {
        return UIEdgeInsetsMake(10, 0, 6, 0);
    }
    return UIEdgeInsetsZero;
}

- (CGSize)collectionView:(UICollectionView *)cv
                  layout:(UICollectionViewLayout *)layout
referenceSizeForHeaderInSection:(NSInteger)section {
    if (section == 0 && [self showsFolderChips]) {
        return CGSizeMake(cv.bounds.size.width, [SCIGalleryFolderChipBar preferredHeight]);
    }
    return CGSizeZero;
}

- (CGFloat)collectionView:(UICollectionView *)cv
                   layout:(UICollectionViewLayout *)layout
 minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    if ([self showsFolderSection] && section == 0) {
        return 0;
    }
    return self.viewMode == SCIGalleryViewModeGrid ? kGridSpacing : 0;
}

- (CGFloat)collectionView:(UICollectionView *)cv
                   layout:(UICollectionViewLayout *)layout
 minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    if ([self showsFolderSection] && section == 0) {
        return 0;
    }
    return self.viewMode == SCIGalleryViewModeGrid ? kGridSpacing : 0;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [cv deselectItemAtIndexPath:indexPath animated:YES];

    if ([self isFolderIndexPath:indexPath]) {
        if (self.selectionMode) {
            return;
        }
        [self navigateIntoFolder:self.subfolders[indexPath.item]];
        return;
    }

    NSIndexPath *filePath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    SCIGalleryFile *selectedFile = [self.fetchedResultsController objectAtIndexPath:filePath];
    if (self.selectionMode) {
        [self toggleSelectionForFile:selectedFile];
        return;
    }

    NSArray *allFiles = self.fetchedResultsController.fetchedObjects;
    NSInteger idx = [allFiles indexOfObject:selectedFile];
    if (idx == NSNotFound) idx = 0;
    [SCIFullScreenMediaPlayer showGalleryFiles:allFiles
                             startingAtIndex:idx
                          fromViewController:self];
}

- (void)showGalleryOpenFailureMessage:(NSString *)title actionIdentifier:(NSString *)actionIdentifier {
    SCINotify(actionIdentifier, title, @"The original content may no longer exist.", @"error_filled", SCINotificationToneError);
}

- (void)dismissGalleryForOriginOpenWithCompletion:(void (^)(void))completion {
    if ([SCIGalleryManager sharedManager].isLockEnabled) {
        [[SCIGalleryManager sharedManager] lockGallery];
    }

    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        if (completion) {
            completion();
        }
    }];
}

- (void)openOriginalPostForFile:(SCIGalleryFile *)file {
    NSString *noun = [[file openOriginalActionTitle] hasPrefix:@"Open "]
        ? [[file openOriginalActionTitle] substringFromIndex:5]
        : @"original post";
    NSString *lowerNoun = noun.lowercaseString;
    if ([SCIGalleryOriginController openOriginalPostForGalleryFile:file]) {
        [self dismissGalleryForOriginOpenWithCompletion:^{
            SCINotify(kSCINotificationGalleryOpenOriginal, [NSString stringWithFormat:@"Opened %@", lowerNoun], nil, @"external_link", SCINotificationToneInfo);
        }];
    } else {
        [self showGalleryOpenFailureMessage:[NSString stringWithFormat:@"Unable to open %@", lowerNoun] actionIdentifier:kSCINotificationGalleryOpenOriginal];
    }
}

- (void)openProfileForFile:(SCIGalleryFile *)file {
    if ([SCIGalleryOriginController openProfileForGalleryFile:file]) {
        [self dismissGalleryForOriginOpenWithCompletion:^{
            SCINotify(kSCINotificationGalleryOpenProfile, @"Opened profile", nil, @"user_circle", SCINotificationToneForIconResource(@"user_circle"));
        }];
    } else {
        [self showGalleryOpenFailureMessage:@"Unable to open profile" actionIdentifier:kSCINotificationGalleryOpenProfile];
    }
}

- (NSArray<SCIGalleryFile *> *)visibleGalleryFiles {
    return self.fetchedResultsController.fetchedObjects ?: @[];
}

- (SCIGalleryFile *)galleryFileForCollectionIndexPath:(NSIndexPath *)indexPath {
    if ([self isFolderIndexPath:indexPath]) {
        return nil;
    }
    NSIndexPath *filePath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    return [self.fetchedResultsController objectAtIndexPath:filePath];
}

- (void)animateSelectionModeTransition {
    for (NSIndexPath *indexPath in self.collectionView.indexPathsForVisibleItems) {
        SCIGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];
        if (!file) {
            continue;
        }

        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
        BOOL selected = [self.selectedFileIDs containsObject:file.identifier];
        if ([cell isKindOfClass:[SCIGalleryListCollectionCell class]]) {
            [(SCIGalleryListCollectionCell *)cell setSelectionMode:self.selectionMode selected:selected animated:YES];
            [(SCIGalleryListCollectionCell *)cell setMoreActionsMenu:self.selectionMode ? nil : [self fileActionsMenuForFile:file]];
        } else if ([cell isKindOfClass:[SCIGalleryGridCell class]]) {
            [(SCIGalleryGridCell *)cell setSelectionMode:self.selectionMode selected:selected animated:YES];
        }
    }
}

- (NSArray<SCIGalleryFile *> *)selectedGalleryFiles {
    if (self.selectedFileIDs.count == 0) {
        return @[];
    }

    NSMutableArray<SCIGalleryFile *> *files = [NSMutableArray array];
    for (SCIGalleryFile *file in [self visibleGalleryFiles]) {
        if ([self.selectedFileIDs containsObject:file.identifier]) {
            [files addObject:file];
        }
    }
    return files;
}

- (void)enterSelectionMode {
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        self.preservingSearchQuery = YES;
        self.searchController.active = NO;
    }
    self.selectionMode = YES;
    [self.selectedFileIDs removeAllObjects];
    [self setupCenteredTitle];
    [self refreshNavigationItems];
    [self refreshBottomToolbarItems];
    [self animateSelectionModeTransition];
    // Folder chips hide during selection; reflect the header change.
    [self.collectionView.collectionViewLayout invalidateLayout];
}

- (void)exitSelectionMode {
    self.selectionMode = NO;
    [self.selectedFileIDs removeAllObjects];
    
    if (self.searchQuery.length > 0) {
        self.searchQuery = nil;
        self.searchController.searchBar.text = nil;
        [self refetch];
    }

    [self setupCenteredTitle];
    [self refreshNavigationItems];
    [self refreshBottomToolbarItems];
    [self animateSelectionModeTransition];
    // Folder chips return after leaving selection mode.
    [self.collectionView.collectionViewLayout invalidateLayout];
}

- (void)toggleSelectionForFile:(SCIGalleryFile *)file {
    if (file.identifier.length == 0) {
        return;
    }
    BOOL nowSelected;
    if ([self.selectedFileIDs containsObject:file.identifier]) {
        [self.selectedFileIDs removeObject:file.identifier];
        nowSelected = NO;
    } else {
        [self.selectedFileIDs addObject:file.identifier];
        nowSelected = YES;
    }
    [self setupCenteredTitle];
    [self refreshNavigationItems];
    // Update just the tapped cell's selection badge. A full reloadData here
    // reconfigures every visible cell, which re-toggles their gradient scrims and
    // makes them flash.
    [self updateSelectionBadgeForFile:file selected:nowSelected];
}

- (void)updateSelectionBadgeForFile:(SCIGalleryFile *)file selected:(BOOL)selected {
    for (NSIndexPath *indexPath in self.collectionView.indexPathsForVisibleItems) {
        SCIGalleryFile *visibleFile = [self galleryFileForCollectionIndexPath:indexPath];
        if (![visibleFile.identifier isEqualToString:file.identifier]) {
            continue;
        }
        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
        if ([cell isKindOfClass:[SCIGalleryGridCell class]]) {
            [(SCIGalleryGridCell *)cell setSelectionMode:self.selectionMode selected:selected animated:YES];
        } else if ([cell isKindOfClass:[SCIGalleryListCollectionCell class]]) {
            [(SCIGalleryListCollectionCell *)cell setSelectionMode:self.selectionMode selected:selected animated:YES];
        }
        break;
    }
}

- (void)selectAllVisibleFiles {
    NSArray<SCIGalleryFile *> *files = [self visibleGalleryFiles];
    if (files.count > 0 && self.selectedFileIDs.count == files.count) {
        [self.selectedFileIDs removeAllObjects];
    } else {
        [self.selectedFileIDs removeAllObjects];
        for (SCIGalleryFile *file in files) {
            if (file.identifier.length > 0) {
                [self.selectedFileIDs addObject:file.identifier];
            }
        }
    }
    [self setupCenteredTitle];
    [self refreshNavigationItems];
    [self.collectionView reloadData];
}

- (void)activateSearch {
    CGFloat revealOffsetY = -self.collectionView.adjustedContentInset.top;
    if (self.collectionView.contentOffset.y > revealOffsetY) {
        [self.collectionView setContentOffset:CGPointMake(self.collectionView.contentOffset.x, revealOffsetY) animated:NO];
        [self.collectionView layoutIfNeeded];
        [self.navigationController.navigationBar layoutIfNeeded];
    }
    self.searchController.active = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.searchController.searchBar becomeFirstResponder];
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    if (self.preservingSearchQuery) {
        return;
    }
    NSString *nextQuery = searchController.searchBar.text ?: @"";
    if ((self.searchQuery ?: @"").length == nextQuery.length && [(self.searchQuery ?: @"") isEqualToString:nextQuery]) {
        return;
    }
    self.searchQuery = nextQuery;
    [self refetch];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    BOOL allFolders = (selectedScope == 1);
    if (allFolders == self.searchAllFolders) {
        return;
    }
    self.searchAllFolders = allFolders;
    [self refetch];
}

- (void)willDismissSearchController:(UISearchController *)searchController {
    if (self.selectionMode) {
        self.preservingSearchQuery = YES;
    }
}

- (void)didDismissSearchController:(UISearchController *)searchController {
    self.preservingSearchQuery = NO;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    if (self.selectionMode) {
        [self.searchController setActive:NO];
    } else {
        [searchBar resignFirstResponder];
    }
}

- (void)shareSelectedFiles {
    NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) {
        return;
    }

    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:files.count];
    for (SCIGalleryFile *file in files) {
        [urls addObject:file.fileURL];
    }

    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)moveSelectedFiles {
    NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) {
        return;
    }
    [self presentMoveSheetForFiles:files];
}

- (void)toggleFavoriteForSelectedFiles {
    NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) {
        return;
    }

    BOOL shouldFavorite = NO;
    for (SCIGalleryFile *file in files) {
        if (!file.isFavorite) {
            shouldFavorite = YES;
            break;
        }
    }

    for (SCIGalleryFile *file in files) {
        file.isFavorite = shouldFavorite;
    }
    [[SCIGalleryCoreDataStack shared] saveContext];
    [self refetch];
}

- (void)deleteSelectedFiles {
    NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) {
        return;
    }

    NSString *message = [NSString stringWithFormat:@"This will permanently remove %ld file%@ from the gallery.", (long)files.count, files.count == 1 ? @"" : @"s"];
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Delete Selected Files?"
                                                message:message
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Delete" style:SCIIGAlertActionStyleDestructive handler:^{
        NSError *firstError = nil;
        for (SCIGalleryFile *file in files) {
            NSError *removeError = nil;
            [file removeWithError:&removeError];
            if (!firstError && removeError) {
                firstError = removeError;
            }
        }
        if (firstError) {
            SCINotify(kSCINotificationGalleryDeleteSelected, @"Failed to delete", firstError.localizedDescription, @"error_filled", SCINotificationToneError);
            return;
        }
        SCINotify(kSCINotificationGalleryDeleteSelected, @"Deleted selected files", nil, @"circle_check_filled", SCINotificationToneSuccess);
        [self pruneStaleUsernameFilters];
        [self exitSelectionMode];
    }],
    ]];
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv
    contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath
                                         point:(CGPoint)point {
    if (self.selectionMode) {
        return nil;
    }
    if ([self isFolderIndexPath:indexPath]) {
        NSString *folder = self.subfolders[indexPath.item];
        return [self contextMenuForFolder:folder];
    }

    NSIndexPath *filePath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    SCIGalleryFile *file = [self.fetchedResultsController objectAtIndexPath:filePath];
    return [self contextMenuForFile:file];
}

- (UIMenu *)fileActionsMenuForFile:(SCIGalleryFile *)file {
    __weak typeof(self) weakSelf = self;

    NSString *favTitle = file.isFavorite ? @"Unfavorite" : @"Favorite";
    UIImage *favImg = file.isFavorite
        ? SCIGalleryMenuActionIcon(@"heart_filled")
        : SCIGalleryMenuActionIcon(@"heart");

    UIAction *favoriteAction = [UIAction actionWithTitle:favTitle
                                                   image:favImg
                                              identifier:nil
                                                 handler:^(UIAction *a) {
        file.isFavorite = !file.isFavorite;
        [[SCIGalleryCoreDataStack shared] saveContext];
        // Re-sort/reload so the item visibly moves (e.g. up to the top when
        // "favorites at top" is on) and its badge updates — the FRC's implicit
        // re-sort on an in-place property change isn't reliable. Matches the bulk
        // favorite path.
        [weakSelf refetch];
    }];

     UIImage *editImg = SCIGalleryMenuActionIcon(@"edit");
    UIAction *renameAction = [UIAction actionWithTitle:@"Edit Details"
                                                 image:editImg
                                            identifier:nil
                                               handler:^(UIAction *a) { [weakSelf editDetailsForFile:file]; }];

     UIImage *moveImg = SCIGalleryMenuActionIcon(@"folder_move");
    UIAction *moveAction = [UIAction actionWithTitle:@"Move to Folder"
                                               image:moveImg
                                          identifier:nil
                                             handler:^(UIAction *a) { [weakSelf moveFile:file]; }];

    UIAction *trimAction = nil;
    if (file.mediaType == SCIGalleryMediaTypeVideo) {
        trimAction = [UIAction actionWithTitle:@"Trim"
                                         image:SCIGalleryMenuActionIcon(@"trim")
                                    identifier:nil
                                       handler:^(__unused UIAction *a) { [weakSelf trimFile:file]; }];
    }

     UIImage *shareImg = SCIGalleryMenuActionIcon(@"share");
    UIAction *shareAction = [UIAction actionWithTitle:@"Share"
                                                image:shareImg
                                           identifier:nil
                                              handler:^(UIAction *a) {
        NSURL *url = [file fileURL];
        UIActivityViewController *acVC = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        [weakSelf presentViewController:acVC animated:YES completion:nil];
    }];

    UIAction *openOriginalAction = nil;
    if (file.hasOpenableOriginalMedia) {
        openOriginalAction = [UIAction actionWithTitle:[file openOriginalActionTitle]
                                                 image:SCIGalleryMenuActionIcon(@"external_link")
                                            identifier:nil
                                               handler:^(__unused UIAction *a) {
            [weakSelf openOriginalPostForFile:file];
        }];
    }

    UIAction *openProfileAction = nil;
    if (file.hasOpenableProfile) {
        openProfileAction = [UIAction actionWithTitle:@"Open Profile"
                                                image:SCIGalleryMenuActionIcon(@"user_circle")
                                           identifier:nil
                                              handler:^(__unused UIAction *a) {
            [weakSelf openProfileForFile:file];
        }];
    }

    UIImage *deleteImg = SCIGalleryMenuActionIcon(@"trash");
    UIAction *deleteAction = [UIAction actionWithTitle:@"Delete"
                                                 image:deleteImg
                                            identifier:nil
                                               handler:^(UIAction *a) {
        [SCIIGAlertPresenter presentAlertFromViewController:weakSelf
                                                      title:@"Delete from Gallery"
                                                    message:@"This will permanently remove this file from the gallery."
                                                    actions:@[
            [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
            [SCIIGAlertAction actionWithTitle:@"Delete" style:SCIIGAlertActionStyleDestructive handler:^{
            NSError *err;
            [file removeWithError:&err];
            if (err) {
                SCINotify(kSCINotificationGalleryDeleteFile, @"Failed to delete", err.localizedDescription, @"error_filled", SCINotificationToneError);
            } else {
                SCINotify(kSCINotificationGalleryDeleteFile, @"Deleted from Gallery", nil, @"circle_check_filled", SCINotificationToneSuccess);
            }
        }],
        ]];
    }];
    /// TODO: investigate whether native UIMenu destructive tint can be customized. UIMenuElement exposes no supported color API.
    deleteAction.attributes = UIMenuElementAttributesDestructive;

    UIAction *usernameAction = nil;
    if (file.sourceUsername.length > 0) {
        NSString *username = [file.sourceUsername copy];
        BOOL isCurrentUsernameFilter = [self usernameFilterContainsUsername:username];
        usernameAction = [UIAction actionWithTitle:[NSString stringWithFormat:@"%@ %@", (isCurrentUsernameFilter ? @"Undo View All from" : @"View All from"), username]
                                             image:SCIGalleryMenuActionIcon(@"mention")
                                        identifier:nil
                                           handler:^(__unused UIAction *a) {
            [weakSelf toggleUsernameFilter:username];
        }];
    }

    // Grouped into inline sections so related actions read together and the
    // destructive delete is isolated at the bottom: open/navigate · edit · share ·
    // delete.
    NSMutableArray<UIMenuElement *> *openSection = [NSMutableArray array];
    if (openOriginalAction) [openSection addObject:openOriginalAction];
    if (openProfileAction) [openSection addObject:openProfileAction];
    if (usernameAction) [openSection addObject:usernameAction];

    NSMutableArray<UIMenuElement *> *editSection = [NSMutableArray arrayWithObject:favoriteAction];
    [editSection addObject:renameAction];
    [editSection addObject:moveAction];
    if (trimAction) [editSection addObject:trimAction];

    NSMutableArray<UIMenu *> *sections = [NSMutableArray array];
    if (openSection.count > 0) {
        [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:openSection]];
    }
    [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:editSection]];
    [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[shareAction]]];
    [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[deleteAction]]];
    return [UIMenu menuWithTitle:@"" children:sections];
}

- (UIContextMenuConfiguration *)contextMenuForFile:(SCIGalleryFile *)file {
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        return strongSelf ? [strongSelf fileActionsMenuForFile:file] : nil;
    }];
}

- (UIContextMenuConfiguration *)contextMenuForFolder:(NSString *)folderPath {
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        return [weakSelf folderActionsMenuForFolderPath:folderPath];
    }];
}

- (UIMenu *)folderActionsMenuForFolderPath:(NSString *)folderPath {
    __weak typeof(self) weakSelf = self;
    UIImage *folderRenameImg = SCIGalleryMenuActionIcon(@"edit");
    UIAction *renameAction = [UIAction actionWithTitle:@"Rename Folder"
                                                 image:folderRenameImg
                                            identifier:nil
                                               handler:^(UIAction *a) { [weakSelf renameFolder:folderPath]; }];

    UIImage *folderDeleteImg = SCIGalleryMenuActionIcon(@"trash");
    UIAction *deleteAction = [UIAction actionWithTitle:@"Delete Folder"
                                                 image:folderDeleteImg
                                            identifier:nil
                                               handler:^(UIAction *a) { [weakSelf deleteFolder:folderPath]; }];
    /// TODO: investigate whether native UIMenu destructive tint can be customized. UIMenuElement exposes no supported color API.
    deleteAction.attributes = UIMenuElementAttributesDestructive;

    return [UIMenu menuWithTitle:@"" children:@[renameAction, deleteAction]];
}

#pragma mark - Folder CRUD

- (void)presentCreateFolder {
    [SCIIGAlertPresenter presentTextInputAlertFromViewController:self
                                                           title:@"New Folder"
                                                         message:@""
                                                     placeholder:@"Folder name"
                                                     initialText:nil
                                                 autocapitalized:YES
                                                    confirmTitle:@"Create"
                                                     cancelTitle:@"Cancel"
                                                    confirmStyle:SCIIGAlertActionStyleDefault
                                                    confirmBlock:^(NSString *text) {
                                                        NSString *name = [text stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                                        if (name.length == 0) return;
                                                        [self createFolderNamed:name];
                                                    }
                                                     cancelBlock:nil];
}

- (void)createFolderNamed:(NSString *)name {
    NSString *newPath = [self folderPathByAppendingComponent:name toBase:self.currentFolderPath];

    // Folders materialize when any file references them. To make empty folders
    // discoverable, we store a placeholder record in NSUserDefaults.
    NSString *key = @"gallery_folders";
    NSMutableArray<NSString *> *placeholders = [[[NSUserDefaults standardUserDefaults] arrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    if (![placeholders containsObject:newPath]) {
        [placeholders addObject:newPath];
        [[NSUserDefaults standardUserDefaults] setObject:placeholders forKey:key];
    }
    [self reloadSubfolders];
    [self.collectionView reloadData];
    [self updateEmptyState];
}

- (NSString *)folderPathByAppendingComponent:(NSString *)component toBase:(NSString *)base {
    NSString *sanitized = [component stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    if (base.length == 0) return [@"/" stringByAppendingString:sanitized];
    return [base stringByAppendingFormat:@"/%@", sanitized];
}

- (void)mergePlaceholderSubfolders {
    NSArray<NSString *> *placeholders = [[NSUserDefaults standardUserDefaults] arrayForKey:@"gallery_folders"] ?: @[];
    NSString *base = self.currentFolderPath ?: @"";
    NSString *prefix = base.length == 0 ? @"/" : [base stringByAppendingString:@"/"];

    NSMutableSet<NSString *> *merged = [NSMutableSet setWithArray:self.subfolders];
    for (NSString *p in placeholders) {
        if (![p hasPrefix:prefix]) continue;
        NSString *rest = [p substringFromIndex:prefix.length];
        if (rest.length == 0) continue;
        NSRange slash = [rest rangeOfString:@"/"];
        NSString *folderName = slash.location == NSNotFound ? rest : [rest substringToIndex:slash.location];
        [merged addObject:[prefix stringByAppendingString:folderName]];
    }
    self.subfolders = [[merged allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (void)renameFolder:(NSString *)folderPath {
    [SCIIGAlertPresenter presentTextInputAlertFromViewController:self
                                                           title:@"Rename Folder"
                                                         message:@"Enter a new name for this folder."
                                                     placeholder:nil
                                                     initialText:[folderPath lastPathComponent]
                                                autocapitalized:YES
                                                    confirmTitle:@"Rename"
                                                     cancelTitle:@"Cancel"
                                                    confirmStyle:SCIIGAlertActionStyleDefault
                                                    confirmBlock:^(NSString *text) {
        NSString *newName = [text stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newName.length == 0) return;
        [self performRenameOfFolder:folderPath toName:newName];
    }
                                                     cancelBlock:nil];
}

- (void)performRenameOfFolder:(NSString *)oldPath toName:(NSString *)newName {
    NSString *parent = [oldPath stringByDeletingLastPathComponent];
    if (![parent hasPrefix:@"/"]) parent = [@"/" stringByAppendingString:parent];
    NSString *newPath = [parent isEqualToString:@"/"]
        ? [@"/" stringByAppendingString:newName]
        : [parent stringByAppendingFormat:@"/%@", newName];

    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.predicate = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@",
                     oldPath, [oldPath stringByAppendingString:@"/"]];
    NSArray<SCIGalleryFile *> *files = [ctx executeFetchRequest:req error:nil];
    for (SCIGalleryFile *f in files) {
        NSString *current = f.folderPath ?: @"";
        if ([current isEqualToString:oldPath]) {
            f.folderPath = newPath;
        } else if ([current hasPrefix:[oldPath stringByAppendingString:@"/"]]) {
            NSString *suffix = [current substringFromIndex:oldPath.length];
            f.folderPath = [newPath stringByAppendingString:suffix];
        }
    }
    [ctx save:nil];

    // Update placeholders.
    NSString *key = @"gallery_folders";
    NSMutableArray<NSString *> *placeholders = [[[NSUserDefaults standardUserDefaults] arrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    NSMutableArray<NSString *> *updated = [NSMutableArray array];
    for (NSString *p in placeholders) {
        if ([p isEqualToString:oldPath]) {
            [updated addObject:newPath];
        } else if ([p hasPrefix:[oldPath stringByAppendingString:@"/"]]) {
            [updated addObject:[newPath stringByAppendingString:[p substringFromIndex:oldPath.length]]];
        } else {
            [updated addObject:p];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:updated forKey:key];

    [self reloadSubfolders];
    [self.collectionView reloadData];
}

- (void)deleteFolder:(NSString *)folderPath {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.predicate = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@",
                     folderPath, [folderPath stringByAppendingString:@"/"]];
    NSInteger count = [ctx countForFetchRequest:req error:nil];

    NSString *msg = count == 0
        ? @"This folder is empty."
        : [NSString stringWithFormat:@"This folder contains %ld file(s). They will be moved to the parent folder.", (long)count];

    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Delete Folder?"
                                                message:msg
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Delete" style:SCIIGAlertActionStyleDestructive handler:^{
        [self performDeleteFolder:folderPath];
    }],
    ]];
}

- (void)performDeleteFolder:(NSString *)folderPath {
    NSString *parent = [folderPath stringByDeletingLastPathComponent];
    if (parent.length == 0 || [parent isEqualToString:@"/"]) parent = nil; // move to root

    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.predicate = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@",
                     folderPath, [folderPath stringByAppendingString:@"/"]];
    NSArray<SCIGalleryFile *> *files = [ctx executeFetchRequest:req error:nil];
    for (SCIGalleryFile *f in files) {
        f.folderPath = parent;
    }
    [ctx save:nil];

    // Remove placeholders beneath the folder path.
    NSString *key = @"gallery_folders";
    NSMutableArray<NSString *> *placeholders = [[[NSUserDefaults standardUserDefaults] arrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    NSString *prefix = [folderPath stringByAppendingString:@"/"];
    [placeholders filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *p, NSDictionary *b) {
        return ![p isEqualToString:folderPath] && ![p hasPrefix:prefix];
    }]];
    [[NSUserDefaults standardUserDefaults] setObject:placeholders forKey:key];

    [self reloadSubfolders];
    [self.collectionView reloadData];
    [self updateEmptyState];
}

#pragma mark - File rename / move

- (void)editDetailsForFile:(SCIGalleryFile *)file {
    SCIGalleryFileDetailsViewController *vc = [[SCIGalleryFileDetailsViewController alloc] initWithFile:file];
    __weak typeof(self) weakSelf = self;
    vc.onSaved = ^{ [weakSelf refetch]; };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 16.0, *)) {
        nav.sheetPresentationController.detents = @[
            UISheetPresentationControllerDetent.mediumDetent,
            UISheetPresentationControllerDetent.largeDetent,
        ];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)trimFile:(SCIGalleryFile *)file {
    NSURL *url = [file fileURL];
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        SCINotify(@"sci.trim.gallery", @"Cannot trim", @"The original file is missing.", @"error_filled", SCINotificationToneError);
        return;
    }
    SCITrimConfiguration *config = [SCITrimConfiguration configurationWithVideoURL:url];
    __weak typeof(self) weakSelf = self;
    [SCITrimEditorViewController presentWithConfiguration:config
                                                    from:self
                                              completion:^(SCITrimResult *result) {
        if (!result) return; // Cancelled.
        [weakSelf saveTrimResult:result fromFile:file];
    }];
}

- (void)saveTrimResult:(SCITrimResult *)result fromFile:(SCIGalleryFile *)sourceFile {
    __weak typeof(self) weakSelf = self;
    [SCITrimSaveCoordinator saveResult:result
                            originFile:sourceFile
                        fallbackSource:(SCIGallerySource)sourceFile.source
                            folderPath:sourceFile.folderPath
                             presenter:self
                            completion:^(BOOL didChange) {
        if (didChange) {
            [weakSelf refetch];
        }
    }];
}

- (void)assignFolderPath:(nullable NSString *)folderPath toFiles:(NSArray<SCIGalleryFile *> *)files {
    for (SCIGalleryFile *file in files) {
        file.folderPath = folderPath;
    }
    [[SCIGalleryCoreDataStack shared] saveContext];
    [self refetch];
}

- (void)presentMoveSheetForFiles:(NSArray<SCIGalleryFile *> *)files {
    NSArray<NSString *> *allFolders = [self allFolderPaths];
    NSMutableArray<SCIIGAlertAction *> *actions = [NSMutableArray array];

    [actions addObject:[SCIIGAlertAction actionWithTitle:@"Root"
                                                   style:SCIIGAlertActionStyleDefault
                                                 handler:^{
        [self assignFolderPath:nil toFiles:files];
    }]];

    for (NSString *folder in allFolders) {
        [actions addObject:[SCIIGAlertAction actionWithTitle:folder
                                                       style:SCIIGAlertActionStyleDefault
                                                     handler:^{
            [self assignFolderPath:folder toFiles:files];
        }]];
    }

    [actions addObject:[SCIIGAlertAction actionWithTitle:@"New folder…"
                                                   style:SCIIGAlertActionStyleDefault
                                                 handler:^{
        [SCIIGAlertPresenter presentTextInputAlertFromViewController:self
                                                               title:@"New Folder"
                                                             message:@"Enter a new folder name, then move the selected files there."
                                                         placeholder:@"Folder name"
                                                         initialText:nil
                                                    autocapitalized:NO
                                                        confirmTitle:@"Create & Move"
                                                         cancelTitle:@"Cancel"
                                                        confirmStyle:SCIIGAlertActionStyleDefault
                                                        confirmBlock:^(NSString *text) {
            NSString *name = [text stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (name.length == 0) return;
            NSString *newPath = [self folderPathByAppendingComponent:name toBase:self.currentFolderPath];
            [self assignFolderPath:newPath toFiles:files];
        }
                                                         cancelBlock:nil];
    }]];

    [actions addObject:[SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil]];
    [SCIIGAlertPresenter presentActionSheetFromViewController:self
                                                        title:@"Move to Folder"
                                                      message:@"Choose where to move the selected file(s)."
                                                      actions:actions];
}

- (void)moveFile:(SCIGalleryFile *)file {
    [self presentMoveSheetForFiles:@[file]];
}

- (NSArray<NSString *> *)allFolderPaths {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.resultType = NSDictionaryResultType;
    req.propertiesToFetch = @[@"folderPath"];
    req.returnsDistinctResults = YES;
    req.predicate = [NSPredicate predicateWithFormat:@"folderPath != nil AND folderPath != ''"];
    NSArray<NSDictionary *> *results = [ctx executeFetchRequest:req error:nil];

    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (NSDictionary *d in results) {
        NSString *p = d[@"folderPath"];
        if (p.length > 0) [set addObject:p];
    }
    NSArray<NSString *> *placeholders = [[NSUserDefaults standardUserDefaults] arrayForKey:@"gallery_folders"] ?: @[];
    [set addObjectsFromArray:placeholders];

    return [[set allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (NSArray<NSString *> *)availableSourceUsernamesForCurrentFilterContext {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.resultType = NSDictionaryResultType;
    req.propertiesToFetch = @[@"sourceUsername"];
    req.returnsDistinctResults = YES;

    NSMutableArray<NSPredicate *> *predicates = [NSMutableArray array];
    NSPredicate *contextPredicate = [SCIGalleryFilterViewController predicateForTypes:self.filterTypes
                                                                             sources:self.filterSources
                                                                       favoritesOnly:self.filterFavoritesOnly
                                                                           usernames:[NSSet set]
                                                                          folderPath:self.currentFolderPath];
    if (contextPredicate) [predicates addObject:contextPredicate];
    NSPredicate *visibleSources = SCIGalleryVisibleSourcesPredicate();
    if (visibleSources) [predicates addObject:visibleSources];
    NSString *query = [self.searchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length > 0) {
        [predicates addObject:[NSPredicate predicateWithFormat:@"(sourceUsername CONTAINS[cd] %@) OR (customName CONTAINS[cd] %@) OR (relativePath CONTAINS[cd] %@)",
                               query, query, query]];
    }
    [predicates addObject:[NSPredicate predicateWithFormat:@"sourceUsername != nil AND sourceUsername != ''"]];
    req.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];

    NSArray<NSDictionary *> *results = [ctx executeFetchRequest:req error:nil];

    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (NSDictionary *row in results) {
        NSString *username = [row[@"sourceUsername"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (username.length > 0) [set addObject:username];
    }
    return [[set allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray<NSString *> *)usernamesForFilterDisplayFromUsernames:(NSArray<NSString *> *)usernames {
    return [usernames sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL aSelected = [self usernameFilterContainsUsername:a];
        BOOL bSelected = [self usernameFilterContainsUsername:b];
        if (aSelected && !bSelected) return NSOrderedAscending;
        if (!aSelected && bSelected) return NSOrderedDescending;
        return [a localizedCaseInsensitiveCompare:b];
    }];
}

- (NSString *)matchingSelectedUsernameForUsername:(NSString *)username {
    if (username.length == 0) return nil;
    for (NSString *selectedUsername in self.filterUsernames) {
        if ([selectedUsername caseInsensitiveCompare:username] == NSOrderedSame) return selectedUsername;
    }
    return nil;
}

- (BOOL)usernameFilterContainsUsername:(NSString *)username {
    return [self matchingSelectedUsernameForUsername:username].length > 0;
}

- (void)toggleUsernameFilter:(NSString *)username {
    NSString *existing = [self matchingSelectedUsernameForUsername:username];
    if (existing.length > 0) {
        [self.filterUsernames removeObject:existing];
    } else if (username.length > 0) {
        [self.filterUsernames addObject:username];
    }
    [self refetch];
}

/// Drops any active username filters that no longer have matching media (e.g. after
/// the last item from that user was deleted). Returns YES if the filter set changed.
///
/// Uses a per-username count fetch with `includesPendingChanges = YES` rather than the
/// store-only distinct fetch in `availableSourceUsernamesForCurrentFilterContext`. This
/// matters because the FRC fires `controllerDidChangeContent:` during `processPendingChanges`,
/// *before* the deletes are flushed to SQLite — a store-only (NSDictionaryResultType) fetch
/// would still see the just-deleted rows and never prune the filter.
- (BOOL)pruneStaleUsernameFilters {
    if (self.filterUsernames.count == 0) return NO;
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSMutableArray<NSString *> *stale = [NSMutableArray array];
    for (NSString *selected in self.filterUsernames) {
        if ([self countOfMediaForUsername:selected inContext:ctx] == 0) {
            [stale addObject:selected];
        }
    }
    if (stale.count == 0) return NO;
    for (NSString *username in stale) [self.filterUsernames removeObject:username];
    return YES;
}

/// Counts media for a username within the current (non-username) filter context, honoring
/// unsaved in-memory deletions so prune works mid-save from the FRC delegate.
- (NSUInteger)countOfMediaForUsername:(NSString *)username inContext:(NSManagedObjectContext *)ctx {
    if (username.length == 0) return 0;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.includesPendingChanges = YES;

    NSMutableArray<NSPredicate *> *predicates = [NSMutableArray array];
    [predicates addObject:[NSPredicate predicateWithFormat:@"sourceUsername ==[c] %@", username]];
    NSPredicate *contextPredicate = [SCIGalleryFilterViewController predicateForTypes:self.filterTypes
                                                                             sources:self.filterSources
                                                                       favoritesOnly:self.filterFavoritesOnly
                                                                           usernames:[NSSet set]
                                                                          folderPath:self.currentFolderPath];
    if (contextPredicate) [predicates addObject:contextPredicate];
    NSPredicate *visibleSources = SCIGalleryVisibleSourcesPredicate();
    if (visibleSources) [predicates addObject:visibleSources];
    req.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];

    NSUInteger count = [ctx countForFetchRequest:req error:nil];
    return count == NSNotFound ? 0 : count;
}


#pragma mark - Sort / Filter

- (void)configureGallerySheetForNavigation:(UINavigationController *)nav {
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = nav.sheetPresentationController;
    if (sheet) {
        sheet.detents = @[
            UISheetPresentationControllerDetent.mediumDetent,
            UISheetPresentationControllerDetent.largeDetent
        ];
        sheet.prefersGrabberVisible = YES;
    }
}

- (void)presentSort {
    SCIGallerySortViewController *vc = [[SCIGallerySortViewController alloc] init];
    vc.delegate = self;
    vc.currentSortMode = self.sortMode;
    vc.currentGroupByMediaType = self.sortGroupByMediaType;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self configureGallerySheetForNavigation:nav];

    UISheetPresentationController *sheet = nav.sheetPresentationController;
    if (sheet) {
        if (@available(iOS 16.0, *)) {
            CGFloat fitHeight = [self sheetFitHeightForContentHeight:[vc sciContentHeightForWidth:[self sheetContentWidth]]];
            UISheetPresentationControllerDetent *fit = [UISheetPresentationControllerDetent
                customDetentWithIdentifier:@"scinsta.gallery.sort.fit"
                                   resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                return MIN(context.maximumDetentValue, fitHeight);
            }];
            sheet.detents = @[fit];
            sheet.selectedDetentIdentifier = fit.identifier;
        } else {
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        }
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    }

    [self presentViewController:nav animated:YES completion:nil];
}

// Single fixed sheet height for the sort/filter sheets: the controller's content
// height plus the sheet nav bar and the device's bottom safe area. Computed once
// at present time so there's no layout-time detent invalidation (which deadlocks
// iOS 26 via an observation feedback loop).
- (CGFloat)sheetFitHeightForContentHeight:(CGFloat)contentHeight {
    CGFloat bottomSafe = self.view.window.safeAreaInsets.bottom;
    CGFloat navBar = 56.0; // grabber + nav bar in a sheet
    return navBar + contentHeight + bottomSafe + 8.0;
}

- (CGFloat)sheetContentWidth {
    return CGRectGetWidth(self.view.bounds);
}

- (void)presentFilter {
    SCIGalleryFilterViewController *vc = [[SCIGalleryFilterViewController alloc] init];
    vc.delegate = self;
    vc.filterTypes = self.filterTypes;
    vc.filterSources = self.filterSources;
    vc.filterFavoritesOnly = self.filterFavoritesOnly;
    vc.filterUsernames = [self.filterUsernames mutableCopy];
    NSArray<NSString *> *availableUsernames = [self availableSourceUsernamesForCurrentFilterContext];
    BOOL showsUsernameSection = availableUsernames.count > 1;
    vc.availableUsernames = showsUsernameSection ? [self usernamesForFilterDisplayFromUsernames:availableUsernames] : @[];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self configureGallerySheetForNavigation:nav];

    UISheetPresentationController *sheet = nav.sheetPresentationController;
    if (sheet) {
        if (@available(iOS 16.0, *)) {
            CGFloat fitHeight = [self sheetFitHeightForContentHeight:[vc sciContentHeightForWidth:[self sheetContentWidth]]];
            UISheetPresentationControllerDetent *fit = [UISheetPresentationControllerDetent
                customDetentWithIdentifier:@"scinsta.gallery.filter.fit"
                                   resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                return MIN(context.maximumDetentValue, fitHeight);
            }];
            sheet.detents = @[fit];
            sheet.selectedDetentIdentifier = fit.identifier;
        } else {
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        }
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    }

    [self presentViewController:nav animated:YES completion:nil];
}

- (void)sortController:(SCIGallerySortViewController *)controller didSelectSortMode:(SCIGallerySortMode)mode groupByMediaType:(BOOL)groupByMediaType {
    self.sortMode = mode;
    self.sortGroupByMediaType = groupByMediaType;
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kSortModeKey];
    [[NSUserDefaults standardUserDefaults] setBool:groupByMediaType forKey:kSortGroupByTypeKey];
    [self refetch];
}

- (void)filterController:(SCIGalleryFilterViewController *)controller
           didApplyTypes:(NSSet<NSNumber *> *)types
                 sources:(NSSet<NSNumber *> *)sources
           favoritesOnly:(BOOL)favoritesOnly
               usernames:(NSSet<NSString *> *)usernames {
    self.filterTypes = [types mutableCopy];
    self.filterSources = [sources mutableCopy];
    self.filterFavoritesOnly = favoritesOnly;
    self.filterUsernames = [usernames mutableCopy] ?: [NSMutableSet set];
    [self refetch];
}

- (void)filterControllerDidClear:(SCIGalleryFilterViewController *)controller {
    [self.filterTypes removeAllObjects];
    [self.filterSources removeAllObjects];
    self.filterFavoritesOnly = NO;
    [self.filterUsernames removeAllObjects];
    [self refetch];
}

- (void)handleGalleryPreferencesChanged:(NSNotification *)note {
    (void)note;
    [self refetch];
}

- (void)handleGridControlsPreferenceChanged:(NSNotification *)note {
    (void)note;
    [self refreshBottomToolbarItems];
    [self reconfigureVisibleGridCells];
    if ([self.collectionView.collectionViewLayout isKindOfClass:[UICollectionViewFlowLayout class]]) {
        UICollectionViewFlowLayout *flow = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
        BOOL pinned = SCIGalleryFolderBarPinned();
        if (flow.sectionHeadersPinToVisibleBounds != pinned) {
            flow.sectionHeadersPinToVisibleBounds = pinned;
            [flow invalidateLayout];
        }
    }
}

#pragma mark - Settings

- (void)pushSettings {
    SCIGallerySettingsViewController *vc = [[SCIGallerySettingsViewController alloc] init];
    vc.importDestinationFolderPath = self.currentFolderPath;
    [self.navigationController pushViewController:vc animated:YES];
}

@end

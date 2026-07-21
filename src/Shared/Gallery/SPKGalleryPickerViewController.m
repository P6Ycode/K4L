#import "SPKGalleryPickerViewController.h"

#import <CoreData/CoreData.h>

#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../UI/SPKMediaChrome.h"
#import "SPKGalleryCoreDataStack.h"
#import "SPKGalleryFile.h"
#import "SPKGalleryFilterViewController.h"
#import "SPKGalleryFolderChipBar.h"
#import "SPKGalleryGridCell.h"
#import "SPKGalleryGridDensity.h"
#import "SPKGalleryHiddenSources.h"
#import "SPKGalleryListCollectionCell.h"
#import "SPKGalleryLockViewController.h"
#import "SPKGalleryManager.h"
#import "SPKGallerySortViewController.h"

static NSString *const kSPKGalleryPickerListCellID = @"SPKGalleryPickerListCell";
static NSString *const kSPKGalleryPickerGridCellID = @"SPKGalleryPickerGridCell";
static NSString *const kSPKGalleryPickerFolderChipHeaderID = @"SPKGalleryPickerFolderChipHeader";
static NSString *const kSPKGalleryPickerViewModeKey = @"gallery_picker_view_mode"; // 0 = grid, 1 = list
static CGFloat const kSPKGalleryPickerGridSpacing = 2.0;

typedef NS_ENUM(NSInteger, SPKGalleryPickerViewMode) {
    SPKGalleryPickerViewModeGrid = 0,
    SPKGalleryPickerViewModeList = 1,
};

@interface SPKGalleryPickerViewController () <UICollectionViewDataSource,
                                              UICollectionViewDelegate,
                                              UICollectionViewDelegateFlowLayout,
                                              UIAdaptivePresentationControllerDelegate,
                                              UISearchResultsUpdating,
                                              SPKGallerySortViewControllerDelegate,
                                              SPKGalleryFilterViewControllerDelegate>
@property (nonatomic, copy, nullable) NSString *folderPath;
@property (nonatomic, copy) NSString *pickerTitle;
@property (nonatomic, strong, nullable) NSSet<NSNumber *> *allowedMediaTypes;
@property (nonatomic, assign) BOOL allowsMultipleSelection;
@property (nonatomic, copy) SPKGalleryPickerCompletion completion;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) NSArray<NSString *> *subfolders;
@property (nonatomic, strong) NSArray<SPKGalleryFile *> *files;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedIDs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SPKGalleryFile *> *selectedFilesByID;
@property (nonatomic, assign) SPKGalleryPickerViewMode viewMode;
@property (nonatomic, assign) NSInteger gridColumns;
@property (nonatomic, assign) SPKGallerySortMode sortMode;
@property (nonatomic, assign) BOOL sortGroupByMediaType;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterTypes;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterSources;
@property (nonatomic, assign) BOOL filterFavoritesOnly;
@property (nonatomic, strong) NSMutableSet<NSString *> *filterUsernames;
@property (nonatomic, strong) UIBarButtonItem *cachedSearchToolbarItem;
@end

@implementation SPKGalleryPickerViewController

+ (BOOL)hasSelectableFilesForAllowedMediaTypes:(NSSet<NSNumber *> *)allowedMediaTypes {
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    NSMutableArray *predicates = [NSMutableArray array];
    if (allowedMediaTypes.count > 0)
        [predicates addObject:[NSPredicate predicateWithFormat:@"mediaType IN %@", allowedMediaTypes.allObjects]];
    NSPredicate *visibleSources = SPKGalleryVisibleSourcesPredicate();
    if (visibleSources)
        [predicates addObject:visibleSources];
    request.predicate = predicates.count > 0 ? [NSCompoundPredicate andPredicateWithSubpredicates:predicates] : nil;
    request.fetchLimit = 50;
    request.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO] ];
    NSArray<SPKGalleryFile *> *files = [[SPKGalleryCoreDataStack shared].viewContext executeFetchRequest:request error:nil] ?: @[];
    for (SPKGalleryFile *file in files) {
        if ([file fileExists])
            return YES;
    }
    return NO;
}

+ (void)presentFromViewController:(UIViewController *)presenter
                            title:(NSString *)title
                allowedMediaTypes:(NSSet<NSNumber *> *)allowedMediaTypes
          allowsMultipleSelection:(BOOL)allowsMultipleSelection
                       completion:(SPKGalleryPickerCompletion)completion {
    if (!presenter || !completion)
        return;

    SPKGalleryManager *mgr = [SPKGalleryManager sharedManager];

    void (^presentPicker)(void) = ^{
        SPKGalleryPickerViewController *picker = [[self alloc] initWithTitle:title
                                                           allowedMediaTypes:allowedMediaTypes
                                                     allowsMultipleSelection:allowsMultipleSelection
                                                                  completion:completion];
        UINavigationController *nav = [[SPKChromeNavigationController alloc] initWithRootViewController:picker];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [presenter presentViewController:nav animated:YES completion:nil];
    };

    if (mgr.isLockEnabled && !mgr.isUnlocked) {
        [SPKGalleryLockViewController presentUnlockFromViewController:presenter
                                                           completion:^(BOOL success) {
                                                               if (!success)
                                                                   return;
                                                               presentPicker();
                                                           }];
    } else {
        presentPicker();
    }
}

- (instancetype)initWithTitle:(NSString *)title
            allowedMediaTypes:(NSSet<NSNumber *> *)allowedMediaTypes
      allowsMultipleSelection:(BOOL)allowsMultipleSelection
                   completion:(SPKGalleryPickerCompletion)completion {
    return [self initWithFolderPath:nil
                              title:title
                  allowedMediaTypes:allowedMediaTypes
            allowsMultipleSelection:allowsMultipleSelection
                         completion:completion];
}

- (instancetype)initWithFolderPath:(NSString *)folderPath
                             title:(NSString *)title
                 allowedMediaTypes:(NSSet<NSNumber *> *)allowedMediaTypes
           allowsMultipleSelection:(BOOL)allowsMultipleSelection
                        completion:(SPKGalleryPickerCompletion)completion {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _folderPath = [folderPath copy];
        _pickerTitle = [title.length > 0 ? title : @"Gallery" copy];
        _allowedMediaTypes = [allowedMediaTypes copy];
        _allowsMultipleSelection = allowsMultipleSelection;
        _completion = [completion copy];
        _searchQuery = @"";
        _subfolders = @[];
        _files = @[];
        _selectedIDs = [NSMutableArray array];
        _selectedFilesByID = [NSMutableDictionary dictionary];
        _viewMode = (SPKGalleryPickerViewMode)[[NSUserDefaults standardUserDefaults] integerForKey:kSPKGalleryPickerViewModeKey];
        _gridColumns = SPKGalleryGridColumns();
        _sortMode = SPKGallerySortModeDateAddedDesc;
        _sortGroupByMediaType = NO;
        _filterTypes = [NSMutableSet set];
        _filterSources = [NSMutableSet set];
        _filterFavoritesOnly = NO;
        _filterUsernames = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hiddenSourcesChanged:)
                                                 name:SPKGalleryHiddenSourcesDidChangeNotification
                                               object:nil];

    self.view.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
    self.title = self.folderPath.length > 0 ? self.folderPath.lastPathComponent : self.pickerTitle;

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[self makeLayout]];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:SPKGalleryListCollectionCell.class forCellWithReuseIdentifier:kSPKGalleryPickerListCellID];
    [self.collectionView registerClass:SPKGalleryGridCell.class forCellWithReuseIdentifier:kSPKGalleryPickerGridCellID];
    [self.collectionView registerClass:SPKGalleryFolderChipBar.class
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:kSPKGalleryPickerFolderChipHeaderID];
    [self.view addSubview:self.collectionView];

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleGridPinch:)];
    [self.collectionView addGestureRecognizer:pinch];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"No matching Gallery files";
    self.emptyLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    self.emptyLabel.numberOfLines = 0;
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                      constant:24.0],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                       constant:-24.0],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    BOOL isRoot = (self.navigationController.viewControllers.firstObject == self || self.folderPath.length == 0);
    if (isRoot) {
        UIBarButtonItem *cancelItem = SPKMediaChromeTopBarButtonItem(@"xmark", self, @selector(cancelTapped));
        cancelItem.accessibilityLabel = @"Cancel";
        self.navigationItem.leftBarButtonItem = cancelItem;
    }
    [self refreshNavigationRightItems];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Gallery";
    [self.searchController.searchBar setImage:[SPKAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                             forSearchBarIcon:UISearchBarIconSearch
                                        state:UIControlStateNormal];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    if (@available(iOS 26.0, *)) {
        @try {
            [self.navigationItem setValue:@(4) forKey:@"preferredSearchBarPlacement"];
            [self.searchController loadViewIfNeeded];
            UIBarButtonItem *vended = [self.navigationItem valueForKey:@"searchBarPlacementBarButtonItem"];
            if ([vended isKindOfClass:[UIBarButtonItem class]]) {
                self.cachedSearchToolbarItem = vended;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    self.definesPresentationContext = YES;

    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationController.presentationController.delegate = self;
    }

    [self reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)hiddenSourcesChanged:(NSNotification *)notification {
    (void)notification;
    [self reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        self.navigationController.navigationBar.prefersLargeTitles = NO;
        SPKApplyMediaChromeNavigationBar(self.navigationController.navigationBar);
    }
    self.navigationController.toolbarHidden = NO;
    [self refreshBottomToolbarItems];
    [self reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.navigationController.viewControllers.firstObject != self)
        return;
    if (self.isMovingFromParentViewController)
        return;
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed) {
        if ([SPKGalleryManager sharedManager].isLockEnabled) {
            [[SPKGalleryManager sharedManager] lockGallery];
        }
    }
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if ([SPKGalleryManager sharedManager].isLockEnabled) {
        [[SPKGalleryManager sharedManager] lockGallery];
    }
}

- (NSArray<NSNumber *> *)allowedMediaTypeValues {
    return self.allowedMediaTypes.count > 0 ? self.allowedMediaTypes.allObjects : @[];
}

- (NSPredicate *)filePredicateForFolderPath:(NSString *)folderPath includeDescendants:(BOOL)includeDescendants {
    NSMutableArray<NSPredicate *> *predicates = [NSMutableArray array];
    NSArray<NSNumber *> *allowed = [self allowedMediaTypeValues];
    if (allowed.count > 0) {
        [predicates addObject:[NSPredicate predicateWithFormat:@"mediaType IN %@", allowed]];
    }
    NSPredicate *visibleSources = SPKGalleryVisibleSourcesPredicate();
    if (visibleSources)
        [predicates addObject:visibleSources];

    if (folderPath.length > 0) {
        if (includeDescendants) {
            [predicates addObject:[NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@",
                                                                   folderPath,
                                                                   [folderPath stringByAppendingString:@"/"]]];
        } else {
            [predicates addObject:[NSPredicate predicateWithFormat:@"folderPath == %@", folderPath]];
        }
    } else if (!includeDescendants) {
        [predicates addObject:[NSPredicate predicateWithFormat:@"folderPath == nil OR folderPath == %@", @""]];
    }

    NSString *query = [self.searchQuery stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length > 0) {
        [predicates addObject:[NSPredicate predicateWithFormat:@"sourceUsername CONTAINS[cd] %@ OR customName CONTAINS[cd] %@ OR relativePath CONTAINS[cd] %@",
                                                               query, query, query]];
    }

    return predicates.count > 0 ? [NSCompoundPredicate andPredicateWithSubpredicates:predicates] : nil;
}

- (NSArray<SPKGalleryFile *> *)fetchFiles {
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    NSMutableArray<NSPredicate *> *predicates = [NSMutableArray array];

    NSPredicate *basePred = [self filePredicateForFolderPath:self.folderPath includeDescendants:NO];
    if (basePred) [predicates addObject:basePred];

    NSPredicate *filterPred = [SPKGalleryFilterViewController predicateForTypes:self.filterTypes
                                                                        sources:self.filterSources
                                                                  favoritesOnly:self.filterFavoritesOnly
                                                                      usernames:self.filterUsernames
                                                                     folderPath:self.folderPath
                                                                  scopeToFolder:NO];
    if (filterPred) [predicates addObject:filterPred];

    request.predicate = predicates.count > 0 ? [NSCompoundPredicate andPredicateWithSubpredicates:predicates] : nil;

    NSArray<NSSortDescriptor *> *sortDescriptors = [SPKGallerySortViewController sortDescriptorsForMode:self.sortMode groupByMediaType:self.sortGroupByMediaType];
    if (sortDescriptors.count > 0) {
        request.sortDescriptors = sortDescriptors;
    } else {
        request.sortDescriptors = @[
            [NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO],
            [NSSortDescriptor sortDescriptorWithKey:@"relativePath" ascending:YES selector:@selector(localizedStandardCompare:)]
        ];
    }

    NSArray<SPKGalleryFile *> *fetched = [[SPKGalleryCoreDataStack shared].viewContext executeFetchRequest:request error:nil] ?: @[];
    NSMutableArray<SPKGalleryFile *> *existing = [NSMutableArray arrayWithCapacity:fetched.count];
    for (SPKGalleryFile *file in fetched) {
        if ([file fileExists])
            [existing addObject:file];
    }
    return existing;
}

- (NSInteger)eligibleFileCountForFolderPath:(NSString *)folderPath {
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    request.predicate = [self filePredicateForFolderPath:folderPath includeDescendants:YES];
    return [[SPKGalleryCoreDataStack shared].viewContext countForFetchRequest:request error:nil];
}

- (NSArray<NSString *> *)fetchSubfolders {
    if (self.searchQuery.length > 0)
        return @[];

    NSManagedObjectContext *context = [SPKGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    request.resultType = NSDictionaryResultType;
    request.propertiesToFetch = @[ @"folderPath" ];
    request.returnsDistinctResults = YES;

    NSString *base = self.folderPath ?: @"";
    NSString *prefix = base.length == 0 ? @"/" : [base stringByAppendingString:@"/"];
    NSPredicate *folderPredicate = [NSPredicate predicateWithFormat:@"folderPath BEGINSWITH %@", prefix];
    NSPredicate *visibleSources = SPKGalleryVisibleSourcesPredicate();
    request.predicate = visibleSources
                            ? [NSCompoundPredicate andPredicateWithSubpredicates:@[ folderPredicate, visibleSources ]]
                            : folderPredicate;

    NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil] ?: @[];
    NSMutableSet<NSString *> *folders = [NSMutableSet set];
    for (NSDictionary *row in rows) {
        NSString *path = row[@"folderPath"];
        if (path.length <= prefix.length)
            continue;
        NSString *rest = [path substringFromIndex:prefix.length];
        NSRange slash = [rest rangeOfString:@"/"];
        NSString *folderName = slash.location == NSNotFound ? rest : [rest substringToIndex:slash.location];
        if (folderName.length == 0)
            continue;
        NSString *folderPath = [prefix stringByAppendingString:folderName];
        if ([self eligibleFileCountForFolderPath:folderPath] > 0) {
            [folders addObject:folderPath];
        }
    }
    return [[folders allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (void)reloadData {
    self.subfolders = [self fetchSubfolders];
    self.files = [self fetchFiles];
    [self.collectionView reloadData];
    [self updateEmptyState];
    [self updateDoneButton];
}

#pragma mark - View Mode & Density

- (UICollectionViewLayout *)makeLayout {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    if (self.viewMode == SPKGalleryPickerViewModeGrid) {
        layout.minimumLineSpacing = kSPKGalleryPickerGridSpacing;
        layout.minimumInteritemSpacing = kSPKGalleryPickerGridSpacing;
    } else {
        layout.minimumLineSpacing = 0.0;
        layout.minimumInteritemSpacing = 0.0;
    }
    return layout;
}

- (void)setGridColumns:(NSInteger)gridColumns {
    NSInteger clamped = MAX(kSPKGalleryGridColumnsMin, MIN(kSPKGalleryGridColumnsMax, gridColumns));
    if (clamped == _gridColumns)
        return;
    _gridColumns = clamped;
    SPKGalleryGridSetColumns(clamped);
}

- (UIBarButtonItem *)pickerBottomBarItemWithResource:(NSString *)resourceName accessibility:(NSString *)label action:(SEL)action {
    return SPKMediaChromeBottomBarButtonItem(resourceName, label, self, action);
}

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
        searchItem = [self pickerBottomBarItemWithResource:@"search" accessibility:@"Search" action:@selector(activateSearch)];
    }
    return searchItem;
}

- (void)activateSearch {
    if (!self.searchController.active) {
        self.searchController.active = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.searchController.searchBar becomeFirstResponder];
    });
}

- (void)refreshBottomToolbarItems {
    SPKMediaChromeConfigureBottomToolbar(self.navigationController.toolbar);

    NSString *toggleResource = self.viewMode == SPKGalleryPickerViewModeGrid ? @"list" : @"grid";
    NSString *toggleAX = self.viewMode == SPKGalleryPickerViewModeGrid ? @"List view" : @"Grid view";
    UIBarButtonItem *toggleItem = [self pickerBottomBarItemWithResource:toggleResource accessibility:toggleAX action:@selector(togglePickerViewMode)];

    UIBarButtonItem *sortItem = [self pickerBottomBarItemWithResource:@"sort" accessibility:@"Sort" action:@selector(presentSort)];
    UIBarButtonItem *filterItem = [self pickerBottomBarItemWithResource:@"filter" accessibility:@"Filter" action:@selector(presentFilter)];

    NSArray<UIBarButtonItem *> *primary = @[ toggleItem, sortItem, filterItem ];
    self.toolbarItems = SPKMediaChromeBottomToolbarItemsWithTrailingGroup(primary, @[ [self bottomToolbarSearchItem] ]);
}

- (void)refreshNavigationRightItems {
    if (self.allowsMultipleSelection) {
        UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithTitle:@"Add"
                                                                    style:UIBarButtonItemStyleDone
                                                                   target:self
                                                                   action:@selector(doneTapped)];
        addItem.enabled = self.selectedIDs.count > 0;
        self.navigationItem.rightBarButtonItems = @[ addItem ];
    } else {
        self.navigationItem.rightBarButtonItems = @[];
    }
}

- (void)togglePickerViewMode {
    self.viewMode = self.viewMode == SPKGalleryPickerViewModeGrid ? SPKGalleryPickerViewModeList : SPKGalleryPickerViewModeGrid;
    [[NSUserDefaults standardUserDefaults] setInteger:self.viewMode forKey:kSPKGalleryPickerViewModeKey];
    [self.collectionView setCollectionViewLayout:[self makeLayout] animated:NO];
    [self.collectionView reloadData];
    [self refreshBottomToolbarItems];
}

#pragma mark - Sort & Filter Presentation

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

- (CGFloat)sheetFitHeightForContentHeight:(CGFloat)contentHeight {
    CGFloat bottomSafe = self.view.window.safeAreaInsets.bottom;
    CGFloat navBar = 56.0;
    return navBar + contentHeight + bottomSafe + 8.0;
}

- (CGFloat)sheetContentWidth {
    return CGRectGetWidth(self.view.bounds);
}

- (void)presentSort {
    SPKGallerySortViewController *vc = [[SPKGallerySortViewController alloc] init];
    vc.delegate = self;
    vc.currentSortMode = self.sortMode;
    vc.currentGroupByMediaType = self.sortGroupByMediaType;
    UINavigationController *nav = [[SPKChromeNavigationController alloc] initWithRootViewController:vc];
    [self configureGallerySheetForNavigation:nav];

    UISheetPresentationController *sheet = nav.sheetPresentationController;
    if (sheet) {
        if (@available(iOS 16.0, *)) {
            CGFloat fitHeight = [self sheetFitHeightForContentHeight:[vc spkContentHeightForWidth:[self sheetContentWidth]]];
            UISheetPresentationControllerDetent *fit = [UISheetPresentationControllerDetent
                customDetentWithIdentifier:@"sparkle.picker.sort.fit"
                                  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                                      return MIN(context.maximumDetentValue, fitHeight);
                                  }];
            sheet.detents = @[ fit ];
            sheet.selectedDetentIdentifier = fit.identifier;
        } else {
            sheet.detents = @[ UISheetPresentationControllerDetent.mediumDetent ];
        }
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    }

    [self presentViewController:nav animated:YES completion:nil];
}

- (NSArray<NSString *> *)availableSourceUsernames {
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    req.resultType = NSDictionaryResultType;
    req.propertiesToFetch = @[ @"sourceUsername" ];
    req.returnsDistinctResults = YES;
    NSArray<NSDictionary *> *rows = [[SPKGalleryCoreDataStack shared].viewContext executeFetchRequest:req error:nil] ?: @[];
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (NSDictionary *row in rows) {
        NSString *u = row[@"sourceUsername"];
        if (u.length > 0) [set addObject:u];
    }
    return [[set allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (void)presentFilter {
    SPKGalleryFilterViewController *vc = [[SPKGalleryFilterViewController alloc] init];
    vc.delegate = self;
    vc.filterTypes = self.filterTypes;
    vc.filterSources = self.filterSources;
    vc.filterFavoritesOnly = self.filterFavoritesOnly;
    vc.filterUsernames = [self.filterUsernames mutableCopy];
    NSArray<NSString *> *available = [self availableSourceUsernames];
    vc.availableUsernames = available.count > 1 ? available : @[];
    UINavigationController *nav = [[SPKChromeNavigationController alloc] initWithRootViewController:vc];
    [self configureGallerySheetForNavigation:nav];

    UISheetPresentationController *sheet = nav.sheetPresentationController;
    if (sheet) {
        if (@available(iOS 16.0, *)) {
            CGFloat fitHeight = [self sheetFitHeightForContentHeight:[vc spkContentHeightForWidth:[self sheetContentWidth]]];
            UISheetPresentationControllerDetent *fit = [UISheetPresentationControllerDetent
                customDetentWithIdentifier:@"sparkle.picker.filter.fit"
                                  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                                      return MIN(context.maximumDetentValue, fitHeight);
                                  }];
            sheet.detents = @[ fit ];
            sheet.selectedDetentIdentifier = fit.identifier;
        } else {
            sheet.detents = @[ UISheetPresentationControllerDetent.mediumDetent ];
        }
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    }

    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Sort & Filter Delegates

- (void)sortController:(SPKGallerySortViewController *)controller didSelectSortMode:(SPKGallerySortMode)mode groupByMediaType:(BOOL)groupByMediaType {
    self.sortMode = mode;
    self.sortGroupByMediaType = groupByMediaType;
    [self reloadData];
}

- (void)filterController:(SPKGalleryFilterViewController *)controller
           didApplyTypes:(NSSet<NSNumber *> *)types
                 sources:(NSSet<NSNumber *> *)sources
           favoritesOnly:(BOOL)favoritesOnly
               usernames:(NSSet<NSString *> *)usernames {
    self.filterTypes = [types mutableCopy];
    self.filterSources = [sources mutableCopy];
    self.filterFavoritesOnly = favoritesOnly;
    self.filterUsernames = [usernames mutableCopy] ?: [NSMutableSet set];
    [self reloadData];
}

- (void)filterControllerDidClear:(SPKGalleryFilterViewController *)controller {
    [self.filterTypes removeAllObjects];
    [self.filterSources removeAllObjects];
    self.filterFavoritesOnly = NO;
    [self.filterUsernames removeAllObjects];
    [self reloadData];
}

- (void)handleGridPinch:(UIPinchGestureRecognizer *)pinch {
    if (self.viewMode != SPKGalleryPickerViewModeGrid)
        return;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSPKGalleryGridPinchDisabledKey])
        return;
    if (pinch.state != UIGestureRecognizerStateChanged)
        return;
    CGFloat threshold = 0.30;
    if (pinch.scale > 1.0 + threshold && self.gridColumns > kSPKGalleryGridColumnsMin) {
        self.gridColumns = SPKGalleryGridColumnsAdjacent(self.gridColumns, YES);
        [self.collectionView.collectionViewLayout invalidateLayout];
        pinch.scale = 1.0;
    } else if (pinch.scale < 1.0 - threshold && self.gridColumns < kSPKGalleryGridColumnsMax) {
        self.gridColumns = SPKGalleryGridColumnsAdjacent(self.gridColumns, NO);
        [self.collectionView.collectionViewLayout invalidateLayout];
        pinch.scale = 1.0;
    }
}

- (void)updateEmptyState {
    BOOL empty = self.subfolders.count == 0 && self.files.count == 0;
    self.emptyLabel.hidden = !empty;
    self.collectionView.hidden = empty;
}

- (void)updateDoneButton {
    if (!self.allowsMultipleSelection)
        return;
    [self refreshNavigationRightItems];
}

- (BOOL)showsFolderChips {
    return self.subfolders.count > 0 && self.searchQuery.length == 0;
}

- (void)cancelTapped {
    [self dismissPickerWithCompletion:nil];
}

- (void)doneTapped {
    NSMutableArray<SPKGalleryFile *> *files = [NSMutableArray arrayWithCapacity:self.selectedIDs.count];
    for (NSString *identifier in self.selectedIDs) {
        SPKGalleryFile *file = self.selectedFilesByID[identifier];
        if (file)
            [files addObject:file];
    }
    SPKGalleryPickerCompletion completion = [self.completion copy];
    [self dismissPickerWithCompletion:^{
        if (completion)
            completion(files);
    }];
}

- (void)dismissPickerWithCompletion:(void (^)(void))completion {
    UIViewController *controller = self.navigationController ?: self;
    [controller dismissViewControllerAnimated:YES completion:completion];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.files.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SPKGalleryFile *file = self.files[indexPath.item];
    if (self.viewMode == SPKGalleryPickerViewModeGrid) {
        SPKGalleryGridCell *gridCell = [collectionView dequeueReusableCellWithReuseIdentifier:kSPKGalleryPickerGridCellID forIndexPath:indexPath];
        BOOL showsMeta = ![[NSUserDefaults standardUserDefaults] boolForKey:kSPKGalleryGridShowSourceUsernameDisabledKey];
        BOOL showsUsername = showsMeta && self.gridColumns <= 3;
        [gridCell configureWithGalleryFile:file
                             selectionMode:self.allowsMultipleSelection
                                  selected:[self.selectedIDs containsObject:file.identifier]
                               showsSource:showsMeta
                             showsUsername:showsUsername];
        return gridCell;
    }

    SPKGalleryListCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kSPKGalleryPickerListCellID forIndexPath:indexPath];
    [cell configureWithGalleryFile:file
                     selectionMode:self.allowsMultipleSelection
                          selected:[self.selectedIDs containsObject:file.identifier]];
    [cell setMoreActionsMenu:nil];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if (![kind isEqualToString:UICollectionElementKindSectionHeader]) {
        return [[UICollectionReusableView alloc] init];
    }
    SPKGalleryFolderChipBar *header =
        [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                           withReuseIdentifier:kSPKGalleryPickerFolderChipHeaderID
                                                  forIndexPath:indexPath];
    if (![self showsFolderChips]) {
        return header;
    }

    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:self.subfolders.count];
    NSMutableArray<NSNumber *> *counts = [NSMutableArray arrayWithCapacity:self.subfolders.count];
    for (NSString *path in self.subfolders) {
        [names addObject:path.lastPathComponent];
        [counts addObject:@([self eligibleFileCountForFolderPath:path])];
    }

    __weak typeof(self) weakSelf = self;
    [header configureWithFolderNames:names
                              counts:counts
                            onSelect:^(NSInteger index) {
                                [weakSelf openSubfolderAtIndex:index];
                            }
                        menuProvider:nil];
    return header;
}

- (void)openSubfolderAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.subfolders.count)
        return;
    NSString *folder = self.subfolders[index];
    SPKGalleryPickerViewController *child = [[SPKGalleryPickerViewController alloc] initWithFolderPath:folder
                                                                                                 title:self.pickerTitle
                                                                                     allowedMediaTypes:self.allowedMediaTypes
                                                                               allowsMultipleSelection:self.allowsMultipleSelection
                                                                                            completion:self.completion];
    child.selectedIDs = self.selectedIDs;
    child.selectedFilesByID = self.selectedFilesByID;
    [self.navigationController pushViewController:child animated:YES];
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)layout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = collectionView.bounds.size.width;
    if (self.viewMode == SPKGalleryPickerViewModeGrid) {
        NSInteger columns = MAX(kSPKGalleryGridColumnsMin, MIN(kSPKGalleryGridColumnsMax, self.gridColumns));
        CGFloat totalSpacing = kSPKGalleryPickerGridSpacing * (columns - 1);
        CGFloat side = floor((width - totalSpacing) / columns);
        return CGSizeMake(side, side);
    }
    return CGSizeMake(width, 72.0);
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                             layout:(UICollectionViewLayout *)layout
    referenceSizeForHeaderInSection:(NSInteger)section {
    if (section == 0 && [self showsFolderChips]) {
        return CGSizeMake(collectionView.bounds.size.width, [SPKGalleryFolderChipBar preferredHeight]);
    }
    return CGSizeZero;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    SPKGalleryFile *file = self.files[indexPath.item];
    if (self.allowsMultipleSelection) {
        if ([self.selectedIDs containsObject:file.identifier]) {
            [self.selectedIDs removeObject:file.identifier];
            [self.selectedFilesByID removeObjectForKey:file.identifier];
        } else {
            [self.selectedIDs addObject:file.identifier];
            self.selectedFilesByID[file.identifier] = file;
        }
        [self.collectionView reloadItemsAtIndexPaths:@[ indexPath ]];
        [self updateDoneButton];
        return;
    }

    SPKGalleryPickerCompletion completion = [self.completion copy];
    [self dismissPickerWithCompletion:^{
        if (completion)
            completion(@[ file ]);
    }];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self reloadData];
}

@end

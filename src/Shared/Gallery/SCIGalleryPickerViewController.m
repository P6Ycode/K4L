#import "SCIGalleryPickerViewController.h"

#import <CoreData/CoreData.h>

#import "SCIGalleryCoreDataStack.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryGridCell.h"
#import "SCIGalleryListCollectionCell.h"
#import "SCIGalleryFolderChipBar.h"
#import "SCIGalleryGridDensity.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"

static NSString * const kSCIGalleryPickerListCellID = @"SCIGalleryPickerListCell";
static NSString * const kSCIGalleryPickerGridCellID = @"SCIGalleryPickerGridCell";
static NSString * const kSCIGalleryPickerFolderChipHeaderID = @"SCIGalleryPickerFolderChipHeader";
static NSString * const kSCIGalleryPickerViewModeKey = @"gallery_picker_view_mode"; // 0 = grid, 1 = list
static CGFloat const kSCIGalleryPickerGridSpacing = 2.0;

typedef NS_ENUM(NSInteger, SCIGalleryPickerViewMode) {
    SCIGalleryPickerViewModeGrid = 0,
    SCIGalleryPickerViewModeList = 1,
};

@interface SCIGalleryPickerViewController () <UICollectionViewDataSource,
                                             UICollectionViewDelegate,
                                             UICollectionViewDelegateFlowLayout,
                                             UISearchResultsUpdating>
@property (nonatomic, copy, nullable) NSString *folderPath;
@property (nonatomic, copy) NSString *pickerTitle;
@property (nonatomic, strong, nullable) NSSet<NSNumber *> *allowedMediaTypes;
@property (nonatomic, assign) BOOL allowsMultipleSelection;
@property (nonatomic, copy) SCIGalleryPickerCompletion completion;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) NSArray<NSString *> *subfolders;
@property (nonatomic, strong) NSArray<SCIGalleryFile *> *files;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedIDs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCIGalleryFile *> *selectedFilesByID;
@property (nonatomic, assign) SCIGalleryPickerViewMode viewMode;
@property (nonatomic, assign) NSInteger gridColumns;
@end

@implementation SCIGalleryPickerViewController

+ (BOOL)hasSelectableFilesForAllowedMediaTypes:(NSSet<NSNumber *> *)allowedMediaTypes {
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    if (allowedMediaTypes.count > 0) {
        request.predicate = [NSPredicate predicateWithFormat:@"mediaType IN %@", allowedMediaTypes.allObjects];
    }
    request.fetchLimit = 50;
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO]];
    NSArray<SCIGalleryFile *> *files = [[SCIGalleryCoreDataStack shared].viewContext executeFetchRequest:request error:nil] ?: @[];
    for (SCIGalleryFile *file in files) {
        if ([file fileExists]) return YES;
    }
    return NO;
}

+ (void)presentFromViewController:(UIViewController *)presenter
                            title:(NSString *)title
                allowedMediaTypes:(NSSet<NSNumber *> *)allowedMediaTypes
          allowsMultipleSelection:(BOOL)allowsMultipleSelection
                       completion:(SCIGalleryPickerCompletion)completion {
    if (!presenter || !completion) return;
    SCIGalleryPickerViewController *picker = [[self alloc] initWithTitle:title
                                                       allowedMediaTypes:allowedMediaTypes
                                                 allowsMultipleSelection:allowsMultipleSelection
                                                              completion:completion];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:nav animated:YES completion:nil];
}

- (instancetype)initWithTitle:(NSString *)title
            allowedMediaTypes:(NSSet<NSNumber *> *)allowedMediaTypes
      allowsMultipleSelection:(BOOL)allowsMultipleSelection
                   completion:(SCIGalleryPickerCompletion)completion {
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
                         completion:(SCIGalleryPickerCompletion)completion {
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
        _viewMode = (SCIGalleryPickerViewMode)[[NSUserDefaults standardUserDefaults] integerForKey:kSCIGalleryPickerViewModeKey];
        _gridColumns = SCIGalleryGridColumns();
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Match the real gallery: use the Instagram palette (dynamic colors that
    // adapt to light/dark) rather than a plain system background or a forced
    // appearance style.
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.title = self.folderPath.length > 0 ? self.folderPath.lastPathComponent : self.pickerTitle;

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[self makeLayout]];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:SCIGalleryListCollectionCell.class forCellWithReuseIdentifier:kSCIGalleryPickerListCellID];
    [self.collectionView registerClass:SCIGalleryGridCell.class forCellWithReuseIdentifier:kSCIGalleryPickerGridCellID];
    [self.collectionView registerClass:SCIGalleryFolderChipBar.class
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:kSCIGalleryPickerFolderChipHeaderID];
    [self.view addSubview:self.collectionView];

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleGridPinch:)];
    [self.collectionView addGestureRecognizer:pinch];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"No matching Gallery files";
    self.emptyLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    self.emptyLabel.numberOfLines = 0;
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24.0],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    // Only the root picker shows "Cancel"; pushed folder screens keep the system
    // back button (and its swipe-to-go-back gesture).
    BOOL isRoot = (self.navigationController.viewControllers.firstObject == self || self.folderPath.length == 0);
    if (isRoot) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                                 style:UIBarButtonItemStylePlain
                                                                                target:self
                                                                                action:@selector(cancelTapped)];
    }
    [self refreshNavigationRightItems];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Gallery";
    [self.searchController.searchBar setImage:[SCIAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                             forSearchBarIcon:UISearchBarIconSearch
                                        state:UIControlStateNormal];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;

    [self reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadData];
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

- (NSArray<SCIGalleryFile *> *)fetchFiles {
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    request.predicate = [self filePredicateForFolderPath:self.folderPath includeDescendants:NO];
    request.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"relativePath" ascending:YES selector:@selector(localizedStandardCompare:)]
    ];
    NSArray<SCIGalleryFile *> *fetched = [[SCIGalleryCoreDataStack shared].viewContext executeFetchRequest:request error:nil] ?: @[];
    NSMutableArray<SCIGalleryFile *> *existing = [NSMutableArray arrayWithCapacity:fetched.count];
    for (SCIGalleryFile *file in fetched) {
        if ([file fileExists]) [existing addObject:file];
    }
    return existing;
}

- (NSInteger)eligibleFileCountForFolderPath:(NSString *)folderPath {
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    request.predicate = [self filePredicateForFolderPath:folderPath includeDescendants:YES];
    return [[SCIGalleryCoreDataStack shared].viewContext countForFetchRequest:request error:nil];
}

- (NSArray<NSString *> *)fetchSubfolders {
    if (self.searchQuery.length > 0) return @[];

    NSManagedObjectContext *context = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    request.resultType = NSDictionaryResultType;
    request.propertiesToFetch = @[@"folderPath"];
    request.returnsDistinctResults = YES;

    NSString *base = self.folderPath ?: @"";
    NSString *prefix = base.length == 0 ? @"/" : [base stringByAppendingString:@"/"];
    request.predicate = [NSPredicate predicateWithFormat:@"folderPath BEGINSWITH %@", prefix];

    NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil] ?: @[];
    NSMutableSet<NSString *> *folders = [NSMutableSet set];
    for (NSDictionary *row in rows) {
        NSString *path = row[@"folderPath"];
        if (path.length <= prefix.length) continue;
        NSString *rest = [path substringFromIndex:prefix.length];
        NSRange slash = [rest rangeOfString:@"/"];
        NSString *folderName = slash.location == NSNotFound ? rest : [rest substringToIndex:slash.location];
        if (folderName.length == 0) continue;
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
    if (self.viewMode == SCIGalleryPickerViewModeGrid) {
        layout.minimumLineSpacing = kSCIGalleryPickerGridSpacing;
        layout.minimumInteritemSpacing = kSCIGalleryPickerGridSpacing;
    } else {
        layout.minimumLineSpacing = 0.0;
        layout.minimumInteritemSpacing = 0.0;
    }
    return layout;
}

- (void)setGridColumns:(NSInteger)gridColumns {
    NSInteger clamped = MAX(kSCIGalleryGridColumnsMin, MIN(kSCIGalleryGridColumnsMax, gridColumns));
    if (clamped == _gridColumns) return;
    _gridColumns = clamped;
    SCIGalleryGridSetColumns(clamped);
}

/// Trailing nav-bar items: the grid/list toggle, plus the "Add" confirm button
/// when multi-selecting.
- (void)refreshNavigationRightItems {
    NSString *toggleResource = self.viewMode == SCIGalleryPickerViewModeGrid ? @"list" : @"grid";
    NSString *toggleAX = self.viewMode == SCIGalleryPickerViewModeGrid ? @"List view" : @"Grid view";
    UIBarButtonItem *toggleItem = [[UIBarButtonItem alloc] initWithImage:[SCIAssetUtils instagramIconNamed:toggleResource pointSize:22.0]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(togglePickerViewMode)];
    toggleItem.accessibilityLabel = toggleAX;
    toggleItem.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];

    if (self.allowsMultipleSelection) {
        UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithTitle:@"Add"
                                                                    style:UIBarButtonItemStyleDone
                                                                   target:self
                                                                   action:@selector(doneTapped)];
        addItem.enabled = self.selectedIDs.count > 0;
        self.navigationItem.rightBarButtonItems = @[addItem, toggleItem];
    } else {
        self.navigationItem.rightBarButtonItems = @[toggleItem];
    }
}

- (void)togglePickerViewMode {
    self.viewMode = self.viewMode == SCIGalleryPickerViewModeGrid ? SCIGalleryPickerViewModeList : SCIGalleryPickerViewModeGrid;
    [[NSUserDefaults standardUserDefaults] setInteger:self.viewMode forKey:kSCIGalleryPickerViewModeKey];
    [self.collectionView setCollectionViewLayout:[self makeLayout] animated:NO];
    [self.collectionView reloadData];
    [self refreshNavigationRightItems];
}

- (void)handleGridPinch:(UIPinchGestureRecognizer *)pinch {
    if (self.viewMode != SCIGalleryPickerViewModeGrid) return;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSCIGalleryGridPinchDisabledKey]) return;
    if (pinch.state != UIGestureRecognizerStateChanged) return;
    CGFloat threshold = 0.30;
    if (pinch.scale > 1.0 + threshold && self.gridColumns > kSCIGalleryGridColumnsMin) {
        self.gridColumns = SCIGalleryGridColumnsAdjacent(self.gridColumns, YES);
        [self.collectionView.collectionViewLayout invalidateLayout];
        pinch.scale = 1.0;
    } else if (pinch.scale < 1.0 - threshold && self.gridColumns < kSCIGalleryGridColumnsMax) {
        self.gridColumns = SCIGalleryGridColumnsAdjacent(self.gridColumns, NO);
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
    if (!self.allowsMultipleSelection) return;
    [self refreshNavigationRightItems];
}

- (BOOL)showsFolderChips {
    return self.subfolders.count > 0 && self.searchQuery.length == 0;
}

- (void)cancelTapped {
    [self dismissPickerWithCompletion:nil];
}

- (void)doneTapped {
    NSMutableArray<SCIGalleryFile *> *files = [NSMutableArray arrayWithCapacity:self.selectedIDs.count];
    for (NSString *identifier in self.selectedIDs) {
        SCIGalleryFile *file = self.selectedFilesByID[identifier];
        if (file) [files addObject:file];
    }
    SCIGalleryPickerCompletion completion = [self.completion copy];
    [self dismissPickerWithCompletion:^{
        if (completion) completion(files);
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
    SCIGalleryFile *file = self.files[indexPath.item];
    if (self.viewMode == SCIGalleryPickerViewModeGrid) {
        SCIGalleryGridCell *gridCell = [collectionView dequeueReusableCellWithReuseIdentifier:kSCIGalleryPickerGridCellID forIndexPath:indexPath];
        BOOL showsMeta = ![[NSUserDefaults standardUserDefaults] boolForKey:kSCIGalleryGridShowSourceUsernameDisabledKey];
        BOOL showsUsername = showsMeta && self.gridColumns <= 3;
        [gridCell configureWithGalleryFile:file
                             selectionMode:self.allowsMultipleSelection
                                  selected:[self.selectedIDs containsObject:file.identifier]
                               showsSource:showsMeta
                             showsUsername:showsUsername];
        return gridCell;
    }

    SCIGalleryListCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kSCIGalleryPickerListCellID forIndexPath:indexPath];
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
    SCIGalleryFolderChipBar *header =
        [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                           withReuseIdentifier:kSCIGalleryPickerFolderChipHeaderID
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
    if (index < 0 || index >= (NSInteger)self.subfolders.count) return;
    NSString *folder = self.subfolders[index];
    SCIGalleryPickerViewController *child = [[SCIGalleryPickerViewController alloc] initWithFolderPath:folder
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
    if (self.viewMode == SCIGalleryPickerViewModeGrid) {
        NSInteger columns = MAX(kSCIGalleryGridColumnsMin, MIN(kSCIGalleryGridColumnsMax, self.gridColumns));
        CGFloat totalSpacing = kSCIGalleryPickerGridSpacing * (columns - 1);
        CGFloat side = floor((width - totalSpacing) / columns);
        return CGSizeMake(side, side);
    }
    return CGSizeMake(width, 88.0);
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
referenceSizeForHeaderInSection:(NSInteger)section {
    if (section == 0 && [self showsFolderChips]) {
        return CGSizeMake(collectionView.bounds.size.width, [SCIGalleryFolderChipBar preferredHeight]);
    }
    return CGSizeZero;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    SCIGalleryFile *file = self.files[indexPath.item];
    if (self.allowsMultipleSelection) {
        if ([self.selectedIDs containsObject:file.identifier]) {
            [self.selectedIDs removeObject:file.identifier];
            [self.selectedFilesByID removeObjectForKey:file.identifier];
        } else {
            [self.selectedIDs addObject:file.identifier];
            self.selectedFilesByID[file.identifier] = file;
        }
        [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
        [self updateDoneButton];
        return;
    }

    SCIGalleryPickerCompletion completion = [self.completion copy];
    [self dismissPickerWithCompletion:^{
        if (completion) completion(@[file]);
    }];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self reloadData];
}

@end

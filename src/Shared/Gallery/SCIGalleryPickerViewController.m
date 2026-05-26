#import "SCIGalleryPickerViewController.h"

#import <CoreData/CoreData.h>

#import "SCIGalleryCoreDataStack.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryFolderCell.h"
#import "SCIGalleryListCollectionCell.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"

static NSString * const kSCIGalleryPickerListCellID = @"SCIGalleryPickerListCell";
static NSString * const kSCIGalleryPickerFolderCellID = @"SCIGalleryPickerFolderCell";

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
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = self.folderPath.length > 0 ? self.folderPath.lastPathComponent : self.pickerTitle;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 0.0;
    layout.minimumInteritemSpacing = 0.0;
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:SCIGalleryListCollectionCell.class forCellWithReuseIdentifier:kSCIGalleryPickerListCellID];
    [self.collectionView registerClass:SCIGalleryFolderCell.class forCellWithReuseIdentifier:kSCIGalleryPickerFolderCellID];
    [self.view addSubview:self.collectionView];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"No matching Gallery files";
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
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

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(cancelTapped)];
    if (self.allowsMultipleSelection) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Add"
                                                                                  style:UIBarButtonItemStyleDone
                                                                                 target:self
                                                                                 action:@selector(doneTapped)];
        self.navigationItem.rightBarButtonItem.enabled = NO;
    }

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

- (void)updateEmptyState {
    BOOL empty = self.subfolders.count == 0 && self.files.count == 0;
    self.emptyLabel.hidden = !empty;
    self.collectionView.hidden = empty;
}

- (void)updateDoneButton {
    if (!self.allowsMultipleSelection) return;
    self.navigationItem.rightBarButtonItem.enabled = self.selectedIDs.count > 0;
}

- (BOOL)isFolderIndexPath:(NSIndexPath *)indexPath {
    return self.subfolders.count > 0 && indexPath.section == 0;
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
    return self.subfolders.count > 0 ? 2 : 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (self.subfolders.count > 0 && section == 0) return self.subfolders.count;
    return self.files.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isFolderIndexPath:indexPath]) {
        SCIGalleryFolderCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kSCIGalleryPickerFolderCellID forIndexPath:indexPath];
        NSString *folder = self.subfolders[indexPath.item];
        [cell configureWithFolderName:folder.lastPathComponent itemCount:[self eligibleFileCountForFolderPath:folder]];
        return cell;
    }

    SCIGalleryFile *file = self.files[indexPath.item];
    SCIGalleryListCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kSCIGalleryPickerListCellID forIndexPath:indexPath];
    [cell configureWithGalleryFile:file
                   selectionMode:self.allowsMultipleSelection
                        selected:[self.selectedIDs containsObject:file.identifier]];
    [cell setMoreActionsMenu:nil];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(collectionView.bounds.size.width, 88.0);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView
                        layout:(UICollectionViewLayout *)layout
        insetForSectionAtIndex:(NSInteger)section {
    if (self.subfolders.count > 0 && section == 0) {
        return UIEdgeInsetsMake(10.0, 0.0, 6.0, 0.0);
    }
    return UIEdgeInsetsZero;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    if ([self isFolderIndexPath:indexPath]) {
        NSString *folder = self.subfolders[indexPath.item];
        SCIGalleryPickerViewController *child = [[SCIGalleryPickerViewController alloc] initWithFolderPath:folder
                                                                                                    title:self.pickerTitle
                                                                                        allowedMediaTypes:self.allowedMediaTypes
                                                                                  allowsMultipleSelection:self.allowsMultipleSelection
                                                                                               completion:self.completion];
        child.selectedIDs = self.selectedIDs;
        child.selectedFilesByID = self.selectedFilesByID;
        [self.navigationController pushViewController:child animated:YES];
        return;
    }

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

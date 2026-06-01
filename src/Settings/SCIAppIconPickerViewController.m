#import "SCIAppIconPickerViewController.h"

#import "SCIAppIconCatalog.h"
#import "../AssetUtils.h"
#import "../Shared/UI/SCIIGAlertPresenter.h"
#import "../Shared/UI/SCINotificationCenter.h"
#import "../Utils.h"

static NSString * const kSCIAppIconPickerCellIdentifier = @"SCIAppIconPickerCell";
@interface SCIAppIconPickerCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *checkmarkView;
- (void)configureWithItem:(SCIAppIconItem *)item image:(UIImage *)image selected:(BOOL)selected;
@end

@implementation SCIAppIconPickerCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.contentView.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    self.contentView.layer.cornerRadius = 8.0;
    self.contentView.layer.borderWidth = 0.0;

    _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.clipsToBounds = YES;
    _iconView.layer.cornerRadius = 14.0;
    [self.contentView addSubview:_iconView];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    _titleLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.numberOfLines = 2;
    [self.contentView addSubview:_titleLabel];

    _checkmarkView = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"circle_check_filled" pointSize:20.0]];
    _checkmarkView.translatesAutoresizingMaskIntoConstraints = NO;
    _checkmarkView.tintColor = [SCIUtils SCIColor_Primary];
    _checkmarkView.hidden = YES;
    [self.contentView addSubview:_checkmarkView];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14.0],
        [_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:72.0],
        [_iconView.heightAnchor constraintEqualToConstant:72.0],

        [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:10.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
        [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],

        [_checkmarkView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
        [_checkmarkView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
        [_checkmarkView.widthAnchor constraintEqualToConstant:20.0],
        [_checkmarkView.heightAnchor constraintEqualToConstant:20.0]
    ]];

    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
    self.titleLabel.text = nil;
    [self configureSelected:NO];
}

- (void)configureSelected:(BOOL)selected {
    self.checkmarkView.hidden = !selected;
    if (selected) self.contentView.layer.borderColor = [SCIUtils SCIColor_Primary].CGColor;
    self.contentView.layer.borderWidth = selected ? 2.0 : 0.0;
    self.contentView.backgroundColor = selected
        ? [[SCIUtils SCIColor_Primary] colorWithAlphaComponent:0.12]
        : [SCIUtils SCIColor_InstagramSecondaryBackground];
}

- (void)configureWithItem:(SCIAppIconItem *)item image:(UIImage *)image selected:(BOOL)selected {
    self.titleLabel.text = item.displayName;
    self.iconView.image = image ?: [SCIAssetUtils instagramIconNamed:@"app" pointSize:44.0];
    [self configureSelected:selected];
}

@end

@interface SCIAppIconPickerViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSArray<SCIAppIconItem *> *allItems;
@property (nonatomic, strong) NSArray<SCIAppIconItem *> *filteredItems;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *imageCache;
@property (nonatomic, copy) NSString *selectedIdentifier;
@property (nonatomic, copy) void (^onSelect)(NSString *identifier);

@end

@implementation SCIAppIconPickerViewController

- (instancetype)initWithSelectedIdentifier:(NSString *)selectedIdentifier
                                  onSelect:(void (^)(NSString *identifier))onSelect
{
    self = [super init];
    if (self) {
        _selectedIdentifier = [selectedIdentifier copy] ?: @"";
        _onSelect = [onSelect copy];
        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 64;
        self.title = @"App Icon";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];

    self.allItems = [SCIAppIconCatalog availableAppIcons];
    self.filteredItems = self.allItems;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 12.0;
    layout.minimumLineSpacing = 12.0;
    layout.sectionInset = UIEdgeInsetsMake(14.0, 14.0, 24.0, 14.0);

    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.collectionView registerClass:[SCIAppIconPickerCell class] forCellWithReuseIdentifier:kSCIAppIconPickerCellIdentifier];
    [self.view addSubview:self.collectionView];

    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.searchResultsUpdater = self;
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.hidesNavigationBarDuringPresentation = NO;
    searchController.searchBar.placeholder = @"Search Icons";
    [searchController.searchBar setImage:[SCIAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                        forSearchBarIcon:UISearchBarIconSearch
                                    state:UIControlStateNormal];
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.selectedIdentifier = [SCIAppIconCatalog currentAppIconIdentifier];
    [self.collectionView reloadData];
    [self scrollToSelectedIconIfNeeded];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
    CGFloat horizontalInset = layout.sectionInset.left + layout.sectionInset.right;
    CGFloat availableWidth = MAX(1.0, self.view.bounds.size.width - horizontalInset);
    NSInteger columns = availableWidth >= 500.0 ? 4 : 3;
    CGFloat itemWidth = floor((availableWidth - (columns - 1) * layout.minimumInteritemSpacing) / columns);
    layout.itemSize = CGSizeMake(itemWidth, 124.0);
}

- (UIImage *)imageForItem:(SCIAppIconItem *)item {
    NSString *cacheKey = item.identifier ?: @"";
    UIImage *cached = [self.imageCache objectForKey:cacheKey];
    if (cached) return cached;

    UIImage *image = [SCIAppIconCatalog imageForAppIcon:item];
    if (image) {
        [self.imageCache setObject:image forKey:cacheKey];
    }
    return image;
}

- (void)scrollToSelectedIconIfNeeded {
    NSUInteger index = [self.filteredItems indexOfObjectPassingTest:^BOOL(SCIAppIconItem *item, NSUInteger idx, BOOL *stop) {
        (void)idx;
        (void)stop;
        return [item.identifier isEqualToString:self.selectedIdentifier];
    }];
    if (index != NSNotFound) {
        [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]
                                    atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                            animated:NO];
    }
}

- (NSArray<NSString *> *)searchTokensForText:(NSString *)text {
    NSString *normalized = [[[text ?: @"" stringByReplacingOccurrencesOfString:@"_" withString:@" "] stringByReplacingOccurrencesOfString:@"-" withString:@" "] lowercaseString];
    NSArray<NSString *> *parts = [normalized componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) [tokens addObject:part];
    }
    return tokens;
}

- (void)filterForSearchText:(NSString *)searchText {
    NSArray<NSString *> *tokens = [self searchTokensForText:searchText];
    if (tokens.count == 0) {
        self.filteredItems = self.allItems;
        [self.collectionView reloadData];
        return;
    }

    NSMutableArray<SCIAppIconItem *> *matches = [NSMutableArray array];
    for (SCIAppIconItem *item in self.allItems) {
        NSString *searchText = [[[NSString stringWithFormat:@"%@ %@ %@", item.identifier ?: @"", item.displayName ?: @"", [item.iconFiles componentsJoinedByString:@" "]]
                                 stringByReplacingOccurrencesOfString:@"_" withString:@" "] lowercaseString];
        BOOL matchesAllTokens = YES;
        for (NSString *token in tokens) {
            if ([searchText rangeOfString:token].location == NSNotFound) {
                matchesAllTokens = NO;
                break;
            }
        }
        if (matchesAllTokens) [matches addObject:item];
    }
    self.filteredItems = matches;
    [self.collectionView reloadData];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    (void)collectionView;
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)collectionView;
    (void)section;
    return self.filteredItems.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SCIAppIconPickerCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kSCIAppIconPickerCellIdentifier forIndexPath:indexPath];
    SCIAppIconItem *item = self.filteredItems[indexPath.item];
    [cell configureWithItem:item image:[self imageForItem:item] selected:[item.identifier isEqualToString:self.selectedIdentifier]];
    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    SCIAppIconItem *item = self.filteredItems[indexPath.item];
    NSString *identifier = item.identifier ?: @"";
    if ([identifier isEqualToString:self.selectedIdentifier]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    if (!UIApplication.sharedApplication.supportsAlternateIcons) {
        [SCIIGAlertPresenter presentAlertFromViewController:self
                                                      title:@"App Icons Unavailable"
                                                    message:@"This device or app build does not allow alternate app icons."
                                                    actions:@[[SCIIGAlertAction actionWithTitle:@"OK" style:SCIIGAlertActionStyleDefault handler:nil]]];
        return;
    }

    NSString *alternateIconName = item.isPrimary ? nil : identifier;
    __weak typeof(self) weakSelf = self;
    [UIApplication.sharedApplication setAlternateIconName:alternateIconName completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            if (error) {
                [SCIIGAlertPresenter presentAlertFromViewController:self
                                                              title:@"Changing App Icon Failed"
                                                            message:error.localizedDescription ?: @"Unable to change the app icon."
                                                            actions:@[[SCIIGAlertAction actionWithTitle:@"OK" style:SCIIGAlertActionStyleDefault handler:nil]]];
                return;
            }

            self.selectedIdentifier = identifier;
            [SCIAppIconCatalog setStoredSelectedIdentifier:identifier];
            if (self.onSelect) self.onSelect(identifier);
            [collectionView reloadData];
            SCINotify(@"settings_app_icon", @"App icon changed", item.displayName, @"circle_check_filled", SCINotificationToneForIconResource(@"circle_check_filled"));
            [self.navigationController popViewControllerAnimated:YES];
        });
    }];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self filterForSearchText:searchController.searchBar.text];
}

@end

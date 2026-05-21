#import "SCIActionSectionIconPickerViewController.h"

#import "SCIInstagramIconCatalog.h"
#import "SCITopicSettingsSupport.h"
#import "../AssetUtils.h"
#import "../Shared/ActionButton/SCIActionDescriptor.h"
#import "../Utils.h"

static NSString * const kSCISectionIconCellIdentifier = @"SCISectionIconCell";
static NSString * const kSCISectionIconHeaderIdentifier = @"SCISectionIconHeader";
static NSInteger const kSCIUINavigationItemSearchBarPlacementStacked = 2;

@interface SCISectionIconPickerItem : NSObject
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *searchText;
@end

@implementation SCISectionIconPickerItem
@end

@interface SCISectionIconPickerCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *checkmarkView;
- (void)configureWithItem:(SCISectionIconPickerItem *)item image:(UIImage *)image selected:(BOOL)selected;
@end

static NSString *SCISectionIconPickerCellTitle(NSString *title) {
    if (title.length == 0 || ![title containsString:@"_"]) {
        return title ?: @"";
    }

    NSArray<NSString *> *parts = [title componentsSeparatedByString:@"_"];
    if (parts.count < 2) {
        return title;
    }

    NSUInteger target = title.length / 2;
    NSUInteger bestIndex = NSNotFound;
    NSUInteger bestDistance = NSUIntegerMax;
    NSUInteger cursor = 0;
    for (NSUInteger i = 0; i + 1 < parts.count; i++) {
        cursor += parts[i].length;
        NSUInteger distance = cursor > target ? cursor - target : target - cursor;
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = i;
        }
        cursor += 1;
    }

    if (bestIndex == NSNotFound) {
        return title;
    }

    NSMutableArray<NSString *> *first = [NSMutableArray array];
    NSMutableArray<NSString *> *second = [NSMutableArray array];
    for (NSUInteger i = 0; i < parts.count; i++) {
        [(i <= bestIndex ? first : second) addObject:parts[i]];
    }
    return [NSString stringWithFormat:@"%@\n%@", [first componentsJoinedByString:@"_"], [second componentsJoinedByString:@"_"]];
}

@implementation SCISectionIconPickerCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.contentView.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    self.contentView.layer.cornerRadius = 8.0;
    self.contentView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.contentView.layer.borderColor = [SCIUtils SCIColor_InstagramSeparator].CGColor;

    _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeCenter;
    _iconView.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    [self.contentView addSubview:_iconView];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightRegular];
    _titleLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _titleLabel.numberOfLines = 2;
    [self.contentView addSubview:_titleLabel];

    _checkmarkView = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"circle_check_filled" pointSize:18.0]];
    _checkmarkView.translatesAutoresizingMaskIntoConstraints = NO;
    _checkmarkView.tintColor = [SCIUtils SCIColor_Primary];
    _checkmarkView.hidden = YES;
    [self.contentView addSubview:_checkmarkView];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
        [_iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
        [_iconView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
        [_iconView.heightAnchor constraintEqualToConstant:32.0],

        [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:6.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6.0],
        [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-7.0],

        [_checkmarkView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
        [_checkmarkView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6.0],
        [_checkmarkView.widthAnchor constraintEqualToConstant:18.0],
        [_checkmarkView.heightAnchor constraintEqualToConstant:18.0]
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
    self.contentView.layer.borderColor = selected ? [SCIUtils SCIColor_Primary].CGColor : [SCIUtils SCIColor_InstagramSeparator].CGColor;
    self.contentView.layer.borderWidth = selected ? 2.0 : 1.0 / UIScreen.mainScreen.scale;
    self.contentView.backgroundColor = selected
        ? [[SCIUtils SCIColor_Primary] colorWithAlphaComponent:0.12]
        : [SCIUtils SCIColor_InstagramSecondaryBackground];
    self.iconView.tintColor = selected ? [SCIUtils SCIColor_Primary] : [SCIUtils SCIColor_InstagramPrimaryText];
}

- (void)configureWithItem:(SCISectionIconPickerItem *)item image:(UIImage *)image selected:(BOOL)selected {
    self.titleLabel.text = SCISectionIconPickerCellTitle(item.title);
    self.iconView.image = image;
    [self configureSelected:selected];
}

@end

@interface SCISectionIconPickerHeaderView : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
- (void)configureWithTitle:(NSString *)title;
@end

@implementation SCISectionIconPickerHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    [self addSubview:_titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14.0],
        [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0]
    ]];

    return self;
}

- (void)configureWithTitle:(NSString *)title {
    self.titleLabel.text = title;
}

@end

@interface SCIActionSectionIconPickerViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSArray<NSArray<SCISectionIconPickerItem *> *> *allSections;
@property (nonatomic, strong) NSArray<NSArray<SCISectionIconPickerItem *> *> *filteredSections;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSString *> *filteredSectionTitles;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *imageCache;
@property (nonatomic, copy) NSString *selectedIconName;
@property (nonatomic, copy) void (^onSelect)(NSString *iconName);

@end

@implementation SCIActionSectionIconPickerViewController

- (instancetype)initWithSelectedIconName:(NSString *)selectedIconName
                                onSelect:(void (^)(NSString *iconName))onSelect
{
    self = [super init];
    if (self) {
        _selectedIconName = [selectedIconName copy] ?: @"more";
        _onSelect = [onSelect copy];
        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 220;
        self.title = @"Section Icon";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];

    [self buildSections];
    self.filteredSections = self.allSections;
    self.filteredSectionTitles = self.sectionTitles;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 10.0;
    layout.minimumLineSpacing = 10.0;
    layout.sectionInset = UIEdgeInsetsMake(14.0, 14.0, 24.0, 14.0);
    layout.headerReferenceSize = CGSizeMake(1.0, 42.0);

    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.collectionView registerClass:[SCISectionIconPickerCell class] forCellWithReuseIdentifier:kSCISectionIconCellIdentifier];
    [self.collectionView registerClass:[SCISectionIconPickerHeaderView class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:kSCISectionIconHeaderIdentifier];
    [self.view addSubview:self.collectionView];

    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.searchResultsUpdater = self;
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.hidesNavigationBarDuringPresentation = NO;
    searchController.searchBar.placeholder = @"Search icons";
    [searchController.searchBar setImage:[SCIAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                        forSearchBarIcon:UISearchBarIconSearch
                                    state:UIControlStateNormal];
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    if (@available(iOS 26.0, *)) {
        @try {
            [self.navigationItem setValue:@(kSCIUINavigationItemSearchBarPlacementStacked) forKey:@"preferredSearchBarPlacement"];
        } @catch (__unused NSException *exception) {
        }
    }
    self.definesPresentationContext = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self scrollToSelectedIconIfNeeded];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
    CGFloat horizontalInset = layout.sectionInset.left + layout.sectionInset.right;
    CGFloat availableWidth = MAX(1.0, self.view.bounds.size.width - horizontalInset);
    NSInteger columns = 3;
    CGFloat itemWidth = floor((availableWidth - (columns - 1) * layout.minimumInteritemSpacing) / columns);
    layout.itemSize = CGSizeMake(itemWidth, 96.0);
}

- (SCISectionIconPickerItem *)itemWithIconName:(NSString *)iconName title:(NSString *)title {
    SCISectionIconPickerItem *item = [[SCISectionIconPickerItem alloc] init];
    item.iconName = iconName ?: @"more";
    item.title = title.length > 0 ? title : [SCIInstagramIconCatalog displayNameForIconName:item.iconName];
    item.searchText = [[NSString stringWithFormat:@"%@ %@",
                        [SCIInstagramIconCatalog searchTextForIconName:item.iconName],
                        [item.title lowercaseString]] lowercaseString];
    return item;
}

- (void)buildSections {
    NSMutableArray<SCISectionIconPickerItem *> *shortcutItems = [NSMutableArray array];
    NSMutableArray<SCISectionIconPickerItem *> *instagramItems = [NSMutableArray array];
    NSMutableSet<NSString *> *seenIconNames = [NSMutableSet set];

    void (^addShortcutItem)(SCISectionIconPickerItem *) = ^(SCISectionIconPickerItem *item) {
        if (item.iconName.length == 0 || [seenIconNames containsObject:item.iconName]) {
            return;
        }
        [seenIconNames addObject:item.iconName];
        [shortcutItems addObject:item];
    };

    void (^addInstagramItem)(SCISectionIconPickerItem *) = ^(SCISectionIconPickerItem *item) {
        if (item.iconName.length == 0 || [seenIconNames containsObject:item.iconName]) {
            return;
        }
        [seenIconNames addObject:item.iconName];
        [instagramItems addObject:item];
    };

    BOOL selectedIsKnownDescriptor = NO;
    for (SCIActionDescriptor *descriptor in [SCIActionDescriptor availableSectionIconDescriptors]) {
        if ([descriptor.iconName isEqualToString:self.selectedIconName]) {
            selectedIsKnownDescriptor = YES;
            break;
        }
    }

    if (self.selectedIconName.length > 0 &&
        !selectedIsKnownDescriptor &&
        ![[SCIInstagramIconCatalog availableInstagramIconNames] containsObject:self.selectedIconName]) {
        addShortcutItem([self itemWithIconName:self.selectedIconName title:[NSString stringWithFormat:@"Current: %@", [SCIInstagramIconCatalog displayNameForIconName:self.selectedIconName]]]);
    }

    for (SCIActionDescriptor *descriptor in [SCIActionDescriptor availableSectionIconDescriptors]) {
        addShortcutItem([self itemWithIconName:descriptor.iconName title:descriptor.title]);
    }

    for (NSString *iconName in [SCIInstagramIconCatalog availableInstagramIconNames]) {
        addInstagramItem([self itemWithIconName:iconName title:[SCIInstagramIconCatalog displayNameForIconName:iconName]]);
    }

    NSMutableArray<NSArray<SCISectionIconPickerItem *> *> *sections = [NSMutableArray array];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    if (shortcutItems.count > 0) {
        [sections addObject:shortcutItems];
        [titles addObject:@"Shortcuts"];
    }
    if (instagramItems.count > 0) {
        [sections addObject:instagramItems];
        [titles addObject:@"Instagram Icons"];
    }
    self.allSections = sections;
    self.sectionTitles = titles;
}

- (UIImage *)imageForIconName:(NSString *)iconName {
    UIImage *cached = [self.imageCache objectForKey:iconName];
    if (cached) {
        return cached;
    }

    UIImage *image = [SCIAssetUtils instagramIconNamed:iconName
                                             pointSize:28.0
                                                source:[SCIInstagramIconCatalog isInstagramBundleIconName:iconName] ? SCIAssetCatalogSourceFBSharedFramework : SCIAssetCatalogSourceAutomatic
                                         renderingMode:UIImageRenderingModeAlwaysTemplate];
    if (image) {
        [self.imageCache setObject:image forKey:iconName];
    }
    return image;
}

- (void)scrollToSelectedIconIfNeeded {
    for (NSUInteger section = 0; section < self.filteredSections.count; section++) {
        NSArray<SCISectionIconPickerItem *> *items = self.filteredSections[section];
        NSUInteger index = [items indexOfObjectPassingTest:^BOOL(SCISectionIconPickerItem *item, NSUInteger idx, BOOL *stop) {
            (void)idx;
            (void)stop;
            return [item.iconName isEqualToString:self.selectedIconName];
        }];
        if (index != NSNotFound) {
            [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:section]
                                        atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                                animated:NO];
            return;
        }
    }
}

- (NSArray<NSString *> *)searchTokensForText:(NSString *)text {
    NSString *normalized = [[[text ?: @"" stringByReplacingOccurrencesOfString:@"_" withString:@" "] stringByReplacingOccurrencesOfString:@"-" withString:@" "] lowercaseString];
    NSArray<NSString *> *parts = [normalized componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) {
            [tokens addObject:part];
        }
    }
    return tokens;
}

- (void)filterForSearchText:(NSString *)searchText {
    NSArray<NSString *> *tokens = [self searchTokensForText:searchText];
    if (tokens.count == 0) {
        self.filteredSections = self.allSections;
        self.filteredSectionTitles = self.sectionTitles;
        [self.collectionView reloadData];
        return;
    }

    NSMutableArray<NSArray<SCISectionIconPickerItem *> *> *filteredSections = [NSMutableArray array];
    NSMutableArray<NSString *> *filteredTitles = [NSMutableArray array];
    for (NSUInteger section = 0; section < self.allSections.count; section++) {
        NSMutableArray<SCISectionIconPickerItem *> *matches = [NSMutableArray array];
        for (SCISectionIconPickerItem *item in self.allSections[section]) {
            BOOL matchesAllTokens = YES;
            for (NSString *token in tokens) {
                if ([item.searchText rangeOfString:token].location == NSNotFound) {
                    matchesAllTokens = NO;
                    break;
                }
            }
            if (matchesAllTokens) {
                [matches addObject:item];
            }
        }
        if (matches.count > 0) {
            [filteredSections addObject:matches];
            [filteredTitles addObject:self.sectionTitles[section]];
        }
    }
    self.filteredSections = filteredSections;
    self.filteredSectionTitles = filteredTitles;
    [self.collectionView reloadData];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    (void)collectionView;
    return self.filteredSections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)collectionView;
    return self.filteredSections[section].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SCISectionIconPickerCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kSCISectionIconCellIdentifier forIndexPath:indexPath];
    SCISectionIconPickerItem *item = self.filteredSections[indexPath.section][indexPath.item];
    [cell configureWithItem:item
                      image:[self imageForIconName:item.iconName]
                   selected:[item.iconName isEqualToString:self.selectedIconName]];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                  atIndexPath:(NSIndexPath *)indexPath {
    SCISectionIconPickerHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                                withReuseIdentifier:kSCISectionIconHeaderIdentifier
                                                                                       forIndexPath:indexPath];
    [header configureWithTitle:self.filteredSectionTitles[indexPath.section]];
    return header;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    SCISectionIconPickerItem *item = self.filteredSections[indexPath.section][indexPath.item];
    self.selectedIconName = item.iconName;
    if (self.onSelect) self.onSelect(item.iconName);
    [collectionView reloadData];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self filterForSearchText:searchController.searchBar.text];
}

@end

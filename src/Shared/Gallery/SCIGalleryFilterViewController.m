#import "SCIGalleryFilterViewController.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "SCIGalleryHiddenSources.h"
#import "SCIGalleryUserPickerViewController.h"

static CGFloat const kSCIGalleryFilterChipLabelPointSize = 16.0;
static CGFloat const kSCIGalleryFilterChipIconPointSize = 14.0;

@interface SCIGalleryFilterChip : UIButton
@property (nonatomic, assign) NSInteger itemTag;
@property (nonatomic, assign) BOOL selectedChip;
- (void)updateChipAppearance;
@end

@implementation SCIGalleryFilterChip

- (instancetype)initWithTag:(NSInteger)tag {
    if ((self = [super initWithFrame:CGRectZero])) {
        _itemTag = tag;
        self.layer.cornerRadius = 12;
        self.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        self.titleLabel.font = [UIFont systemFontOfSize:kSCIGalleryFilterChipLabelPointSize weight:UIFontWeightMedium];
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.78;
        [self updateChipAppearance];
    }
    return self;
}

- (void)setSelectedChip:(BOOL)selectedChip {
    _selectedChip = selectedChip;
    [self updateChipAppearance];
}

- (void)updateChipAppearance {
    if (self.selectedChip) {
        self.backgroundColor = [[SCIUtils SCIColor_Primary] colorWithAlphaComponent:0.18];
        self.tintColor = [SCIUtils SCIColor_Primary];
        [self setTitleColor:[SCIUtils SCIColor_InstagramPrimaryText] forState:UIControlStateNormal];
    } else {
        self.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
        self.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
        [self setTitleColor:[SCIUtils SCIColor_InstagramPrimaryText] forState:UIControlStateNormal];
    }
}

@end

@interface SCIGalleryFilterViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;

@property (nonatomic, strong) NSMutableArray<SCIGalleryFilterChip *> *typeChips;
@property (nonatomic, strong) NSMutableArray<SCIGalleryFilterChip *> *sourceChips;
@property (nonatomic, strong) UILabel *usernameSectionTitle;
@property (nonatomic, strong) UIControl *favoritesRow;
@property (nonatomic, strong) UIImageView *favoritesLeadingIcon;
@property (nonatomic, strong) UILabel *favoritesLabel;
@property (nonatomic, strong) UIControl *clearRow;
@property (nonatomic, strong) UIImageView *clearLeadingIcon;
@property (nonatomic, strong) UILabel *clearLabel;
@property (nonatomic, strong) UILabel *usernameRowLabel;

@end

@implementation SCIGalleryFilterViewController

+ (NSPredicate *)predicateForTypes:(NSSet<NSNumber *> *)types
                           sources:(NSSet<NSNumber *> *)sources
                     favoritesOnly:(BOOL)favoritesOnly
                           usernames:(NSSet<NSString *> *)usernames
                        folderPath:(NSString *)folderPath {
    return [self predicateForTypes:types sources:sources favoritesOnly:favoritesOnly usernames:usernames folderPath:folderPath scopeToFolder:YES];
}

+ (NSPredicate *)predicateForTypes:(NSSet<NSNumber *> *)types
                           sources:(NSSet<NSNumber *> *)sources
                     favoritesOnly:(BOOL)favoritesOnly
                           usernames:(NSSet<NSString *> *)usernames
                        folderPath:(NSString *)folderPath
                     scopeToFolder:(BOOL)scopeToFolder {
    NSMutableArray<NSPredicate *> *parts = [NSMutableArray new];
    if (types.count > 0) {
        NSArray *typeList = [types.allObjects sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]];
        [parts addObject:[NSPredicate predicateWithFormat:@"mediaType IN %@", typeList]];
    }
    if (sources.count > 0) {
        NSArray *sourceList = [sources.allObjects sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]];
        [parts addObject:[NSPredicate predicateWithFormat:@"source IN %@", sourceList]];
    }
    if (favoritesOnly) {
        [parts addObject:[NSPredicate predicateWithFormat:@"isFavorite == %@", @(YES)]];
    }
    if (usernames.count > 0) {
        NSMutableArray<NSPredicate *> *usernameParts = [NSMutableArray array];
        for (NSString *username in usernames) {
            if (username.length == 0) continue;
            [usernameParts addObject:[NSPredicate predicateWithFormat:@"sourceUsername ==[c] %@", username]];
        }
        if (usernameParts.count > 0) {
            [parts addObject:[NSCompoundPredicate orPredicateWithSubpredicates:usernameParts]];
        }
    }
    if (scopeToFolder) {
        if (folderPath.length > 0) {
            [parts addObject:[NSPredicate predicateWithFormat:@"folderPath == %@", folderPath]];
        } else {
            // Root: only items not stored inside a folder (nil or empty string).
            [parts addObject:[NSPredicate predicateWithFormat:@"(folderPath == nil) OR (folderPath == %@)", @""]];
        }
    }
    if (parts.count == 0) return nil;
    return [NSCompoundPredicate andPredicateWithSubpredicates:parts];
}

- (instancetype)init {
    if ((self = [super init])) {
        _filterTypes = [NSMutableSet new];
        _filterSources = [NSMutableSet new];
        _typeChips = [NSMutableArray new];
        _sourceChips = [NSMutableArray new];
        _filterUsernames = [NSMutableSet new];
        _availableUsernames = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    [self setupNavigationBar];
    [self setupContent];
    [self updateClearRowState];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateScrollAvailability];
}

// Height the content needs at `width`: the content stack's fitting height plus
// its 12pt top/bottom insets. Excludes the nav bar and bottom safe area, which
// the presenter adds.
- (CGFloat)sciContentHeightForWidth:(CGFloat)width {
    [self loadViewIfNeeded];
    CGFloat innerWidth = MAX(0.0, width - 32.0); // 16pt leading + 16pt trailing
    CGFloat stackHeight = [self.contentStack systemLayoutSizeFittingSize:CGSizeMake(innerWidth, 0.0)
                                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    return 12.0 + stackHeight + 12.0;
}

- (void)setupNavigationBar {
    self.title = @"Filter";
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem = nil;
}

- (void)setupContent {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = NO;
    self.scrollView.bounces = NO;
    self.scrollView.scrollEnabled = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 10;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentStack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:12],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:16],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-16],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-12],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-32],
    ]];

    [self.contentStack addArrangedSubview:[self sectionTitle:@"Type"]];
    [self.contentStack addArrangedSubview:[self createTypeRow]];
    [self.contentStack addArrangedSubview:[self sectionTitle:@"Source"]];
    [self.contentStack addArrangedSubview:[self createSourceGrid]];
    if (self.availableUsernames.count > 0) {
        self.usernameSectionTitle = [self sectionTitle:@"Username"];
        [self updateUsernameSectionTitle];
        [self.contentStack addArrangedSubview:self.usernameSectionTitle];
        [self.contentStack addArrangedSubview:[self createUsernameRow]];
    }
    [self.contentStack addArrangedSubview:[self sectionTitle:@"Options"]];
    [self.contentStack addArrangedSubview:[self createOptionsRow]];
}

- (BOOL)isPresentedAtFullscreenHeight {
    UIView *presentedView = self.navigationController.view ?: self.view;
    UIView *containerView = self.presentationController.containerView ?: presentedView.superview;
    if (!containerView) return NO;

    CGFloat presentedHeight = CGRectGetHeight(presentedView.bounds);
    CGFloat containerHeight = CGRectGetHeight(containerView.bounds);
    if (presentedHeight <= 0.0 || containerHeight <= 0.0) return NO;
    return presentedHeight >= floor(containerHeight * 0.92);
}

- (void)updateScrollAvailability {
    CGFloat viewportHeight = CGRectGetHeight(self.scrollView.bounds);
    CGFloat contentHeight = self.scrollView.contentSize.height;
    BOOL contentOverflows = contentHeight > viewportHeight + 1.0;
    BOOL shouldScroll = contentOverflows && [self isPresentedAtFullscreenHeight];
    self.scrollView.scrollEnabled = shouldScroll;
    self.scrollView.bounces = shouldScroll;
    self.scrollView.alwaysBounceVertical = shouldScroll;
    self.scrollView.showsVerticalScrollIndicator = shouldScroll;
}

- (UILabel *)sectionTitle:(NSString *)title {
    UILabel *l = [[UILabel alloc] init];
    l.text = title;
    l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    l.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    return l;
}

- (UIView *)createTypeRow {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFillEqually;

    NSArray *defs = @[
        @{@"label": @"Images", @"resource": @"photo", @"tag": @(SCIGalleryMediaTypeImage)},
        @{@"label": @"Videos", @"resource": @"video", @"tag": @(SCIGalleryMediaTypeVideo)},
        @{@"label": @"Audio", @"resource": @"audio", @"tag": @(SCIGalleryMediaTypeAudio)},
    ];
    for (NSDictionary *d in defs) {
        NSInteger tag = [d[@"tag"] integerValue];
        SCIGalleryFilterChip *chip = [[SCIGalleryFilterChip alloc] initWithTag:tag];
        [chip setTitle:d[@"label"] forState:UIControlStateNormal];
        UIImage *icon = [SCIAssetUtils instagramIconNamed:d[@"resource"] pointSize:kSCIGalleryFilterChipIconPointSize];
        [chip setImage:icon forState:UIControlStateNormal];
        chip.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
        chip.selectedChip = [self.filterTypes containsObject:@(tag)];
        [chip addTarget:self action:@selector(typeChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [chip.heightAnchor constraintEqualToConstant:44].active = YES;
        [row addArrangedSubview:chip];
        [self.typeChips addObject:chip];
    }
    return row;
}

- (UIView *)createSourceGrid {
    UIStackView *grid = [[UIStackView alloc] init];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 8;

    NSArray *sources = @[
        @(SCIGallerySourceFeed), @(SCIGallerySourceStories), @(SCIGallerySourceReels),
        @(SCIGallerySourceProfile), @(SCIGallerySourceDMs), @(SCIGallerySourceThumbnail),
        @(SCIGallerySourceInstants), @(SCIGallerySourceAudioPage), @(SCIGallerySourceComments),
    ];

    NSInteger columns = 3;
    NSInteger visibleIndex = 0;
    UIStackView *currentRow = nil;
    for (NSInteger i = 0; i < sources.count; i++) {
        if (SCIGallerySourceIsHidden([sources[i] integerValue])) continue;
        if (visibleIndex % columns == 0) {
            currentRow = [[UIStackView alloc] init];
            currentRow.axis = UILayoutConstraintAxisHorizontal;
            currentRow.spacing = 8;
            currentRow.distribution = UIStackViewDistributionFillEqually;
            [grid addArrangedSubview:currentRow];
        }

        SCIGallerySource src = (SCIGallerySource)[sources[i] integerValue];
        SCIGalleryFilterChip *chip = [[SCIGalleryFilterChip alloc] initWithTag:src];
        [chip setTitle:[SCIGalleryFile labelForSource:src] forState:UIControlStateNormal];
        UIImage *icon = [SCIAssetUtils instagramIconNamed:[SCIGalleryFile symbolNameForSource:src] pointSize:kSCIGalleryFilterChipIconPointSize];
        [chip setImage:icon forState:UIControlStateNormal];
        chip.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
        chip.selectedChip = [self.filterSources containsObject:@(src)];
        [chip addTarget:self action:@selector(sourceChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [chip.heightAnchor constraintEqualToConstant:44].active = YES;
        [currentRow addArrangedSubview:chip];
        [self.sourceChips addObject:chip];
        visibleIndex += 1;
    }

    // Pad last row so chips have equal width
    while (currentRow && currentRow.arrangedSubviews.count % columns != 0) {
        UIView *spacer = [[UIView alloc] init];
        [currentRow addArrangedSubview:spacer];
    }
    return grid;
}

// A disclosure row that pushes a full-screen searchable multi-select picker —
// scales to hundreds of users, unlike the old horizontal chip strip.
- (UIView *)createUsernameRow {
    UIControl *row = [[UIControl alloc] init];
    row.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    row.layer.cornerRadius = 12;
    [row.heightAnchor constraintEqualToConstant:50].active = YES;
    [row addTarget:self action:@selector(usernameRowTapped) forControlEvents:UIControlEventTouchUpInside];

    UIImage *rowIcon = [SCIAssetUtils instagramIconNamed:@"mention" pointSize:18.0];
    UIImageView *icon = [[UIImageView alloc] initWithImage:rowIcon];
    icon.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:icon];

    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:kSCIGalleryFilterChipLabelPointSize weight:UIFontWeightMedium];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.78;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    self.usernameRowLabel = label;

    UIImage *chevronImg = [SCIAssetUtils instagramIconNamed:@"chevron_right" pointSize:14.0];
    UIImageView *chevron = [[UIImageView alloc] initWithImage:chevronImg];
    chevron.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:8],
        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:14],
        [chevron.heightAnchor constraintEqualToConstant:14],
    ]];
    [self updateUsernameRowLabel];
    return row;
}

- (void)updateUsernameRowLabel {
    NSUInteger count = self.filterUsernames.count;
    self.usernameRowLabel.text = count > 0
        ? [NSString stringWithFormat:@"%lu user%@ selected", (unsigned long)count, count == 1 ? @"" : @"s"]
        : @"All users";
    self.usernameRowLabel.textColor = count > 0
        ? [SCIUtils SCIColor_InstagramPrimaryText]
        : [SCIUtils SCIColor_InstagramSecondaryText];
}

- (void)usernameRowTapped {
    SCIGalleryUserPickerViewController *picker = [[SCIGalleryUserPickerViewController alloc]
        initWithUsernames:self.availableUsernames selected:self.filterUsernames];
    __weak typeof(self) weakSelf = self;
    picker.selectionChanged = ^(NSSet<NSString *> *selected) {
        weakSelf.filterUsernames = [selected mutableCopy];
        [weakSelf updateUsernameRowLabel];
        [weakSelf updateUsernameSectionTitle];
        [weakSelf notifyFilterStateChanged];
    };
    // Present as its own full-height sheet rather than pushing into the filter's
    // single-size sheet, so the searchable list gets full height and the filter
    // sheet keeps one fixed size.
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 16.0, *)) {
        nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

- (UIView *)createFavoritesRow {
    UIControl *row = [[UIControl alloc] init];
    row.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    row.layer.cornerRadius = 12;
    [row.heightAnchor constraintEqualToConstant:50].active = YES;
    [row addTarget:self action:@selector(favoritesRowTapped) forControlEvents:UIControlEventTouchUpInside];

    UIImage *favRowIcon = [SCIAssetUtils instagramIconNamed:@"heart" pointSize:18.0];
    UIImageView *icon = [[UIImageView alloc] initWithImage:favRowIcon];
    icon.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:icon];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Favorites";
    label.font = [UIFont systemFontOfSize:kSCIGalleryFilterChipLabelPointSize weight:UIFontWeightMedium];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.78;
    label.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];

    self.favoritesRow = row;
    self.favoritesLeadingIcon = icon;
    self.favoritesLabel = label;
    [self updateFavoritesRowAppearance];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-12],
    ]];
    return row;
}

- (UIView *)createOptionsRow {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFillEqually;
    [row addArrangedSubview:[self createFavoritesRow]];
    [row addArrangedSubview:[self createClearRow]];
    return row;
}

- (UIView *)createClearRow {
    UIControl *row = [[UIControl alloc] init];
    row.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    row.layer.cornerRadius = 12;
    [row.heightAnchor constraintEqualToConstant:50].active = YES;
    [row addTarget:self action:@selector(clearFilters) forControlEvents:UIControlEventTouchUpInside];

    UIImage *clearIcon = [SCIAssetUtils instagramIconNamed:@"backspace" pointSize:18.0];
    UIImageView *icon = [[UIImageView alloc] initWithImage:clearIcon];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:icon];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Clear filters";
    label.font = [UIFont systemFontOfSize:kSCIGalleryFilterChipLabelPointSize weight:UIFontWeightMedium];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.78;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];

    self.clearRow = row;
    self.clearLeadingIcon = icon;
    self.clearLabel = label;

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-12],
    ]];

    return row;
}

#pragma mark - Actions

- (void)typeChipTapped:(SCIGalleryFilterChip *)chip {
    NSNumber *tag = @(chip.itemTag);
    if ([self.filterTypes containsObject:tag]) {
        [self.filterTypes removeObject:tag];
        chip.selectedChip = NO;
    } else {
        [self.filterTypes addObject:tag];
        chip.selectedChip = YES;
    }
    [self notifyFilterStateChanged];
}

- (void)sourceChipTapped:(SCIGalleryFilterChip *)chip {
    NSNumber *tag = @(chip.itemTag);
    if ([self.filterSources containsObject:tag]) {
        [self.filterSources removeObject:tag];
        chip.selectedChip = NO;
    } else {
        [self.filterSources addObject:tag];
        chip.selectedChip = YES;
    }
    [self notifyFilterStateChanged];
}

- (void)updateUsernameSectionTitle {
    // Static header like the other sections; the selection count lives on the row
    // itself, so don't duplicate it here.
    if (!self.usernameSectionTitle) return;
    self.usernameSectionTitle.text = @"Username";
}

- (void)favoritesRowTapped {
    self.filterFavoritesOnly = !self.filterFavoritesOnly;
    [self updateFavoritesRowAppearance];
    [self notifyFilterStateChanged];
}

- (void)updateFavoritesRowAppearance {
    if (!self.favoritesRow || !self.favoritesLeadingIcon || !self.favoritesLabel) return;

    if (self.filterFavoritesOnly) {
        UIColor *accent = [SCIUtils SCIColor_InstagramFavorite];
        self.favoritesRow.backgroundColor = [accent colorWithAlphaComponent:0.2];
        self.favoritesLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
        self.favoritesLeadingIcon.image = [SCIAssetUtils instagramIconNamed:@"heart_filled" pointSize:14.0];
        self.favoritesLeadingIcon.tintColor = accent;
    } else {
        self.favoritesRow.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
        self.favoritesLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
        self.favoritesLeadingIcon.image = [SCIAssetUtils instagramIconNamed:@"heart" pointSize:14.0];
        self.favoritesLeadingIcon.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
    }
}

- (void)updateClearRowState {
    if (!self.clearRow || !self.clearLeadingIcon || !self.clearLabel) return;

    BOOL active = [self hasActiveFilters];
    self.clearRow.userInteractionEnabled = active;
    self.clearRow.backgroundColor = active
        ? [[SCIUtils SCIColor_InstagramDestructive] colorWithAlphaComponent:0.16]
        : [SCIUtils SCIColor_InstagramSecondaryBackground];
    self.clearLeadingIcon.tintColor = active ? [SCIUtils SCIColor_InstagramDestructive] : [SCIUtils SCIColor_InstagramTertiaryText];
    self.clearLabel.textColor = active ? [SCIUtils SCIColor_InstagramDestructive] : [SCIUtils SCIColor_InstagramTertiaryText];
}

- (BOOL)hasActiveFilters {
    return self.filterTypes.count > 0 || self.filterSources.count > 0 || self.filterFavoritesOnly || self.filterUsernames.count > 0;
}

- (void)notifyFilterStateChanged {
    [self updateClearRowState];
    if ([self.delegate respondsToSelector:@selector(filterController:didApplyTypes:sources:favoritesOnly:usernames:)]) {
        [self.delegate filterController:self
                          didApplyTypes:[self.filterTypes copy]
                                sources:[self.filterSources copy]
                          favoritesOnly:self.filterFavoritesOnly
                              usernames:[self.filterUsernames copy]];
    }
}

- (void)clearFilters {
    if (![self hasActiveFilters]) return;
    [self.filterTypes removeAllObjects];
    [self.filterSources removeAllObjects];
    self.filterFavoritesOnly = NO;
    [self.filterUsernames removeAllObjects];
    [self updateFavoritesRowAppearance];
    for (SCIGalleryFilterChip *c in self.typeChips) c.selectedChip = NO;
    for (SCIGalleryFilterChip *c in self.sourceChips) c.selectedChip = NO;
    [self updateUsernameSectionTitle];
    [self updateUsernameRowLabel];
    if ([self.delegate respondsToSelector:@selector(filterControllerDidClear:)]) {
        [self.delegate filterControllerDidClear:self];
    } else {
        [self notifyFilterStateChanged];
    }
    [self updateClearRowState];
}

@end

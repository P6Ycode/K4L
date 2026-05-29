#import "SCIGallerySortViewController.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"

static NSString *SCIGallerySortResourceSymbol(SCIGallerySortMode mode) {
    switch (mode) {
        case SCIGallerySortModeDateAddedDesc:
        case SCIGallerySortModeDateAddedAsc:
            return @"calendar";
        case SCIGallerySortModeNameAsc:
        case SCIGallerySortModeNameDesc:
            return @"text";
        case SCIGallerySortModeSizeDesc:
            return @"size_large";
        case SCIGallerySortModeSizeAsc:
            return @"size_small";
        case SCIGallerySortModeTypeAsc:
        case SCIGallerySortModeTypeDesc:
            return @"photo_gallery";
    }
    return @"sort";
}

@interface SCIGallerySortChip : UIButton
@property (nonatomic, assign) SCIGallerySortMode mode;
@property (nonatomic, assign) BOOL selectedChip;
- (void)updateChipAppearance;
@end

@implementation SCIGallerySortChip

- (instancetype)initWithMode:(SCIGallerySortMode)mode {
    if ((self = [super initWithFrame:CGRectZero])) {
        _mode = mode;
        self.layer.cornerRadius = 12;
        self.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
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
        self.layer.borderColor = [SCIUtils SCIColor_Primary].CGColor;
    } else {
        self.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
        self.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
        [self setTitleColor:[SCIUtils SCIColor_InstagramPrimaryText] forState:UIControlStateNormal];
        self.layer.borderColor = [SCIUtils SCIColor_InstagramSeparator].CGColor;
    }
}

@end

@interface SCIGallerySortViewController ()
@property (nonatomic, strong) NSMutableArray<SCIGallerySortChip *> *sortChips;
@property (nonatomic, strong) NSMutableArray<UIButton *> *groupChips;
@end

@implementation SCIGallerySortViewController

+ (NSArray<NSSortDescriptor *> *)sortDescriptorsForMode:(SCIGallerySortMode)mode {
    return [self sortDescriptorsForMode:mode groupByMediaType:NO];
}

+ (NSArray<NSSortDescriptor *> *)sortDescriptorsForMode:(SCIGallerySortMode)mode groupByMediaType:(BOOL)groupByMediaType {
    NSMutableArray<NSSortDescriptor *> *descriptors = [NSMutableArray array];
    if (groupByMediaType || mode == SCIGallerySortModeTypeAsc || mode == SCIGallerySortModeTypeDesc) {
        [descriptors addObject:[NSSortDescriptor sortDescriptorWithKey:@"mediaType" ascending:YES]];
    }

    switch (mode) {
        case SCIGallerySortModeDateAddedDesc:
        case SCIGallerySortModeTypeAsc:
        case SCIGallerySortModeTypeDesc:
            [descriptors addObject:[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO]];
            break;
        case SCIGallerySortModeDateAddedAsc:
            [descriptors addObject:[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:YES]];
            break;
        case SCIGallerySortModeNameAsc:
            [descriptors addObject:[NSSortDescriptor sortDescriptorWithKey:@"relativePath" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]];
            break;
        case SCIGallerySortModeNameDesc:
            [descriptors addObject:[NSSortDescriptor sortDescriptorWithKey:@"relativePath" ascending:NO selector:@selector(localizedCaseInsensitiveCompare:)]];
            break;
        case SCIGallerySortModeSizeDesc:
            [descriptors addObject:[NSSortDescriptor sortDescriptorWithKey:@"fileSize" ascending:NO]];
            break;
        case SCIGallerySortModeSizeAsc:
            [descriptors addObject:[NSSortDescriptor sortDescriptorWithKey:@"fileSize" ascending:YES]];
            break;
    }
    return descriptors.count ? descriptors : @[[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO]];
}

+ (NSString *)labelForMode:(SCIGallerySortMode)mode {
    switch (mode) {
        case SCIGallerySortModeDateAddedDesc: return @"Newest first";
        case SCIGallerySortModeDateAddedAsc:  return @"Oldest first";
        case SCIGallerySortModeNameAsc:       return @"Name A-Z";
        case SCIGallerySortModeNameDesc:      return @"Name Z-A";
        case SCIGallerySortModeSizeDesc:      return @"Largest first";
        case SCIGallerySortModeSizeAsc:       return @"Smallest first";
        case SCIGallerySortModeTypeAsc:
        case SCIGallerySortModeTypeDesc:      return @"Newest first";
    }
    return @"Newest first";
}

- (instancetype)init {
    if ((self = [super init])) {
        _sortChips = [NSMutableArray new];
        _groupChips = [NSMutableArray new];
        _currentSortMode = SCIGallerySortModeDateAddedDesc;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    [self setupNavigationBar];
    [self setupContent];
}

- (void)setupNavigationBar {
    self.title = @"Sort";
}

- (void)setupContent {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-20],
    ]];

    [stack addArrangedSubview:[self sectionTitle:@"Order"]];
    NSArray<NSArray<NSNumber *> *> *rows = @[
        @[@(SCIGallerySortModeDateAddedDesc), @(SCIGallerySortModeDateAddedAsc)],
        @[@(SCIGallerySortModeNameAsc),       @(SCIGallerySortModeNameDesc)],
        @[@(SCIGallerySortModeSizeDesc),      @(SCIGallerySortModeSizeAsc)],
    ];

    for (NSInteger i = 0; i < rows.count; i++) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 10;
        row.distribution = UIStackViewDistributionFillEqually;

        for (NSNumber *modeNum in rows[i]) {
            SCIGallerySortMode mode = (SCIGallerySortMode)modeNum.integerValue;
            SCIGallerySortChip *chip = [[SCIGallerySortChip alloc] initWithMode:mode];
            [chip setTitle:[SCIGallerySortViewController labelForMode:mode] forState:UIControlStateNormal];
            UIImage *icon = [SCIAssetUtils instagramIconNamed:SCIGallerySortResourceSymbol(mode) pointSize:14.0];
            [chip setImage:icon forState:UIControlStateNormal];
            chip.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
            chip.selectedChip = (mode == self.currentSortMode);
            [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
            [chip.heightAnchor constraintEqualToConstant:44].active = YES;
            [row addArrangedSubview:chip];
            [self.sortChips addObject:chip];
        }
        [stack addArrangedSubview:row];
    }

    [stack addArrangedSubview:[self sectionTitle:@"Grouping"]];
    UIStackView *groupRow = [[UIStackView alloc] init];
    groupRow.axis = UILayoutConstraintAxisHorizontal;
    groupRow.spacing = 10;
    groupRow.distribution = UIStackViewDistributionFillEqually;
    [groupRow addArrangedSubview:[self groupChipWithTitle:@"None" icon:@"circle_off" selected:!self.currentGroupByMediaType tag:0]];
    [groupRow addArrangedSubview:[self groupChipWithTitle:@"Media type" icon:@"photo_gallery" selected:self.currentGroupByMediaType tag:1]];
    [stack addArrangedSubview:groupRow];
}

- (UILabel *)sectionTitle:(NSString *)title {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    return label;
}

- (UIButton *)groupChipWithTitle:(NSString *)title icon:(NSString *)icon selected:(BOOL)selected tag:(NSInteger)tag {
    UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
    chip.tag = tag;
    chip.layer.cornerRadius = 12;
    chip.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    chip.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    chip.titleLabel.adjustsFontSizeToFitWidth = YES;
    chip.titleLabel.minimumScaleFactor = 0.78;
    [chip setTitle:title forState:UIControlStateNormal];
    [chip setImage:[SCIAssetUtils instagramIconNamed:icon pointSize:14.0] forState:UIControlStateNormal];
    chip.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
    [chip.heightAnchor constraintEqualToConstant:44].active = YES;
    [chip addTarget:self action:@selector(groupChipTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.groupChips addObject:chip];
    [self updateGroupChip:chip selected:selected];
    return chip;
}

- (void)updateGroupChip:(UIButton *)chip selected:(BOOL)selected {
    if (selected) {
        chip.backgroundColor = [[SCIUtils SCIColor_Primary] colorWithAlphaComponent:0.18];
        chip.tintColor = [SCIUtils SCIColor_Primary];
        [chip setTitleColor:[SCIUtils SCIColor_InstagramPrimaryText] forState:UIControlStateNormal];
    } else {
        chip.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
        chip.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
        [chip setTitleColor:[SCIUtils SCIColor_InstagramPrimaryText] forState:UIControlStateNormal];
    }
}

- (void)chipTapped:(SCIGallerySortChip *)chip {
    self.currentSortMode = chip.mode;
    for (SCIGallerySortChip *c in self.sortChips) c.selectedChip = (c.mode == chip.mode);
    if ([self.delegate respondsToSelector:@selector(sortController:didSelectSortMode:groupByMediaType:)]) {
        [self.delegate sortController:self didSelectSortMode:self.currentSortMode groupByMediaType:self.currentGroupByMediaType];
    }
    [self dismissController];
}

- (void)groupChipTapped:(UIButton *)chip {
    self.currentGroupByMediaType = chip.tag == 1;
    for (UIButton *c in self.groupChips) [self updateGroupChip:c selected:(c.tag == chip.tag)];
    if ([self.delegate respondsToSelector:@selector(sortController:didSelectSortMode:groupByMediaType:)]) {
        [self.delegate sortController:self didSelectSortMode:self.currentSortMode groupByMediaType:self.currentGroupByMediaType];
    }
    [self dismissController];
}

- (void)dismissController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

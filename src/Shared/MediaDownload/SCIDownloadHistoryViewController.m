#import "SCIDownloadHistoryViewController.h"

#import "SCIDownloadQueueManager.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGalleryViewController.h"
#import "../MediaPreview/SCIFullScreenMediaPlayer.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"

typedef NS_ENUM(NSUInteger, SCIDownloadHistoryFilter) {
    SCIDownloadHistoryFilterAll = 0,
    SCIDownloadHistoryFilterActive,
    SCIDownloadHistoryFilterQueued,
    SCIDownloadHistoryFilterFailed,
    SCIDownloadHistoryFilterRecent,
};

static NSNumber *SCIHistoryChildIndex(NSDictionary *row) { return row[@"descriptor"][@"_childIndex"]; }
static NSString *SCIHistoryParentID(NSDictionary *row) { return row[@"descriptor"][@"_parentID"]; }

static BOOL SCIHistoryStateIsFailed(NSString *state) {
    return [@[@"failed", @"partial", @"interrupted"] containsObject:state];
}

static BOOL SCIHistoryStateIsRecent(NSString *state) {
    return [@[@"completed", @"cancelled"] containsObject:state];
}

static NSString *SCIHistoryDateString(NSNumber *timestamp) {
    if (timestamp.doubleValue <= 0) return @"";
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeStyle = NSDateFormatterShortStyle;
        formatter.dateStyle = NSDateFormatterShortStyle;
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue]];
}

static void SCIOpenDownloadCompletionAction(NSString *action) {
    if ([action isEqualToString:@"openGallery"]) [SCIGalleryViewController presentGallery];
    else if ([action isEqualToString:@"openPhotos"]) [SCIUtils openPhotosApp];
}

static NSString *SCIHistoryLeadIconName(NSDictionary *row) {
    NSDictionary *descriptor = row[@"descriptor"] ?: @{};
    NSString *mediaKind = descriptor[@"mediaKind"] ?: row[@"mediaKind"];
    if ([descriptor[@"itemCount"] integerValue] > 1) return @"download";
    if ([mediaKind isEqualToString:@"Audio"]) return @"audio_page";
    if ([mediaKind isEqualToString:@"Video"]) return @"reels";
    return @"photo_gallery";
}

static NSString *SCIHistoryStatusIconName(NSString *state) {
    if ([state isEqualToString:@"completed"]) return @"circle_check_filled";
    if (SCIHistoryStateIsFailed(state)) return @"error_filled";
    if ([state isEqualToString:@"cancelled"]) return @"xmark";
    if ([state isEqualToString:@"queued"]) return @"clock";
    return @"warning_filled";
}

static UIColor *SCIHistoryStatusColor(NSString *state) {
    if ([state isEqualToString:@"completed"]) return [UIColor systemGreenColor];
    if (SCIHistoryStateIsFailed(state)) return [SCIUtils SCIColor_InstagramDestructive];
    if ([state isEqualToString:@"queued"]) return [SCIUtils SCIColor_InstagramSecondaryText];
    if ([state isEqualToString:@"running"]) return [SCIUtils SCIColor_Primary];
    if ([state isEqualToString:@"cancelled"]) return [SCIUtils SCIColor_InstagramSecondaryText];
    return [UIColor systemOrangeColor];
}

@interface SCIDownloadFilterChipBar : UIView
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^selectionChanged)(NSInteger index);
- (void)setTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)selectedIndex;
@end

@implementation SCIDownloadFilterChipBar

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    _selectedIndex = 0;

    _scrollView = [UIScrollView new];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.contentInset = UIEdgeInsetsMake(0, 16, 0, 16);
    [self addSubview:_scrollView];

    _stackView = [UIStackView new];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackView.axis = UILayoutConstraintAxisHorizontal;
    _stackView.spacing = 8.0;
    [_scrollView addSubview:_stackView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_stackView.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor],
        [_stackView.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor],
        [_stackView.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor constant:6.0],
        [_stackView.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor constant:-6.0],
        [_stackView.heightAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.heightAnchor constant:-12.0],
    ]];
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 50.0);
}

- (void)setTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)selectedIndex {
    self.titles = titles ?: @[];
    self.selectedIndex = MIN(MAX(0, selectedIndex), (NSInteger)MAX((NSInteger)0, (NSInteger)self.titles.count - 1));

    for (UIView *view in self.stackView.arrangedSubviews) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    [self.titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
        (void)stop;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = idx;
        button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        button.contentEdgeInsets = UIEdgeInsetsMake(7.0, 14.0, 7.0, 14.0);
        button.layer.cornerRadius = 15.0;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        [button setTitle:title forState:UIControlStateNormal];
        [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button.heightAnchor constraintEqualToConstant:30.0].active = YES;
        [self.stackView addArrangedSubview:button];
        [buttons addObject:button];
    }];
    self.buttons = buttons;
    [self refreshSelection];
}

- (void)refreshSelection {
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger idx, BOOL *stop) {
        (void)stop;
        BOOL selected = (NSInteger)idx == self.selectedIndex;
        button.backgroundColor = selected ? [SCIUtils SCIColor_InstagramPrimaryText] : [SCIUtils SCIColor_InstagramSecondaryBackground];
        UIColor *titleColor = selected ? [SCIUtils SCIColor_InstagramBackground] : [SCIUtils SCIColor_InstagramPrimaryText];
        [button setTitleColor:titleColor forState:UIControlStateNormal];
    }];
}

- (void)buttonTapped:(UIButton *)button {
    self.selectedIndex = button.tag;
    [self refreshSelection];
    if (self.selectionChanged) self.selectionChanged(button.tag);
}

@end

@interface SCIDownloadHistoryCell : UITableViewCell
@property (nonatomic, strong) NSLayoutConstraint *leadingConstraint;
@property (nonatomic, strong) UIView *iconBackgroundView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIView *sourcePillView;
@property (nonatomic, strong) UILabel *sourcePillLabel;
@property (nonatomic, strong) UILabel *timestampLabel;
@property (nonatomic, strong) UIImageView *statusView;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, copy) NSString *jobID;
@property (nonatomic, copy) void (^primaryAction)(void);
@property (nonatomic, copy) void (^cancelAction)(void);
@property (nonatomic, copy) void (^menuPrimaryAction)(void);
- (void)configureWithRow:(NSDictionary *)row;
@end

@implementation SCIDownloadHistoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) return nil;
    self.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    UIView *selectedBackground = [UIView new];
    selectedBackground.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
    self.selectedBackgroundView = selectedBackground;

    _iconBackgroundView = [UIView new];
    _iconBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconBackgroundView.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    _iconBackgroundView.layer.cornerRadius = 6.0;
    _iconBackgroundView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.contentView addSubview:_iconBackgroundView];

    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
    [_iconBackgroundView addSubview:_iconView];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    [self.contentView addSubview:_titleLabel];

    _detailLabel = [UILabel new];
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailLabel.font = [UIFont systemFontOfSize:12.5];
    _detailLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    _detailLabel.numberOfLines = 2;
    [self.contentView addSubview:_detailLabel];

    _sourcePillView = [UIView new];
    _sourcePillView.translatesAutoresizingMaskIntoConstraints = NO;
    _sourcePillView.backgroundColor = [SCIUtils SCIColor_InstagramTertiaryBackground];
    _sourcePillView.layer.cornerRadius = 11.0;
    _sourcePillView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.contentView addSubview:_sourcePillView];

    _sourcePillLabel = [UILabel new];
    _sourcePillLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _sourcePillLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    _sourcePillLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    [_sourcePillView addSubview:_sourcePillLabel];

    _timestampLabel = [UILabel new];
    _timestampLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _timestampLabel.font = [UIFont systemFontOfSize:11.5];
    _timestampLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    [self.contentView addSubview:_timestampLabel];

    _statusView = [UIImageView new];
    _statusView.translatesAutoresizingMaskIntoConstraints = NO;
    _statusView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:_statusView];

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_actionButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_actionButton];

    self.leadingConstraint = [_iconBackgroundView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0];
    [NSLayoutConstraint activateConstraints:@[
        self.leadingConstraint,
        [_iconBackgroundView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_iconBackgroundView.widthAnchor constraintEqualToConstant:52.0],
        [_iconBackgroundView.heightAnchor constraintEqualToConstant:52.0],
        [_iconView.centerXAnchor constraintEqualToAnchor:_iconBackgroundView.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconBackgroundView.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:20.0],
        [_iconView.heightAnchor constraintEqualToConstant:20.0],

        [_actionButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
        [_actionButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_actionButton.widthAnchor constraintEqualToConstant:40.0],
        [_actionButton.heightAnchor constraintEqualToConstant:40.0],

        [_statusView.trailingAnchor constraintEqualToAnchor:_actionButton.leadingAnchor constant:-8.0],
        [_statusView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_statusView.widthAnchor constraintEqualToConstant:16.0],
        [_statusView.heightAnchor constraintEqualToConstant:16.0],

        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconBackgroundView.trailingAnchor constant:12.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_statusView.leadingAnchor constant:-10.0],

        [_detailLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3.0],
        [_detailLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],

        [_sourcePillView.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:6.0],
        [_sourcePillView.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_sourcePillLabel.leadingAnchor constraintEqualToAnchor:_sourcePillView.leadingAnchor constant:8.0],
        [_sourcePillLabel.trailingAnchor constraintEqualToAnchor:_sourcePillView.trailingAnchor constant:-8.0],
        [_sourcePillLabel.topAnchor constraintEqualToAnchor:_sourcePillView.topAnchor constant:4.0],
        [_sourcePillLabel.bottomAnchor constraintEqualToAnchor:_sourcePillView.bottomAnchor constant:-4.0],

        [_timestampLabel.leadingAnchor constraintEqualToAnchor:_sourcePillView.trailingAnchor constant:8.0],
        [_timestampLabel.centerYAnchor constraintEqualToAnchor:_sourcePillView.centerYAnchor],
        [_timestampLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_titleLabel.trailingAnchor],
        [_timestampLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],

        [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:78.0]
    ]];

    UIView *separator = [UIView new];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = [SCIUtils SCIColor_InstagramSeparator];
    [self.contentView addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
        [separator.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:80.0],
        [separator.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
    ]];
    return self;
}

- (void)actionButtonTapped {
    if (self.primaryAction) self.primaryAction();
    else if (self.cancelAction) self.cancelAction();
    else if (self.menuPrimaryAction) self.menuPrimaryAction();
}

- (void)configureWithRow:(NSDictionary *)row {
    NSDictionary *descriptor = row[@"descriptor"] ?: @{};
    NSString *state = row[@"state"] ?: @"queued";
    self.jobID = row[@"id"];
    BOOL isChild = SCIHistoryChildIndex(row) != nil;
    self.leadingConstraint.constant = isChild ? 34.0 : 16.0;

    self.iconBackgroundView.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    self.iconView.image = [SCIAssetUtils instagramIconNamed:SCIHistoryLeadIconName(row) pointSize:20.0 renderingMode:UIImageRenderingModeAlwaysTemplate];

    NSString *title = row[@"title"];
    NSString *username = descriptor[@"username"] ?: descriptor[@"metadata"][@"sourceUsername"];
    if ((title.length == 0 || [title isEqualToString:@"Media download"]) && username.length > 0) {
        title = [username hasPrefix:@"@"] ? username : [@"@" stringByAppendingString:username];
    }
    if (isChild && title.length == 0) {
        NSUInteger childIndex = SCIHistoryChildIndex(row).unsignedIntegerValue + 1;
        title = [NSString stringWithFormat:@"Item %lu", (unsigned long)childIndex];
    }
    self.titleLabel.text = title.length > 0 ? title : @"Media download";

    NSString *detail = row[@"detail"];
    if (detail.length == 0) {
        NSString *destination = descriptor[@"destinationLabel"];
        NSString *mediaKind = descriptor[@"mediaKind"] ?: @"Media";
        detail = destination.length > 0 ? [NSString stringWithFormat:@"%@ · %@", mediaKind, destination] : mediaKind;
    }
    if ([state isEqualToString:@"running"]) {
        detail = detail.length > 0 ? detail : @"In progress";
    } else if ([state isEqualToString:@"queued"]) {
        detail = detail.length > 0 ? detail : @"Queued";
    } else if ([state isEqualToString:@"completed"] && detail.length == 0) {
        detail = @"Completed";
    }
    self.detailLabel.text = detail;

    NSString *sourceLabel = descriptor[@"sourceLabel"];
    self.sourcePillLabel.text = sourceLabel;
    self.sourcePillView.hidden = sourceLabel.length == 0;
    self.timestampLabel.text = SCIHistoryDateString(row[@"createdAt"] ?: descriptor[@"timestamp"] ?: row[@"descriptor"][@"timestamp"]);

    UIImage *statusImage = [SCIAssetUtils instagramIconNamed:SCIHistoryStatusIconName(state) pointSize:18.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    self.statusView.image = statusImage;
    self.statusView.tintColor = SCIHistoryStatusColor(state);

    self.primaryAction = nil;
    self.cancelAction = nil;
    self.menuPrimaryAction = nil;
    self.actionButton.menu = nil;
    self.actionButton.showsMenuAsPrimaryAction = NO;

    if ([[SCIDownloadQueueManager shared] canRetryJob:row] ||
        (SCIHistoryChildIndex(row) && [[SCIDownloadQueueManager shared] canRetryChildAtIndex:SCIHistoryChildIndex(row).unsignedIntegerValue forJob:@{@"descriptor": descriptor[@"_parentDescriptor"] ?: @{}}])) {
        [self.actionButton setImage:[SCIAssetUtils instagramIconNamed:@"arrow_cw" pointSize:20.0 renderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        self.actionButton.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    } else if ([state isEqualToString:@"running"] || [state isEqualToString:@"queued"]) {
        [self.actionButton setImage:[SCIAssetUtils instagramIconNamed:@"xmark" pointSize:20.0 renderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        self.actionButton.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
    } else {
        [self.actionButton setImage:[SCIAssetUtils instagramIconNamed:@"more" pointSize:20.0 renderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        self.actionButton.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
    }
}

@end

@interface SCIDownloadHistoryViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) SCIDownloadFilterChipBar *chipBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *jobs;
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@property (nonatomic, strong) NSMutableSet<NSString *> *expandedJobIDs;
@property (nonatomic, assign) SCIDownloadHistoryFilter selectedFilter;
@end

@implementation SCIDownloadHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Downloads";
    self.selectedFilter = SCIDownloadHistoryFilterAll;
    self.expandedJobIDs = [NSMutableSet set];
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];

    self.chipBar = [SCIDownloadFilterChipBar new];
    self.chipBar.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.chipBar.selectionChanged = ^(NSInteger index) {
        weakSelf.selectedFilter = (SCIDownloadHistoryFilter)index;
        [weakSelf reloadJobs];
    };
    [self.chipBar setTitles:@[@"All", @"Active", @"Queued", @"Failed", @"Recent"] selectedIndex:self.selectedFilter];
    [self.view addSubview:self.chipBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 78.0;
    self.tableView.sectionHeaderTopPadding = 8.0;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.chipBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.chipBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.chipBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.chipBar.heightAnchor constraintEqualToConstant:50.0],

        [self.tableView.topAnchor constraintEqualToAnchor:self.chipBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"more" pointSize:22.0]
                                                                               menu:[self actionsMenu]];
    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"xmark" pointSize:22.0]
                                                                                 style:UIBarButtonItemStylePlain
                                                                                target:self
                                                                                action:@selector(dismissSelf)];
        self.navigationItem.leftBarButtonItem.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(queueChanged:) name:SCIDownloadQueueDidChangeNotification object:nil];
    [self reloadJobs];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)queueChanged:(NSNotification *)note {
    (void)note;
    [self reloadJobs];
}

- (void)dismissSelf {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (NSArray<NSDictionary *> *)rowsByFlatteningActions:(NSArray<NSDictionary *> *)actions {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *job in actions) {
        [rows addObject:job];
        if (![self.expandedJobIDs containsObject:job[@"id"]]) continue;
        NSArray *items = job[@"items"] ?: @[];
        if (items.count <= 1) continue;
        [items enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop) {
            (void)stop;
            NSMutableDictionary *descriptor = [NSMutableDictionary dictionaryWithDictionary:item];
            descriptor[@"_childIndex"] = @(idx);
            descriptor[@"_parentID"] = job[@"id"];
            descriptor[@"_parentDescriptor"] = job[@"descriptor"] ?: @{};
            descriptor[@"timestamp"] = job[@"createdAt"] ?: @(NSDate.date.timeIntervalSince1970);
            [rows addObject:@{
                @"id": [NSString stringWithFormat:@"%@:%lu", job[@"id"], (unsigned long)idx],
                @"title": item[@"title"] ?: [NSString stringWithFormat:@"Item %lu", (unsigned long)(idx + 1)],
                @"detail": item[@"error"] ?: item[@"detail"] ?: @"",
                @"state": item[@"state"] ?: @"queued",
                @"descriptor": descriptor,
                @"createdAt": job[@"createdAt"] ?: @(NSDate.date.timeIntervalSince1970),
                @"localFilePath": item[@"previewPath"] ?: @""
            }];
        }];
    }
    return rows;
}

- (NSArray<NSDictionary *> *)actionsMatchingFilter:(SCIDownloadHistoryFilter)filter {
    NSPredicate *predicate = nil;
    switch (filter) {
        case SCIDownloadHistoryFilterActive:
            predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, id bindings) {
                (void)bindings;
                return [job[@"state"] isEqualToString:@"running"];
            }];
            break;
        case SCIDownloadHistoryFilterQueued:
            predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, id bindings) {
                (void)bindings;
                return [job[@"state"] isEqualToString:@"queued"];
            }];
            break;
        case SCIDownloadHistoryFilterFailed:
            predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, id bindings) {
                (void)bindings;
                return SCIHistoryStateIsFailed(job[@"state"]);
            }];
            break;
        case SCIDownloadHistoryFilterRecent:
            predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, id bindings) {
                (void)bindings;
                return SCIHistoryStateIsRecent(job[@"state"]);
            }];
            break;
        case SCIDownloadHistoryFilterAll:
        default:
            break;
    }
    return predicate ? [self.jobs filteredArrayUsingPredicate:predicate] : self.jobs;
}

- (void)reloadJobs {
    self.jobs = [SCIDownloadQueueManager shared].jobs ?: @[];
    NSMutableArray *sections = [NSMutableArray array];

    if (self.selectedFilter == SCIDownloadHistoryFilterAll) {
        NSArray *active = [self.jobs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, id bindings) {
            (void)bindings;
            return [job[@"state"] isEqualToString:@"running"];
        }]];
        NSArray *queued = [self.jobs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, id bindings) {
            (void)bindings;
            return [job[@"state"] isEqualToString:@"queued"];
        }]];
        NSArray *failed = [self.jobs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, id bindings) {
            (void)bindings;
            return SCIHistoryStateIsFailed(job[@"state"]);
        }]];
        NSArray *recent = [self.jobs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, id bindings) {
            (void)bindings;
            return SCIHistoryStateIsRecent(job[@"state"]);
        }]];

        NSArray *defs = @[
            @{@"title": @"Active", @"actions": active},
            @{@"title": @"Queued", @"actions": queued},
            @{@"title": @"Failed", @"actions": failed},
            @{@"title": @"Recent", @"actions": recent},
        ];
        for (NSDictionary *def in defs) {
            NSArray *rows = [self rowsByFlatteningActions:def[@"actions"]];
            if (rows.count == 0) continue;
            [sections addObject:@{@"title": def[@"title"], @"rows": rows}];
        }
    } else {
        NSArray *actions = [self actionsMatchingFilter:self.selectedFilter];
        [sections addObject:@{@"title": @"", @"rows": [self rowsByFlatteningActions:actions]}];
    }

    self.sections = sections;
    [self.tableView reloadData];
}

- (void)toggleItemsForJobID:(NSString *)jobID {
    if ([self.expandedJobIDs containsObject:jobID]) [self.expandedJobIDs removeObject:jobID];
    else [self.expandedJobIDs addObject:jobID];
    [self reloadJobs];
}

- (NSDictionary *)rowAtIndexPath:(NSIndexPath *)indexPath {
    return self.sections[indexPath.section][@"rows"][indexPath.row];
}

- (void)confirmCancelAllPending {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Cancel pending downloads?"
                                                message:@"This stops queued work and any active downloads that still support cancellation."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Keep" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Cancel All" style:SCIIGAlertActionStyleDestructive handler:^{
            [[SCIDownloadQueueManager shared] cancelAllPending];
        }]
    ]];
}

- (void)confirmClearHistory {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Clear download history?"
                                                message:@"This removes saved history entries and temporary download staging, but does not delete Gallery or Photos media."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Keep" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Clear" style:SCIIGAlertActionStyleDestructive handler:^{
            [[SCIDownloadQueueManager shared] clearHistory];
        }]
    ]];
}

- (BOOL)rowHasOpenResult:(NSDictionary *)row {
    NSNumber *childIndex = SCIHistoryChildIndex(row);
    NSString *path = row[@"localFilePath"];
    if (childIndex) return path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path];
    NSString *completionAction = [[SCIDownloadQueueManager shared] completionActionForJob:row];
    if (completionAction.length > 0 && ![completionAction isEqualToString:@"expand"]) return YES;
    if ([row[@"items"] count] > 1 || [completionAction isEqualToString:@"expand"]) return YES;
    return path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (NSString *)openResultTitleForRow:(NSDictionary *)row {
    NSString *completionAction = [[SCIDownloadQueueManager shared] completionActionForJob:row];
    if ([completionAction isEqualToString:@"openPhotos"]) return @"Open Photos";
    if ([completionAction isEqualToString:@"openGallery"]) return @"Open Gallery";
    if ([row[@"items"] count] > 1 || [completionAction isEqualToString:@"expand"]) {
        return [self.expandedJobIDs containsObject:row[@"id"]] ? @"Hide Items" : @"Show Items";
    }
    return @"Preview";
}

- (UIMenu *)actionsMenu {
    __weak typeof(self) weakSelf = self;
    return [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:@"Retry All Failed" image:[SCIAssetUtils instagramIconNamed:@"arrow_cw" pointSize:18.0] identifier:nil handler:^(__unused UIAction *action) {
            [[SCIDownloadQueueManager shared] retryAllFailed];
        }],
        [UIAction actionWithTitle:@"Cancel All Pending" image:[SCIAssetUtils instagramIconNamed:@"xmark" pointSize:18.0] identifier:nil handler:^(__unused UIAction *action) {
            [weakSelf confirmCancelAllPending];
        }],
        [UIAction actionWithTitle:@"Clear History" image:[SCIAssetUtils instagramIconNamed:@"trash" pointSize:18.0] identifier:nil handler:^(__unused UIAction *action) {
            [weakSelf confirmClearHistory];
        }]
    ]];
}

- (BOOL)openResultForRow:(NSDictionary *)row {
    NSNumber *childIndex = SCIHistoryChildIndex(row);
    NSString *path = row[@"localFilePath"];
    if (childIndex) {
        if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [SCIFullScreenMediaPlayer showFileURL:[NSURL fileURLWithPath:path]];
            return YES;
        }
        return NO;
    }

    NSString *completionAction = [[SCIDownloadQueueManager shared] completionActionForJob:row];
    if (completionAction.length > 0 && ![completionAction isEqualToString:@"expand"]) {
        SCIOpenDownloadCompletionAction(completionAction);
        return YES;
    }
    if ([row[@"items"] count] > 1 || [completionAction isEqualToString:@"expand"]) {
        [self toggleItemsForJobID:row[@"id"]];
        return YES;
    }
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [SCIFullScreenMediaPlayer showFileURL:[NSURL fileURLWithPath:path]];
        return YES;
    }
    return NO;
}

- (UIMenu *)menuForRow:(NSDictionary *)row {
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    NSNumber *childIndex = SCIHistoryChildIndex(row);
    NSString *parentID = SCIHistoryParentID(row);
    NSString *state = row[@"state"];

    if ([self rowHasOpenResult:row]) {
        NSString *completionAction = [[SCIDownloadQueueManager shared] completionActionForJob:row];
        NSString *title = [self openResultTitleForRow:row];
        NSString *iconName = ([completionAction isEqualToString:@"openPhotos"] || [completionAction isEqualToString:@"openGallery"]) ? @"photo_gallery" : (([row[@"items"] count] > 1 || [completionAction isEqualToString:@"expand"]) ? @"list" : @"eye");
        UIImage *icon = [SCIAssetUtils instagramIconNamed:iconName pointSize:18.0];
        [actions addObject:[UIAction actionWithTitle:title image:icon identifier:nil handler:^(__unused UIAction *action) {
            [self openResultForRow:row];
        }]];
    }

    if (childIndex) {
        if ([[SCIDownloadQueueManager shared] canRetryChildAtIndex:childIndex.unsignedIntegerValue forJob:@{@"descriptor": row[@"descriptor"][@"_parentDescriptor"] ?: @{}}]) {
            [actions addObject:[UIAction actionWithTitle:@"Retry Item" image:[SCIAssetUtils instagramIconNamed:@"arrow_cw" pointSize:18.0] identifier:nil handler:^(__unused UIAction *action) {
                [[SCIDownloadQueueManager shared] retryChildAtIndex:childIndex.unsignedIntegerValue forJobID:parentID];
            }]];
        }
        return [UIMenu menuWithChildren:actions];
    }

    if ([[SCIDownloadQueueManager shared] canRetryJob:row]) {
        [actions addObject:[UIAction actionWithTitle:@"Retry" image:[SCIAssetUtils instagramIconNamed:@"arrow_cw" pointSize:18.0] identifier:nil handler:^(__unused UIAction *action) {
            [[SCIDownloadQueueManager shared] retryJobID:row[@"id"]];
        }]];
    }

    if ([row[@"items"] count] > 1) {
        BOOL expanded = [self.expandedJobIDs containsObject:row[@"id"]];
        [actions addObject:[UIAction actionWithTitle:(expanded ? @"Hide Items" : @"Show Items") image:[SCIAssetUtils instagramIconNamed:@"list" pointSize:18.0] identifier:nil handler:^(__unused UIAction *action) {
            [self toggleItemsForJobID:row[@"id"]];
        }]];
    }

    if ([state isEqualToString:@"running"] || [state isEqualToString:@"queued"]) {
        UIAction *cancel = [UIAction actionWithTitle:@"Cancel" image:[SCIAssetUtils instagramIconNamed:@"xmark" pointSize:18.0] identifier:nil handler:^(__unused UIAction *action) {
            [[SCIDownloadQueueManager shared] cancelJobID:row[@"id"]];
        }];
        cancel.attributes = UIMenuElementAttributesDestructive;
        [actions addObject:cancel];
    } else {
        UIAction *remove = [UIAction actionWithTitle:@"Remove from History" image:[SCIAssetUtils instagramIconNamed:@"trash" pointSize:18.0] identifier:nil handler:^(__unused UIAction *action) {
            [[SCIDownloadQueueManager shared] removeJobID:row[@"id"]];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;
        [actions addObject:remove];
    }

    return [UIMenu menuWithChildren:actions];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return MAX(1, self.sections.count);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (self.sections.count == 0) return 0;
    return [self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (self.sections.count == 0) return nil;
    NSString *title = self.sections[section][@"title"];
    return title.length > 0 ? title : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.sections.count == 0 ? @"No downloads yet." : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIDownloadHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"download"];
    if (!cell) cell = [[SCIDownloadHistoryCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"download"];

    NSDictionary *row = [self rowAtIndexPath:indexPath];
    [cell configureWithRow:row];

    NSNumber *childIndex = SCIHistoryChildIndex(row);
    NSString *state = row[@"state"];
    NSString *parentID = SCIHistoryParentID(row);

    if (childIndex) {
        if ([[SCIDownloadQueueManager shared] canRetryChildAtIndex:childIndex.unsignedIntegerValue forJob:@{@"descriptor": row[@"descriptor"][@"_parentDescriptor"] ?: @{}}]) {
            cell.primaryAction = ^{
                [[SCIDownloadQueueManager shared] retryChildAtIndex:childIndex.unsignedIntegerValue forJobID:parentID];
            };
        } else {
            cell.actionButton.menu = [self menuForRow:row];
            cell.actionButton.showsMenuAsPrimaryAction = YES;
        }
    } else if ([[SCIDownloadQueueManager shared] canRetryJob:row]) {
        cell.primaryAction = ^{
            [[SCIDownloadQueueManager shared] retryJobID:row[@"id"]];
        };
    } else if ([state isEqualToString:@"running"] || [state isEqualToString:@"queued"]) {
        cell.cancelAction = ^{
            [[SCIDownloadQueueManager shared] cancelJobID:row[@"id"]];
        };
    } else {
        cell.actionButton.menu = [self menuForRow:row];
        cell.actionButton.showsMenuAsPrimaryAction = YES;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = [self rowAtIndexPath:indexPath];
    NSNumber *childIndex = SCIHistoryChildIndex(row);
    if (childIndex) {
        if ([self openResultForRow:row]) return;
        if ([[SCIDownloadQueueManager shared] canRetryChildAtIndex:childIndex.unsignedIntegerValue forJob:@{@"descriptor": row[@"descriptor"][@"_parentDescriptor"] ?: @{}}]) {
            [[SCIDownloadQueueManager shared] retryChildAtIndex:childIndex.unsignedIntegerValue forJobID:SCIHistoryParentID(row)];
        }
        return;
    }

    NSString *state = row[@"state"];
    if ([self openResultForRow:row]) return;
    if (SCIHistoryStateIsFailed(state) && [[SCIDownloadQueueManager shared] canRetryJob:row]) {
        [SCIIGAlertPresenter presentAlertFromViewController:self
                                                      title:@"Retry download?"
                                                    message:@"This action can be retried with the original request data that is still available."
                                                    actions:@[
            [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
            [SCIIGAlertAction actionWithTitle:@"Retry" style:SCIIGAlertActionStyleDefault handler:^{
                [[SCIDownloadQueueManager shared] retryJobID:row[@"id"]];
            }]
        ]];
    } else if ([state isEqualToString:@"running"] || [state isEqualToString:@"queued"]) {
        if ([row[@"items"] count] > 1) [self toggleItemsForJobID:row[@"id"]];
    }
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    (void)tableView;
    (void)point;
    NSDictionary *row = [self rowAtIndexPath:indexPath];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(__unused NSArray<UIMenuElement *> *suggestedActions) {
        return [self menuForRow:row];
    }];
}

@end

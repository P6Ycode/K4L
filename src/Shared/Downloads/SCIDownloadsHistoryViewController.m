#import "SCIDownloadsHistoryViewController.h"

#import "SCIDownloadService.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "SCIDownloadTypes.h"
#import "../Gallery/SCIGalleryViewController.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../MediaPreview/SCIFullScreenMediaPlayer.h"
#import "../MediaPreview/SCIMediaItem.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../UI/SCIChipBar.h"
#import "../UI/SCIMediaChrome.h"
#import <AVFoundation/AVFoundation.h>

#pragma mark - Helpers

static NSString *SCIDownloadHistoryDisplayUsername(NSString *username) {
    NSString *trimmed = [username stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || trimmed.length > 30) return nil;
    NSString *lower = trimmed.lowercaseString;
    NSSet<NSString *> *blocked = [NSSet setWithArray:@[
        @"more", @"options", @"menu", @"close", @"done", @"cancel", @"all",
        @"active", @"queued", @"failed", @"completed", @"clipboard", @"download",
        @"save", @"share", @"copy", @"gallery", @"photos", @"instants"
    ]];
    if ([blocked containsObject:lower]) return nil;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"] invertedSet];
    return [trimmed rangeOfCharacterFromSet:invalid].location == NSNotFound ? trimmed : nil;
}

static NSCache<NSString *, UIImage *> *SCIDownloadThumbnailCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 100;
    });
    return cache;
}

static void SCIDownloadLoadThumbnailForItem(SCIDownloadItem *item, void (^completion)(UIImage * _Nullable)) {
    if (!item) { completion(nil); return; }
    NSString *path = item.finalPath ?: item.stagedPath;
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { completion(nil); return; }

    UIImage *cached = [SCIDownloadThumbnailCache() objectForKey:item.itemID];
    if (cached) { completion(cached); return; }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *thumb = nil;
        if (item.mediaKind == SCIDownloadMediaKindImage) {
            UIImage *full = [UIImage imageWithContentsOfFile:path];
            if (full) {
                CGFloat s = MIN(200.0 / full.size.width, 200.0 / full.size.height);
                CGSize sz = CGSizeMake(full.size.width * s, full.size.height * s);
                UIGraphicsBeginImageContextWithOptions(sz, NO, 1.0);
                [full drawInRect:CGRectMake(0, 0, sz.width, sz.height)];
                thumb = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            }
        } else if (item.mediaKind == SCIDownloadMediaKindVideo) {
            AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:path]];
            AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
            gen.appliesPreferredTrackTransform = YES;
            gen.maximumSize = CGSizeMake(200.0, 200.0);
            CGImageRef cg = [gen copyCGImageAtTime:CMTimeMake(1, 2) actualTime:NULL error:nil];
            if (cg) { thumb = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        }
        if (thumb) [SCIDownloadThumbnailCache() setObject:thumb forKey:item.itemID];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(thumb); });
    });
}

static NSString *SCIDownloadHistoryDateString(NSTimeInterval timestamp) {
    if (timestamp <= 0) return @"";
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MMM d 'at' h:mm a";
    });
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}

#pragma mark - Row model

typedef NS_ENUM(NSUInteger, SCIDownloadsHistoryRowKind) {
    SCIDownloadsHistoryRowKindJob,
    SCIDownloadsHistoryRowKindChild,
};

@interface SCIDownloadsHistoryRow : NSObject
@property (nonatomic, assign) SCIDownloadsHistoryRowKind kind;
@property (nonatomic, strong) SCIDownloadJob *job;
@property (nonatomic, strong, nullable) SCIDownloadItem *item;
@property (nonatomic, assign) BOOL expanded;
@end
@implementation SCIDownloadsHistoryRow
@end

#pragma mark - Cell

@interface SCIDownloadHistoryCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIImageView *statusBadge;
@property (nonatomic, strong) UIImageView *rowTypeIcon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *technicalLabel;
@property (nonatomic, strong) UIView *pillBackground;
@property (nonatomic, strong) UILabel *pillLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) NSLayoutConstraint *thumbLeading;
@property (nonatomic, copy, nullable) NSString *representedID;
@end

@implementation SCIDownloadHistoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
        self.contentView.backgroundColor = [SCIUtils SCIColor_InstagramBackground];

        UIView *bg = [UIView new];
        bg.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
        self.selectedBackgroundView = bg;

        // Thumbnail 52x52, rounded
        _thumbnailView = [UIImageView new];
        _thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnailView.clipsToBounds = YES;
        _thumbnailView.layer.cornerRadius = 6;
        _thumbnailView.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
        [self.contentView addSubview:_thumbnailView];

        // Status badge (bottom-right of thumbnail)
        _statusBadge = [UIImageView new];
        _statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _statusBadge.contentMode = UIViewContentModeScaleAspectFit;
        _statusBadge.hidden = YES;
        [self.contentView addSubview:_statusBadge];

        // Title
        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];

        // Media type icon (14x14 in the technical row)
        _rowTypeIcon = [UIImageView new];
        _rowTypeIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _rowTypeIcon.contentMode = UIViewContentModeScaleAspectFit;
        _rowTypeIcon.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
        [self.contentView addSubview:_rowTypeIcon];

        // Technical label
        _technicalLabel = [UILabel new];
        _technicalLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _technicalLabel.font = [UIFont systemFontOfSize:12];
        _technicalLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
        _technicalLabel.numberOfLines = 1;
        _technicalLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_technicalLabel];

        // Pill
        _pillBackground = [UIView new];
        _pillBackground.translatesAutoresizingMaskIntoConstraints = NO;
        _pillBackground.backgroundColor = [SCIUtils SCIColor_InstagramTertiaryBackground];
        _pillBackground.layer.cornerRadius = 5;
        _pillBackground.clipsToBounds = YES;
        [self.contentView addSubview:_pillBackground];

        _pillLabel = [UILabel new];
        _pillLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _pillLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _pillLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
        _pillLabel.numberOfLines = 1;
        [_pillBackground addSubview:_pillLabel];

        // Date label
        _dateLabel = [UILabel new];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.font = [UIFont systemFontOfSize:11];
        _dateLabel.textColor = [SCIUtils SCIColor_InstagramTertiaryText];
        _dateLabel.numberOfLines = 1;
        _dateLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_dateLabel];

        _thumbLeading = [_thumbnailView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16];

        [NSLayoutConstraint activateConstraints:@[
            _thumbLeading,
            [_thumbnailView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_thumbnailView.widthAnchor constraintEqualToConstant:52],
            [_thumbnailView.heightAnchor constraintEqualToConstant:52],

            [_statusBadge.trailingAnchor constraintEqualToAnchor:_thumbnailView.trailingAnchor constant:3],
            [_statusBadge.bottomAnchor constraintEqualToAnchor:_thumbnailView.bottomAnchor constant:3],
            [_statusBadge.widthAnchor constraintEqualToConstant:16],
            [_statusBadge.heightAnchor constraintEqualToConstant:16],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_thumbnailView.trailingAnchor constant:12],
            [_titleLabel.topAnchor constraintEqualToAnchor:_thumbnailView.topAnchor constant:-1],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [_rowTypeIcon.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_rowTypeIcon.centerYAnchor constraintEqualToAnchor:_technicalLabel.centerYAnchor],
            [_rowTypeIcon.widthAnchor constraintEqualToConstant:14],
            [_rowTypeIcon.heightAnchor constraintEqualToConstant:14],

            [_technicalLabel.leadingAnchor constraintEqualToAnchor:_rowTypeIcon.trailingAnchor constant:4],
            [_technicalLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3],
            [_technicalLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [_pillBackground.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_pillBackground.topAnchor constraintEqualToAnchor:_technicalLabel.bottomAnchor constant:4],
            [_pillLabel.leadingAnchor constraintEqualToAnchor:_pillBackground.leadingAnchor constant:8],
            [_pillLabel.trailingAnchor constraintEqualToAnchor:_pillBackground.trailingAnchor constant:-8],
            [_pillLabel.topAnchor constraintEqualToAnchor:_pillBackground.topAnchor constant:3],
            [_pillLabel.bottomAnchor constraintEqualToAnchor:_pillBackground.bottomAnchor constant:-3],

            [_dateLabel.leadingAnchor constraintEqualToAnchor:_pillBackground.trailingAnchor constant:8],
            [_dateLabel.centerYAnchor constraintEqualToAnchor:_pillBackground.centerYAnchor],
            [_dateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.thumbnailView.image = nil;
    self.thumbnailView.tintColor = nil;
    self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
    self.statusBadge.image = nil;
    self.statusBadge.hidden = YES;
    self.rowTypeIcon.image = nil;
    self.titleLabel.text = nil;
    self.technicalLabel.text = nil;
    self.pillLabel.text = nil;
    self.pillBackground.hidden = NO;
    self.dateLabel.text = nil;
    self.dateLabel.hidden = NO;
    self.thumbLeading.constant = 16;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.representedID = nil;
}

@end

#pragma mark - View Controller

@interface SCIDownloadsHistoryViewController () <UITableViewDelegate, UITableViewDataSource, SCIChipBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) SCIChipBar *chipBar;
@property (nonatomic, copy)   NSArray<SCIDownloadsHistoryRow *> *rows;
@property (nonatomic, strong) NSMutableSet<NSString *> *expandedJobIDs;
@property (nonatomic, assign) BOOL swipeInProgress;

@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyStateIcon;
@property (nonatomic, strong) UILabel *emptyStateTitle;
@property (nonatomic, strong) UILabel *emptyStateSubtitle;

@property (nonatomic, assign) BOOL lastHasHiddenPill;
@property (nonatomic, assign) BOOL lastHasActiveJobs;
@property (nonatomic, assign) BOOL hasSetInitialTopBarStates;
@end

@implementation SCIDownloadsHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Downloads";
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.expandedJobIDs = [NSMutableSet set];

    // Chrome
    [self updateTopBarItems];
    if (self.navigationController.viewControllers.firstObject == self) {
        SCIMediaChromeSetLeadingTopBarItems(self.navigationItem, @[SCIMediaChromeTopBarButtonItem(@"xmark", self, @selector(close))]);
    }

    // Chip bar
    self.chipBar = [[SCIChipBar alloc] initWithFrame:CGRectZero];
    self.chipBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipBar.delegate = self;
    [self.chipBar setItems:@[@"All", @"Active", @"Queued", @"Failed", @"Recent"]
                   symbols:@[@"download", @"play_filled", @"clock", @"error", @"circle_check"]
           selectedSymbols:@[@"download", @"play_filled", @"clock", @"error_filled", @"circle_check_filled"]];
    self.chipBar.selectedIndex = 0;
    [self.view addSubview:self.chipBar];

    // Table
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 80, 0, 0);
    [self.tableView registerClass:[SCIDownloadHistoryCell class] forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.tableView];

    [self setupEmptyState];

    [NSLayoutConstraint activateConstraints:@[
        [self.chipBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.chipBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.chipBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.chipBar.heightAnchor constraintEqualToConstant:50],

        [self.tableView.topAnchor constraintEqualToAnchor:self.chipBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serviceDidChange) name:SCIDownloadServiceDidChangeNotification object:nil];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        self.navigationController.navigationBar.prefersLargeTitles = NO;
        SCIApplyMediaChromeNavigationBar(self.navigationController.navigationBar);
    }
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Reload (swipe-safe)

- (void)serviceDidChange {
    // Skip full reloads while the user is swiping a row — this prevents
    // the swipe action from snapping back during an active download.
    if (self.swipeInProgress) return;
    [self reload];
}

- (void)reload {
    SCIDownloadHistoryFilter filter = [self currentFilter];
    NSArray<SCIDownloadJob *> *jobs = [[SCIDownloadService shared] jobsMatchingFilter:filter];
    NSMutableArray *rows = [NSMutableArray array];
    for (SCIDownloadJob *job in jobs) {
        SCIDownloadsHistoryRow *parent = [SCIDownloadsHistoryRow new];
        parent.kind = SCIDownloadsHistoryRowKindJob;
        parent.job = job;
        parent.expanded = [self.expandedJobIDs containsObject:job.jobID];
        [rows addObject:parent];
        if (job.items.count > 1 && parent.expanded) {
            for (SCIDownloadItem *item in job.items) {
                SCIDownloadsHistoryRow *child = [SCIDownloadsHistoryRow new];
                child.kind = SCIDownloadsHistoryRowKindChild;
                child.job = job;
                child.item = item;
                [rows addObject:child];
            }
        }
    }
    self.rows = rows;
    [self.tableView reloadData];
    [self updateEmptyState];
    [self updateTopBarItems];
}

- (void)updateTopBarItems {
    BOOL hasHiddenPill = [[SCIDownloadService shared] hasActiveJobWithHiddenPill];

    BOOL hasActiveJobs = NO;
    for (SCIDownloadJob *job in [[SCIDownloadService shared] jobsMatchingFilter:SCIDownloadHistoryFilterAll]) {
        if (job.state == SCIDownloadStateRunning || job.state == SCIDownloadStateQueued || job.state == SCIDownloadStatePending) {
            hasActiveJobs = YES;
            break;
        }
    }

    if (self.hasSetInitialTopBarStates &&
        hasHiddenPill == self.lastHasHiddenPill &&
        hasActiveJobs == self.lastHasActiveJobs) {
        return;
    }

    self.lastHasHiddenPill = hasHiddenPill;
    self.lastHasActiveJobs = hasActiveJobs;
    self.hasSetInitialTopBarStates = YES;

    UIMenu *menu = [self moreMenu];
    UIBarButtonItem *moreItem = SCIMediaChromeTopBarMenuButtonItem(@"more", menu, @"More");
    if (hasHiddenPill) {
        UIBarButtonItem *showProgressItem = SCIMediaChromeTopBarButtonItem(@"play_filled", self, @selector(showProgressTapped));
        SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[showProgressItem, moreItem]);
    } else {
        SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[moreItem]);
    }
}

- (void)showProgressTapped {
    [[SCIDownloadService shared] reshowProgressPill];
    [self reload];
}

- (SCIDownloadHistoryFilter)currentFilter {
    switch (self.chipBar.selectedIndex) {
        case 1: return SCIDownloadHistoryFilterActive;
        case 2: return SCIDownloadHistoryFilterQueued;
        case 3: return SCIDownloadHistoryFilterFailed;
        case 4: return SCIDownloadHistoryFilterRecent;
        default: return SCIDownloadHistoryFilterAll;
    }
}

#pragma mark - Empty state

- (void)setupEmptyState {
    self.emptyStateView = [UIView new];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateView.hidden = YES;
    [self.view addSubview:self.emptyStateView];

    self.emptyStateIcon = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"download" pointSize:96 renderingMode:UIImageRenderingModeAlwaysTemplate]];
    self.emptyStateIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.emptyStateIcon.tintColor = [SCIUtils SCIColor_InstagramTertiaryText];
    [self.emptyStateView addSubview:self.emptyStateIcon];

    self.emptyStateTitle = [UILabel new];
    self.emptyStateTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.emptyStateTitle.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    self.emptyStateTitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateTitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateTitle];

    self.emptyStateSubtitle = [UILabel new];
    self.emptyStateSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateSubtitle.font = [UIFont systemFontOfSize:14];
    self.emptyStateSubtitle.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    self.emptyStateSubtitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateSubtitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateSubtitle];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
        [self.emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40],

        [self.emptyStateIcon.topAnchor constraintEqualToAnchor:self.emptyStateView.topAnchor],
        [self.emptyStateIcon.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
        [self.emptyStateIcon.widthAnchor constraintEqualToConstant:72],
        [self.emptyStateIcon.heightAnchor constraintEqualToConstant:72],

        [self.emptyStateTitle.topAnchor constraintEqualToAnchor:self.emptyStateIcon.bottomAnchor constant:18],
        [self.emptyStateTitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateTitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],

        [self.emptyStateSubtitle.topAnchor constraintEqualToAnchor:self.emptyStateTitle.bottomAnchor constant:6],
        [self.emptyStateSubtitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateSubtitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],
        [self.emptyStateSubtitle.bottomAnchor constraintEqualToAnchor:self.emptyStateView.bottomAnchor],
    ]];
}

- (void)updateEmptyState {
    BOOL empty = (self.rows.count == 0);
    self.emptyStateView.hidden = !empty;
    self.tableView.hidden = empty;
    if (!empty) return;

    self.emptyStateIcon.image = [SCIAssetUtils instagramIconNamed:@"download" pointSize:96 renderingMode:UIImageRenderingModeAlwaysTemplate];
    switch ([self currentFilter]) {
        case SCIDownloadHistoryFilterFailed:
            self.emptyStateTitle.text = @"No failed downloads";
            self.emptyStateSubtitle.text = @"Any download jobs that fail will show up here.";
            break;
        case SCIDownloadHistoryFilterActive:
            self.emptyStateTitle.text = @"No active downloads";
            self.emptyStateSubtitle.text = @"Currently running download tasks will appear here.";
            break;
        case SCIDownloadHistoryFilterQueued:
            self.emptyStateTitle.text = @"Nothing queued";
            self.emptyStateSubtitle.text = @"Downloads waiting in the queue will be listed here.";
            break;
        case SCIDownloadHistoryFilterRecent:
            self.emptyStateTitle.text = @"No recent downloads";
            self.emptyStateSubtitle.text = @"Recently finished or cancelled downloads will show here.";
            break;
        default:
            self.emptyStateTitle.text = @"No downloads yet";
            self.emptyStateSubtitle.text = @"Start downloading media from feeds, reels, or stories to build your history.";
            break;
    }
}

#pragma mark - More menu

- (void)clearFinished {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Clear finished downloads?"
                                                message:@"Active and queued downloads are kept."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Clear Finished" style:SCIIGAlertActionStyleDestructive handler:^{
            [[SCIDownloadService shared] clearFinishedHistory];
            [self reload];
        }],
    ]];
}

- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;
    UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion([weakSelf moreMenuElements]);
    }];
    return [UIMenu menuWithTitle:@"" children:@[deferred]];
}

- (NSArray<UIMenuElement *> *)moreMenuElements {
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *elements = [NSMutableArray array];

    UIAction *clearAction = [UIAction actionWithTitle:@"Clear Finished"
                                                image:[SCIAssetUtils instagramIconNamed:@"trash" pointSize:22 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                           identifier:nil
                                              handler:^(__unused UIAction *a) { [weakSelf clearFinished]; }];
    [elements addObject:clearAction];

    BOOL hasActive = NO;
    for (SCIDownloadJob *job in [[SCIDownloadService shared] jobsMatchingFilter:SCIDownloadHistoryFilterAll]) {
        if (job.state == SCIDownloadStateRunning || job.state == SCIDownloadStateQueued || job.state == SCIDownloadStatePending) {
            hasActive = YES; break;
        }
    }
    if (hasActive) {
        UIAction *cancelAll = [UIAction actionWithTitle:@"Cancel All Active"
                                                  image:[SCIAssetUtils instagramIconNamed:@"xmark" pointSize:22 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                             identifier:nil
                                                handler:^(__unused UIAction *a) { [SCIDownloadService confirmCancelAllActive]; }];
        cancelAll.attributes = UIMenuElementAttributesDestructive;
        [elements addObject:cancelAll];
    }

    NSMutableArray<UIAction *> *nav = [NSMutableArray array];
    [nav addObject:[UIAction actionWithTitle:@"Go to Gallery"
                                       image:[SCIAssetUtils instagramIconNamed:@"media" pointSize:22 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                  identifier:nil
                                     handler:^(__unused UIAction *a) { [SCIGalleryViewController presentGallery]; }]];
    [nav addObject:[UIAction actionWithTitle:@"Open Photos App"
                                       image:[SCIAssetUtils instagramIconNamed:@"photo" pointSize:22 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                  identifier:nil
                                     handler:^(__unused UIAction *a) { [SCIUtils openPhotosApp]; }]];
    [elements addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:nav]];
    return elements;
}

#pragma mark - SCIChipBarDelegate

- (void)chipBar:(SCIChipBar *)bar didSelectIndex:(NSInteger)index {
    (void)bar; (void)index;
    [self reload];
}

#pragma mark - Cell configuration helpers

/// Returns the icon name for the download destination, used as thumbnail placeholder.
static NSString *SCIActionIconForDestination(SCIDownloadDestination dest) {
    switch (dest) {
        case SCIDownloadDestinationPhotos:    return @"photo";
        case SCIDownloadDestinationGallery:   return @"media";
        case SCIDownloadDestinationShare:     return @"share";
        case SCIDownloadDestinationClipboard: return @"copy";
        default:                             return @"download";
    }
}

/// Returns the media-type icon name for the row-type icon.
static NSString *SCIMediaIconName(SCIDownloadMediaKind kind) {
    switch (kind) {
        case SCIDownloadMediaKindVideo: return @"video_filled";
        case SCIDownloadMediaKindAudio: return @"audio";
        default:                       return @"photo_filled";
    }
}

/// Sets the status badge on the cell.
static void SCIApplyStatusBadge(SCIDownloadHistoryCell *cell, SCIDownloadState state) {
    NSString *icon = nil;
    UIColor *color = nil;
    switch (state) {
        case SCIDownloadStateSucceeded:
            icon = @"circle_check_filled";
            color = [UIColor systemGreenColor];
            break;
        case SCIDownloadStateFailed:
        case SCIDownloadStateInterrupted:
            icon = @"error_filled";
            color = [SCIUtils SCIColor_InstagramDestructive];
            break;
        case SCIDownloadStateCancelled:
            icon = @"circle_off";
            color = [SCIUtils SCIColor_InstagramSecondaryText];
            break;
        case SCIDownloadStateRunning:
        case SCIDownloadStateFinalizing:
            icon = @"play_filled";
            color = [SCIUtils SCIColor_Primary];
            break;
        case SCIDownloadStateQueued:
        case SCIDownloadStatePending:
        case SCIDownloadStateWaitingForPreflight:
            icon = @"clock";
            color = [SCIUtils SCIColor_InstagramSecondaryText];
            break;
        case SCIDownloadStatePartial:
            icon = @"error";
            color = [UIColor systemOrangeColor];
            break;
        default: break;
    }
    if (icon) {
        cell.statusBadge.image = [SCIAssetUtils instagramIconNamed:icon pointSize:12];
        cell.statusBadge.tintColor = color;
        cell.statusBadge.hidden = NO;
    } else {
        cell.statusBadge.hidden = YES;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.rows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return self.rows[indexPath.row].kind == SCIDownloadsHistoryRowKindChild ? 60 : 72;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIDownloadHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    SCIDownloadsHistoryRow *row = self.rows[indexPath.row];
    SCIDownloadJob *job = row.job;
    SCIDownloadItem *item = row.item;

    if (row.kind == SCIDownloadsHistoryRowKindChild && item) {
        [self configureCell:cell withChildItem:item job:job];
    } else {
        [self configureCell:cell withJob:job];
    }
    return cell;
}

- (void)configureCell:(SCIDownloadHistoryCell *)cell withJob:(SCIDownloadJob *)job {
    cell.representedID = job.jobID;

    // Title
    cell.titleLabel.text = job.title ?: @"Download";

    // Thumbnail: destination action icon, no tint bleed
    NSString *actionIcon = SCIActionIconForDestination(job.request.destination);
    cell.thumbnailView.contentMode = UIViewContentModeCenter;
    cell.thumbnailView.image = [SCIAssetUtils instagramIconNamed:actionIcon pointSize:24];
    cell.thumbnailView.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];

    // Status badge
    SCIApplyStatusBadge(cell, job.state);

    // Row-type icon (carousel vs media kind)
    if (job.items.count > 1) {
        cell.rowTypeIcon.image = [SCIAssetUtils instagramIconNamed:@"carousel" pointSize:12];
    } else {
        SCIDownloadItem *first = job.items.firstObject;
        cell.rowTypeIcon.image = [SCIAssetUtils instagramIconNamed:SCIMediaIconName(first.mediaKind) pointSize:12];
    }

    // Technical line
    NSMutableArray *parts = [NSMutableArray array];
    NSString *destName = SCIDownloadDestinationDisplayName(job.request.destination);
    [parts addObject:destName];
    if (job.state == SCIDownloadStateRunning || job.state == SCIDownloadStateFinalizing) {
        int pct = MIN(100, MAX(0, (int)(job.aggregateProgress * 100)));
        [parts addObject:[NSString stringWithFormat:@"%d%%", pct]];
    }
    if (job.items.count > 1) {
        [parts addObject:[NSString stringWithFormat:@"%lu items", (unsigned long)job.items.count]];
    } else {
        SCIDownloadItem *first = job.items.firstObject;
        if (first.totalBytesExpected > 0) {
            [parts addObject:[NSByteCountFormatter stringFromByteCount:first.totalBytesExpected countStyle:NSByteCountFormatterCountStyleFile]];
        }
    }
    cell.technicalLabel.text = [parts componentsJoinedByString:@" · "];

    // Pill: source surface
    cell.pillBackground.hidden = NO;
    cell.pillLabel.text = SCIDownloadSourceSurfaceDisplayName(job.request.sourceSurface);

    // Date
    cell.dateLabel.hidden = NO;
    cell.dateLabel.text = SCIDownloadHistoryDateString(job.createdAt);

    cell.accessoryType = job.items.count > 1 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.thumbLeading.constant = 16;
}

- (void)configureCell:(SCIDownloadHistoryCell *)cell withChildItem:(SCIDownloadItem *)item job:(SCIDownloadJob *)job {
    cell.representedID = item.itemID;

    // Title
    NSString *username = SCIDownloadHistoryDisplayUsername(item.metadata.sourceUsername);
    cell.titleLabel.text = username.length > 0 ? username : [NSString stringWithFormat:@"Item %ld", (long)(item.index + 1)];

    // Thumbnail: placeholder then async load
    NSString *mediaIcon = SCIMediaIconName(item.mediaKind);
    cell.thumbnailView.contentMode = UIViewContentModeCenter;
    cell.thumbnailView.image = [SCIAssetUtils instagramIconNamed:mediaIcon pointSize:20];
    cell.thumbnailView.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];

    NSString *targetID = item.itemID;
    __weak typeof(cell) weakCell = cell;
    SCIDownloadLoadThumbnailForItem(item, ^(UIImage *img) {
        if (!img) return;
        SCIDownloadHistoryCell *c = weakCell;
        if (c && [c.representedID isEqualToString:targetID]) {
            c.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
            c.thumbnailView.tintColor = nil;
            c.thumbnailView.image = img;
        }
    });

    // Status badge
    SCIApplyStatusBadge(cell, item.state);

    // Row type icon
    cell.rowTypeIcon.image = [SCIAssetUtils instagramIconNamed:mediaIcon pointSize:12];

    // Technical line
    NSMutableArray *parts = [NSMutableArray array];
    if (item.state == SCIDownloadStateRunning || item.state == SCIDownloadStateFinalizing) {
        int pct = MIN(100, MAX(0, (int)(item.progress * 100)));
        [parts addObject:[NSString stringWithFormat:@"%d%%", pct]];
    }
    if (item.totalBytesExpected > 0) {
        [parts addObject:[NSByteCountFormatter stringFromByteCount:item.totalBytesExpected countStyle:NSByteCountFormatterCountStyleFile]];
    }
    if (item.metadata.pixelWidth > 0 && item.metadata.pixelHeight > 0) {
        [parts addObject:[NSString stringWithFormat:@"%dx%d", (int)item.metadata.pixelWidth, (int)item.metadata.pixelHeight]];
    }
    if (item.metadata.durationSeconds > 0.05) {
        NSInteger total = (NSInteger)llround(item.metadata.durationSeconds);
        [parts addObject:[NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)]];
    }
    cell.technicalLabel.text = parts.count > 0 ? [parts componentsJoinedByString:@" · "] : SCIDownloadDestinationDisplayName(job.request.destination);

    // No pill/date for children
    cell.pillBackground.hidden = YES;
    cell.dateLabel.hidden = YES;

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.thumbLeading.constant = 40;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCIDownloadsHistoryRow *row = self.rows[indexPath.row];

    // Expand/collapse carousel
    if (row.kind == SCIDownloadsHistoryRowKindJob && row.job.items.count > 1) {
        if ([self.expandedJobIDs containsObject:row.job.jobID]) [self.expandedJobIDs removeObject:row.job.jobID];
        else [self.expandedJobIDs addObject:row.job.jobID];
        [self reload];
        return;
    }

    SCIDownloadItem *item = row.item ?: row.job.items.firstObject;
    if (!item) return;

    // Failed/interrupted → show error alert with Retry + Dismiss
    if (item.state == SCIDownloadStateFailed || item.state == SCIDownloadStateInterrupted) {
        NSString *title = item.state == SCIDownloadStateFailed ? @"Download Failed" : @"Download Interrupted";
        NSString *message = item.error.localizedDescription ?: item.detail ?: @"An unknown error occurred.";
        NSString *jobID = row.job.jobID;
        NSString *itemID = item.itemID;
        BOOL isChild = (row.kind == SCIDownloadsHistoryRowKindChild);
        [SCIIGAlertPresenter presentAlertFromViewController:self
                                                      title:title
                                                    message:message
                                                    actions:@[
            [SCIIGAlertAction actionWithTitle:@"Dismiss" style:SCIIGAlertActionStyleCancel handler:nil],
            [SCIIGAlertAction actionWithTitle:@"Retry" style:SCIIGAlertActionStyleDefault handler:^{
                if (isChild) [[SCIDownloadService shared] retryItemID:itemID inJobID:jobID];
                else [[SCIDownloadService shared] retryJobID:jobID];
            }],
        ]];
        return;
    }

    // Completed → preview
    NSString *path = item.finalPath ?: item.stagedPath;
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        SCIMediaItem *media = [SCIMediaItem itemWithFileURL:[NSURL fileURLWithPath:path]];
        [SCIFullScreenMediaPlayer showMediaItems:@[media] startingAtIndex:0 metadata:item.metadata playbackSource:SCIFullScreenPlaybackSourceUnknown sourceView:nil controller:self pausePlayback:nil resumePlayback:nil];
        return;
    }

    if ([row.job.completionAction isEqualToString:@"openGallery"]) [SCIGalleryViewController presentGallery];
    else if ([row.job.completionAction isEqualToString:@"openPhotos"]) [SCIUtils openPhotosApp];
}

#pragma mark - Swipe Actions (swipe-safe)

- (void)tableView:(UITableView *)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    self.swipeInProgress = YES;
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    self.swipeInProgress = NO;
    // Catch up on any notifications we skipped
    [self reload];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(11.0)) {
    (void)tableView;
    if (indexPath.row >= (NSInteger)self.rows.count) return nil;
    SCIDownloadsHistoryRow *row = self.rows[indexPath.row];
    SCIDownloadItem *item = row.item ?: row.job.items.firstObject;
    if (!item) return nil;

    NSMutableArray *actions = [NSMutableArray array];

    // Retry (failed / interrupted / cancelled)
    if (item.state == SCIDownloadStateFailed || item.state == SCIDownloadStateInterrupted || item.state == SCIDownloadStateCancelled) {
        UIContextualAction *retry = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            (void)a; (void)v;
            if (row.kind == SCIDownloadsHistoryRowKindChild) [[SCIDownloadService shared] retryItemID:item.itemID inJobID:row.job.jobID];
            else [[SCIDownloadService shared] retryJobID:row.job.jobID];
            done(YES);
        }];
        retry.image = [SCIAssetUtils instagramIconNamed:@"arrow_cw" pointSize:22 renderingMode:UIImageRenderingModeAlwaysTemplate];
        retry.backgroundColor = [SCIUtils SCIColor_Primary];
        retry.accessibilityLabel = @"Retry";
        [actions addObject:retry];
    }

    // Cancel (active)
    if (!SCIDownloadStateIsTerminal(item.state)) {
        UIContextualAction *cancel = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            (void)a; (void)v;
            if (row.kind == SCIDownloadsHistoryRowKindChild) [[SCIDownloadService shared] cancelItemID:item.itemID inJobID:row.job.jobID];
            else [[SCIDownloadService shared] cancelJobID:row.job.jobID];
            done(YES);
        }];
        cancel.image = [SCIAssetUtils instagramIconNamed:@"xmark" pointSize:22 renderingMode:UIImageRenderingModeAlwaysTemplate];
        cancel.backgroundColor = [SCIUtils SCIColor_InstagramDestructive];
        cancel.accessibilityLabel = @"Cancel";
        [actions addObject:cancel];
    }

    // Remove
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        (void)a; (void)v;
        [[SCIDownloadService shared] removeJobID:row.job.jobID];
        done(YES);
    }];
    remove.image = [SCIAssetUtils instagramIconNamed:@"trash" pointSize:22 renderingMode:UIImageRenderingModeAlwaysTemplate];
    remove.backgroundColor = [SCIUtils SCIColor_InstagramDestructive];
    remove.accessibilityLabel = @"Remove";
    [actions addObject:remove];

    // Copy link
    NSString *link = item.linkString ?: item.request.linkString;
    if (link.length > 0) {
        UIContextualAction *copy = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            (void)a; (void)v;
            UIPasteboard.generalPasteboard.string = link;
            done(YES);
        }];
        copy.image = [SCIAssetUtils instagramIconNamed:@"copy" pointSize:22 renderingMode:UIImageRenderingModeAlwaysTemplate];
        copy.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryText];
        copy.accessibilityLabel = @"Copy Link";
        [actions addObject:copy];
    }

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:actions];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

@end

#import "SCIDownloadsHistoryViewController.h"

#import "SCIDownloadService.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "SCIDownloadTypes.h"
#import "../Gallery/SCIGalleryViewController.h"
#import "../MediaPreview/SCIFullScreenMediaPlayer.h"
#import "../MediaPreview/SCIMediaItem.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"

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

@interface SCIDownloadsHistoryViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, copy) NSArray<SCIDownloadsHistoryRow *> *rows;
@property (nonatomic, strong) NSMutableSet<NSString *> *expandedJobIDs;
@end

@implementation SCIDownloadsHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Downloads";
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.expandedJobIDs = [NSMutableSet set];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear Finished"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(clearFinished)];
    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Active", @"Queued", @"Failed", @"Recent"]];
    self.filterControl.selectedSegmentIndex = 0;
    [self.filterControl addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.filterControl];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.filterControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.tableView.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:SCIDownloadServiceDidChangeNotification object:nil];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (SCIDownloadHistoryFilter)currentFilter {
    switch (self.filterControl.selectedSegmentIndex) {
        case 1: return SCIDownloadHistoryFilterActive;
        case 2: return SCIDownloadHistoryFilterQueued;
        case 3: return SCIDownloadHistoryFilterFailed;
        case 4: return SCIDownloadHistoryFilterRecent;
        default: return SCIDownloadHistoryFilterAll;
    }
}

- (void)filterChanged {
    [self reload];
}

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

- (void)reload {
    NSArray<SCIDownloadJob *> *jobs = [self currentFilter] == SCIDownloadHistoryFilterAll
        ? [[SCIDownloadService shared] jobsMatchingFilter:SCIDownloadHistoryFilterAll]
        : [[SCIDownloadService shared] jobsMatchingFilter:[self currentFilter]];
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
    if (rows.count == 0) {
        self.tableView.backgroundView = [self emptyLabel];
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (UILabel *)emptyLabel {
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    switch ([self currentFilter]) {
        case SCIDownloadHistoryFilterFailed: label.text = @"No failed downloads"; break;
        case SCIDownloadHistoryFilterActive: label.text = @"No active downloads"; break;
        case SCIDownloadHistoryFilterQueued: label.text = @"Nothing queued"; break;
        default: label.text = @"No downloads yet"; break;
    }
    return label;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    SCIDownloadsHistoryRow *row = self.rows[indexPath.row];
    SCIDownloadJob *job = row.job;
    SCIDownloadItem *item = row.item;
    if (row.kind == SCIDownloadsHistoryRowKindChild && item) {
        cell.textLabel.text = [NSString stringWithFormat:@"Item %ld", (long)(item.index + 1)];
        cell.detailTextLabel.text = item.detail ?: SCIDownloadStateDisplayName(item.state);
        cell.imageView.image = [SCIAssetUtils instagramIconNamed:@"download" pointSize:20.0];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    cell.textLabel.text = job.title ?: @"Download";
    NSString *dest = SCIDownloadDestinationDisplayName(job.request.destination);
    NSString *surface = SCIDownloadSourceSurfaceDisplayName(job.request.sourceSurface);
    if (job.items.count > 1) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu items · %@ · %@",
                                   SCIDownloadStateDisplayName(job.state),
                                   (unsigned long)job.items.count,
                                   dest,
                                   surface];
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", SCIDownloadStateDisplayName(job.state), dest, surface];
    }
    cell.imageView.image = [SCIAssetUtils instagramIconNamed:@"download" pointSize:22.0];
    cell.accessoryType = job.items.count > 1 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCIDownloadsHistoryRow *row = self.rows[indexPath.row];
    if (row.kind == SCIDownloadsHistoryRowKindJob && row.job.items.count > 1) {
        if ([self.expandedJobIDs containsObject:row.job.jobID]) [self.expandedJobIDs removeObject:row.job.jobID];
        else [self.expandedJobIDs addObject:row.job.jobID];
        [self reload];
        return;
    }
    SCIDownloadItem *item = row.item ?: row.job.items.firstObject;
    if (item.state == SCIDownloadStateFailed || item.state == SCIDownloadStateInterrupted) {
        [[SCIDownloadService shared] retryItemID:item.itemID inJobID:row.job.jobID];
        return;
    }
    NSString *path = item.finalPath ?: item.stagedPath;
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        SCIMediaItem *media = [SCIMediaItem itemWithFileURL:[NSURL fileURLWithPath:path]];
        [SCIFullScreenMediaPlayer showMediaItems:@[media] startingAtIndex:0 metadata:item.metadata playbackSource:SCIFullScreenPlaybackSourceUnknown sourceView:nil controller:self pausePlayback:nil resumePlayback:nil];
        return;
    }
    if ([row.job.completionAction isEqualToString:@"openGallery"]) [SCIGalleryViewController presentGallery];
    else if ([row.job.completionAction isEqualToString:@"openPhotos"]) [SCIUtils openPhotosApp];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(11.0)) {
    (void)tableView;
    SCIDownloadsHistoryRow *row = self.rows[indexPath.row];
    SCIDownloadItem *item = row.item ?: row.job.items.firstObject;
    NSMutableArray *actions = [NSMutableArray array];
    if (item.state == SCIDownloadStateFailed || item.state == SCIDownloadStateInterrupted || item.state == SCIDownloadStateCancelled) {
        [actions addObject:[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Retry" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            (void)a; (void)v;
            if (row.kind == SCIDownloadsHistoryRowKindChild) [[SCIDownloadService shared] retryItemID:item.itemID inJobID:row.job.jobID];
            else [[SCIDownloadService shared] retryJobID:row.job.jobID];
            done(YES);
        }]];
    }
    if (!SCIDownloadStateIsTerminal(item.state)) {
        [actions addObject:[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Cancel" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            (void)a; (void)v;
            [[SCIDownloadService shared] cancelItemID:item.itemID inJobID:row.job.jobID];
            done(YES);
        }]];
    }
    [actions addObject:[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Remove" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        (void)a; (void)v;
        [[SCIDownloadService shared] removeJobID:row.job.jobID];
        done(YES);
    }]];
    if (item.linkString.length > 0 || item.request.linkString.length > 0) {
        NSString *link = item.linkString ?: item.request.linkString;
        [actions addObject:[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Copy Link" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            (void)a; (void)v;
            UIPasteboard.generalPasteboard.string = link;
            done(YES);
        }]];
    }
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:actions];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

@end

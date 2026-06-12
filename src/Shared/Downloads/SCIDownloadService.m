#import "SCIDownloadService.h"

#import "SCIDownloadPresenter.h"
#import "SCIDownloadScheduler.h"
#import "SCIDownloadsHistoryViewController.h"
#import "../../Utils.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../UI/SCINotificationCenter.h"

@interface SCIDownloadService ()
@property (nonatomic, strong) SCIDownloadScheduler *scheduler;
@property (nonatomic, strong) SCIDownloadPresenter *presenter;
@end

@implementation SCIDownloadService

+ (instancetype)shared {
    static SCIDownloadService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [SCIDownloadService new];
    });
    return service;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _scheduler = [SCIDownloadScheduler new];
    _presenter = [SCIDownloadPresenter new];
    _scheduler.presenter = _presenter;
    _presenter.cancelAllActiveHandler = ^{
        [SCIDownloadService confirmCancelAllActive];
    };
    __weak typeof(self) weakSelf = self;
    _presenter.cancelHandlerForActiveJob = ^(NSString *jobID) {
        [weakSelf confirmCancelForJobID:jobID];
    };
    _presenter.openHistoryForJobID = ^(NSString *jobID) {
        (void)jobID;
        [SCIDownloadService presentDownloadsHistorySheet];
    };
    return self;
}

+ (void)presentDownloadsHistorySheet {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = topMostController();
        if ([presenter isKindOfClass:UINavigationController.class] &&
            [((UINavigationController *)presenter).topViewController isKindOfClass:SCIDownloadsHistoryViewController.class]) {
            return;
        }
        SCIDownloadsHistoryViewController *vc = [SCIDownloadsHistoryViewController new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.prefersGrabberVisible = YES;
        sheet.detents = @[
            UISheetPresentationControllerDetent.mediumDetent,
            UISheetPresentationControllerDetent.largeDetent
        ];
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
        [presenter presentViewController:nav animated:YES completion:nil];
    });
}

+ (void)confirmCancelAllActive {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = topMostController();
        if (!presenter) return;
        [SCIIGAlertPresenter presentAlertFromViewController:presenter
                                                      title:@"Cancel Pending Downloads"
                                                    message:@"This stops queued work and any active downloads that can still be cancelled."
                                                    actions:@[
            [SCIIGAlertAction actionWithTitle:@"Keep" style:SCIIGAlertActionStyleCancel handler:nil],
            [SCIIGAlertAction actionWithTitle:@"Cancel All" style:SCIIGAlertActionStyleDestructive handler:^{
                [[SCIDownloadService shared] cancelAllActive];
            }],
        ]];
    });
}

- (void)cancelAllActive {
    for (SCIDownloadJob *job in [self.scheduler allJobs]) {
        if (job.state == SCIDownloadStateRunning || job.state == SCIDownloadStateQueued || job.state == SCIDownloadStatePending) {
            [self.scheduler cancelJobID:job.jobID];
        }
    }
}

- (void)submitRequest:(SCIDownloadRequest *)request completion:(SCIDownloadSubmissionCompletion)completion {
    if (request.presentationMode != SCIDownloadPresentationModeQuiet) {
        request.notificationIdentifier = request.notificationIdentifier ?: kSCINotificationDownloadLibrary;
        [self.presenter prepareForNewJobSubmission];
    }
    [self.scheduler submitRequest:request completion:completion];
}

- (NSArray<SCIDownloadJob *> *)jobsMatchingFilter:(SCIDownloadHistoryFilter)filter {
    NSArray<SCIDownloadJob *> *jobs = [self.scheduler allJobs];
    NSArray *filtered = [jobs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SCIDownloadJob *job, NSDictionary *bindings) {
        (void)bindings;
        switch (filter) {
            case SCIDownloadHistoryFilterActive:
                return job.state == SCIDownloadStateRunning || job.state == SCIDownloadStateFinalizing;
            case SCIDownloadHistoryFilterQueued:
                return job.state == SCIDownloadStateQueued || job.state == SCIDownloadStatePending;
            case SCIDownloadHistoryFilterFailed:
                return job.state == SCIDownloadStateFailed || job.state == SCIDownloadStatePartial || job.state == SCIDownloadStateInterrupted;
            case SCIDownloadHistoryFilterRecent:
                return job.state == SCIDownloadStateSucceeded || job.state == SCIDownloadStateCancelled;
            default:
                return YES;
        }
    }]];
    return [filtered sortedArrayUsingComparator:^NSComparisonResult(SCIDownloadJob *a, SCIDownloadJob *b) {
        if (a.updatedAt == b.updatedAt) return NSOrderedSame;
        return a.updatedAt < b.updatedAt ? NSOrderedDescending : NSOrderedAscending;
    }];
}

- (SCIDownloadJob *)jobWithID:(NSString *)jobID {
    return [self.scheduler jobWithID:jobID];
}

- (void)cancelJobID:(NSString *)jobID { [self.scheduler cancelJobID:jobID]; }
- (void)cancelItemID:(NSString *)itemID inJobID:(NSString *)jobID { [self.scheduler cancelItemID:itemID inJobID:jobID]; }
- (void)retryJobID:(NSString *)jobID { [self.scheduler retryJobID:jobID]; }
- (void)retryItemID:(NSString *)itemID inJobID:(NSString *)jobID { [self.scheduler retryItemID:itemID inJobID:jobID]; }
- (void)clearFinishedHistory { [self.scheduler clearFinishedHistory]; }
- (void)refreshSettings { [self.scheduler refreshConcurrencyLimit]; }
- (void)removeJobID:(NSString *)jobID { [self.scheduler removeJobID:jobID]; }

- (BOOL)hasActiveJobWithHiddenPill {
    for (SCIDownloadJob *job in [self.scheduler allJobs]) {
        if ([self.presenter jobIsActive:job]) {
            if ([self.presenter hasActiveJobWithoutPillForJobID:job.jobID]) {
                return YES;
            }
        }
    }
    return NO;
}

- (void)reshowProgressPill {
    for (SCIDownloadJob *job in [self.scheduler allJobs]) {
        if ([self.presenter jobIsActive:job]) {
            if ([self.presenter hasActiveJobWithoutPillForJobID:job.jobID]) {
                [self.presenter reshowPillForJob:job];
                break;
            }
        }
    }
}

- (void)confirmCancelForJobID:(NSString *)jobID {
    if (!jobID) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenterHost = topMostController();
        if (!presenterHost) return;
        
        NSUInteger activeCount = 0;
        for (SCIDownloadJob *job in [self.scheduler allJobs]) {
            if ([self.presenter jobIsActive:job]) {
                activeCount++;
            }
        }
        
        NSMutableArray<SCIIGAlertAction *> *actions = [NSMutableArray array];
        
        // Keep at the top, blue bold font
        [actions addObject:[SCIIGAlertAction actionWithTitle:@"Keep" style:SCIIGAlertActionStyleCancel handler:nil]];
        
        if (activeCount > 1) {
            // Cancel current, still blue but not bold
            [actions addObject:[SCIIGAlertAction actionWithTitle:@"Cancel Current" style:SCIIGAlertActionStyleDefault handler:^{
                [self cancelJobID:jobID];
            }]];
            // Cancel all, red, not bold
            [actions addObject:[SCIIGAlertAction actionWithTitle:@"Cancel All" style:SCIIGAlertActionStyleDestructive handler:^{
                [self cancelAllActive];
            }]];
        } else {
            // Cancel, red not bold
            [actions addObject:[SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleDestructive handler:^{
                [self cancelJobID:jobID];
            }]];
        }
        
        [SCIIGAlertPresenter presentAlertFromViewController:presenterHost
                                                      title:@"Cancel Download"
                                                    message:activeCount > 1 ? @"Do you want to cancel the current download or all active downloads?" : @"Are you sure you want to cancel the download?"
                                                    actions:actions];
    });
}

@end

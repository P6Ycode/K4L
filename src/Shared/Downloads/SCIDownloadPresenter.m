#import "SCIDownloadPresenter.h"
#import "SCIDownloadService.h"

#import "SCIDownloadJob.h"
#import "SCIDownloadTypes.h"
#import "../Gallery/SCIGalleryViewController.h"
#import "../UI/SCINotificationCenter.h"
#import "../../Utils.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static UIViewController *SCIDownloadPresenterHost(SCIDownloadJob *job) {
    return job.request.presenter ?: topMostController();
}

static NSArray<NSURL *> *SCIDownloadSucceededFileURLsForJob(SCIDownloadJob *job) {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (SCIDownloadItem *item in job.items) {
        if (item.state != SCIDownloadStateSucceeded) continue;
        NSString *path = item.finalPath ?: item.stagedPath;
        if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [urls addObject:[NSURL fileURLWithPath:path]];
        }
    }
    return urls;
}

@interface SCIDownloadPresenter ()
@property (nonatomic, strong, nullable) SCINotificationPillView *activePill;
@property (nonatomic, copy, nullable) NSString *activeJobID;
@property (nonatomic, assign) NSTimeInterval lastProgressUpdate;
@property (nonatomic, assign) BOOL terminalShownForActiveJob;
@property (nonatomic, assign) BOOL pillDismissedByUser;
@end

@implementation SCIDownloadPresenter

- (BOOL)itemIsInFlight:(SCIDownloadItem *)item {
    switch (item.state) {
        case SCIDownloadStatePending:
        case SCIDownloadStateWaitingForPreflight:
        case SCIDownloadStateQueued:
        case SCIDownloadStateRunning:
        case SCIDownloadStateFinalizing:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)jobIsActive:(SCIDownloadJob *)job {
    if (job.state == SCIDownloadStateRunning || job.state == SCIDownloadStateQueued || job.state == SCIDownloadStateFinalizing) {
        return YES;
    }
    for (SCIDownloadItem *item in job.items) {
        if ([self itemIsInFlight:item]) return YES;
    }
    return NO;
}

- (NSUInteger)completedItemCount:(SCIDownloadJob *)job {
    NSUInteger count = 0;
    for (SCIDownloadItem *item in job.items) {
        if (item.state == SCIDownloadStateSucceeded) count++;
    }
    return count;
}

- (NSString *)progressTitleForJob:(SCIDownloadJob *)job {
    if (job.items.count > 1) {
        NSUInteger current = MIN(job.items.count, [self completedItemCount:job] + 1);
        return [NSString stringWithFormat:@"Downloads [%lu of %lu]", (unsigned long)current, (unsigned long)job.items.count];
    }
    SCIDownloadItem *item = job.items.firstObject;
    if (item.state == SCIDownloadStateFinalizing) {
        return [NSString stringWithFormat:@"Saving to %@", SCIDownloadDestinationDisplayName(job.request.destination)];
    }
    if (item.detail.length > 0) {
        if ([item.detail containsString:@"Merging"] || [item.detail containsString:@"Re-encoding"]) return item.detail;
        if ([item.detail containsString:@"Converting"]) return @"Converting audio";
        if ([item.detail containsString:@"Downloading video"]) return @"Downloading video";
        if ([item.detail containsString:@"Downloading audio"]) return @"Downloading audio";
    }
    switch (item.mediaKind) {
        case SCIDownloadMediaKindVideo: return @"Downloading video";
        case SCIDownloadMediaKindAudio: return @"Downloading audio";
        case SCIDownloadMediaKindImage: return @"Downloading image";
        default: return @"Downloading";
    }
}

- (float)displayProgressForJob:(SCIDownloadJob *)job {
    float progress = (float)job.aggregateProgress;
    SCIDownloadItem *item = job.items.firstObject;
    if (item.state == SCIDownloadStateFinalizing) {
        return fmaxf(progress, 0.97f);
    }
    return progress;
}

- (NSArray<SCIDownloadJob *> *)activeJobsSortedByCreationTime {
    NSArray<SCIDownloadJob *> *allJobs = [[SCIDownloadService shared] jobsMatchingFilter:SCIDownloadHistoryFilterAll];
    NSMutableArray<SCIDownloadJob *> *activeJobs = [NSMutableArray array];
    for (SCIDownloadJob *job in allJobs) {
        if ([self jobIsActive:job]) {
            [activeJobs addObject:job];
        }
    }
    [activeJobs sortUsingComparator:^NSComparisonResult(SCIDownloadJob *a, SCIDownloadJob *b) {
        if (a.createdAt == b.createdAt) return NSOrderedSame;
        return a.createdAt < b.createdAt ? NSOrderedAscending : NSOrderedDescending;
    }];
    return activeJobs;
}

- (NSString *)progressSubtitleForJob:(SCIDownloadJob *)job activeJobsCount:(NSUInteger)activeCount activeJobIndex:(NSUInteger)activeIndex {
    float progress = [self displayProgressForJob:job];
    NSInteger percent = (NSInteger)lroundf(progress * 100.0f);
    percent = MAX(0, MIN(100, percent));
    NSString *percentString = [NSString stringWithFormat:@"%ld%%", (long)percent];

    // Check style
    NSString *style = [NSUserDefaults.standardUserDefaults stringForKey:kSCINotificationProgressSubtitleStyleKey];
    if (style.length == 0) style = @"both";
    if ([style isEqualToString:@"off"]) {
        return nil;
    }

    SCIDownloadItem *primary = job.items.firstObject;
    int64_t bytesWritten = primary.bytesWritten;
    int64_t totalBytesExpected = primary.totalBytesExpected;

    BOOL hasByteTotals = (bytesWritten > 0 && totalBytesExpected > 0);
    NSString *bytesString = nil;
    if (hasByteTotals) {
        NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
        formatter.countStyle = NSByteCountFormatterCountStyleFile;
        formatter.allowedUnits = NSByteCountFormatterUseKB | NSByteCountFormatterUseMB | NSByteCountFormatterUseGB;
        formatter.includesUnit = YES;
        formatter.includesCount = YES;
        formatter.zeroPadsFractionDigits = NO;
        bytesString = [NSString stringWithFormat:@"%@ of %@",
                       [formatter stringFromByteCount:bytesWritten],
                       [formatter stringFromByteCount:totalBytesExpected]];
    }

    NSMutableArray *parts = [NSMutableArray array];
    if ([style isEqualToString:@"percent"]) {
        [parts addObject:percentString];
    } else if ([style isEqualToString:@"bytes"]) {
        if (bytesString) [parts addObject:bytesString];
        else [parts addObject:percentString];
    } else { // @"both" or default
        [parts addObject:percentString];
        if (bytesString) [parts addObject:bytesString];
    }

    if (activeCount > 1) {
        [parts addObject:[NSString stringWithFormat:@"%lu of %lu", (unsigned long)activeIndex, (unsigned long)activeCount]];
    }

    return [parts componentsJoinedByString:@" • "];
}

- (void)handleJobSnapshot:(SCIDownloadJob *)job {
    if (job.request.presentationMode == SCIDownloadPresentationModeQuiet) return;

    NSArray<SCIDownloadJob *> *activeJobs = [self activeJobsSortedByCreationTime];

    if (activeJobs.count > 0) {
        SCIDownloadJob *focusedJob = activeJobs.firstObject;

        if (![focusedJob.jobID isEqualToString:self.activeJobID]) {
            self.activeJobID = focusedJob.jobID;
            self.terminalShownForActiveJob = NO;
        }

        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        BOOL throttle = (now - self.lastProgressUpdate < 0.066) && self.activePill;
        if (!throttle) self.lastProgressUpdate = now;

        if (!self.activePill && !self.pillDismissedByUser) {
            __weak typeof(self) weakSelf = self;
            NSString *identifier = focusedJob.request.notificationIdentifier ?: kSCINotificationDownloadLibrary;
            self.activePill = SCINotifyProgress(identifier, [self progressTitleForJob:focusedJob], ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf && strongSelf.cancelHandlerForActiveJob) {
                    strongSelf.cancelHandlerForActiveJob(strongSelf.activeJobID);
                } else if (weakSelf.cancelAllActiveHandler) {
                    weakSelf.cancelAllActiveHandler();
                }
            });
            self.activePill.onTapWhenProgress = ^{
                if (weakSelf.openHistoryForJobID) weakSelf.openHistoryForJobID(focusedJob.jobID);
            };
            void (^previousDismiss)(void) = [self.activePill.onDidDismiss copy];
            __weak SCINotificationPillView *weakPill = self.activePill;
            self.activePill.onDidDismiss = ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf) {
                    if (strongSelf.activePill == weakPill) {
                        if (!strongSelf.terminalShownForActiveJob) {
                            strongSelf.pillDismissedByUser = YES;
                        }
                        strongSelf.activePill = nil;
                    }
                }
                if (previousDismiss) {
                    previousDismiss();
                }
            };
            throttle = NO;
        }

        if (self.activePill && !throttle) {
            NSUInteger activeIndex = [activeJobs indexOfObject:focusedJob] + 1;
            NSString *title = [self progressTitleForJob:focusedJob];
            NSString *subtitle = [self progressSubtitleForJob:focusedJob activeJobsCount:activeJobs.count activeJobIndex:activeIndex];

            [self.activePill updateProgressTitle:title subtitle:subtitle];

            float progress = [self displayProgressForJob:focusedJob];
            SCIDownloadItem *primary = focusedJob.items.firstObject;
            if (primary.totalBytesExpected > 0 && primary.bytesWritten > 0) {
                [self.activePill setProgress:progress
                                bytesWritten:primary.bytesWritten
                          totalBytesExpected:primary.totalBytesExpected
                                    animated:YES];
            } else {
                [self.activePill setProgress:progress
                                bytesWritten:0
                          totalBytesExpected:0
                                    animated:YES];
            }
        }
    } else {
        if ([job.jobID isEqualToString:self.activeJobID] && self.activePill && !self.terminalShownForActiveJob) {
            [self showTerminalOnActivePillForJob:job];
            self.terminalShownForActiveJob = YES;
        }
    }
}

- (void)presentBatchShareForJob:(SCIDownloadJob *)job {
    NSArray<NSURL *> *urls = SCIDownloadSucceededFileURLsForJob(job);
    if (urls.count == 0) return;
    UIViewController *host = SCIDownloadPresenterHost(job);
    if (!host) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UIView *source = job.request.anchorView ?: host.view;
        activity.popoverPresentationController.sourceView = source;
        activity.popoverPresentationController.sourceRect = source.bounds;
    }
    [host presentViewController:activity animated:YES completion:nil];
}

- (void)copyBatchToClipboardForJob:(SCIDownloadJob *)job {
    NSArray<NSURL *> *urls = SCIDownloadSucceededFileURLsForJob(job);
    if (urls.count == 0) return;
    NSMutableArray *items = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSData *data = [NSData dataWithContentsOfURL:url];
        UTType *type = [UTType typeWithFilenameExtension:url.pathExtension];
        if (data && type.identifier) [items addObject:@{type.identifier: data}];
    }
    if (items.count > 0) UIPasteboard.generalPasteboard.items = items;
}

- (void)showTerminalOnActivePillForJob:(SCIDownloadJob *)job {
    if (!self.activePill) return;
    __weak typeof(self) weakSelf = self;
    NSString *title = @"Download complete";
    NSString *subtitle = @"Tap to open Downloads";
    void (^openHistory)(void) = ^{
        if (weakSelf.openHistoryForJobID) weakSelf.openHistoryForJobID(nil);
    };

    if (job.request.finalizeAsBatchShare && job.state == SCIDownloadStateSucceeded) {
        [self presentBatchShareForJob:job];
    } else if (job.request.finalizeAsBatchClipboard && job.state == SCIDownloadStateSucceeded) {
        [self copyBatchToClipboardForJob:job];
    }

    if (job.state == SCIDownloadStateFailed || job.state == SCIDownloadStatePartial) {
        NSString *message = job.items.firstObject.error.localizedDescription ?: @"Download failed";
        [self.activePill showErrorWithTitle:job.state == SCIDownloadStatePartial ? @"Some downloads failed" : @"Download failed"
                                   subtitle:message
                                       icon:nil];
        self.activePill.onTapWhenCompleted = openHistory;
        return;
    }
    if (job.state == SCIDownloadStateCancelled) {
        [self.activePill showInfoWithTitle:@"Download cancelled" subtitle:@"Tap to open Downloads" icon:nil];
        self.activePill.onTapWhenCompleted = openHistory;
        return;
    }
    if (job.request.destination == SCIDownloadDestinationPhotos) {
        title = @"Saved to Photos";
        subtitle = @"Tap to open Photos";
        self.activePill.onTapWhenCompleted = ^{
            [SCIUtils openPhotosApp];
        };
    } else if (job.request.destination == SCIDownloadDestinationGallery) {
        title = @"Saved to Gallery";
        subtitle = @"Tap to open Gallery";
        self.activePill.onTapWhenCompleted = ^{
            [SCIGalleryViewController presentGallery];
        };
    } else if (job.request.finalizeAsBatchShare) {
        title = [NSString stringWithFormat:@"Shared %lu items", (unsigned long)[self completedItemCount:job]];
        subtitle = @"Tap to open Downloads";
        self.activePill.onTapWhenCompleted = openHistory;
    } else if (job.request.finalizeAsBatchClipboard) {
        title = [NSString stringWithFormat:@"Copied %lu items", (unsigned long)[self completedItemCount:job]];
        subtitle = @"Tap to open Downloads";
        self.activePill.onTapWhenCompleted = openHistory;
    } else if (job.request.destination == SCIDownloadDestinationShare) {
        title = @"Ready to share";
        subtitle = nil;
        self.activePill.onTapWhenCompleted = nil;
    } else if (job.items.count > 1) {
        title = [NSString stringWithFormat:@"%lu items saved", (unsigned long)[self completedItemCount:job]];
        subtitle = @"Tap to open Downloads";
        self.activePill.onTapWhenCompleted = openHistory;
    } else {
        title = @"Download complete";
        subtitle = @"Tap to open Downloads";
        self.activePill.onTapWhenCompleted = openHistory;
    }

    [self.activePill showSuccessWithTitle:title subtitle:subtitle icon:nil];
}

- (void)dismissProgress {
    SCINotificationPillView *oldPill = self.activePill;
    self.activePill = nil;
    [oldPill dismiss];
    self.activeJobID = nil;
    self.terminalShownForActiveJob = NO;
    self.pillDismissedByUser = NO;
}

- (void)prepareForNewJobSubmission {
    self.pillDismissedByUser = NO;
    self.terminalShownForActiveJob = NO;
}

- (BOOL)hasActiveJobWithoutPillForJobID:(NSString *)jobID {
    if ([self.activeJobID isEqualToString:jobID] && self.activePill == nil) {
        return YES;
    }
    if (self.activeJobID == nil && self.activePill == nil) {
        return YES;
    }
    return NO;
}

- (void)reshowPillForJob:(SCIDownloadJob *)job {
    self.activeJobID = job.jobID;
    self.pillDismissedByUser = NO;
    [self handleJobSnapshot:job];
}

@end

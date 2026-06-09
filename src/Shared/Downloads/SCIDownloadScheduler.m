#import "SCIDownloadScheduler.h"

#import "SCIDownloadDestinationWriter.h"
#import "SCIDownloadHelpers.h"
#import "SCIDownloadDuplicatePolicy.h"
#import "SCIDownloadPresenter.h"
#import "SCIDownloadStore.h"
#import "SCIDownloadTransfer.h"
#import "../../Utils.h"
#import "../Audio/SCIAudioDownloadCoordinator.h"
#import "SCIDownloadDuplicatePolicy.h"
#import "../MediaDownload/SCIMediaQualityManager.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGallerySaveMetadata.h"

@interface SCIDownloadActiveTransfer : NSObject
@property (nonatomic, copy) NSString *jobID;
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, strong, nullable) SCIDownloadTransfer *transfer;
@property (nonatomic, copy, nullable) dispatch_block_t cancelHandler;
@end
@implementation SCIDownloadActiveTransfer
@end

@interface SCIDownloadScheduler ()
@property (nonatomic, strong) NSMutableArray<SCIDownloadJob *> *jobs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCIDownloadActiveTransfer *> *activeTransfers;
@property (nonatomic, strong) SCIDownloadDuplicatePolicy *duplicatePolicy;
@property (nonatomic, strong) SCIDownloadDestinationWriter *destinationWriter;
@property (nonatomic, assign) NSInteger concurrencyLimit;
@end

static SCIGalleryMediaType SCIGalleryMediaTypeForDownloadKind(SCIDownloadMediaKind kind) {
    switch (kind) {
        case SCIDownloadMediaKindVideo: return SCIGalleryMediaTypeVideo;
        case SCIDownloadMediaKindAudio: return SCIGalleryMediaTypeAudio;
        default: return SCIGalleryMediaTypeImage;
    }
}

static BOOL SCIDownloadJobHasInFlightItems(SCIDownloadJob *job) {
    for (SCIDownloadItem *item in job.mutableItems) {
        switch (item.state) {
            case SCIDownloadStatePending:
            case SCIDownloadStateWaitingForPreflight:
            case SCIDownloadStateQueued:
            case SCIDownloadStateRunning:
            case SCIDownloadStateFinalizing:
                return YES;
            default:
                break;
        }
    }
    return NO;
}

static NSString *SCIPreferredExtensionForDownloadItem(NSString *stagedPath, NSURL *sourceURL, SCIDownloadItem *item) {
    NSString *extension = item.request.preferredFileExtension;
    if (extension.length == 0) extension = stagedPath.pathExtension;
    if (extension.length == 0) extension = sourceURL.pathExtension;
    if ([extension hasPrefix:@"."]) extension = [extension substringFromIndex:1];
    extension = extension.lowercaseString;

    // Guard against an audio item inheriting a video/container extension (e.g. an
    // audio track extracted from an .mp4). The on-disk file is audio, so its name
    // must reflect that — otherwise it gets misclassified as video everywhere.
    if (item.mediaKind == SCIDownloadMediaKindAudio) {
        static NSSet<NSString *> *audioExts;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            audioExts = [NSSet setWithArray:@[ @"m4a", @"aac", @"mp3", @"wav", @"caf", @"aiff", @"flac", @"opus", @"ogg" ]];
        });
        if (![audioExts containsObject:extension]) extension = @"m4a";
    }

    if (extension.length == 0) {
        switch (item.mediaKind) {
            case SCIDownloadMediaKindVideo: extension = @"mp4"; break;
            case SCIDownloadMediaKindAudio: extension = @"m4a"; break;
            default: extension = @"jpg"; break;
        }
    }
    return extension.length > 0 ? extension : nil;
}

static NSString *SCIRenameStagedPath(NSString *stagedPath, SCIDownloadItem *item, SCIDownloadJob *job) {
    if (!stagedPath.length) return stagedPath;
    SCIGallerySaveMetadata *metadata = item.request.metadata ?: job.request.metadata;
    NSURL *sourceURL = item.request.remoteURLString.length ? [NSURL URLWithString:item.request.remoteURLString] : [NSURL fileURLWithPath:stagedPath];
    NSString *preferred = nil;
    NSString *expectedStem = item.request.expectedFilenameStem;
    if (expectedStem.length > 0) {
        NSString *extension = SCIPreferredExtensionForDownloadItem(stagedPath, sourceURL, item);
        preferred = extension.length > 0 ? [expectedStem stringByAppendingPathExtension:extension] : expectedStem;
    }
    if (preferred.length == 0) {
        preferred = SCIFileNameForMedia(sourceURL, SCIGalleryMediaTypeForDownloadKind(item.mediaKind), metadata);
    }
    if (!preferred.length) return stagedPath;
    NSString *directory = stagedPath.stringByDeletingLastPathComponent;
    NSString *destination = [directory stringByAppendingPathComponent:preferred];
    if ([destination isEqualToString:stagedPath]) return stagedPath;
    [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
    NSError *moveError = nil;
    if ([[NSFileManager defaultManager] moveItemAtPath:stagedPath toPath:destination error:&moveError]) {
        return destination;
    }
    return stagedPath;
}

@implementation SCIDownloadScheduler

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _store = [SCIDownloadStore new];
    _jobs = [[self.store loadJobsMarkingInterrupted:YES] mutableCopy];
    _activeTransfers = [NSMutableDictionary dictionary];
    _duplicatePolicy = [SCIDownloadDuplicatePolicy new];
    _destinationWriter = [SCIDownloadDestinationWriter new];
    [self refreshConcurrencyLimit];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(defaultsChanged) name:NSUserDefaultsDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)defaultsChanged {
    [self refreshConcurrencyLimit];
    [self trimHistory];
}

- (NSArray<SCIDownloadJob *> *)allJobs {
    @synchronized (self) {
        return [[NSArray alloc] initWithArray:self.jobs copyItems:YES];
    }
}

- (SCIDownloadJob *)jobWithID:(NSString *)jobID {
    @synchronized (self) {
        for (SCIDownloadJob *job in self.jobs) {
            if ([job.jobID isEqualToString:jobID]) return [job copy];
        }
    }
    return nil;
}

- (NSInteger)historyLimit {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kSCIDownloadHistoryLimitKey];
    if (value <= 0) value = 300;
    return MAX(50, MIN(1000, value));
}

- (void)refreshConcurrencyLimit {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kSCIDownloadMaxConcurrentKey];
    self.concurrencyLimit = MAX(1, MIN(4, value > 0 ? value : 2));
}

- (void)notifyJob:(SCIDownloadJob *)job itemID:(NSString *)itemID {
    SCIDownloadJob *snapshot = [job copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIDownloadJobDidChangeNotification
                                                            object:self
                                                          userInfo:@{
            SCIDownloadNotificationJobIDKey: job.jobID ?: @"",
            SCIDownloadNotificationItemIDKey: itemID ?: @"",
            SCIDownloadNotificationSnapshotKey: snapshot,
        }];
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIDownloadServiceDidChangeNotification object:self];
        [self.presenter handleJobSnapshot:snapshot];
    });
}

- (void)reportItemProgressForJobID:(NSString *)jobID
                            itemID:(NSString *)itemID
                             block:(void (^)(SCIDownloadItem *))block {
    if (!block) return;
    @synchronized (self) {
        for (SCIDownloadJob *job in self.jobs) {
            if (![job.jobID isEqualToString:jobID]) continue;
            SCIDownloadItem *item = [job itemWithIdentifier:itemID];
            if (!item || SCIDownloadStateIsTerminal(item.state)) return;
            block(item);
            job.updatedAt = NSDate.date.timeIntervalSince1970;
            [job recomputeDerivedState];
            [self notifyJob:job itemID:itemID];
            return;
        }
    }
}

- (void)persist {
    @synchronized (self) {
        BOOL hasActive = NO;
        for (SCIDownloadJob *job in self.jobs) {
            for (SCIDownloadItem *item in job.items) {
                if (!SCIDownloadStateIsTerminal(item.state)) {
                    hasActive = YES;
                    break;
                }
            }
        }
        if (hasActive) {
            [self.store debouncedPersistJobs:[self allJobs]];
        } else {
            [self.store persistJobs:[self allJobs] immediately:YES];
        }
    }
}

- (void)trimHistory {
    @synchronized (self) {
        NSInteger limit = [self historyLimit];
        NSMutableArray *finished = [NSMutableArray array];
        NSMutableArray *active = [NSMutableArray array];
        for (SCIDownloadJob *job in self.jobs) {
            if (SCIDownloadStateIsTerminal(job.state)) [finished addObject:job];
            else [active addObject:job];
        }
        [finished sortUsingComparator:^NSComparisonResult(SCIDownloadJob *a, SCIDownloadJob *b) {
            return a.updatedAt < b.updatedAt ? NSOrderedDescending : NSOrderedAscending;
        }];
        if (finished.count > limit) {
            NSRange trim = NSMakeRange(limit, finished.count - limit);
            [finished removeObjectsInRange:trim];
        }
        self.jobs = [[active arrayByAddingObjectsFromArray:finished] mutableCopy];
        [self.store persistJobs:[self allJobs] immediately:YES];
    }
}

- (void)submitRequest:(SCIDownloadRequest *)request completion:(void (^)(NSString *, NSError *))completion {
    NSString *jobID = NSUUID.UUID.UUIDString;
    SCIDownloadJob *job = [[SCIDownloadJob alloc] initWithRequest:request jobID:jobID];
    NSString *title = [SCIDownloadHelpers historyTitleForRequest:request];
    if (!title.length) {
        title = request.items.count > 1 ? @"Bulk download" : @"Media download";
    }
    job.title = title;
    @synchronized (self) {
        [self.jobs insertObject:job atIndex:0];
    }
    [self.store persistJobs:[self allJobs] immediately:YES];
    __weak typeof(self) weakSelf = self;
    [self.duplicatePolicy runPreflightForRequest:request presenter:request.presenter completion:^(SCIDownloadPreflightResult result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (result == SCIDownloadPreflightCancelled) {
            [strongSelf cancelJobID:jobID];
            SCIDownloadJob *cancelled = [strongSelf jobWithID:jobID];
            if (cancelled) [strongSelf notifyJob:cancelled itemID:nil];
            if (completion) completion(nil, SCIDownloadError(SCIDownloadErrorCancelled, @"Download cancelled.", nil));
            return;
        }
        if (result == SCIDownloadPreflightSkipSucceeded) {
            SCIDownloadDuplicateDestination duplicateDest = SCIDownloadDuplicateDestinationGallery;
            BOOL checksDuplicates = [strongSelf.duplicatePolicy duplicateDestinationFor:request.destination outValue:&duplicateDest];
            NSUInteger queuedCount = 0;
            for (NSUInteger index = 0; index < job.mutableItems.count; index++) {
                SCIDownloadItem *item = job.mutableItems[index];
                SCIDownloadItemRequest *itemRequest = request.items[index];
                BOOL isDuplicate = checksDuplicates && [SCIDownloadDuplicatePolicy hasDuplicateForDestination:duplicateDest
                                                                                                     metadata:itemRequest.metadata ?: request.metadata
                                                                                                    mediaType:[strongSelf.duplicatePolicy mediaTypeForKind:item.mediaKind]];
                if (isDuplicate) {
                    item.state = SCIDownloadStateSucceeded;
                    item.progress = 1.0;
                    item.detail = @"Skipped duplicate";
                } else {
                    [strongSelf transitionItemID:item.itemID jobID:jobID from:SCIDownloadStatePending to:SCIDownloadStateQueued update:nil];
                    queuedCount++;
                }
            }
            [job recomputeDerivedState];
            [strongSelf notifyJob:job itemID:nil];
            [strongSelf persist];
            if (queuedCount > 0) {
                [strongSelf pumpQueue];
            }
            if (completion) completion(jobID, nil);
            return;
        }
        for (SCIDownloadItem *item in job.mutableItems) {
            [strongSelf transitionItemID:item.itemID jobID:jobID from:SCIDownloadStatePending to:SCIDownloadStateQueued update:nil];
        }
        [strongSelf notifyJob:job itemID:nil];
        [strongSelf pumpQueue];
        if (completion) completion(jobID, nil);
    }];
}

- (BOOL)transitionItemID:(NSString *)itemID
                  jobID:(NSString *)jobID
                    from:(SCIDownloadState)expectedState
                      to:(SCIDownloadState)newState
                  update:(void (^)(SCIDownloadMutableItemSnapshot *))update {
    @synchronized (self) {
        SCIDownloadJob *job = nil;
        for (SCIDownloadJob *candidate in self.jobs) {
            if ([candidate.jobID isEqualToString:jobID]) {
                job = candidate;
                break;
            }
        }
        if (!job) return NO;
        SCIDownloadItem *item = [job itemWithIdentifier:itemID];
        if (!item) return NO;
        if (SCIDownloadStateIsTerminal(item.state)) return NO;
        if (item.state != expectedState) return NO;
        if (!SCIDownloadStateAllowsTransition(item.state, newState)) return NO;
        item.state = newState;
        if (update) update((SCIDownloadMutableItemSnapshot *)item);
        job.updatedAt = NSDate.date.timeIntervalSince1970;
        [job recomputeDerivedState];
        [self notifyJob:job itemID:itemID];
        if (SCIDownloadStateIsTerminal(newState)) {
            [self.store persistJobs:[self allJobs] immediately:YES];
        } else {
            [self persist];
        }
        return YES;
    }
}

- (NSUInteger)runningTransferCount {
    return self.activeTransfers.count;
}

- (void)pumpQueue {
    @synchronized (self) {
        if ([self runningTransferCount] >= self.concurrencyLimit) return;
        NSArray *sortedJobs = [self.jobs sortedArrayUsingComparator:^NSComparisonResult(SCIDownloadJob *a, SCIDownloadJob *b) {
            return a.createdAt < b.createdAt ? NSOrderedAscending : NSOrderedDescending;
        }];
        for (SCIDownloadJob *job in sortedJobs) {
            NSArray *sortedItems = [job.mutableItems sortedArrayUsingComparator:^NSComparisonResult(SCIDownloadItem *a, SCIDownloadItem *b) {
                return a.index > b.index ? NSOrderedDescending : NSOrderedAscending;
            }];
            for (SCIDownloadItem *item in sortedItems) {
                if (item.state != SCIDownloadStateQueued) continue;
                if ([self runningTransferCount] >= self.concurrencyLimit) return;
                [self startItem:item job:job];
                if ([self runningTransferCount] >= self.concurrencyLimit) return;
            }
        }
    }
}

- (void)startItem:(SCIDownloadItem *)item job:(SCIDownloadJob *)job {
    SCIDownloadItemRequest *req = item.request;
    if (req.requiresDashMerge && req.remoteURLString.length > 0) {
        [self startDashMergeItem:item job:job];
        return;
    }
    if (req.requiresAudioConversion && req.remoteURLString.length > 0) {
        [self startAudioConversionItem:item job:job];
        return;
    }
    if (req.localSourcePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:req.localSourcePath]) {
        [self transitionItemID:item.itemID jobID:job.jobID from:SCIDownloadStateQueued to:SCIDownloadStateRunning update:^(SCIDownloadMutableItemSnapshot *snap) {
            snap.detail = @"Preparing local file";
            snap.progress = 0.5;
        }];
        NSString *renamed = SCIRenameStagedPath(req.localSourcePath, item, job);
        [self finalizeItem:item job:job stagedPath:renamed];
        return;
    }
    NSURL *url = req.remoteURLString.length ? [NSURL URLWithString:req.remoteURLString] : nil;
    [self transitionItemID:item.itemID jobID:job.jobID from:SCIDownloadStateQueued to:SCIDownloadStateRunning update:^(SCIDownloadMutableItemSnapshot *snap) {
        snap.detail = @"Downloading";
        snap.progress = 0.05;
    }];
    NSString *staging = [SCIDownloadStore stagingDirectoryForJobID:job.jobID];
    SCIDownloadTransfer *transfer = [SCIDownloadTransfer new];
    SCIDownloadActiveTransfer *active = [SCIDownloadActiveTransfer new];
    active.jobID = job.jobID;
    active.itemID = item.itemID;
    active.transfer = transfer;
    self.activeTransfers[item.itemID] = active;
    __weak typeof(self) weakSelf = self;
    [transfer downloadURL:url
               mediaKind:item.mediaKind
            fileExtension:req.preferredFileExtension
               stagingDir:staging
                   itemID:item.itemID
                 progress:^(int64_t written, int64_t expected, double progress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf reportItemProgressForJobID:job.jobID itemID:item.itemID block:^(SCIDownloadItem *snap) {
            snap.bytesWritten = written;
            snap.totalBytesExpected = expected;
            snap.progress = progress;
            snap.detail = @"Downloading";
        }];
    } completion:^(NSString *stagedPath, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.activeTransfers removeObjectForKey:item.itemID];
        if (!stagedPath || error) {
            [strongSelf transitionItemID:item.itemID jobID:job.jobID from:SCIDownloadStateRunning to:SCIDownloadStateFailed update:^(SCIDownloadMutableItemSnapshot *snap) {
                snap.error = error ?: SCIDownloadError(SCIDownloadErrorHTTPFailure, @"Download failed.", nil);
                snap.progress = 1.0;
            }];
            [strongSelf pumpQueue];
            return;
        }
        NSString *renamed = SCIRenameStagedPath(stagedPath, item, job);
        [strongSelf finalizeItem:item job:job stagedPath:renamed];
    }];
}

- (void)startDashMergeItem:(SCIDownloadItem *)item job:(SCIDownloadJob *)job {
    SCIDownloadItemRequest *req = item.request;
    NSURL *primary = [NSURL URLWithString:req.remoteURLString];
    NSURL *secondary = req.dashSecondaryURLString.length ? [NSURL URLWithString:req.dashSecondaryURLString] : nil;
    if (!primary) {
        [self transitionItemID:item.itemID jobID:job.jobID from:SCIDownloadStateQueued to:SCIDownloadStateFailed update:^(SCIDownloadMutableItemSnapshot *snap) {
            snap.error = SCIDownloadError(SCIDownloadErrorInvalidURL, @"Invalid media URL.", nil);
            snap.progress = 1.0;
        }];
        [self pumpQueue];
        return;
    }
    [self transitionItemID:item.itemID jobID:job.jobID from:SCIDownloadStateQueued to:SCIDownloadStateRunning update:^(SCIDownloadMutableItemSnapshot *snap) {
        snap.progress = 0.05;
        snap.detail = @"Preparing media";
        snap.bytesWritten = 0;
        snap.totalBytesExpected = 0;
    }];
    NSString *basename = req.expectedFilenameStem.length > 0 ? req.expectedFilenameStem : NSUUID.UUID.UUIDString;
    SCIDownloadActiveTransfer *active = [SCIDownloadActiveTransfer new];
    active.jobID = job.jobID;
    active.itemID = item.itemID;
    self.activeTransfers[item.itemID] = active;

    __weak typeof(self) weakSelf = self;
    NSString *jobID = job.jobID;
    NSString *itemID = item.itemID;
    [SCIMediaQualityManager runDashDownloadWithPrimaryURL:primary
                                             secondaryURL:secondary
                                               optionKind:req.dashOptionKind
                                                 basename:basename
                                                 duration:req.dashDuration
                                                    width:req.dashWidth
                                                   height:req.dashHeight
                                            sourceBitrate:req.dashBandwidth
                                                extension:req.preferredFileExtension ?: @"mp4"
                                                 progress:^(float progress, NSString *stageTitle, int64_t bytesWritten, int64_t totalBytesExpected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf reportItemProgressForJobID:jobID itemID:itemID block:^(SCIDownloadItem *snap) {
                snap.progress = progress;
                snap.detail = stageTitle;
                snap.bytesWritten = bytesWritten;
                snap.totalBytesExpected = totalBytesExpected;
            }];
        });
    }
                                                  failure:^(NSString *title, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.activeTransfers removeObjectForKey:itemID];
            [weakSelf transitionItemID:itemID jobID:jobID from:SCIDownloadStateRunning to:SCIDownloadStateFailed update:^(SCIDownloadMutableItemSnapshot *snap) {
                snap.error = SCIDownloadError(SCIDownloadErrorHTTPFailure, message ?: title, nil);
                snap.progress = 1.0;
                snap.detail = title;
            }];
            [weakSelf pumpQueue];
        });
    }
                                                  success:^(NSURL *outputURL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.activeTransfers removeObjectForKey:itemID];
            SCIDownloadJob *liveJob = nil;
            SCIDownloadItem *liveItem = nil;
            @synchronized (weakSelf) {
                for (SCIDownloadJob *j in weakSelf.jobs) {
                    if ([j.jobID isEqualToString:jobID]) {
                        liveJob = j;
                        liveItem = [j itemWithIdentifier:itemID];
                        break;
                    }
                }
            }
            if (liveJob && liveItem) {
                if (SCIDownloadStateIsTerminal(liveItem.state)) {
                    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
                    [weakSelf pumpQueue];
                    return;
                }
                NSString *renamed = SCIRenameStagedPath(outputURL.path, liveItem, liveJob);
                [weakSelf finalizeItem:liveItem job:liveJob stagedPath:renamed];
            }
            else [weakSelf pumpQueue];
        });
    }
                                                cancelOut:^(dispatch_block_t cancelBlock) {
        active.cancelHandler = cancelBlock;
    }];
}

- (void)startAudioConversionItem:(SCIDownloadItem *)item job:(SCIDownloadJob *)job {
    SCIDownloadItemRequest *req = item.request;
    NSURL *url = [NSURL URLWithString:req.remoteURLString];
    if (!url) {
        [self transitionItemID:item.itemID jobID:job.jobID from:SCIDownloadStateQueued to:SCIDownloadStateFailed update:^(SCIDownloadMutableItemSnapshot *snap) {
            snap.error = SCIDownloadError(SCIDownloadErrorInvalidURL, @"Invalid audio URL.", nil);
            snap.progress = 1.0;
        }];
        [self pumpQueue];
        return;
    }
    [self transitionItemID:item.itemID jobID:job.jobID from:SCIDownloadStateQueued to:SCIDownloadStateRunning update:^(SCIDownloadMutableItemSnapshot *snap) {
        snap.progress = 0.05;
        snap.detail = @"Downloading audio";
    }];
    NSString *basename = req.audioProcessingBasename.length > 0 ? req.audioProcessingBasename : NSUUID.UUID.UUIDString;
    NSString *staging = [SCIDownloadStore stagingDirectoryForJobID:job.jobID];
    [[NSFileManager defaultManager] createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:nil];

    SCIDownloadActiveTransfer *active = [SCIDownloadActiveTransfer new];
    active.jobID = job.jobID;
    active.itemID = item.itemID;
    __block NSURLSessionDownloadTask *task = nil;
    __block NSURLSession *session = nil;
    active.cancelHandler = ^{
        [task cancel];
        [session invalidateAndCancel];
    };
    self.activeTransfers[item.itemID] = active;

    __weak typeof(self) weakSelf = self;
    NSString *jobID = job.jobID;
    NSString *itemID = item.itemID;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    session = [NSURLSession sessionWithConfiguration:config];
    task = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        (void)response;
        __block NSURL *rawURL = nil;
        if (location && !error) {
            NSString *ext = url.pathExtension.length > 0 ? url.pathExtension : @"m4a";
            rawURL = [NSURL fileURLWithPath:[staging stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-raw.%@", itemID, ext]]];
            [[NSFileManager defaultManager] removeItemAtURL:rawURL error:nil];
            if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:rawURL error:nil]) {
                rawURL = nil;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error || !rawURL) {
                [strongSelf.activeTransfers removeObjectForKey:itemID];
                [strongSelf transitionItemID:itemID jobID:jobID from:SCIDownloadStateRunning to:SCIDownloadStateFailed update:^(SCIDownloadMutableItemSnapshot *snap) {
                    snap.error = error ?: SCIDownloadError(SCIDownloadErrorHTTPFailure, @"Audio download failed.", nil);
                    snap.progress = 1.0;
                }];
                [strongSelf pumpQueue];
                return;
            }
            [strongSelf reportItemProgressForJobID:jobID itemID:itemID block:^(SCIDownloadItem *snap) {
                snap.progress = 0.72;
                snap.detail = @"Converting audio";
                snap.bytesWritten = 0;
                snap.totalBytesExpected = 0;
            }];
            [SCIAudioDownloadCoordinator convertAudioAtURL:rawURL basename:basename progress:^(float convertProgress, NSString *title) {
                [strongSelf reportItemProgressForJobID:jobID itemID:itemID block:^(SCIDownloadItem *snap) {
                    snap.progress = 0.72 + (convertProgress * 0.23);
                    snap.detail = title.length > 0 ? title : @"Converting audio";
                    snap.bytesWritten = 0;
                    snap.totalBytesExpected = 0;
                }];
            } completion:^(NSURL *outputURL, NSError *convertError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf.activeTransfers removeObjectForKey:itemID];
                    if (!outputURL || convertError) {
                        [strongSelf transitionItemID:itemID jobID:jobID from:SCIDownloadStateRunning to:SCIDownloadStateFailed update:^(SCIDownloadMutableItemSnapshot *snap) {
                            snap.error = convertError ?: SCIDownloadError(SCIDownloadErrorHTTPFailure, @"Audio conversion failed.", nil);
                            snap.progress = 1.0;
                        }];
                        [strongSelf pumpQueue];
                        return;
                    }
                    NSString *dest = [staging stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", itemID]];
                    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
                    NSError *moveError = nil;
                    if (![[NSFileManager defaultManager] moveItemAtURL:outputURL toURL:[NSURL fileURLWithPath:dest] error:&moveError]) {
                        dest = outputURL.path;
                    }
                    SCIDownloadJob *liveJob = nil;
                    SCIDownloadItem *liveItem = nil;
                    @synchronized (strongSelf) {
                        for (SCIDownloadJob *j in strongSelf.jobs) {
                            if ([j.jobID isEqualToString:jobID]) {
                                liveJob = j;
                                liveItem = [j itemWithIdentifier:itemID];
                                break;
                            }
                        }
                    }
                    if (liveJob && liveItem) {
                        if (SCIDownloadStateIsTerminal(liveItem.state)) {
                            [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
                            [strongSelf pumpQueue];
                            return;
                        }
                        NSString *renamed = SCIRenameStagedPath(dest, liveItem, liveJob);
                        [strongSelf finalizeItem:liveItem job:liveJob stagedPath:renamed];
                    }
                    else [strongSelf pumpQueue];
                });
            }];
        });
    }];
    [task resume];
}

- (void)finalizeItem:(SCIDownloadItem *)item job:(SCIDownloadJob *)job stagedPath:(NSString *)stagedPath {
    [self transitionItemID:item.itemID jobID:job.jobID from:item.state to:SCIDownloadStateFinalizing update:^(SCIDownloadMutableItemSnapshot *snap) {
        snap.stagedPath = stagedPath;
        snap.progress = 0.97;
        snap.detail = [NSString stringWithFormat:@"Saving to %@", SCIDownloadDestinationDisplayName(job.request.destination)];
    }];
    __weak typeof(self) weakSelf = self;
    [self.destinationWriter finalizeFileAtPath:stagedPath
                                       request:job.request
                                    itemRequest:item.request
                                     presenter:job.request.presenter
                                    anchorView:job.request.anchorView
                                    completion:^(NSString *finalPath, NSString *photosAssetID, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            [strongSelf transitionItemID:item.itemID jobID:job.jobID from:SCIDownloadStateFinalizing to:SCIDownloadStateFailed update:^(SCIDownloadMutableItemSnapshot *snap) {
                snap.error = error;
                snap.progress = 1.0;
            }];
        } else {
            [strongSelf transitionItemID:item.itemID jobID:job.jobID from:SCIDownloadStateFinalizing to:SCIDownloadStateSucceeded update:^(SCIDownloadMutableItemSnapshot *snap) {
                snap.finalPath = finalPath;
                snap.photosAssetIdentifier = photosAssetID;
                snap.progress = 1.0;
                snap.detail = @"Completed";
            }];
        }
        [strongSelf pumpQueue];
        [strongSelf trimHistory];
        });
    }];
}

- (void)cancelJobID:(NSString *)jobID {
    @synchronized (self) {
        for (SCIDownloadJob *job in self.jobs) {
            if (![job.jobID isEqualToString:jobID]) continue;
            for (SCIDownloadItem *item in job.mutableItems) {
                [self cancelItemInternal:item job:job];
            }
            [job recomputeDerivedState];
        }
    }
    [self pumpQueue];
    SCIDownloadJob *snapshot = [self jobWithID:jobID];
    if (snapshot) [self notifyJob:snapshot itemID:nil];
}

- (void)cancelItemID:(NSString *)itemID inJobID:(NSString *)jobID {
    @synchronized (self) {
        for (SCIDownloadJob *job in self.jobs) {
            if (![job.jobID isEqualToString:jobID]) continue;
            SCIDownloadItem *item = [job itemWithIdentifier:itemID];
            if (item) [self cancelItemInternal:item job:job];
        }
    }
    [self pumpQueue];
}

- (void)cancelItemInternal:(SCIDownloadItem *)item job:(SCIDownloadJob *)job {
    if (SCIDownloadStateIsTerminal(item.state)) return;
    SCIDownloadActiveTransfer *active = self.activeTransfers[item.itemID];
    if (active) {
        [active.transfer cancel];
        if (active.cancelHandler) active.cancelHandler();
        [self.activeTransfers removeObjectForKey:item.itemID];
    }
    SCIDownloadState from = item.state;
    if (![self transitionItemID:item.itemID jobID:job.jobID from:from to:SCIDownloadStateCancelled update:^(SCIDownloadMutableItemSnapshot *snap) {
        snap.error = SCIDownloadError(SCIDownloadErrorCancelled, @"Download cancelled.", nil);
        snap.progress = 1.0;
        snap.detail = @"Cancelled";
    }]) {
        item.state = SCIDownloadStateCancelled;
        item.error = SCIDownloadError(SCIDownloadErrorCancelled, @"Download cancelled.", nil);
        item.progress = 1.0;
        item.detail = @"Cancelled";
        [job recomputeDerivedState];
        [self notifyJob:job itemID:item.itemID];
        [self persist];
    }
}

- (void)retryJobID:(NSString *)jobID {
    @synchronized (self) {
        for (SCIDownloadJob *job in self.jobs) {
            if (![job.jobID isEqualToString:jobID]) continue;
            for (SCIDownloadItem *item in job.mutableItems) {
                if (item.state == SCIDownloadStateFailed || item.state == SCIDownloadStateCancelled || item.state == SCIDownloadStateInterrupted) {
                    item.state = SCIDownloadStateQueued;
                    item.progress = 0;
                    item.error = nil;
                    item.stagedPath = nil;
                }
            }
            [job recomputeDerivedState];
            [self notifyJob:job itemID:nil];
        }
    }
    [self pumpQueue];
}

- (void)retryItemID:(NSString *)itemID inJobID:(NSString *)jobID {
    @synchronized (self) {
        for (SCIDownloadJob *job in self.jobs) {
            if (![job.jobID isEqualToString:jobID]) continue;
            SCIDownloadItem *item = [job itemWithIdentifier:itemID];
            if (!item) continue;
            item.state = SCIDownloadStateQueued;
            item.progress = 0;
            item.error = nil;
            item.stagedPath = nil;
            [job recomputeDerivedState];
            [self notifyJob:job itemID:itemID];
        }
    }
    [self pumpQueue];
}

- (void)clearFinishedHistory {
    @synchronized (self) {
        NSMutableArray *remaining = [NSMutableArray array];
        for (SCIDownloadJob *job in self.jobs) {
            if (SCIDownloadJobHasInFlightItems(job)) {
                [remaining addObject:job];
            }
        }
        self.jobs = remaining;
    }
    [self.store persistJobs:[self allJobs] immediately:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIDownloadServiceDidChangeNotification object:self];
}

- (void)removeJobID:(NSString *)jobID {
    @synchronized (self) {
        NSIndexSet *indexes = [self.jobs indexesOfObjectsPassingTest:^BOOL(SCIDownloadJob *obj, NSUInteger idx, BOOL *stop) {
            (void)idx;
            return [obj.jobID isEqualToString:jobID];
        }];
        if (indexes.count) [self.jobs removeObjectsAtIndexes:indexes];
    }
    [self.store persistJobs:[self allJobs] immediately:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIDownloadServiceDidChangeNotification object:self];
}

@end

#import "Download.h"
#import "../Utils.h"
#import "../Shared/Gallery/SCIGalleryFile.h"
#import "../Shared/Gallery/SCIGallerySaveMetadata.h"
#import "../Shared/Gallery/SCIGalleryViewController.h"
#import "../Shared/MediaDownload/SCIDownloadDuplicateTracker.h"
#import "../Shared/MediaDownload/SCIDownloadQueueManager.h"
#import <Photos/Photos.h>

@implementation SCIDownloadDelegate

static NSCountedSet *SCIActiveDownloadDelegates(void) {
    static NSCountedSet *delegates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegates = [NSCountedSet set];
    });
    return delegates;
}

static void SCIRetainActiveDownloadDelegate(SCIDownloadDelegate *delegate) {
    if (!delegate || delegate.retainedForOperation) return;
    @synchronized (SCIActiveDownloadDelegates()) {
        [SCIActiveDownloadDelegates() addObject:delegate];
    }
    delegate.retainedForOperation = YES;
}

static void SCIReleaseActiveDownloadDelegate(SCIDownloadDelegate *delegate) {
    if (!delegate || !delegate.retainedForOperation) {
        return;
    }
    @synchronized (SCIActiveDownloadDelegates()) {
        [SCIActiveDownloadDelegates() removeObject:delegate];
    }
    delegate.retainedForOperation = NO;
}

static void SCIInvokeDownloadCompletion(SCIDownloadDelegate *delegate, NSURL *fileURL, NSError *error) {
    SCIDownloadCompletionBlock completion = [delegate.completionBlock copy];
    delegate.completionBlock = nil;
    if (completion) {
        completion(fileURL, error);
    }
}

static NSError *SCIDownloadErrorWithDescription(NSString *description, NSInteger code) {
    return [NSError errorWithDomain:@"SCInsta.Download"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @"Download failed"}];
}

static NSString *SCIDownloadDefaultNotificationIdentifier(DownloadAction action) {
    switch (action) {
        case share:
            return kSCINotificationDownloadShare;
        case saveToGallery:
            return kSCINotificationDownloadGallery;
        case saveToPhotos:
        case downloadOnly:
        default:
            return kSCINotificationDownloadLibrary;
    }
}

static NSDictionary *SCIDownloadMetadataDescriptor(SCIGallerySaveMetadata *metadata) {
    if (!metadata) return @{};
    NSMutableDictionary *descriptor = [NSMutableDictionary dictionary];
    descriptor[@"source"] = @(metadata.source);
    if (metadata.sourceUsername) descriptor[@"sourceUsername"] = metadata.sourceUsername;
    if (metadata.sourceUserPK) descriptor[@"sourceUserPK"] = metadata.sourceUserPK;
    if (metadata.sourceMediaPK) descriptor[@"sourceMediaPK"] = metadata.sourceMediaPK;
    if (metadata.sourceMediaCode) descriptor[@"sourceMediaCode"] = metadata.sourceMediaCode;
    if (metadata.sourceMediaURLString) descriptor[@"sourceMediaURLString"] = metadata.sourceMediaURLString;
    return descriptor;
}

static SCIGallerySaveMetadata *SCIDownloadMetadataFromDescriptor(NSDictionary *descriptor) {
    if (![descriptor isKindOfClass:NSDictionary.class] || descriptor.count == 0) return nil;
    SCIGallerySaveMetadata *metadata = [SCIGallerySaveMetadata new];
    metadata.source = [descriptor[@"source"] shortValue];
    metadata.sourceUsername = descriptor[@"sourceUsername"];
    metadata.sourceUserPK = descriptor[@"sourceUserPK"];
    metadata.sourceMediaPK = descriptor[@"sourceMediaPK"];
    metadata.sourceMediaCode = descriptor[@"sourceMediaCode"];
    metadata.sourceMediaURLString = descriptor[@"sourceMediaURLString"];
    return metadata;
}

static NSString *SCIDownloadDestinationLabel(DownloadAction action) {
    switch (action) {
        case saveToPhotos: return @"Photos";
        case saveToGallery: return @"Gallery";
        case share: return @"Share";
        case downloadOnly: return @"Download";
    }
}

static NSString *SCIDownloadCompletionAction(DownloadAction action) {
    switch (action) {
        case saveToPhotos: return @"openPhotos";
        case saveToGallery: return @"openGallery";
        default: return nil;
    }
}

static NSString *SCIDownloadMediaKindForExtension(NSString *fileExtension) {
    NSString *extension = fileExtension.lowercaseString;
    if ([SCIDownloadDelegate isAudioFileAtURL:[NSURL fileURLWithPath:[@"file." stringByAppendingString:extension ?: @""]]]) return @"Audio";
    if ([SCIDownloadDelegate isVideoFileAtURL:[NSURL fileURLWithPath:[@"file." stringByAppendingString:extension ?: @""]]]) return @"Video";
    return @"Image";
}

static NSString *SCIDownloadDisplayTitle(SCIGallerySaveMetadata *metadata, NSString *fallback) {
    if (metadata.sourceUsername.length > 0) {
        return [metadata.sourceUsername hasPrefix:@"@"] ? metadata.sourceUsername : [@"@" stringByAppendingString:metadata.sourceUsername];
    }
    return fallback.length > 0 ? fallback : @"Media download";
}

static void SCIDownloadPresentAfterPillDismiss(dispatch_block_t presentation) {
    if (!presentation) return;
    dispatch_async(dispatch_get_main_queue(), presentation);
}

static NSMutableDictionary *SCIDownloadUserDescriptor(SCIDownloadDelegate *delegate, NSString *fileExtension) {
    SCIGallerySaveMetadata *metadata = delegate.pendingGallerySaveMetadata;
    NSMutableDictionary *descriptor = [NSMutableDictionary dictionary];
    descriptor[@"metadata"] = SCIDownloadMetadataDescriptor(metadata);
    descriptor[@"mediaKind"] = SCIDownloadMediaKindForExtension(fileExtension);
    descriptor[@"destinationLabel"] = SCIDownloadDestinationLabel(delegate.action);
    descriptor[@"sourceLabel"] = [SCIGalleryFile shortLabelForSource:(SCIGallerySource)metadata.source] ?: @"Other";
    if (metadata.sourceUsername.length > 0) descriptor[@"username"] = metadata.sourceUsername;
    NSString *completionAction = SCIDownloadCompletionAction(delegate.action);
    if (completionAction.length > 0) descriptor[@"completionAction"] = completionAction;
    return descriptor;
}

+ (BOOL)isVideoFileAtURL:(NSURL *)fileURL {
    NSString *ext = fileURL.pathExtension.lowercaseString;
    NSSet<NSString *> *videoExtensions = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"avi", @"webm", @"mkv", @"3gp"]];
    return [videoExtensions containsObject:ext];
}

+ (BOOL)isAudioFileAtURL:(NSURL *)fileURL {
    NSString *ext = fileURL.pathExtension.lowercaseString;
    NSSet<NSString *> *audioExtensions = [NSSet setWithArray:@[@"m4a", @"aac", @"mp3", @"wav", @"caf", @"aiff", @"flac", @"opus", @"ogg"]];
    return [audioExtensions containsObject:ext];
}

+ (SCIGallerySaveMetadata *)metadataFromDescriptor:(NSDictionary *)descriptor {
    return SCIDownloadMetadataFromDescriptor(descriptor);
}

+ (void)saveFileURLToPhotos:(NSURL *)fileURL completion:(void(^)(BOOL success, NSError *error))completion {
    [self saveFileURLToPhotos:fileURL metadata:nil completion:completion];
}

+ (void)saveFileURLToPhotos:(NSURL *)fileURL
                   metadata:(SCIGallerySaveMetadata *)metadata
                 completion:(void(^)(BOOL success, NSError *error))completion {
    BOOL isVideo = [self isVideoFileAtURL:fileURL];
    SCIGalleryMediaType mediaType = [self isAudioFileAtURL:fileURL] ? SCIGalleryMediaTypeAudio : (isVideo ? SCIGalleryMediaTypeVideo : SCIGalleryMediaTypeImage);
    __block NSString *assetLocalIdentifier = nil;

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *request = nil;
        if (isVideo) {
            request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
        } else {
            request = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:fileURL];
        }
        assetLocalIdentifier = request.placeholderForCreatedAsset.localIdentifier;
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [SCIDownloadDuplicateTracker recordPhotosSaveWithMetadata:metadata
                                                                mediaType:mediaType
                                                     assetLocalIdentifier:assetLocalIdentifier];
            }
            if (completion) {
                completion(success, error);
            }
        });
    }];
}

+ (SCIGalleryFile *)saveFileURLToGallery:(NSURL *)fileURL
                                metadata:(SCIGallerySaveMetadata *)metadata
                                   error:(NSError **)error {
    SCIGalleryMediaType galleryType = [self isAudioFileAtURL:fileURL] ? SCIGalleryMediaTypeAudio : ([self isVideoFileAtURL:fileURL] ? SCIGalleryMediaTypeVideo : SCIGalleryMediaTypeImage);
    return [SCIGalleryFile saveFileToGallery:fileURL
                                      source:SCIGallerySourceOther
                                   mediaType:galleryType
                                  folderPath:nil
                                    metadata:metadata
                                       error:error];
}

- (void)showCompletionPillWithTitle:(NSString *)title
                            subtitle:(NSString *)subtitle
                    completionImmediately:(BOOL)completionImmediately
                              completion:(void(^)(void))completion {
    if (!self.progressView) {
        if (completion) {
            completion();
        }
        return;
    }

    [self.progressView showSuccessWithTitle:title ?: @"Download complete" subtitle:subtitle icon:nil];
    self.progressView.onTapWhenCompleted = nil;
    self.progressView.onCancel = nil;

    if (completionImmediately && completion) {
        completion();
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SCINotificationPillDuration() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.progressView dismiss];
        if (!completionImmediately && completion) {
            completion();
        }
    });
}

- (instancetype)initWithAction:(DownloadAction)action showProgress:(BOOL)showProgress {
    self = [super init];
    
    if (self) {
        _action = action;
        _showProgress = showProgress;
        _notificationIdentifier = SCIDownloadDefaultNotificationIdentifier(action);

        self.downloadManager = [[SCIDownloadManager alloc] initWithDelegate:self];
    }

    return self;
}

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel {
    SCIDownloadDuplicateDestination destination = self.action == saveToPhotos
        ? SCIDownloadDuplicateDestinationPhotos
        : SCIDownloadDuplicateDestinationGallery;
    BOOL supportsDuplicatePreflight = self.action == saveToPhotos || self.action == saveToGallery;
    SCIGalleryMediaType mediaType = [[self class] isAudioFileAtURL:[NSURL fileURLWithPath:[@"file." stringByAppendingString:fileExtension ?: @"jpg"]]]
        ? SCIGalleryMediaTypeAudio
        : ([[self class] isVideoFileAtURL:[NSURL fileURLWithPath:[@"file." stringByAppendingString:fileExtension ?: @"jpg"]]]
            ? SCIGalleryMediaTypeVideo
            : SCIGalleryMediaTypeImage);
    if (supportsDuplicatePreflight && !self.duplicatePreflightApproved) {
        __weak typeof(self) weakSelf = self;
        BOOL presented = [SCIDownloadDuplicateTracker presentPreflightIfNeededForDestination:destination
                                                                                   metadata:self.pendingGallerySaveMetadata
                                                                                  mediaType:mediaType
                                                                                  presenter:topMostController()
                                                                               continuation:^(SCIDownloadDuplicateDecision decision) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            void (^startDownload)(void) = ^{
                strongSelf.duplicatePreflightApproved = YES;
                [strongSelf downloadFileWithURL:url fileExtension:fileExtension hudLabel:hudLabel];
            };
            if (decision == SCIDownloadDuplicateDecisionDeleteExistingAndDownloadAgain) {
                [SCIDownloadDuplicateTracker deleteExistingForDestination:destination
                                                                 metadata:strongSelf.pendingGallerySaveMetadata
                                                                mediaType:mediaType
                                                               completion:^(BOOL success, NSError *error) {
                    if (success) {
                        startDownload();
                    } else {
                        SCINotify(strongSelf.notificationIdentifier, @"Could not delete existing download", error.localizedDescription, @"error_filled", SCINotificationToneError);
                    }
                }];
            } else {
                startDownload();
            }
        }];
        if (presented) return;
    }

    __weak typeof(self) weakSelf = self;
    NSString *title = SCIDownloadDisplayTitle(self.pendingGallerySaveMetadata, hudLabel);
    NSMutableDictionary *descriptor = SCIDownloadUserDescriptor(self, fileExtension);
    [descriptor addEntriesFromDictionary:@{@"kind": @"url", @"url": url.absoluteString ?: @"", @"extension": fileExtension ?: @"",
                                           @"action": @(self.action), @"showProgress": @(self.showProgress),
                                           @"notificationIdentifier": self.notificationIdentifier ?: @""}];
    NSDictionary *itemDescriptor = @{
        @"state": @"queued",
        @"title": title ?: @"Media download",
        @"detail": [NSString stringWithFormat:@"%@ · Waiting", descriptor[@"mediaKind"] ?: @"Media"],
        @"mediaKind": descriptor[@"mediaKind"] ?: @"Media",
        @"sourceLabel": descriptor[@"sourceLabel"] ?: @"Other",
        @"timestamp": @(NSDate.date.timeIntervalSince1970),
        @"metadata": descriptor[@"metadata"] ?: @{},
        @"url": url.absoluteString ?: @"",
        @"extension": fileExtension ?: @""
    };
    SCIRetainActiveDownloadDelegate(self);
    self.queueActionID = [[SCIDownloadQueueManager shared] createActionWithTitle:title
                                                                          detail:[NSString stringWithFormat:@"%@ · Waiting", descriptor[@"mediaKind"] ?: @"Media"]
                                                                      descriptor:descriptor
                                                                           items:@[itemDescriptor]
                                                                           retry:nil];
    self.queueJobID = [[SCIDownloadQueueManager shared] enqueueTaskForActionID:self.queueActionID
                                                                     itemIndex:0
                                                                         title:@"Waiting"
                                                                         start:^(NSString *jobID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.queueJobID = jobID;
        [strongSelf startDownloadFileWithURL:url fileExtension:fileExtension hudLabel:hudLabel];
    }];
    [[SCIDownloadQueueManager shared] setCancelBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.queuedDownloadStarted) {
            [strongSelf.downloadManager cancelDownload];
        } else {
            strongSelf.pendingGallerySaveMetadata = nil;
            SCIInvokeDownloadCompletion(strongSelf, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
            SCIReleaseActiveDownloadDelegate(strongSelf);
        }
    } forTaskID:self.queueJobID];
}

- (void)startDownloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel {
    self.queuedDownloadStarted = YES;
    self.customCancelHandler = nil;

    if (self.showProgress && [[SCIDownloadQueueManager shared] shouldShowStandaloneProgressForActionID:self.queueActionID]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __weak typeof(self) weakSelf = self;
            NSURL *retryURL = [url copy];
            NSString *retryExtension = [fileExtension copy];
            NSString *retryHudLabel = [hudLabel copy];
            self.progressView = SCINotifyProgress(self.notificationIdentifier, @"Downloading...", ^{
                [[SCIDownloadQueueManager shared] cancelTaskID:weakSelf.queueJobID];
            });
            self.progressView.onRetry = ^{
                if (weakSelf.queueActionID.length) [[SCIDownloadQueueManager shared] retryJobID:weakSelf.queueActionID];
                else [weakSelf downloadFileWithURL:retryURL fileExtension:retryExtension hudLabel:retryHudLabel];
            };
        });
    }

    SCILog(@"General", @"[SCInsta] Download: Will start download for url \"%@\" with file extension: \".%@\"", url, fileExtension);

    // Start download using manager
    [self.downloadManager downloadFileWithURL:url fileExtension:fileExtension];
    __weak typeof(self) weakSelf = self;
    [[SCIDownloadQueueManager shared] setCancelBlock:^{
        [weakSelf.downloadManager cancelDownload];
    } forTaskID:self.queueJobID];
}

- (void)enqueueCustomOperationWithTitle:(NSString *)title
                                 detail:(NSString *)detail
                             descriptor:(NSDictionary *)descriptor
                                  start:(SCIDownloadCustomStartBlock)start {
    if (!start) return;
    SCIRetainActiveDownloadDelegate(self);
    __weak typeof(self) weakSelf = self;
    NSMutableDictionary *resolvedDescriptor = SCIDownloadUserDescriptor(self, descriptor[@"extension"]);
    [resolvedDescriptor addEntriesFromDictionary:descriptor ?: @{}];
    NSDictionary *itemDescriptor = @{
        @"state": @"queued",
        @"title": title ?: @"Media download",
        @"detail": detail ?: @"Waiting",
        @"mediaKind": resolvedDescriptor[@"mediaKind"] ?: @"Media",
        @"sourceLabel": resolvedDescriptor[@"sourceLabel"] ?: @"Other",
        @"timestamp": @(NSDate.date.timeIntervalSince1970),
        @"metadata": resolvedDescriptor[@"metadata"] ?: @{}
    };
    self.queueActionID = [[SCIDownloadQueueManager shared] createActionWithTitle:SCIDownloadDisplayTitle(self.pendingGallerySaveMetadata, title)
                                                                          detail:detail ?: @"Waiting"
                                                                      descriptor:resolvedDescriptor
                                                                           items:@[itemDescriptor]
                                                                           retry:nil];
    self.queueJobID = [[SCIDownloadQueueManager shared] enqueueTaskForActionID:self.queueActionID
                                                                     itemIndex:0
                                                                         title:detail ?: @"Waiting"
                                                                         start:^(NSString *jobID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.queueJobID = jobID;
        [strongSelf beginCustomProgressWithTitle:title subtitle:detail];
        [[SCIDownloadQueueManager shared] setCancelBlock:^{
            [weakSelf cancelCustomOperation];
        } forTaskID:jobID];
        start();
    }];
    [[SCIDownloadQueueManager shared] setCancelBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.pendingGallerySaveMetadata = nil;
        SCIInvokeDownloadCompletion(strongSelf, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        SCIReleaseActiveDownloadDelegate(strongSelf);
    } forTaskID:self.queueJobID];
}

- (void)beginCustomProgressWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    SCIRetainActiveDownloadDelegate(self);

    if (!self.showProgress || ![[SCIDownloadQueueManager shared] shouldShowStandaloneProgressForActionID:self.queueActionID]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.progressView) {
            __weak typeof(self) weakSelf = self;
            self.progressView = SCINotifyProgress(self.notificationIdentifier, title ?: @"Preparing", ^{
                [weakSelf cancelCustomOperation];
            });
        }
        self.progressView.onRetry = nil;
        [self.progressView updateProgressTitle:title subtitle:subtitle];
        [self.progressView setProgress:0.02f animated:NO];
    });
}

- (void)updateCustomProgress:(float)progress title:(NSString *)title subtitle:(NSString *)subtitle {
    [self updateCustomProgress:progress
                          title:title
                       subtitle:subtitle
                   bytesWritten:0
             totalBytesExpected:0];
}

- (void)updateCustomProgress:(float)progress
                        title:(NSString *)title
                     subtitle:(NSString *)subtitle
                 bytesWritten:(int64_t)bytesWritten
           totalBytesExpected:(int64_t)totalBytesExpected {
    if (self.queueJobID.length) {
        [[SCIDownloadQueueManager shared] updateTaskID:self.queueJobID progress:progress detail:title ?: subtitle];
    }
    if (!self.showProgress || ![[SCIDownloadQueueManager shared] shouldShowStandaloneProgressForActionID:self.queueActionID]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.progressView) {
            self.progressView = SCINotifyProgress(self.notificationIdentifier, title ?: @"Working", nil);
        }
        [self.progressView updateProgressTitle:title subtitle:subtitle];
        [self.progressView setProgress:progress
                          bytesWritten:bytesWritten
                    totalBytesExpected:totalBytesExpected
                              animated:YES];
    });
}

- (void)showCustomErrorWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    NSError *error = SCIDownloadErrorWithDescription(subtitle.length > 0 ? subtitle : title, 50);
    if (self.queueJobID.length) [[SCIDownloadQueueManager shared] failTaskID:self.queueJobID error:error];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.showProgress && self.progressView) {
            [self.progressView showErrorWithTitle:title subtitle:subtitle icon:nil];
        }
        SCIInvokeDownloadCompletion(self, nil, error);
        SCIReleaseActiveDownloadDelegate(self);
    });
}

- (void)finishWithLocalFileURL:(NSURL *)fileURL {
    [self downloadDidFinishWithFileURL:fileURL];
}

- (void)cancelCustomOperation {
    dispatch_block_t cancelHandler = [self.customCancelHandler copy];
    self.customCancelHandler = nil;
    if (cancelHandler) {
        cancelHandler();
    }
    self.pendingGallerySaveMetadata = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressView dismiss];
    });
    SCIInvokeDownloadCompletion(self, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
    SCIReleaseActiveDownloadDelegate(self);
    if (self.queueJobID.length) [[SCIDownloadQueueManager shared] cancelTaskID:self.queueJobID];
}

// Delegate methods
- (void)downloadDidStart {
    SCILog(@"General", @"[SCInsta] Download: Download started");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressView setProgress:0.02f animated:NO];
    });
}

- (void)downloadDidCancel {
    self.queuedDownloadStarted = NO;
    self.pendingGallerySaveMetadata = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressView dismiss];
    });
    SCIInvokeDownloadCompletion(self, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
    SCIReleaseActiveDownloadDelegate(self);
    if (self.queueJobID.length) [[SCIDownloadQueueManager shared] cancelTaskID:self.queueJobID];

    SCILog(@"General", @"[SCInsta] Download: Download cancelled");
}

- (void)downloadDidProgress:(float)progress {
    SCILog(@"General", @"[SCInsta] Download: Download progress: %f", progress);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressView setProgress:progress animated:YES];
    });
    if (self.queueJobID.length) [[SCIDownloadQueueManager shared] updateTaskID:self.queueJobID progress:progress detail:@"Downloading"];
}

- (void)downloadDidProgress:(float)progress
               bytesWritten:(int64_t)bytesWritten
         totalBytesExpected:(int64_t)totalBytesExpected {
    SCILog(@"General", @"[SCInsta] Download: Download progress: %f", progress);

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressView setProgress:progress
                          bytesWritten:bytesWritten
                    totalBytesExpected:totalBytesExpected
                              animated:YES];
    });
    if (self.queueJobID.length) [[SCIDownloadQueueManager shared] updateTaskID:self.queueJobID progress:progress detail:@"Downloading"];
}

- (void)downloadDidFinishWithError:(NSError *)error {
    self.pendingGallerySaveMetadata = nil;
    if (!self.queueSettleExternally && error.code != NSURLErrorCancelled && self.queueJobID.length) [[SCIDownloadQueueManager shared] failTaskID:self.queueJobID error:error];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (error && error.code != NSURLErrorCancelled) {
            SCILog(@"General", @"[SCInsta] Download: Download failed with error: \"%@\"", error);
            if (self.showProgress && self.progressView) {
                void (^existingDismissHandler)(void) = [self.progressView.onDidDismiss copy];
                __weak typeof(self) weakSelf = self;
                self.progressView.onDidDismiss = ^{
                    if (existingDismissHandler) {
                        existingDismissHandler();
                    }
                    SCIReleaseActiveDownloadDelegate(weakSelf);
                };
                [self.progressView showError:@"Download failed"];
                SCIInvokeDownloadCompletion(self, nil, error);
                return;
            }
        }

        if (error) {
            SCIInvokeDownloadCompletion(self, nil, error);
        }
        SCIReleaseActiveDownloadDelegate(self);
    });
}

- (void)downloadDidFinishWithFileURL:(NSURL *)fileURL {
    SCIGallerySaveMetadata *galleryMeta = self.pendingGallerySaveMetadata;
    self.pendingGallerySaveMetadata = nil;
    if (!galleryMeta) {
        galleryMeta = [[SCIGallerySaveMetadata alloc] init];
        galleryMeta.source = (int16_t)SCIGallerySourceOther;
    }

    BOOL isVideo = [[self class] isVideoFileAtURL:fileURL];
    BOOL isAudio = [[self class] isAudioFileAtURL:fileURL];
    SCIGalleryMediaType galleryType = isAudio ? SCIGalleryMediaTypeAudio : (isVideo ? SCIGalleryMediaTypeVideo : SCIGalleryMediaTypeImage);
    NSString *fileName = SCIFileNameForMedia(fileURL, galleryType, galleryMeta);
    if (isAudio) {
        NSString *audioExtension = fileURL.pathExtension.length > 0 ? fileURL.pathExtension.lowercaseString : @"m4a";
        fileName = [[fileName stringByDeletingPathExtension] stringByAppendingPathExtension:audioExtension];
    }
    NSString *newPath = [[fileURL.path stringByDeletingLastPathComponent] stringByAppendingPathComponent:fileName];
    NSURL *newURL = [NSURL fileURLWithPath:newPath];

    if (![newURL isEqual:fileURL]) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *removeError = nil;
        if ([fileManager fileExistsAtPath:newURL.path] && ![fileManager removeItemAtURL:newURL error:&removeError]) {
            SCILog(@"General", @"[SCInsta] Download: Failed removing existing file at \"%@\": %@", newURL.path, removeError);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.showProgress && self.progressView) {
                    [self.progressView showError:@"Failed to prepare file"];
                }
                SCIInvokeDownloadCompletion(self, nil, SCIDownloadErrorWithDescription(@"Failed to prepare file", 1));
            });
            NSError *error = SCIDownloadErrorWithDescription(@"Failed to prepare file", 1);
            if (!self.queueSettleExternally && self.queueJobID.length) [[SCIDownloadQueueManager shared] failTaskID:self.queueJobID error:error];
            SCIReleaseActiveDownloadDelegate(self);
            return;
        }

        NSError *moveError = nil;
        if (![fileManager moveItemAtURL:fileURL toURL:newURL error:&moveError]) {
            SCILog(@"General", @"[SCInsta] Download: Failed renaming downloaded file to \"%@\": %@", newURL.path, moveError);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.showProgress && self.progressView) {
                    [self.progressView showError:@"Failed to finalize file"];
                }
                SCIInvokeDownloadCompletion(self, nil, SCIDownloadErrorWithDescription(@"Failed to finalize file", 2));
            });
            NSError *error = SCIDownloadErrorWithDescription(@"Failed to finalize file", 2);
            if (!self.queueSettleExternally && self.queueJobID.length) [[SCIDownloadQueueManager shared] failTaskID:self.queueJobID error:error];
            SCIReleaseActiveDownloadDelegate(self);
            return;
        }
    } else {
        newURL = fileURL;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        SCILog(@"General", @"[SCInsta] Download: Download finished with url: \"%@\"", [newURL absoluteString]);
        SCILog(@"General", @"[SCInsta] Download: Completed with action %d", (int)self.action);

        if (self.action == downloadOnly) {
            if (!self.queueSettleExternally && self.queueJobID.length) [[SCIDownloadQueueManager shared] finishTaskID:self.queueJobID detail:@"Downloaded" filePath:newURL.path];
            SCIInvokeDownloadCompletion(self, newURL, nil);
            SCIReleaseActiveDownloadDelegate(self);
            return;
        }

        if (self.action == share) {
            [self.progressView updateProgressTitle:@"Preparing share" subtitle:nil];
            [self.progressView setProgress:0.98f animated:YES];
            if (self.queueJobID.length) [[SCIDownloadQueueManager shared] finishTaskID:self.queueJobID detail:@"Opened share sheet" filePath:newURL.path];
            [SCIUtils showShareVC:newURL];
            SCIInvokeDownloadCompletion(self, newURL, nil);
            SCIReleaseActiveDownloadDelegate(self);
            return;
        }

        if (self.action == saveToPhotos) {
            if (self.progressView) {
                [self.progressView updateProgressTitle:@"Saving to Photos" subtitle:nil];
                [self.progressView setProgress:0.98f animated:YES];
            }
            [[self class] saveFileURLToPhotos:newURL metadata:galleryMeta completion:^(BOOL success, NSError *error) {
                if (success) {
                    if (self.queueJobID.length) [[SCIDownloadQueueManager shared] finishTaskID:self.queueJobID detail:@"Saved to Photos" filePath:newURL.path];
                    [self showCompletionPillWithTitle:@"Saved successfully!" subtitle:@"Tap to open Downloads" completionImmediately:NO completion:^{
                        SCIInvokeDownloadCompletion(self, newURL, nil);
                        SCIReleaseActiveDownloadDelegate(self);
                    }];
                } else {
                    if (self.queueJobID.length) [[SCIDownloadQueueManager shared] failTaskID:self.queueJobID error:error ?: SCIDownloadErrorWithDescription(@"Failed to save", 3)];
                    if (self.progressView) {
                        [self.progressView showError:@"Failed to save"];
                    }
                    SCIInvokeDownloadCompletion(self, nil, error ?: SCIDownloadErrorWithDescription(@"Failed to save", 3));
                    SCIReleaseActiveDownloadDelegate(self);
                }
            }];
            return;
        }

        if (self.action == saveToGallery) {
            if (self.progressView) {
                [self.progressView updateProgressTitle:@"Saving to Gallery" subtitle:nil];
                [self.progressView setProgress:0.98f animated:YES];
            }
            NSError *error;
            SCIGalleryFile *file = [[self class] saveFileURLToGallery:newURL metadata:galleryMeta error:&error];
            if (file) {
                if (self.queueJobID.length) [[SCIDownloadQueueManager shared] finishTaskID:self.queueJobID detail:@"Saved to Gallery" filePath:file.filePath];
                [self showCompletionPillWithTitle:@"Saved successfully!" subtitle:@"Tap to open Downloads" completionImmediately:NO completion:^{
                    SCIInvokeDownloadCompletion(self, newURL, nil);
                    SCIReleaseActiveDownloadDelegate(self);
                }];
            } else {
                if (self.queueJobID.length) [[SCIDownloadQueueManager shared] failTaskID:self.queueJobID error:error ?: SCIDownloadErrorWithDescription(@"Failed to save to Gallery", 4)];
                if (self.progressView) {
                    [self.progressView showError:@"Failed to save to Gallery"];
                }
                SCIInvokeDownloadCompletion(self, nil, error ?: SCIDownloadErrorWithDescription(@"Failed to save to Gallery", 4));
                SCIReleaseActiveDownloadDelegate(self);
            }
            return;
        }

        if (self.queueJobID.length) [[SCIDownloadQueueManager shared] finishTaskID:self.queueJobID detail:@"Opened media" filePath:newURL.path];
        [SCIFullScreenMediaPlayer showFileURL:newURL];
        SCIInvokeDownloadCompletion(self, newURL, nil);
        SCIReleaseActiveDownloadDelegate(self);
    });
}

@end

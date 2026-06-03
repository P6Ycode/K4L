#import "BulkDownload.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "Download.h"
#import "../Utils.h"
#import "../Shared/SCIStoragePaths.h"
#import "../Shared/Gallery/SCIGalleryFile.h"
#import "../Shared/Gallery/SCIGallerySaveMetadata.h"
#import "../Shared/Gallery/SCIGalleryViewController.h"
#import "../Shared/MediaDownload/SCIDownloadDuplicateTracker.h"
#import "../Shared/MediaDownload/SCIDownloadQueueManager.h"

@interface SCIBulkDownloadCoordinator ()
@property (nonatomic, assign) SCIBulkDownloadOperation operation;
@property (nonatomic, copy) NSArray<SCIBulkDownloadItem *> *items;
@property (nonatomic, copy) NSString *actionIdentifier;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) UIView *anchorView;
@property (nonatomic, copy) NSString *historyJobID;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *itemDescriptors;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCIDownloadDelegate *> *activeDelegates;
@property (nonatomic, strong) NSMutableSet<NSString *> *activeChildJobIDs;
@property (nonatomic, strong) NSIndexSet *requestedIndexes;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation SCIBulkDownloadItem

+ (instancetype)itemWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension isVideo:(BOOL)isVideo metadata:(SCIGallerySaveMetadata *)metadata linkString:(NSString *)linkString {
    SCIBulkDownloadItem *item = [self new];
    item.fileURL = url;
    item.fileExtension = fileExtension.length ? fileExtension : url.pathExtension;
    item.video = isVideo;
    item.galleryMetadata = metadata;
    item.linkString = linkString.length ? linkString : url.absoluteString;
    return item;
}

+ (instancetype)itemWithImage:(UIImage *)image metadata:(SCIGallerySaveMetadata *)metadata {
    SCIBulkDownloadItem *item = [self new];
    item.image = image;
    item.fileExtension = @"png";
    item.galleryMetadata = metadata;
    return item;
}

@end

static NSMutableSet<SCIBulkDownloadCoordinator *> *SCIActiveBulkCoordinators(void) {
    static NSMutableSet *coordinators;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ coordinators = [NSMutableSet set]; });
    return coordinators;
}

static NSString *SCIBulkProgressTitle(SCIBulkDownloadOperation operation) {
    switch (operation) {
        case SCIBulkDownloadOperationSaveToPhotos: return @"Saving to Photos";
        case SCIBulkDownloadOperationSaveToGallery: return @"Saving to Gallery";
        case SCIBulkDownloadOperationShare: return @"Preparing share";
        case SCIBulkDownloadOperationCopyMedia: return @"Copying media";
    }
}

static NSString *SCIBulkNotificationIdentifier(SCIBulkDownloadOperation operation) {
    switch (operation) {
        case SCIBulkDownloadOperationSaveToPhotos: return kSCINotificationDownloadAllLibrary;
        case SCIBulkDownloadOperationSaveToGallery: return kSCINotificationDownloadAllGallery;
        case SCIBulkDownloadOperationShare: return kSCINotificationDownloadAllShare;
        case SCIBulkDownloadOperationCopyMedia: return kSCINotificationDownloadAllClipboard;
    }
}

static NSString *SCIBulkCompletionAction(SCIBulkDownloadOperation operation) {
    switch (operation) {
        case SCIBulkDownloadOperationSaveToPhotos: return @"openPhotos";
        case SCIBulkDownloadOperationSaveToGallery: return @"openGallery";
        case SCIBulkDownloadOperationShare:
        case SCIBulkDownloadOperationCopyMedia: return @"expand";
    }
}

static NSDictionary *SCIBulkMetadataDescriptor(SCIGallerySaveMetadata *metadata) {
    if (!metadata) return @{};
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"source"] = @(metadata.source);
    if (metadata.sourceUsername) result[@"sourceUsername"] = metadata.sourceUsername;
    if (metadata.sourceUserPK) result[@"sourceUserPK"] = metadata.sourceUserPK;
    if (metadata.sourceMediaPK) result[@"sourceMediaPK"] = metadata.sourceMediaPK;
    if (metadata.sourceMediaCode) result[@"sourceMediaCode"] = metadata.sourceMediaCode;
    if (metadata.sourceMediaURLString) result[@"sourceMediaURLString"] = metadata.sourceMediaURLString;
    return result;
}

static SCIGallerySaveMetadata *SCIBulkMetadataFromDescriptor(NSDictionary *descriptor) {
    SCIGallerySaveMetadata *metadata = [SCIGallerySaveMetadata new];
    metadata.source = [descriptor[@"source"] shortValue];
    metadata.sourceUsername = descriptor[@"sourceUsername"];
    metadata.sourceUserPK = descriptor[@"sourceUserPK"];
    metadata.sourceMediaPK = descriptor[@"sourceMediaPK"];
    metadata.sourceMediaCode = descriptor[@"sourceMediaCode"];
    metadata.sourceMediaURLString = descriptor[@"sourceMediaURLString"];
    return metadata;
}

static NSString *SCIBulkStageImage(UIImage *image) {
    NSData *data = UIImagePNGRepresentation(image);
    if (!data) return nil;
    NSString *directory = [[SCIStoragePaths downloadsDirectory] stringByAppendingPathComponent:@"CarouselSources"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [directory stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"png"]];
    return [data writeToFile:path atomically:YES] ? path : nil;
}

static NSMutableDictionary *SCIBulkDescriptorForItem(SCIBulkDownloadItem *item) {
    NSMutableDictionary *descriptor = [@{@"state": @"queued",
                                         @"extension": item.fileExtension ?: (item.video ? @"mp4" : @"jpg"),
                                         @"video": @(item.video),
                                         @"metadata": SCIBulkMetadataDescriptor(item.galleryMetadata)} mutableCopy];
    if (item.fileURL.absoluteString) descriptor[@"url"] = item.fileURL.absoluteString;
    if (item.linkString) descriptor[@"link"] = item.linkString;
    if (item.image && !item.fileURL) {
        NSString *stagedPath = SCIBulkStageImage(item.image);
        if (stagedPath) descriptor[@"url"] = [NSURL fileURLWithPath:stagedPath].absoluteString;
        else {
            descriptor[@"state"] = @"failed";
            descriptor[@"error"] = @"Retry unavailable: unable to stage image source";
        }
    }
    return descriptor;
}

static SCIBulkDownloadItem *SCIBulkItemFromDescriptor(NSDictionary *descriptor) {
    NSURL *url = [NSURL URLWithString:descriptor[@"url"]];
    if (!url) return nil;
    return [SCIBulkDownloadItem itemWithURL:url
                              fileExtension:descriptor[@"extension"]
                                    isVideo:[descriptor[@"video"] boolValue]
                                   metadata:SCIBulkMetadataFromDescriptor(descriptor[@"metadata"] ?: @{})
                                 linkString:descriptor[@"link"]];
}

static NSString *SCIBulkDisplayTitle(NSDictionary *descriptor) {
    NSString *username = descriptor[@"metadata"][@"sourceUsername"];
    return username.length ? ([username hasPrefix:@"@"] ? username : [@"@" stringByAppendingString:username]) : @"Media download";
}

static BOOL SCIBulkDescriptorSourceExists(NSDictionary *descriptor) {
    NSURL *url = [NSURL URLWithString:descriptor[@"url"]];
    return url && (!url.isFileURL || [[NSFileManager defaultManager] fileExistsAtPath:url.path]);
}

@implementation SCIBulkDownloadCoordinator

+ (void)performOperation:(SCIBulkDownloadOperation)operation items:(NSArray<SCIBulkDownloadItem *> *)items actionIdentifier:(NSString *)actionIdentifier presenter:(UIViewController *)presenter anchorView:(UIView *)anchorView {
    NSMutableArray *descriptors = [NSMutableArray array];
    for (SCIBulkDownloadItem *item in items) {
        if ([item isKindOfClass:SCIBulkDownloadItem.class] && (item.fileURL || item.image)) [descriptors addObject:SCIBulkDescriptorForItem(item)];
    }
    if (!descriptors.count) {
        SCINotify(actionIdentifier ?: SCIBulkNotificationIdentifier(operation), @"No downloadable media", nil, @"error_filled", SCINotificationToneError);
        return;
    }
    SCIBulkDownloadCoordinator *coordinator = [self new];
    coordinator.operation = operation;
    coordinator.items = items;
    coordinator.itemDescriptors = descriptors;
    coordinator.actionIdentifier = actionIdentifier.length ? actionIdentifier : SCIBulkNotificationIdentifier(operation);
    coordinator.presenter = presenter;
    coordinator.anchorView = anchorView;
    coordinator.requestedIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, descriptors.count)];
    [coordinator startCreatingSummary:YES];
}

+ (BOOL)canRetryDescriptor:(NSDictionary *)descriptor childIndexes:(NSIndexSet *)childIndexes {
    if (![descriptor[@"kind"] isEqual:@"bulk"]) return NO;
    NSArray *items = descriptor[@"items"];
    if (!items.count) return NO;
    __block BOOL found = NO;
    [items enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger index, BOOL *stop) {
        if (childIndexes && ![childIndexes containsIndex:index]) return;
        if (![@[@"failed", @"interrupted", @"cancelled"] containsObject:item[@"state"]]) return;
        if (SCIBulkDescriptorSourceExists(item)) { found = YES; *stop = YES; }
    }];
    return found;
}

+ (void)retrySummaryJobID:(NSString *)jobID childIndexes:(NSIndexSet *)childIndexes {
    NSDictionary *job = [[[SCIDownloadQueueManager shared] jobs] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"id == %@", jobID]].firstObject;
    NSDictionary *descriptor = job[@"descriptor"];
    if (![self canRetryDescriptor:descriptor childIndexes:childIndexes]) return;
    SCIBulkDownloadCoordinator *coordinator = [self new];
    coordinator.operation = [descriptor[@"operation"] unsignedIntegerValue];
    coordinator.actionIdentifier = descriptor[@"notificationIdentifier"] ?: SCIBulkNotificationIdentifier(coordinator.operation);
    coordinator.historyJobID = jobID;
    coordinator.itemDescriptors = [NSMutableArray array];
    NSMutableIndexSet *retryIndexes = [NSMutableIndexSet indexSet];
    [descriptor[@"items"] enumerateObjectsUsingBlock:^(NSDictionary *stored, NSUInteger index, BOOL *stop) {
        NSMutableDictionary *item = [stored mutableCopy];
        BOOL selected = (!childIndexes || [childIndexes containsIndex:index]) && [@[@"failed", @"interrupted", @"cancelled"] containsObject:item[@"state"]] && SCIBulkDescriptorSourceExists(item);
        if (selected) {
            item[@"state"] = @"queued";
            [item removeObjectForKey:@"error"];
            [retryIndexes addIndex:index];
        }
        [coordinator.itemDescriptors addObject:item];
    }];
    coordinator.requestedIndexes = retryIndexes;
    [coordinator startCreatingSummary:NO];
}

- (NSMutableDictionary *)summaryDescriptor {
    NSDictionary *first = self.itemDescriptors.firstObject ?: @{};
    return [@{@"kind": @"bulk", @"summary": @YES, @"mediaKind": @"Carousel",
              @"itemCount": @(self.itemDescriptors.count), @"operation": @(self.operation),
              @"notificationIdentifier": self.actionIdentifier ?: @"",
              @"destinationLabel": SCIBulkProgressTitle(self.operation),
              @"completionAction": SCIBulkCompletionAction(self.operation),
              @"sourceLabel": [SCIGalleryFile shortLabelForSource:[first[@"metadata"][@"source"] shortValue]] ?: @"Other",
              @"username": first[@"metadata"][@"sourceUsername"] ?: @"",
              @"items": self.itemDescriptors ?: @[]} mutableCopy];
}

- (void)startCreatingSummary:(BOOL)createSummary {
    self.activeDelegates = [NSMutableDictionary dictionary];
    self.activeChildJobIDs = [NSMutableSet set];
    @synchronized (SCIActiveBulkCoordinators()) { [SCIActiveBulkCoordinators() addObject:self]; }
    if (createSummary) {
        self.historyJobID = [[SCIDownloadQueueManager shared] createActionWithTitle:SCIBulkDisplayTitle(self.itemDescriptors.firstObject)
                                                                             detail:[NSString stringWithFormat:@"Carousel · %lu items", (unsigned long)self.itemDescriptors.count]
                                                                         descriptor:[self summaryDescriptor]
                                                                              items:self.itemDescriptors
                                                                              retry:nil];
    } else {
        [[SCIDownloadQueueManager shared] reactivateActionID:self.historyJobID
                                                 descriptor:[self summaryDescriptor]
                                                     detail:@"Retrying failed items"
                                            resetItemIndexes:self.requestedIndexes];
    }
    __weak typeof(self) weakSelf = self;
    [[SCIDownloadQueueManager shared] setCancelBlock:^{ [weakSelf cancel]; } forActionID:self.historyJobID];
    [self runDuplicatePreflightForIndexes:self.requestedIndexes.firstIndex];
}

- (void)runDuplicatePreflightForIndexes:(NSUInteger)index {
    if (index == NSNotFound || self.cancelled) {
        [self enqueueRequestedChildren];
        return;
    }
    NSUInteger next = [self.requestedIndexes indexGreaterThanIndex:index];
    if (self.operation != SCIBulkDownloadOperationSaveToPhotos && self.operation != SCIBulkDownloadOperationSaveToGallery) {
        [self runDuplicatePreflightForIndexes:next];
        return;
    }
    SCIBulkDownloadItem *item = SCIBulkItemFromDescriptor(self.itemDescriptors[index]);
    SCIDownloadDuplicateDestination destination = self.operation == SCIBulkDownloadOperationSaveToPhotos ? SCIDownloadDuplicateDestinationPhotos : SCIDownloadDuplicateDestinationGallery;
    SCIGalleryMediaType mediaType = item.video ? SCIGalleryMediaTypeVideo : SCIGalleryMediaTypeImage;
    __weak typeof(self) weakSelf = self;
    BOOL presented = [SCIDownloadDuplicateTracker presentPreflightIfNeededForDestination:destination metadata:item.galleryMetadata mediaType:mediaType presenter:self.presenter continuation:^(SCIDownloadDuplicateDecision decision) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (decision == SCIDownloadDuplicateDecisionDeleteExistingAndDownloadAgain) {
            [SCIDownloadDuplicateTracker deleteExistingForDestination:destination metadata:item.galleryMetadata mediaType:mediaType completion:^(__unused BOOL success, __unused NSError *error) {
                [self runDuplicatePreflightForIndexes:next];
            }];
        } else {
            [self runDuplicatePreflightForIndexes:next];
        }
    }];
    if (!presented) [self runDuplicatePreflightForIndexes:next];
}

- (void)enqueueRequestedChildren {
    if (self.cancelled) return;
    [self.requestedIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        NSMutableDictionary *item = self.itemDescriptors[index];
        NSURL *url = [NSURL URLWithString:item[@"url"]];
        if (!url || (url.isFileURL && ![[NSFileManager defaultManager] fileExistsAtPath:url.path])) {
            item[@"state"] = @"failed";
            item[@"error"] = @"Retry unavailable: source file is missing";
            [[SCIDownloadQueueManager shared] updateItemAtIndex:index forJobID:self.historyJobID usingBlock:^(NSMutableDictionary *storedItem) {
                storedItem[@"state"] = @"failed";
                storedItem[@"error"] = @"Retry unavailable: source file is missing";
                storedItem[@"detail"] = storedItem[@"error"];
                storedItem[@"progress"] = @1.0;
            }];
            return;
        }
        __weak typeof(self) weakSelf = self;
        __block NSString *childJobID = nil;
        childJobID = [[SCIDownloadQueueManager shared] enqueueTaskForActionID:self.historyJobID
                                                                    itemIndex:index
                                                                        title:[NSString stringWithFormat:@"Item %lu", (unsigned long)(index + 1)]
                                                                        start:^(NSString *jobID) { [weakSelf startChildAtIndex:index jobID:jobID]; }];
        [self.activeChildJobIDs addObject:childJobID];
    }];
    [self finishIfDone];
}

- (void)startChildAtIndex:(NSUInteger)index jobID:(NSString *)jobID {
    if (self.cancelled) { [[SCIDownloadQueueManager shared] cancelTaskID:jobID]; return; }
    NSMutableDictionary *descriptor = self.itemDescriptors[index];
    descriptor[@"state"] = @"active";
    [[SCIDownloadQueueManager shared] updateItemAtIndex:index forJobID:self.historyJobID usingBlock:^(NSMutableDictionary *storedItem) {
        storedItem[@"state"] = @"running";
        storedItem[@"detail"] = @"Downloading";
    }];
    NSURL *url = [NSURL URLWithString:descriptor[@"url"]];
    if (url.isFileURL) {
        [self finishResolvedURL:url index:index childJobID:jobID error:nil];
        return;
    }
    SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:downloadOnly showProgress:NO];
    delegate.notificationIdentifier = @"";
    delegate.queueJobID = jobID;
    delegate.queueActionID = self.historyJobID;
    delegate.queueSettleExternally = YES;
    delegate.pendingGallerySaveMetadata = SCIBulkMetadataFromDescriptor(descriptor[@"metadata"] ?: @{});
    self.activeDelegates[jobID] = delegate;
    __weak typeof(self) weakSelf = self;
    delegate.completionBlock = ^(NSURL *fileURL, NSError *error) { [weakSelf finishResolvedURL:fileURL index:index childJobID:jobID error:error]; };
    [delegate startDownloadFileWithURL:url fileExtension:descriptor[@"extension"] hudLabel:nil];
    [[SCIDownloadQueueManager shared] setCancelBlock:^{ [delegate.downloadManager cancelDownload]; } forTaskID:jobID];
}

- (void)finishResolvedURL:(NSURL *)url index:(NSUInteger)index childJobID:(NSString *)childJobID error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.activeDelegates removeObjectForKey:childJobID];
        if (error || !url) { [self settleChild:index jobID:childJobID path:nil error:error.localizedDescription ?: @"Download failed"]; return; }
        if (self.operation == SCIBulkDownloadOperationSaveToPhotos) {
            [SCIDownloadDelegate saveFileURLToPhotos:url metadata:SCIBulkMetadataFromDescriptor(self.itemDescriptors[index][@"metadata"]) completion:^(BOOL success, NSError *saveError) {
                [self settleChild:index jobID:childJobID path:url.path error:success ? nil : saveError.localizedDescription];
            }];
        } else if (self.operation == SCIBulkDownloadOperationSaveToGallery) {
            NSError *saveError = nil;
            SCIGalleryFile *file = [SCIDownloadDelegate saveFileURLToGallery:url metadata:SCIBulkMetadataFromDescriptor(self.itemDescriptors[index][@"metadata"]) error:&saveError];
            [self settleChild:index jobID:childJobID path:file.filePath ?: url.path error:file ? nil : saveError.localizedDescription];
        } else {
            [self settleChild:index jobID:childJobID path:url.path error:nil];
        }
    });
}

- (void)settleChild:(NSUInteger)index jobID:(NSString *)jobID path:(NSString *)path error:(NSString *)error {
    NSMutableDictionary *item = self.itemDescriptors[index];
    item[@"state"] = error.length ? @"failed" : @"completed";
    if (path.length) item[@"previewPath"] = path;
    if (error.length) item[@"error"] = error; else [item removeObjectForKey:@"error"];
    if (error.length) [[SCIDownloadQueueManager shared] failTaskID:jobID error:[NSError errorWithDomain:@"SCInsta.BulkDownload" code:20 userInfo:@{NSLocalizedDescriptionKey: error}]];
    else [[SCIDownloadQueueManager shared] finishTaskID:jobID detail:@"Completed" filePath:path];
    [self.activeChildJobIDs removeObject:jobID];
    [self finishIfDone];
}

- (void)finishIfDone {
    if (self.activeChildJobIDs.count) return;
    for (NSUInteger index = 0; index < self.itemDescriptors.count; index++) if ([self.requestedIndexes containsIndex:index] && [@[@"queued", @"active"] containsObject:self.itemDescriptors[index][@"state"]]) return;
    NSUInteger failed = 0, completed = 0;
    for (NSDictionary *item in self.itemDescriptors) {
        if ([item[@"state"] isEqual:@"completed"]) completed++;
        if ([@[@"failed", @"interrupted", @"cancelled"] containsObject:item[@"state"]]) failed++;
    }
    if (self.cancelled) return;
    if (!failed && (self.operation == SCIBulkDownloadOperationShare || self.operation == SCIBulkDownloadOperationCopyMedia)) [self finalizeResolvedFiles];
    NSString *result = failed ? [NSString stringWithFormat:@"%lu items completed · %lu failed", (unsigned long)completed, (unsigned long)failed]
                              : [NSString stringWithFormat:@"%@ %lu items", self.operation == SCIBulkDownloadOperationShare ? @"Shared" : self.operation == SCIBulkDownloadOperationCopyMedia ? @"Copied" : @"Saved", (unsigned long)completed];
    [[SCIDownloadQueueManager shared] updateActionDescriptor:[self summaryDescriptor] forActionID:self.historyJobID];
    [[SCIDownloadQueueManager shared] updateActionDetail:result progress:1.0 forActionID:self.historyJobID];
    [self releaseCoordinator];
}

- (void)finalizeResolvedFiles {
    NSMutableArray *urls = [NSMutableArray array];
    for (NSDictionary *item in self.itemDescriptors) {
        NSString *path = item[@"previewPath"];
        if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]) [urls addObject:[NSURL fileURLWithPath:path]];
    }
    if (self.operation == SCIBulkDownloadOperationShare && urls.count) {
        UIViewController *presenter = self.presenter ?: topMostController();
        UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            activity.popoverPresentationController.sourceView = self.anchorView ?: presenter.view;
            activity.popoverPresentationController.sourceRect = (self.anchorView ?: presenter.view).bounds;
        }
        [presenter presentViewController:activity animated:YES completion:nil];
    } else if (self.operation == SCIBulkDownloadOperationCopyMedia && urls.count) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSURL *url in urls) {
            NSData *data = [NSData dataWithContentsOfURL:url];
            UTType *type = [UTType typeWithFilenameExtension:url.pathExtension];
            if (data && type.identifier) [items addObject:@{type.identifier: data}];
        }
        UIPasteboard.generalPasteboard.items = items;
    }
}

- (void)cancel {
    if (self.cancelled) return;
    self.cancelled = YES;
    for (NSMutableDictionary *item in self.itemDescriptors) if ([@[@"queued", @"active"] containsObject:item[@"state"]]) item[@"state"] = @"cancelled";
    [self releaseCoordinator];
}

- (void)releaseCoordinator {
    @synchronized (SCIActiveBulkCoordinators()) { [SCIActiveBulkCoordinators() removeObject:self]; }
}

@end

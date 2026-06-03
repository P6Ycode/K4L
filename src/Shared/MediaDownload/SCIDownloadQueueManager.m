#import "SCIDownloadQueueManager.h"

#import <float.h>

#import "../SCIStoragePaths.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../UI/SCINotificationCenter.h"
#import "../../Downloader/BulkDownload.h"
#import "../../Downloader/Download.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "SCIDownloadHistoryViewController.h"

NSNotificationName const SCIDownloadQueueDidChangeNotification = @"SCIDownloadQueueDidChangeNotification";
NSString * const kSCIDownloadMaxConcurrentKey = @"general_download_max_concurrent";
NSString * const kSCIDownloadHistoryLimitKey = @"general_download_history_limit";

static NSString * const kSCIDownloadActionStateQueued = @"queued";
static NSString * const kSCIDownloadActionStateRunning = @"running";
static NSString * const kSCIDownloadActionStateCompleted = @"completed";
static NSString * const kSCIDownloadActionStateFailed = @"failed";
static NSString * const kSCIDownloadActionStateCancelled = @"cancelled";
static NSString * const kSCIDownloadActionStateInterrupted = @"interrupted";
static NSString * const kSCIDownloadActionStatePartial = @"partial";

@interface SCIDownloadQueueManager ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *mutableActions;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *taskRecords;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCIDownloadQueueTaskStartBlock> *taskStartBlocks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCIDownloadQueueTaskCancelBlock> *taskCancelBlocks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCIDownloadQueueTaskCancelBlock> *actionCancelBlocks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCIDownloadQueueActionRetryBlock> *actionRetryBlocks;
@property (nonatomic, strong) SCINotificationPillView *queuePill;
@property (nonatomic, strong) NSMutableSet<NSString *> *queueBatchActionIDs;
@property (nonatomic, assign) NSUInteger queueBatchGeneration;
@property (nonatomic, copy) NSString *queueTerminalSignature;
@end

@implementation SCIDownloadQueueManager

static NSTimeInterval SCIQueueNow(void) {
    return NSDate.date.timeIntervalSince1970;
}

static BOOL SCIQueueStateIsTerminal(NSString *state) {
    return [@[kSCIDownloadActionStateCompleted,
              kSCIDownloadActionStateFailed,
              kSCIDownloadActionStateCancelled,
              kSCIDownloadActionStateInterrupted,
              kSCIDownloadActionStatePartial] containsObject:state];
}

static NSString *SCIQueueItemCompletionAction(NSDictionary *descriptor) {
    NSString *completionAction = descriptor[@"completionAction"];
    return completionAction.length > 0 ? completionAction : nil;
}

static NSString *SCIQueueProgressTitleForAction(NSDictionary *action) {
    NSDictionary *descriptor = action[@"descriptor"] ?: @{};
    NSString *detail = action[@"detail"] ?: @"";
    if ([detail containsString:@"Saving to Photos"]) return @"Saving to Photos";
    if ([detail containsString:@"Saving to Gallery"]) return @"Saving to Gallery";
    if ([detail containsString:@"Preparing share"]) return @"Preparing share";
    if ([detail containsString:@"Copying media"]) return @"Copying media";
    if ([detail containsString:@"Merging"]) return @"Merging";
    if ([detail containsString:@"Converting"]) return @"Converting";
    if ([detail containsString:@"Retrying"]) return @"Retrying";
    NSString *kind = descriptor[@"kind"];
    if ([kind isEqualToString:@"url"] || [kind isEqualToString:@"bulk"]) return @"Downloading";
    return descriptor[@"progressTitle"] ?: @"Downloading";
}

static NSMutableDictionary *SCIQueueMutableItemDescriptor(NSDictionary *item, NSUInteger index, NSDictionary *actionDescriptor) {
    NSMutableDictionary *mutable = [NSMutableDictionary dictionaryWithDictionary:item ?: @{}];
    mutable[@"state"] = mutable[@"state"] ?: kSCIDownloadActionStateQueued;
    mutable[@"progress"] = @([mutable[@"progress"] doubleValue]);
    mutable[@"title"] = mutable[@"title"] ?: [NSString stringWithFormat:@"Item %lu", (unsigned long)(index + 1)];
    if (!mutable[@"mediaKind"] && actionDescriptor[@"mediaKind"]) mutable[@"mediaKind"] = actionDescriptor[@"mediaKind"];
    if (!mutable[@"sourceLabel"] && actionDescriptor[@"sourceLabel"]) mutable[@"sourceLabel"] = actionDescriptor[@"sourceLabel"];
    if (!mutable[@"timestamp"] && actionDescriptor[@"createdAt"]) mutable[@"timestamp"] = actionDescriptor[@"createdAt"];
    return mutable;
}

+ (instancetype)shared {
    static SCIDownloadQueueManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [SCIDownloadQueueManager new];
    });
    return manager;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _taskRecords = [NSMutableDictionary dictionary];
    _taskStartBlocks = [NSMutableDictionary dictionary];
    _taskCancelBlocks = [NSMutableDictionary dictionary];
    _actionCancelBlocks = [NSMutableDictionary dictionary];
    _actionRetryBlocks = [NSMutableDictionary dictionary];
    _queueBatchActionIDs = [NSMutableSet set];
    _mutableActions = [NSMutableArray array];

    NSData *data = [NSData dataWithContentsOfFile:[self historyPath]];
    if (data.length > 0) {
        NSArray *stored = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        if ([stored isKindOfClass:NSArray.class]) {
            for (NSDictionary *entry in stored) {
                if (![entry isKindOfClass:NSDictionary.class]) continue;
                NSMutableDictionary *action = [NSMutableDictionary dictionaryWithDictionary:entry];
                NSMutableArray *items = [NSMutableArray array];
                for (NSDictionary *item in action[@"items"] ?: @[]) {
                    if (![item isKindOfClass:NSDictionary.class]) continue;
                    NSMutableDictionary *mutableItem = [NSMutableDictionary dictionaryWithDictionary:item];
                    NSString *state = mutableItem[@"state"];
                    if ([state isEqualToString:kSCIDownloadActionStateQueued] || [state isEqualToString:kSCIDownloadActionStateRunning]) {
                        mutableItem[@"state"] = kSCIDownloadActionStateInterrupted;
                        mutableItem[@"error"] = @"Interrupted when Instagram exited";
                        mutableItem[@"progress"] = @1.0;
                    }
                    [items addObject:mutableItem];
                }
                action[@"items"] = items;
                NSString *state = action[@"state"];
                if ([state isEqualToString:kSCIDownloadActionStateQueued] || [state isEqualToString:kSCIDownloadActionStateRunning]) {
                    action[@"state"] = kSCIDownloadActionStateInterrupted;
                    action[@"detail"] = @"Interrupted when Instagram exited";
                }
                [self.mutableActions addObject:action];
            }
        }
    }

    for (NSMutableDictionary *action in self.mutableActions) {
        [self recomputeAction:action touchUpdatedAt:NO];
    }
    [self trimAndPersist];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(defaultsChanged:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)defaultsChanged:(NSNotification *)notification {
    (void)notification;
    @synchronized (self) {
        [self trimAndPersist];
    }
    [self notifyChanged];
    [self refreshConcurrencyLimit];
}

- (NSString *)historyPath {
    return [[SCIStoragePaths downloadsDirectory] stringByAppendingPathComponent:@"history.json"];
}

- (NSArray<NSDictionary *> *)jobs {
    @synchronized (self) {
        NSArray *copy = [[NSArray alloc] initWithArray:self.mutableActions copyItems:YES];
        return [copy sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            double lhs = [a[@"createdAt"] doubleValue];
            double rhs = [b[@"createdAt"] doubleValue];
            if (lhs == rhs) return NSOrderedSame;
            return lhs < rhs ? NSOrderedDescending : NSOrderedAscending;
        }];
    }
}

- (NSInteger)limit {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kSCIDownloadMaxConcurrentKey];
    return MAX(1, MIN(4, value > 0 ? value : 2));
}

- (NSInteger)historyLimit {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kSCIDownloadHistoryLimitKey];
    if (value <= 0) value = 300;
    return MAX(50, MIN(1000, value));
}

- (NSMutableDictionary *)actionForID:(NSString *)actionID {
    for (NSMutableDictionary *action in self.mutableActions) {
        if ([action[@"id"] isEqualToString:actionID]) return action;
    }
    return nil;
}

- (NSMutableDictionary *)itemForAction:(NSMutableDictionary *)action index:(NSUInteger)index {
    NSMutableArray *items = action[@"items"];
    if (index >= items.count) return nil;
    id item = items[index];
    return [item isKindOfClass:NSMutableDictionary.class] ? item : nil;
}

- (NSMutableDictionary *)taskForID:(NSString *)taskID {
    return self.taskRecords[taskID];
}

- (NSArray<NSMutableDictionary *> *)tasksForActionID:(NSString *)actionID {
    NSMutableArray *tasks = [NSMutableArray array];
    [self.taskRecords enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableDictionary *task, BOOL *stop) {
        (void)key;
        (void)stop;
        if ([task[@"actionID"] isEqualToString:actionID]) [tasks addObject:task];
    }];
    return tasks;
}

- (NSDictionary *)unitCountsForAction:(NSDictionary *)action {
    NSUInteger total = 0;
    NSUInteger active = 0;
    NSUInteger queued = 0;
    NSUInteger completed = 0;
    NSUInteger failed = 0;
    NSUInteger interrupted = 0;
    NSUInteger cancelled = 0;
    for (NSDictionary *item in action[@"items"] ?: @[]) {
        total += 1;
        NSString *state = item[@"state"] ?: kSCIDownloadActionStateQueued;
        if ([state isEqualToString:kSCIDownloadActionStateRunning]) active += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateQueued]) queued += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateCompleted]) completed += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateFailed]) failed += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateInterrupted]) interrupted += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateCancelled]) cancelled += 1;
        else if ([state isEqualToString:kSCIDownloadActionStatePartial]) failed += 1;
    }
    return @{@"total": @(MAX((NSUInteger)1, total)),
             @"active": @(active),
             @"queued": @(queued),
             @"completed": @(completed),
             @"failed": @(failed),
             @"interrupted": @(interrupted),
             @"cancelled": @(cancelled)};
}

- (void)recomputeAction:(NSMutableDictionary *)action touchUpdatedAt:(BOOL)touchUpdatedAt {
    NSMutableDictionary *descriptor = action[@"descriptor"];
    if (![descriptor isKindOfClass:NSMutableDictionary.class]) {
        descriptor = [NSMutableDictionary dictionaryWithDictionary:descriptor ?: @{}];
        action[@"descriptor"] = descriptor;
    }
    NSMutableArray *items = action[@"items"];
    if (![items isKindOfClass:NSMutableArray.class] || items.count == 0) {
        action[@"items"] = [NSMutableArray arrayWithObject:[@{@"state": kSCIDownloadActionStateQueued, @"progress": @0.0, @"title": @"Item 1"} mutableCopy]];
        items = action[@"items"];
    }

    NSUInteger queued = 0;
    NSUInteger running = 0;
    NSUInteger completed = 0;
    NSUInteger failed = 0;
    NSUInteger interrupted = 0;
    NSUInteger cancelled = 0;
    double progressTotal = 0.0;

    for (NSUInteger idx = 0; idx < items.count; idx++) {
        NSMutableDictionary *item = [self itemForAction:action index:idx];
        if (!item) continue;
        NSString *state = item[@"state"] ?: kSCIDownloadActionStateQueued;
        double progress = MAX(0.0, MIN(1.0, [item[@"progress"] doubleValue]));
        if (SCIQueueStateIsTerminal(state)) progress = 1.0;
        item[@"progress"] = @(progress);
        progressTotal += progress;

        if ([state isEqualToString:kSCIDownloadActionStateQueued]) queued += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateRunning]) running += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateCompleted]) completed += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateFailed]) failed += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateInterrupted]) interrupted += 1;
        else if ([state isEqualToString:kSCIDownloadActionStateCancelled]) cancelled += 1;
        else if ([state isEqualToString:kSCIDownloadActionStatePartial]) failed += 1;
    }

    NSString *state = kSCIDownloadActionStateCompleted;
    if (running > 0) state = kSCIDownloadActionStateRunning;
    else if (queued > 0) state = kSCIDownloadActionStateQueued;
    else if (completed == items.count) state = kSCIDownloadActionStateCompleted;
    else if (completed > 0 && (failed > 0 || interrupted > 0 || cancelled > 0)) state = kSCIDownloadActionStatePartial;
    else if (failed > 0) state = kSCIDownloadActionStateFailed;
    else if (interrupted > 0) state = kSCIDownloadActionStateInterrupted;
    else if (cancelled > 0) state = kSCIDownloadActionStateCancelled;

    action[@"state"] = state;
    action[@"progress"] = @(items.count > 0 ? progressTotal / (double)items.count : 0.0);
    if (touchUpdatedAt) action[@"updatedAt"] = @(SCIQueueNow());
    if (SCIQueueStateIsTerminal(state)) {
        if (!action[@"finishedAt"]) action[@"finishedAt"] = @(SCIQueueNow());
    } else {
        [action removeObjectForKey:@"finishedAt"];
    }
    descriptor[@"itemCount"] = @(items.count);
}

- (void)persist {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.mutableActions options:0 error:&error];
    if (data.length > 0 && !error) {
        [data writeToFile:[self historyPath] atomically:YES];
    }
}

- (void)notifyChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIDownloadQueueDidChangeNotification object:self];
    });
}

- (void)trimAndPersist {
    NSInteger limit = [self historyLimit];
    while (self.mutableActions.count > limit) {
        NSUInteger removeIndex = NSNotFound;
        NSTimeInterval oldest = DBL_MAX;
        for (NSUInteger i = 0; i < self.mutableActions.count; i++) {
            NSDictionary *action = self.mutableActions[i];
            if ([action[@"state"] isEqualToString:kSCIDownloadActionStateQueued] || [action[@"state"] isEqualToString:kSCIDownloadActionStateRunning]) continue;
            NSTimeInterval createdAt = [action[@"createdAt"] doubleValue];
            if (createdAt < oldest) {
                oldest = createdAt;
                removeIndex = i;
            }
        }
        if (removeIndex == NSNotFound) break;
        [self.mutableActions removeObjectAtIndex:removeIndex];
    }
    [self persist];
}

- (NSUInteger)activeTaskCountLocked {
    __block NSUInteger count = 0;
    [self.taskRecords enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *task, BOOL *stop) {
        (void)key;
        (void)stop;
        if ([task[@"state"] isEqualToString:kSCIDownloadActionStateRunning]) count += 1;
    }];
    return count;
}

- (BOOL)shouldShowAggregateQueuePillLocked {
    NSUInteger activeUnits = 0;
    NSUInteger queuedUnits = 0;
    for (NSDictionary *action in self.mutableActions) {
        NSDictionary *counts = [self unitCountsForAction:action];
        activeUnits += [counts[@"active"] unsignedIntegerValue];
        queuedUnits += [counts[@"queued"] unsignedIntegerValue];
    }
    return (activeUnits + queuedUnits) > 0;
}

- (BOOL)shouldShowStandaloneProgressForActionID:(NSString *)actionID {
    @synchronized (self) {
        (void)actionID;
        return NO;
    }
}

- (void)openDownloadsHistory {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = topMostController();
        if ([presenter isKindOfClass:UINavigationController.class] &&
            [((UINavigationController *)presenter).topViewController isKindOfClass:SCIDownloadHistoryViewController.class]) {
            return;
        }
        SCIDownloadHistoryViewController *vc = [SCIDownloadHistoryViewController new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        if (@available(iOS 15.0, *)) {
            UISheetPresentationController *sheet = nav.sheetPresentationController;
            sheet.prefersGrabberVisible = YES;
            sheet.detents = @[
                UISheetPresentationControllerDetent.mediumDetent,
                UISheetPresentationControllerDetent.largeDetent
            ];
            sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
        }
        [presenter presentViewController:nav animated:YES completion:nil];
    });
}

- (void)confirmCancelAllPendingFromPill {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = topMostController();
        if (!presenter) return;
        [SCIIGAlertPresenter presentAlertFromViewController:presenter
                                                      title:@"Cancel pending downloads?"
                                                    message:@"This stops queued work and any active downloads that can still be cancelled."
                                                    actions:@[
            [SCIIGAlertAction actionWithTitle:@"Keep" style:SCIIGAlertActionStyleCancel handler:nil],
            [SCIIGAlertAction actionWithTitle:@"Cancel All" style:SCIIGAlertActionStyleDestructive handler:^{
                [self cancelAllPending];
            }]
        ]];
    });
}

- (void)updateQueuePill {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSDictionary *> *actions = nil;
        BOOL shouldShow = NO;
        @synchronized (self) {
            actions = [[self jobs] copy];
            shouldShow = [self shouldShowAggregateQueuePillLocked];
            if (shouldShow) {
                for (NSDictionary *action in actions) {
                    NSDictionary *counts = [self unitCountsForAction:action];
                    if ([counts[@"active"] unsignedIntegerValue] > 0 || [counts[@"queued"] unsignedIntegerValue] > 0) {
                        [self.queueBatchActionIDs addObject:action[@"id"]];
                    }
                }
            }
        }

        if (!shouldShow && !self.queuePill && self.queueBatchActionIDs.count == 0) return;
        if (!self.queuePill && shouldShow) {
            __weak typeof(self) weakSelf = self;
            self.queuePill = [[SCINotificationCenter shared] beginUnmanagedProgressWithTitle:@"Downloads" onCancel:^{
                [weakSelf confirmCancelAllPendingFromPill];
            }];
            self.queuePill.onTapWhenProgress = ^{
                [weakSelf openDownloadsHistory];
            };
            self.queuePill.onTapWhenCompleted = ^{
                [weakSelf openDownloadsHistory];
            };
            self.queueTerminalSignature = nil;
        }
        if (!self.queuePill) return;

        NSUInteger total = 0;
        NSUInteger active = 0;
        NSUInteger queued = 0;
        NSUInteger completed = 0;
        NSUInteger failed = 0;
        NSUInteger interrupted = 0;
        NSUInteger cancelled = 0;
        NSDictionary *singleTrackedAction = nil;
        for (NSDictionary *action in actions) {
            if (![self.queueBatchActionIDs containsObject:action[@"id"]]) continue;
            NSDictionary *counts = [self unitCountsForAction:action];
            total += [counts[@"total"] unsignedIntegerValue];
            active += [counts[@"active"] unsignedIntegerValue];
            queued += [counts[@"queued"] unsignedIntegerValue];
            completed += [counts[@"completed"] unsignedIntegerValue];
            failed += [counts[@"failed"] unsignedIntegerValue];
            interrupted += [counts[@"interrupted"] unsignedIntegerValue];
            cancelled += [counts[@"cancelled"] unsignedIntegerValue];
            if (!singleTrackedAction) singleTrackedAction = action;
            else singleTrackedAction = nil;
        }

        if (total == 0) {
            [self.queuePill dismiss];
            self.queuePill = nil;
            [self.queueBatchActionIDs removeAllObjects];
            self.queueTerminalSignature = nil;
            return;
        }

        NSUInteger terminal = total - active - queued;
        float progress = total > 0 ? (float)terminal / (float)total : 0.0f;
        __weak typeof(self) weakSelf = self;
        BOOL isSingleAction = self.queueBatchActionIDs.count == 1 && singleTrackedAction != nil;
        NSString *progressTitle = isSingleAction ? SCIQueueProgressTitleForAction(singleTrackedAction) : @"Downloads";

        if (active > 0 || queued > 0) {
            self.queueTerminalSignature = nil;
            NSString *subtitle = nil;
            if (isSingleAction) {
                NSString *actionDetail = singleTrackedAction[@"detail"] ?: @"";
                NSUInteger currentIndex = MIN(total, MAX((NSUInteger)1, completed + (active > 0 ? 1 : 0)));
                NSString *indexText = total > 1 ? [NSString stringWithFormat:@"[%lu of %lu]", (unsigned long)currentIndex, (unsigned long)total] : nil;
                if (indexText.length > 0 && actionDetail.length > 0 && ![actionDetail isEqualToString:progressTitle]) {
                    subtitle = [NSString stringWithFormat:@"%@ • %@", actionDetail, indexText];
                } else if (indexText.length > 0) {
                    subtitle = indexText;
                } else if (actionDetail.length > 0 && ![actionDetail isEqualToString:progressTitle]) {
                    subtitle = actionDetail;
                } else {
                    subtitle = queued > 0 ? @"Queued" : nil;
                }
            } else {
                subtitle = queued > 0
                    ? [NSString stringWithFormat:@"%lu active · %lu queued", (unsigned long)active, (unsigned long)queued]
                    : [NSString stringWithFormat:@"%lu of %lu complete", (unsigned long)terminal, (unsigned long)total];
            }
            [self.queuePill updateProgressTitle:progressTitle subtitle:subtitle];
            [self.queuePill setProgress:progress animated:YES];
            self.queuePill.onTapWhenProgress = ^{
                [weakSelf openDownloadsHistory];
            };
            return;
        }

        NSUInteger issueCount = failed + interrupted;
        NSString *terminalSignature = [NSString stringWithFormat:@"%@|%@|%lu|%lu|%lu|%lu|%lu|%lu",
                                       [[self.queueBatchActionIDs.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","],
                                       isSingleAction ? (singleTrackedAction[@"state"] ?: @"") : @"batch",
                                       (unsigned long)completed,
                                       (unsigned long)issueCount,
                                       (unsigned long)cancelled,
                                       (unsigned long)total,
                                       (unsigned long)active,
                                       (unsigned long)queued];
        if ([self.queueTerminalSignature isEqualToString:terminalSignature]) return;
        self.queueTerminalSignature = terminalSignature;
        NSUInteger generation = ++self.queueBatchGeneration;
        NSString *title = nil;
        NSString *subtitle = nil;
        if (issueCount > 0) {
            title = isSingleAction ? SCIQueueProgressTitleForAction(singleTrackedAction) : @"Downloads finished with errors";
            subtitle = isSingleAction
                ? (singleTrackedAction[@"detail"] ?: @"Finished with errors")
                : [NSString stringWithFormat:@"%lu complete · %lu failed", (unsigned long)completed, (unsigned long)issueCount];
            [self.queuePill showErrorWithTitle:title subtitle:subtitle icon:nil];
        } else if (cancelled > 0 && completed == 0) {
            title = isSingleAction ? SCIQueueProgressTitleForAction(singleTrackedAction) : @"Downloads cancelled";
            subtitle = isSingleAction
                ? (singleTrackedAction[@"detail"] ?: @"Cancelled")
                : [NSString stringWithFormat:@"%lu cancelled", (unsigned long)cancelled];
            [self.queuePill showInfoWithTitle:title subtitle:subtitle icon:nil];
        } else {
            title = isSingleAction ? SCIQueueProgressTitleForAction(singleTrackedAction) : @"Downloads complete";
            subtitle = isSingleAction
                ? @"Tap to open Downloads"
                : [NSString stringWithFormat:@"%lu of %lu complete", (unsigned long)completed, (unsigned long)total];
            [self.queuePill showSuccessWithTitle:title subtitle:subtitle icon:nil];
        }
        self.queuePill.onTapWhenCompleted = ^{
            [weakSelf openDownloadsHistory];
        };
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SCINotificationPillDuration() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != self.queueBatchGeneration) return;
            [self.queuePill dismiss];
            self.queuePill = nil;
            [self.queueBatchActionIDs removeAllObjects];
            self.queueTerminalSignature = nil;
        });
    });
}

- (NSString *)createActionWithTitle:(NSString *)title
                             detail:(NSString *)detail
                         descriptor:(NSDictionary *)descriptor
                              items:(NSArray<NSDictionary *> *)items
                              retry:(SCIDownloadQueueActionRetryBlock)retry {
    NSString *actionID = NSUUID.UUID.UUIDString;
    NSTimeInterval now = SCIQueueNow();
    NSMutableDictionary *resolvedDescriptor = [NSMutableDictionary dictionaryWithDictionary:descriptor ?: @{}];
    NSMutableArray *resolvedItems = [NSMutableArray array];
    NSArray *sourceItems = items.count > 0 ? items : @[@{}];
    for (NSUInteger idx = 0; idx < sourceItems.count; idx++) {
        [resolvedItems addObject:SCIQueueMutableItemDescriptor(sourceItems[idx], idx, resolvedDescriptor)];
    }

    NSMutableDictionary *action = [@{
        @"id": actionID,
        @"title": title ?: @"Media download",
        @"detail": detail ?: @"Waiting",
        @"createdAt": @(now),
        @"updatedAt": @(now),
        @"progress": @0.0,
        @"state": kSCIDownloadActionStateQueued,
        @"descriptor": resolvedDescriptor,
        @"items": resolvedItems
    } mutableCopy];

    @synchronized (self) {
        [self.mutableActions addObject:action];
        if (retry) self.actionRetryBlocks[actionID] = [retry copy];
        [self recomputeAction:action touchUpdatedAt:NO];
        [self trimAndPersist];
    }
    [self notifyChanged];
    [self updateQueuePill];
    return actionID;
}

- (void)setRetryBlock:(SCIDownloadQueueActionRetryBlock)retryBlock forActionID:(NSString *)actionID {
    @synchronized (self) {
        if (retryBlock) self.actionRetryBlocks[actionID] = [retryBlock copy];
        else [self.actionRetryBlocks removeObjectForKey:actionID];
    }
}

- (void)setCancelBlock:(SCIDownloadQueueTaskCancelBlock)cancelBlock forActionID:(NSString *)actionID {
    @synchronized (self) {
        if (cancelBlock) self.actionCancelBlocks[actionID] = [cancelBlock copy];
        else [self.actionCancelBlocks removeObjectForKey:actionID];
    }
}

- (void)reactivateActionID:(NSString *)actionID
                descriptor:(NSDictionary *)descriptor
                    detail:(NSString *)detail
           resetItemIndexes:(NSIndexSet *)indexes {
    @synchronized (self) {
        NSMutableDictionary *action = [self actionForID:actionID];
        if (!action) return;
        if (descriptor) action[@"descriptor"] = [NSMutableDictionary dictionaryWithDictionary:descriptor];
        if (detail.length > 0) action[@"detail"] = detail;
        [action removeObjectForKey:@"finishedAt"];
        [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            (void)stop;
            NSMutableDictionary *item = [self itemForAction:action index:idx];
            if (!item) return;
            item[@"state"] = kSCIDownloadActionStateQueued;
            item[@"progress"] = @0.0;
            [item removeObjectForKey:@"error"];
            [item removeObjectForKey:@"previewPath"];
            [item removeObjectForKey:@"localFilePath"];
            if (item[@"detail"]) item[@"detail"] = @"Waiting";
        }];
        [self recomputeAction:action touchUpdatedAt:YES];
        [self trimAndPersist];
    }
    [self notifyChanged];
    [self updateQueuePill];
}

- (NSString *)enqueueTaskForActionID:(NSString *)actionID
                           itemIndex:(NSUInteger)itemIndex
                               title:(NSString *)title
                               start:(SCIDownloadQueueTaskStartBlock)start {
    NSString *taskID = NSUUID.UUID.UUIDString;
    @synchronized (self) {
        NSMutableDictionary *action = [self actionForID:actionID];
        if (!action) return nil;
        NSMutableDictionary *item = [self itemForAction:action index:itemIndex];
        if (!item) return nil;
        item[@"state"] = kSCIDownloadActionStateQueued;
        item[@"progress"] = @0.0;
        item[@"detail"] = title.length > 0 ? title : @"Waiting";
        NSMutableDictionary *task = [@{
            @"id": taskID,
            @"actionID": actionID,
            @"itemIndex": @(itemIndex),
            @"state": kSCIDownloadActionStateQueued,
            @"title": title ?: @"Download"
        } mutableCopy];
        self.taskRecords[taskID] = task;
        if (start) self.taskStartBlocks[taskID] = [start copy];
        [self recomputeAction:action touchUpdatedAt:YES];
        [self trimAndPersist];
    }
    [self notifyChanged];
    [self updateQueuePill];
    [self drain];
    return taskID;
}

- (void)setCancelBlock:(SCIDownloadQueueTaskCancelBlock)cancelBlock forTaskID:(NSString *)taskID {
    @synchronized (self) {
        if (cancelBlock) self.taskCancelBlocks[taskID] = [cancelBlock copy];
        else [self.taskCancelBlocks removeObjectForKey:taskID];
    }
}

- (void)updateActionDescriptor:(NSDictionary *)descriptor forActionID:(NSString *)actionID {
    @synchronized (self) {
        NSMutableDictionary *action = [self actionForID:actionID];
        if (!action) return;
        action[@"descriptor"] = [NSMutableDictionary dictionaryWithDictionary:descriptor ?: @{}];
        [self recomputeAction:action touchUpdatedAt:YES];
        [self persist];
    }
    [self notifyChanged];
}

- (void)updateActionDetail:(NSString *)detail progress:(double)progress forActionID:(NSString *)actionID {
    @synchronized (self) {
        NSMutableDictionary *action = [self actionForID:actionID];
        if (!action) return;
        if (detail.length > 0) action[@"detail"] = detail;
        action[@"progress"] = @(MAX(0.0, MIN(1.0, progress)));
        action[@"updatedAt"] = @(SCIQueueNow());
        [self persist];
    }
    [self notifyChanged];
}

- (void)updateItemAtIndex:(NSUInteger)index forJobID:(NSString *)jobID usingBlock:(SCIDownloadQueueItemMutationBlock)block {
    if (!block) return;
    @synchronized (self) {
        NSMutableDictionary *action = [self actionForID:jobID];
        if (!action) return;
        NSMutableDictionary *item = [self itemForAction:action index:index];
        if (!item) return;
        block(item);
        [self recomputeAction:action touchUpdatedAt:YES];
        [self trimAndPersist];
    }
    [self notifyChanged];
    [self updateQueuePill];
}

- (void)updateTaskID:(NSString *)taskID progress:(double)progress detail:(NSString *)detail {
    @synchronized (self) {
        NSMutableDictionary *task = [self taskForID:taskID];
        if (!task) return;
        task[@"progress"] = @(MAX(0.0, MIN(1.0, progress)));
        NSMutableDictionary *action = [self actionForID:task[@"actionID"]];
        NSMutableDictionary *item = [self itemForAction:action index:[task[@"itemIndex"] unsignedIntegerValue]];
        if (!action || !item) return;
        item[@"state"] = kSCIDownloadActionStateRunning;
        item[@"progress"] = task[@"progress"];
        if (detail.length > 0) item[@"detail"] = detail;
        if (detail.length > 0) action[@"detail"] = detail;
        [self recomputeAction:action touchUpdatedAt:YES];
        [self persist];
    }
    [self notifyChanged];
    [self updateQueuePill];
}

- (void)settleTaskID:(NSString *)taskID
          itemState:(NSString *)itemState
             detail:(NSString *)detail
           filePath:(NSString *)filePath
              error:(NSString *)errorText {
    @synchronized (self) {
        NSMutableDictionary *task = [self taskForID:taskID];
        if (!task) return;
        NSMutableDictionary *action = [self actionForID:task[@"actionID"]];
        NSMutableDictionary *item = [self itemForAction:action index:[task[@"itemIndex"] unsignedIntegerValue]];
        if (!action || !item) {
            [self.taskRecords removeObjectForKey:taskID];
            [self.taskStartBlocks removeObjectForKey:taskID];
            [self.taskCancelBlocks removeObjectForKey:taskID];
            return;
        }
        item[@"state"] = itemState;
        item[@"progress"] = @1.0;
        if (detail.length > 0) {
            item[@"detail"] = detail;
            action[@"detail"] = detail;
        }
        if (filePath.length > 0) {
            item[@"previewPath"] = filePath;
            if ([action[@"items"] count] == 1) action[@"localFilePath"] = filePath;
        }
        if (errorText.length > 0) item[@"error"] = errorText;
        else [item removeObjectForKey:@"error"];
        [self.taskRecords removeObjectForKey:taskID];
        [self.taskStartBlocks removeObjectForKey:taskID];
        [self.taskCancelBlocks removeObjectForKey:taskID];
        [self recomputeAction:action touchUpdatedAt:YES];
        [self trimAndPersist];
    }
    [self notifyChanged];
    [self updateQueuePill];
    [self drain];
}

- (void)finishTaskID:(NSString *)taskID detail:(NSString *)detail filePath:(NSString *)filePath {
    [self settleTaskID:taskID itemState:kSCIDownloadActionStateCompleted detail:detail ?: @"Completed" filePath:filePath error:nil];
}

- (void)failTaskID:(NSString *)taskID error:(NSError *)error {
    [self settleTaskID:taskID
             itemState:kSCIDownloadActionStateFailed
                detail:error.localizedDescription ?: @"Download failed"
              filePath:nil
                 error:error.localizedDescription ?: @"Download failed"];
}

- (void)cancelTaskID:(NSString *)taskID {
    SCIDownloadQueueTaskCancelBlock cancel = nil;
    @synchronized (self) {
        NSMutableDictionary *task = [self taskForID:taskID];
        if (!task) return;
        cancel = self.taskCancelBlocks[taskID];
    }
    if (cancel) cancel();
    [self settleTaskID:taskID itemState:kSCIDownloadActionStateCancelled detail:@"Cancelled" filePath:nil error:nil];
}

- (void)cancelJobID:(NSString *)jobID {
    NSArray<NSMutableDictionary *> *tasks = nil;
    SCIDownloadQueueTaskCancelBlock actionCancel = nil;
    @synchronized (self) {
        NSMutableDictionary *action = [self actionForID:jobID];
        if (!action) return;
        actionCancel = self.actionCancelBlocks[jobID];
        tasks = [[self tasksForActionID:jobID] copy];
        for (NSMutableDictionary *item in action[@"items"] ?: @[]) {
            NSString *state = item[@"state"];
            if ([state isEqualToString:kSCIDownloadActionStateQueued] || [state isEqualToString:kSCIDownloadActionStateRunning]) {
                item[@"state"] = kSCIDownloadActionStateCancelled;
                item[@"progress"] = @1.0;
                item[@"detail"] = @"Cancelled";
            }
        }
        action[@"detail"] = @"Cancelled";
        [self recomputeAction:action touchUpdatedAt:YES];
        [self trimAndPersist];
    }
    if (actionCancel) actionCancel();
    for (NSDictionary *task in tasks) {
        SCIDownloadQueueTaskCancelBlock cancel = nil;
        @synchronized (self) {
            cancel = self.taskCancelBlocks[task[@"id"]];
            [self.taskRecords removeObjectForKey:task[@"id"]];
            [self.taskStartBlocks removeObjectForKey:task[@"id"]];
            [self.taskCancelBlocks removeObjectForKey:task[@"id"]];
        }
        if (cancel) cancel();
    }
    [self notifyChanged];
    [self updateQueuePill];
    [self drain];
}

- (void)cancelAllPending {
    for (NSDictionary *action in self.jobs) {
        NSString *state = action[@"state"];
        if ([state isEqualToString:kSCIDownloadActionStateQueued] || [state isEqualToString:kSCIDownloadActionStateRunning]) {
            [self cancelJobID:action[@"id"]];
        }
    }
}

- (void)retryURLActionID:(NSString *)actionID {
    NSDictionary *action = [self actionForID:actionID];
    NSDictionary *descriptor = action[@"descriptor"] ?: @{};
    NSString *urlString = descriptor[@"url"];
    NSURL *url = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
    if (!url) {
        [self updateItemAtIndex:0 forJobID:actionID usingBlock:^(NSMutableDictionary *item) {
            item[@"state"] = kSCIDownloadActionStateFailed;
            item[@"error"] = @"Retry unavailable: the source URL is missing";
            item[@"detail"] = item[@"error"];
            item[@"progress"] = @1.0;
        }];
        return;
    }

    [self reactivateActionID:actionID descriptor:descriptor detail:@"Retrying" resetItemIndexes:[NSIndexSet indexSetWithIndex:0]];

    SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:[descriptor[@"action"] integerValue]
                                                                    showProgress:[descriptor[@"showProgress"] boolValue]];
    delegate.notificationIdentifier = descriptor[@"notificationIdentifier"];
    delegate.queueActionID = actionID;
    delegate.pendingGallerySaveMetadata = [SCIDownloadDelegate metadataFromDescriptor:descriptor[@"metadata"] ?: @{}];
    __weak typeof(delegate) weakDelegate = delegate;
    NSString *taskID = [self enqueueTaskForActionID:actionID itemIndex:0 title:@"Retrying" start:^(NSString *taskID) {
        __strong typeof(weakDelegate) strongDelegate = weakDelegate;
        if (!strongDelegate) return;
        strongDelegate.queueJobID = taskID;
        [strongDelegate startDownloadFileWithURL:url fileExtension:descriptor[@"extension"] hudLabel:action[@"title"]];
    }];
    [self setCancelBlock:^{
        __strong typeof(weakDelegate) strongDelegate = weakDelegate;
        [strongDelegate.downloadManager cancelDownload];
    } forTaskID:taskID];
}

- (void)retryJobID:(NSString *)jobID {
    NSDictionary *job = [self actionForID:jobID];
    if (!job) return;
    NSDictionary *descriptor = job[@"descriptor"] ?: @{};
    NSString *kind = descriptor[@"kind"];
    if ([kind isEqualToString:@"bulk"]) {
        [SCIBulkDownloadCoordinator retrySummaryJobID:jobID childIndexes:nil];
        return;
    }
    if ([kind isEqualToString:@"url"]) {
        [self retryURLActionID:jobID];
        return;
    }
    SCIDownloadQueueActionRetryBlock retry = self.actionRetryBlocks[jobID];
    if (retry) {
        retry();
        return;
    }
}

- (void)retryChildAtIndex:(NSUInteger)index forJobID:(NSString *)jobID {
    [SCIBulkDownloadCoordinator retrySummaryJobID:jobID childIndexes:[NSIndexSet indexSetWithIndex:index]];
}

- (BOOL)canRetryJob:(NSDictionary *)job {
    NSString *state = job[@"state"] ?: @"";
    if (![@[kSCIDownloadActionStateFailed,
            kSCIDownloadActionStateInterrupted,
            kSCIDownloadActionStatePartial,
            kSCIDownloadActionStateCancelled] containsObject:state]) {
        return NO;
    }
    NSDictionary *descriptor = job[@"descriptor"] ?: @{};
    NSString *kind = descriptor[@"kind"];
    if ([kind isEqualToString:@"bulk"]) return [SCIBulkDownloadCoordinator canRetryDescriptor:descriptor childIndexes:nil];
    if ([kind isEqualToString:@"url"]) return [descriptor[@"url"] length] > 0;
    return self.actionRetryBlocks[job[@"id"]] != nil;
}

- (BOOL)canRetryChildAtIndex:(NSUInteger)index forJob:(NSDictionary *)job {
    return [SCIBulkDownloadCoordinator canRetryDescriptor:job[@"descriptor"] childIndexes:[NSIndexSet indexSetWithIndex:index]];
}

- (NSString *)completionActionForJob:(NSDictionary *)job {
    return SCIQueueItemCompletionAction(job[@"descriptor"] ?: @{});
}

- (void)retryAllFailed {
    for (NSDictionary *job in self.jobs) {
        if ([self canRetryJob:job]) [self retryJobID:job[@"id"]];
    }
}

- (void)removeJobID:(NSString *)jobID {
    @synchronized (self) {
        [self.mutableActions filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *action, id bindings) {
            (void)bindings;
            return ![action[@"id"] isEqualToString:jobID];
        }]];
        [self.actionRetryBlocks removeObjectForKey:jobID];
        [self.actionCancelBlocks removeObjectForKey:jobID];
        NSArray<NSMutableDictionary *> *tasks = [self tasksForActionID:jobID];
        for (NSDictionary *task in tasks) {
            [self.taskRecords removeObjectForKey:task[@"id"]];
            [self.taskStartBlocks removeObjectForKey:task[@"id"]];
            [self.taskCancelBlocks removeObjectForKey:task[@"id"]];
        }
        [self persist];
    }
    [self notifyChanged];
    [self updateQueuePill];
}

- (void)clearHistory {
    BOOL hasActive = NO;
    @synchronized (self) {
        [self.mutableActions filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *action, id bindings) {
            (void)bindings;
            NSString *state = action[@"state"];
            return [state isEqualToString:kSCIDownloadActionStateQueued] || [state isEqualToString:kSCIDownloadActionStateRunning];
        }]];
        for (NSDictionary *action in self.mutableActions) {
            NSString *state = action[@"state"];
            if ([state isEqualToString:kSCIDownloadActionStateQueued] || [state isEqualToString:kSCIDownloadActionStateRunning]) {
                hasActive = YES;
                break;
            }
        }
        [self persist];
    }
    if (!hasActive) {
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm removeItemAtPath:[[SCIStoragePaths downloadsDirectory] stringByAppendingPathComponent:@"CarouselSources"] error:nil];
        [fm removeItemAtPath:[[SCIStoragePaths downloadsDirectory] stringByAppendingPathComponent:@"ActionStaging"] error:nil];
    }
    [self notifyChanged];
    [self updateQueuePill];
}

- (void)refreshConcurrencyLimit {
    [self drain];
}

- (void)drain {
    dispatch_async(dispatch_get_main_queue(), ^{
        while (YES) {
            NSMutableDictionary *nextTask = nil;
            SCIDownloadQueueTaskStartBlock start = nil;
            @synchronized (self) {
                if ([self activeTaskCountLocked] >= [self limit]) break;
                for (NSMutableDictionary *task in self.taskRecords.allValues) {
                    if ([task[@"state"] isEqualToString:kSCIDownloadActionStateQueued]) {
                        nextTask = task;
                        break;
                    }
                }
                if (!nextTask) break;
                start = self.taskStartBlocks[nextTask[@"id"]];
                if (!start) {
                    NSMutableDictionary *action = [self actionForID:nextTask[@"actionID"]];
                    NSMutableDictionary *item = [self itemForAction:action index:[nextTask[@"itemIndex"] unsignedIntegerValue]];
                    item[@"state"] = kSCIDownloadActionStateInterrupted;
                    item[@"error"] = @"Retry unavailable after restart";
                    item[@"detail"] = item[@"error"];
                    item[@"progress"] = @1.0;
                    [self.taskRecords removeObjectForKey:nextTask[@"id"]];
                    [self.taskCancelBlocks removeObjectForKey:nextTask[@"id"]];
                    [self.taskStartBlocks removeObjectForKey:nextTask[@"id"]];
                    [self recomputeAction:action touchUpdatedAt:YES];
                    [self trimAndPersist];
                    nextTask = nil;
                    continue;
                }
                nextTask[@"state"] = kSCIDownloadActionStateRunning;
                NSMutableDictionary *action = [self actionForID:nextTask[@"actionID"]];
                NSMutableDictionary *item = [self itemForAction:action index:[nextTask[@"itemIndex"] unsignedIntegerValue]];
                item[@"state"] = kSCIDownloadActionStateRunning;
                item[@"detail"] = @"Starting";
                item[@"progress"] = @0.02;
                action[@"detail"] = @"Starting";
                [self recomputeAction:action touchUpdatedAt:YES];
                [self persist];
            }
            [self notifyChanged];
            [self updateQueuePill];
            start(nextTask[@"id"]);
        }
        [self updateQueuePill];
    });
}

@end

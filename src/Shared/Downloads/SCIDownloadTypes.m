#import "SCIDownloadTypes.h"

NSErrorDomain const SCIDownloadErrorDomain = @"com.scinsta.download";

NSInteger const SCIDownloadStoreSchemaVersion = 2;

NSString * const kSCIDownloadMaxConcurrentKey = @"downloads_max_concurrent";
NSString * const kSCIDownloadHistoryLimitKey = @"downloads_history_limit";
NSString * const kSCIDownloadDetectDuplicatesKey = @"downloads_detect_duplicates";

NSNotificationName const SCIDownloadServiceDidChangeNotification = @"SCIDownloadServiceDidChangeNotification";
NSNotificationName const SCIDownloadJobDidChangeNotification = @"SCIDownloadJobDidChangeNotification";

NSString * const SCIDownloadNotificationJobIDKey = @"jobID";
NSString * const SCIDownloadNotificationItemIDKey = @"itemID";
NSString * const SCIDownloadNotificationSnapshotKey = @"snapshot";

NSError *SCIDownloadError(SCIDownloadErrorCode code, NSString *description, NSString *recovery) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (description.length > 0) info[NSLocalizedDescriptionKey] = description;
    if (recovery.length > 0) info[NSLocalizedRecoverySuggestionErrorKey] = recovery;
    return [NSError errorWithDomain:SCIDownloadErrorDomain code:code userInfo:info];
}

BOOL SCIDownloadStateIsTerminal(SCIDownloadState state) {
    switch (state) {
        case SCIDownloadStateSucceeded:
        case SCIDownloadStateFailed:
        case SCIDownloadStateCancelled:
        case SCIDownloadStateInterrupted:
            return YES;
        default:
            return NO;
    }
}

BOOL SCIDownloadStateAllowsTransition(SCIDownloadState from, SCIDownloadState to) {
    if (from == to) return YES;
    if (SCIDownloadStateIsTerminal(from)) return NO;
    switch (from) {
        case SCIDownloadStatePending:
            return to == SCIDownloadStateWaitingForPreflight || to == SCIDownloadStateQueued || to == SCIDownloadStateCancelled;
        case SCIDownloadStateWaitingForPreflight:
            return to == SCIDownloadStateQueued || to == SCIDownloadStateCancelled;
        case SCIDownloadStateQueued:
            return to == SCIDownloadStateRunning || to == SCIDownloadStateCancelled;
        case SCIDownloadStateRunning:
            return to == SCIDownloadStateFinalizing || to == SCIDownloadStateFailed || to == SCIDownloadStateCancelled || to == SCIDownloadStateInterrupted;
        case SCIDownloadStateFinalizing:
            return to == SCIDownloadStateSucceeded || to == SCIDownloadStateFailed || to == SCIDownloadStateCancelled;
        case SCIDownloadStateFailed:
        case SCIDownloadStateCancelled:
        case SCIDownloadStateInterrupted:
            return to == SCIDownloadStateQueued;
        default:
            return NO;
    }
}

SCIDownloadState SCIDownloadDerivedJobState(NSArray<NSNumber *> *itemStates) {
    if (itemStates.count == 0) return SCIDownloadStatePending;
    BOOL anyRunning = NO;
    BOOL anyFinalizing = NO;
    BOOL anyQueuedLike = NO;
    NSUInteger succeeded = 0;
    NSUInteger failed = 0;
    NSUInteger cancelled = 0;
    NSUInteger interrupted = 0;
    for (NSNumber *n in itemStates) {
        SCIDownloadState s = (SCIDownloadState)n.integerValue;
        if (s == SCIDownloadStateRunning) anyRunning = YES;
        if (s == SCIDownloadStateFinalizing) anyFinalizing = YES;
        if (s == SCIDownloadStatePending || s == SCIDownloadStateWaitingForPreflight || s == SCIDownloadStateQueued) anyQueuedLike = YES;
        if (s == SCIDownloadStateSucceeded) succeeded++;
        else if (s == SCIDownloadStateFailed) failed++;
        else if (s == SCIDownloadStateCancelled) cancelled++;
        else if (s == SCIDownloadStateInterrupted) interrupted++;
    }
    if (anyRunning || anyFinalizing) return SCIDownloadStateRunning;
    if (anyQueuedLike) return SCIDownloadStateQueued;
    NSUInteger total = itemStates.count;
    if (succeeded == total) return SCIDownloadStateSucceeded;
    if (failed == total) return SCIDownloadStateFailed;
    if (cancelled == total) return SCIDownloadStateCancelled;
    if (interrupted == total) return SCIDownloadStateInterrupted;
    if (succeeded > 0 && (failed + cancelled + interrupted) > 0) return SCIDownloadStatePartial;
    if (failed > 0 && succeeded == 0 && cancelled == 0 && interrupted == 0) return SCIDownloadStateFailed;
    if (cancelled > 0 && succeeded == 0) return SCIDownloadStateCancelled;
    if (interrupted > 0 && succeeded == 0) return SCIDownloadStateInterrupted;
    return SCIDownloadStatePartial;
}

static NSString *SCIStateName(SCIDownloadState state) {
    switch (state) {
        case SCIDownloadStatePending: return @"Pending";
        case SCIDownloadStateWaitingForPreflight: return @"Waiting";
        case SCIDownloadStateQueued: return @"Queued";
        case SCIDownloadStateRunning: return @"Running";
        case SCIDownloadStateFinalizing: return @"Saving";
        case SCIDownloadStateSucceeded: return @"Completed";
        case SCIDownloadStatePartial: return @"Partial";
        case SCIDownloadStateFailed: return @"Failed";
        case SCIDownloadStateCancelled: return @"Cancelled";
        case SCIDownloadStateInterrupted: return @"Interrupted";
    }
    return @"Unknown";
}

NSString *SCIDownloadStateDisplayName(SCIDownloadState state) {
    return SCIStateName(state);
}

NSString *SCIDownloadDestinationDisplayName(SCIDownloadDestination destination) {
    switch (destination) {
        case SCIDownloadDestinationPhotos: return @"Photos";
        case SCIDownloadDestinationGallery: return @"Gallery";
        case SCIDownloadDestinationShare: return @"Share";
        case SCIDownloadDestinationClipboard: return @"Clipboard";
        case SCIDownloadDestinationCacheOnly: return @"Download";
    }
    return @"Download";
}

NSString *SCIDownloadSourceSurfaceDisplayName(SCIDownloadSourceSurface surface) {
    switch (surface) {
        case SCIDownloadSourceSurfaceFeed: return @"Feed";
        case SCIDownloadSourceSurfaceReels: return @"Reels";
        case SCIDownloadSourceSurfaceStories: return @"Stories";
        case SCIDownloadSourceSurfaceDirect: return @"Direct";
        case SCIDownloadSourceSurfaceAudioPage: return @"Audio";
        case SCIDownloadSourceSurfaceMediaPreview: return @"Preview";
        case SCIDownloadSourceSurfaceGallery: return @"Gallery";
        case SCIDownloadSourceSurfaceProfile: return @"Profile";
        case SCIDownloadSourceSurfaceInstants: return @"Instants";
        case SCIDownloadSourceSurfaceComments: return @"Comments";
        default: return @"Other";
    }
}

NSString *SCIDownloadMediaKindDisplayName(SCIDownloadMediaKind kind) {
    switch (kind) {
        case SCIDownloadMediaKindImage: return @"Image";
        case SCIDownloadMediaKindVideo: return @"Video";
        case SCIDownloadMediaKindAudio: return @"Audio";
        default: return @"Media";
    }
}

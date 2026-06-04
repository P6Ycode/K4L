#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const SCIDownloadErrorDomain;

typedef NS_ERROR_ENUM(SCIDownloadErrorDomain, SCIDownloadErrorCode) {
    SCIDownloadErrorInvalidURL = 1,
    SCIDownloadErrorUnsupportedScheme,
    SCIDownloadErrorExpiredURL,
    SCIDownloadErrorHTTPFailure,
    SCIDownloadErrorEmptyFile,
    SCIDownloadErrorInvalidContentType,
    SCIDownloadErrorFileMoveFailed,
    SCIDownloadErrorDiskFull,
    SCIDownloadErrorPhotosPermissionDenied,
    SCIDownloadErrorPhotosSaveFailed,
    SCIDownloadErrorGallerySaveFailed,
    SCIDownloadErrorSharePresentationFailed,
    SCIDownloadErrorClipboardTooLarge,
    SCIDownloadErrorDuplicateSkipped,
    SCIDownloadErrorCancelled,
    SCIDownloadErrorInterrupted,
    SCIDownloadErrorAudioPhotosUnsupported,
};

typedef NS_ENUM(NSInteger, SCIDownloadState) {
    SCIDownloadStatePending = 0,
    SCIDownloadStateWaitingForPreflight,
    SCIDownloadStateQueued,
    SCIDownloadStateRunning,
    SCIDownloadStateFinalizing,
    SCIDownloadStateSucceeded,
    SCIDownloadStatePartial,
    SCIDownloadStateFailed,
    SCIDownloadStateCancelled,
    SCIDownloadStateInterrupted,
};

typedef NS_ENUM(NSInteger, SCIDownloadSourceSurface) {
    SCIDownloadSourceSurfaceOther = 0,
    SCIDownloadSourceSurfaceFeed,
    SCIDownloadSourceSurfaceReels,
    SCIDownloadSourceSurfaceStories,
    SCIDownloadSourceSurfaceDirect,
    SCIDownloadSourceSurfaceAudioPage,
    SCIDownloadSourceSurfaceMediaPreview,
    SCIDownloadSourceSurfaceGallery,
    SCIDownloadSourceSurfaceProfile,
    SCIDownloadSourceSurfaceInstants,
    SCIDownloadSourceSurfaceComments,
};

typedef NS_ENUM(NSInteger, SCIDownloadDestination) {
    SCIDownloadDestinationPhotos = 0,
    SCIDownloadDestinationGallery,
    SCIDownloadDestinationShare,
    SCIDownloadDestinationClipboard,
    SCIDownloadDestinationCacheOnly,
};

typedef NS_ENUM(NSInteger, SCIDownloadPresentationMode) {
    SCIDownloadPresentationModeQueuePill = 0,
    SCIDownloadPresentationModeQuiet,
    SCIDownloadPresentationModeImmediateShare,
};

typedef NS_ENUM(NSInteger, SCIDownloadDuplicatePolicyMode) {
    SCIDownloadDuplicatePolicyAsk = 0,
    SCIDownloadDuplicatePolicyAlwaysDownload,
    SCIDownloadDuplicatePolicyReplaceExisting,
    SCIDownloadDuplicatePolicySkipExisting,
};

typedef NS_ENUM(NSInteger, SCIDownloadQualityPolicy) {
    SCIDownloadQualityPolicyDefault = 0,
    SCIDownloadQualityPolicyBestAvailable,
    SCIDownloadQualityPolicyUserSetting,
};

typedef NS_ENUM(NSInteger, SCIDownloadMediaKind) {
    SCIDownloadMediaKindUnknown = 0,
    SCIDownloadMediaKindImage,
    SCIDownloadMediaKindVideo,
    SCIDownloadMediaKindAudio,
};

typedef NS_ENUM(NSInteger, SCIDownloadHistoryFilter) {
    SCIDownloadHistoryFilterAll = 0,
    SCIDownloadHistoryFilterActive,
    SCIDownloadHistoryFilterQueued,
    SCIDownloadHistoryFilterFailed,
    SCIDownloadHistoryFilterRecent,
};

FOUNDATION_EXPORT NSInteger const SCIDownloadStoreSchemaVersion;

FOUNDATION_EXPORT NSString * const kSCIDownloadMaxConcurrentKey;
FOUNDATION_EXPORT NSString * const kSCIDownloadHistoryLimitKey;
FOUNDATION_EXPORT NSString * const kSCIDownloadDetectDuplicatesKey;

FOUNDATION_EXPORT NSNotificationName const SCIDownloadServiceDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const SCIDownloadJobDidChangeNotification;

FOUNDATION_EXPORT NSString * const SCIDownloadNotificationJobIDKey;
FOUNDATION_EXPORT NSString * const SCIDownloadNotificationItemIDKey;
FOUNDATION_EXPORT NSString * const SCIDownloadNotificationSnapshotKey;

FOUNDATION_EXPORT NSError *SCIDownloadError(SCIDownloadErrorCode code, NSString *description, NSString * _Nullable recovery);
FOUNDATION_EXPORT BOOL SCIDownloadStateIsTerminal(SCIDownloadState state);
FOUNDATION_EXPORT BOOL SCIDownloadStateAllowsTransition(SCIDownloadState from, SCIDownloadState to);
FOUNDATION_EXPORT SCIDownloadState SCIDownloadDerivedJobState(NSArray<NSNumber *> *itemStates);
FOUNDATION_EXPORT NSString *SCIDownloadStateDisplayName(SCIDownloadState state);
FOUNDATION_EXPORT NSString *SCIDownloadDestinationDisplayName(SCIDownloadDestination destination);
FOUNDATION_EXPORT NSString *SCIDownloadSourceSurfaceDisplayName(SCIDownloadSourceSurface surface);
FOUNDATION_EXPORT NSString *SCIDownloadMediaKindDisplayName(SCIDownloadMediaKind kind);

NS_ASSUME_NONNULL_END

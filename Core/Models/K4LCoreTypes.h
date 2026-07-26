#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, K4LTriState) {
    K4LTriStateUnknown = -1,
    K4LTriStateDisabled = 0,
    K4LTriStateEnabled = 1,
};

typedef NS_ENUM(NSInteger, K4LFeatureOverrideState) {
    K4LFeatureOverrideStateInherit = 0,
    K4LFeatureOverrideStateDisabled = 1,
    K4LFeatureOverrideStateEnabled = 2,
};

typedef NS_ENUM(NSInteger, K4LCaptureDisposition) {
    K4LCaptureDispositionPassOriginal = 0,
    K4LCaptureDispositionDrop = 1,
    K4LCaptureDispositionReplace = 2,
};

typedef NS_ENUM(NSInteger, K4LRecordingPhase) {
    K4LRecordingPhaseIdle = 0,
    K4LRecordingPhaseStarting,
    K4LRecordingPhaseRecording,
    K4LRecordingPhaseStopping,
    K4LRecordingPhaseCompleted,
    K4LRecordingPhaseFailed,
};

typedef NS_ENUM(NSInteger, K4LMediaSaveDestination) {
    K4LMediaSaveDestinationNone = 0,
    K4LMediaSaveDestinationPhotos,
    K4LMediaSaveDestinationFiles,
    K4LMediaSaveDestinationVault,
    K4LMediaSaveDestinationCustomDirectory,
};

typedef NS_ENUM(NSInteger, K4LContentCategory) {
    K4LContentCategoryUnspecified = 0,
    K4LContentCategoryChatText,
    K4LContentCategoryChatMedia,
    K4LContentCategorySnap,
    K4LContentCategoryStory,
    K4LContentCategoryVoiceNote,
    K4LContentCategorySpotlightDiscover,
    K4LContentCategoryStranger,
};

typedef NS_ENUM(NSInteger, K4LDaemonStatus) {
    K4LDaemonStatusUnknown = 0,
    K4LDaemonStatusUnavailable,
    K4LDaemonStatusReady,
    K4LDaemonStatusRestarting,
};

NS_ASSUME_NONNULL_END

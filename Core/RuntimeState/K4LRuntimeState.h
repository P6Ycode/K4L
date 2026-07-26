#import <Foundation/Foundation.h>
#import "../Capabilities/K4LCapabilities.h"
#import "../Models/K4LValueModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface K4LCameraRuntimeState : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) BOOL captureActive;
@property (nonatomic, readonly) K4LCaptureDisposition frontDisposition;
@property (nonatomic, readonly) K4LCaptureDisposition rearDisposition;
@property (nonatomic, copy, readonly, nullable) NSString *frontPreparedItemIdentifier;
@property (nonatomic, copy, readonly, nullable) NSString *rearPreparedItemIdentifier;

+ (instancetype)inactiveState;
- (nullable instancetype)initWithCaptureActive:(BOOL)captureActive
                              frontDisposition:(K4LCaptureDisposition)frontDisposition
                               rearDisposition:(K4LCaptureDisposition)rearDisposition
                   frontPreparedItemIdentifier:(nullable NSString *)frontPreparedItemIdentifier
                    rearPreparedItemIdentifier:(nullable NSString *)rearPreparedItemIdentifier NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LAudioRuntimeState : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) BOOL inputActive;
@property (nonatomic, readonly) BOOL substitutionActive;
@property (nonatomic, readonly) BOOL loopsPreparedAudio;
@property (nonatomic, copy, readonly, nullable) NSString *preparedItemIdentifier;

+ (instancetype)inactiveState;
- (nullable instancetype)initWithInputActive:(BOOL)inputActive
                          substitutionActive:(BOOL)substitutionActive
                          loopsPreparedAudio:(BOOL)loopsPreparedAudio
                      preparedItemIdentifier:(nullable NSString *)preparedItemIdentifier NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LRuntimeStateSnapshot : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, copy, readonly, nullable) NSString *foregroundBundleIdentifier;
@property (nonatomic, copy, readonly, nullable) NSString *activeSnapchatAccountIdentifier;
@property (nonatomic, readonly) K4LTriState protectedDataAvailable;
@property (nonatomic, readonly) K4LTriState screenCaptured;
@property (nonatomic, readonly) K4LRecordingPhase recordingPhase;
@property (nonatomic, copy, readonly, nullable) NSURL *recordingOutputURL;
@property (nonatomic, strong, readonly) K4LCameraRuntimeState *cameraState;
@property (nonatomic, strong, readonly) K4LAudioRuntimeState *audioState;
@property (nonatomic, strong, readonly, nullable) K4LLocation *activeLocation;
@property (nonatomic, strong, readonly) K4LBatteryState *genuineBatteryState;
@property (nonatomic, strong, readonly) K4LBatteryOverride *batteryOverride;
@property (nonatomic, strong, readonly) K4LDaemonAvailability *daemonAvailability;
@property (nonatomic, strong, readonly) K4LSnapchatCapabilities *snapchatCapabilities;
@property (nonatomic, strong, readonly) K4LSQLTriggerState *sqlTriggerState;
@property (nonatomic, strong, readonly) K4LValdiPatchState *valdiPatchState;
@property (nonatomic, copy, readonly) NSDate *updatedAt;

+ (instancetype)neutralSnapshot;
- (nullable instancetype)initWithForegroundBundleIdentifier:(nullable NSString *)foregroundBundleIdentifier
                          activeSnapchatAccountIdentifier:(nullable NSString *)activeSnapchatAccountIdentifier
                                     protectedDataAvailable:(K4LTriState)protectedDataAvailable
                                             screenCaptured:(K4LTriState)screenCaptured
                                             recordingPhase:(K4LRecordingPhase)recordingPhase
                                         recordingOutputURL:(nullable NSURL *)recordingOutputURL
                                                cameraState:(K4LCameraRuntimeState *)cameraState
                                                 audioState:(K4LAudioRuntimeState *)audioState
                                             activeLocation:(nullable K4LLocation *)activeLocation
                                        genuineBatteryState:(K4LBatteryState *)genuineBatteryState
                                            batteryOverride:(K4LBatteryOverride *)batteryOverride
                                         daemonAvailability:(K4LDaemonAvailability *)daemonAvailability
                                       snapchatCapabilities:(K4LSnapchatCapabilities *)snapchatCapabilities
                                            sqlTriggerState:(K4LSQLTriggerState *)sqlTriggerState
                                            valdiPatchState:(K4LValdiPatchState *)valdiPatchState
                                                  updatedAt:(NSDate *)updatedAt NS_DESIGNATED_INITIALIZER;

- (BOOL)isSnapchatForeground;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LRuntimeStateStore : NSObject

@property (atomic, copy) K4LRuntimeStateSnapshot *snapshot;

- (instancetype)initWithSnapshot:(K4LRuntimeStateSnapshot *)snapshot NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END

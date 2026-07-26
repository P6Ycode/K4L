#import "K4LRuntimeState.h"

static BOOL K4LCaptureDispositionIsValid(K4LCaptureDisposition disposition) {
    return disposition >= K4LCaptureDispositionPassOriginal &&
        disposition <= K4LCaptureDispositionReplace;
}

static BOOL K4LTriStateIsValid(K4LTriState state) {
    return state >= K4LTriStateUnknown && state <= K4LTriStateEnabled;
}

@implementation K4LCameraRuntimeState

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)inactiveState {
    return [[self alloc] initWithCaptureActive:NO
                              frontDisposition:K4LCaptureDispositionPassOriginal
                               rearDisposition:K4LCaptureDispositionPassOriginal
                   frontPreparedItemIdentifier:nil
                    rearPreparedItemIdentifier:nil];
}

- (nullable instancetype)initWithCaptureActive:(BOOL)captureActive
                              frontDisposition:(K4LCaptureDisposition)frontDisposition
                               rearDisposition:(K4LCaptureDisposition)rearDisposition
                   frontPreparedItemIdentifier:(nullable NSString *)frontPreparedItemIdentifier
                    rearPreparedItemIdentifier:(nullable NSString *)rearPreparedItemIdentifier {
    if (!K4LCaptureDispositionIsValid(frontDisposition) ||
        !K4LCaptureDispositionIsValid(rearDisposition)) {
        return nil;
    }
    if (frontDisposition == K4LCaptureDispositionReplace &&
        frontPreparedItemIdentifier.length == 0) {
        return nil;
    }
    if (rearDisposition == K4LCaptureDispositionReplace &&
        rearPreparedItemIdentifier.length == 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _captureActive = captureActive;
        _frontDisposition = frontDisposition;
        _rearDisposition = rearDisposition;
        _frontPreparedItemIdentifier = [frontPreparedItemIdentifier copy];
        _rearPreparedItemIdentifier = [rearPreparedItemIdentifier copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithCaptureActive:[coder decodeBoolForKey:@"active"]
                      frontDisposition:[coder decodeIntegerForKey:@"frontDisposition"]
                       rearDisposition:[coder decodeIntegerForKey:@"rearDisposition"]
           frontPreparedItemIdentifier:[coder decodeObjectOfClass:NSString.class forKey:@"front"]
            rearPreparedItemIdentifier:[coder decodeObjectOfClass:NSString.class forKey:@"rear"]];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBool:self.captureActive forKey:@"active"];
    [coder encodeInteger:self.frontDisposition forKey:@"frontDisposition"];
    [coder encodeInteger:self.rearDisposition forKey:@"rearDisposition"];
    [coder encodeObject:self.frontPreparedItemIdentifier forKey:@"front"];
    [coder encodeObject:self.rearPreparedItemIdentifier forKey:@"rear"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LAudioRuntimeState

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)inactiveState {
    return [[self alloc] initWithInputActive:NO
                          substitutionActive:NO
                          loopsPreparedAudio:NO
                      preparedItemIdentifier:nil];
}

- (nullable instancetype)initWithInputActive:(BOOL)inputActive
                          substitutionActive:(BOOL)substitutionActive
                          loopsPreparedAudio:(BOOL)loopsPreparedAudio
                      preparedItemIdentifier:(nullable NSString *)preparedItemIdentifier {
    if (substitutionActive && preparedItemIdentifier.length == 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _inputActive = inputActive;
        _substitutionActive = substitutionActive;
        _loopsPreparedAudio = loopsPreparedAudio;
        _preparedItemIdentifier = [preparedItemIdentifier copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithInputActive:[coder decodeBoolForKey:@"inputActive"]
                  substitutionActive:[coder decodeBoolForKey:@"substitutionActive"]
                  loopsPreparedAudio:[coder decodeBoolForKey:@"loopsPreparedAudio"]
              preparedItemIdentifier:[coder decodeObjectOfClass:NSString.class forKey:@"item"]];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBool:self.inputActive forKey:@"inputActive"];
    [coder encodeBool:self.substitutionActive forKey:@"substitutionActive"];
    [coder encodeBool:self.loopsPreparedAudio forKey:@"loopsPreparedAudio"];
    [coder encodeObject:self.preparedItemIdentifier forKey:@"item"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LRuntimeStateSnapshot

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)neutralSnapshot {
    return [[self alloc] initWithForegroundBundleIdentifier:nil
                          activeSnapchatAccountIdentifier:nil
                                     protectedDataAvailable:K4LTriStateUnknown
                                             screenCaptured:K4LTriStateUnknown
                                             recordingPhase:K4LRecordingPhaseIdle
                                         recordingOutputURL:nil
                                                cameraState:K4LCameraRuntimeState.inactiveState
                                                 audioState:K4LAudioRuntimeState.inactiveState
                                             activeLocation:nil
                                        genuineBatteryState:K4LBatteryState.unknownState
                                            batteryOverride:K4LBatteryOverride.disabledOverride
                                         daemonAvailability:K4LDaemonAvailability.unknownAvailability
                                       snapchatCapabilities:K4LSnapchatCapabilities.unsupportedCapabilities
                                            sqlTriggerState:K4LSQLTriggerState.inactiveState
                                            valdiPatchState:K4LValdiPatchState.inactiveState
                                                  updatedAt:[NSDate dateWithTimeIntervalSince1970:0]];
}

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
                                                  updatedAt:(NSDate *)updatedAt {
    if (!K4LTriStateIsValid(protectedDataAvailable) ||
        !K4LTriStateIsValid(screenCaptured) ||
        recordingPhase < K4LRecordingPhaseIdle ||
        recordingPhase > K4LRecordingPhaseFailed) {
        return nil;
    }

    self = [super init];
    if (self) {
        _foregroundBundleIdentifier = [foregroundBundleIdentifier copy];
        _activeSnapchatAccountIdentifier = [activeSnapchatAccountIdentifier copy];
        _protectedDataAvailable = protectedDataAvailable;
        _screenCaptured = screenCaptured;
        _recordingPhase = recordingPhase;
        _recordingOutputURL = [recordingOutputURL copy];
        _cameraState = cameraState;
        _audioState = audioState;
        _activeLocation = activeLocation;
        _genuineBatteryState = genuineBatteryState;
        _batteryOverride = batteryOverride;
        _daemonAvailability = daemonAvailability;
        _snapchatCapabilities = snapchatCapabilities;
        _sqlTriggerState = sqlTriggerState;
        _valdiPatchState = valdiPatchState;
        _updatedAt = [updatedAt copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    K4LCameraRuntimeState *camera =
        [coder decodeObjectOfClass:K4LCameraRuntimeState.class forKey:@"camera"];
    K4LAudioRuntimeState *audio =
        [coder decodeObjectOfClass:K4LAudioRuntimeState.class forKey:@"audio"];
    K4LBatteryState *genuineBattery =
        [coder decodeObjectOfClass:K4LBatteryState.class forKey:@"genuineBattery"];
    K4LBatteryOverride *batteryOverride =
        [coder decodeObjectOfClass:K4LBatteryOverride.class forKey:@"batteryOverride"];
    K4LDaemonAvailability *daemon =
        [coder decodeObjectOfClass:K4LDaemonAvailability.class forKey:@"daemon"];
    K4LSnapchatCapabilities *snapchat =
        [coder decodeObjectOfClass:K4LSnapchatCapabilities.class forKey:@"snapchat"];
    K4LSQLTriggerState *sql =
        [coder decodeObjectOfClass:K4LSQLTriggerState.class forKey:@"sql"];
    K4LValdiPatchState *valdi =
        [coder decodeObjectOfClass:K4LValdiPatchState.class forKey:@"valdi"];
    NSDate *updatedAt =
        [coder decodeObjectOfClass:NSDate.class forKey:@"updatedAt"];

    if (camera == nil || audio == nil || genuineBattery == nil ||
        batteryOverride == nil || daemon == nil || snapchat == nil ||
        sql == nil || valdi == nil || updatedAt == nil) {
        return nil;
    }

    return [self initWithForegroundBundleIdentifier:
                 [coder decodeObjectOfClass:NSString.class forKey:@"foreground"]
                          activeSnapchatAccountIdentifier:
                 [coder decodeObjectOfClass:NSString.class forKey:@"account"]
                                     protectedDataAvailable:
                 [coder decodeIntegerForKey:@"protectedData"]
                                             screenCaptured:
                 [coder decodeIntegerForKey:@"screenCaptured"]
                                             recordingPhase:
                 [coder decodeIntegerForKey:@"recordingPhase"]
                                         recordingOutputURL:
                 [coder decodeObjectOfClass:NSURL.class forKey:@"recordingOutputURL"]
                                                cameraState:camera
                                                 audioState:audio
                                             activeLocation:
                 [coder decodeObjectOfClass:K4LLocation.class forKey:@"location"]
                                        genuineBatteryState:genuineBattery
                                            batteryOverride:batteryOverride
                                         daemonAvailability:daemon
                                       snapchatCapabilities:snapchat
                                            sqlTriggerState:sql
                                            valdiPatchState:valdi
                                                  updatedAt:updatedAt];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.foregroundBundleIdentifier forKey:@"foreground"];
    [coder encodeObject:self.activeSnapchatAccountIdentifier forKey:@"account"];
    [coder encodeInteger:self.protectedDataAvailable forKey:@"protectedData"];
    [coder encodeInteger:self.screenCaptured forKey:@"screenCaptured"];
    [coder encodeInteger:self.recordingPhase forKey:@"recordingPhase"];
    [coder encodeObject:self.recordingOutputURL forKey:@"recordingOutputURL"];
    [coder encodeObject:self.cameraState forKey:@"camera"];
    [coder encodeObject:self.audioState forKey:@"audio"];
    [coder encodeObject:self.activeLocation forKey:@"location"];
    [coder encodeObject:self.genuineBatteryState forKey:@"genuineBattery"];
    [coder encodeObject:self.batteryOverride forKey:@"batteryOverride"];
    [coder encodeObject:self.daemonAvailability forKey:@"daemon"];
    [coder encodeObject:self.snapchatCapabilities forKey:@"snapchat"];
    [coder encodeObject:self.sqlTriggerState forKey:@"sql"];
    [coder encodeObject:self.valdiPatchState forKey:@"valdi"];
    [coder encodeObject:self.updatedAt forKey:@"updatedAt"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isSnapchatForeground {
    return [self.foregroundBundleIdentifier isEqualToString:K4LPinnedSnapchatBundleIdentifier];
}

@end

@implementation K4LRuntimeStateStore

- (instancetype)init {
    return [self initWithSnapshot:K4LRuntimeStateSnapshot.neutralSnapshot];
}

- (instancetype)initWithSnapshot:(K4LRuntimeStateSnapshot *)snapshot {
    self = [super init];
    if (self) {
        _snapshot = [snapshot copy];
    }
    return self;
}

@end

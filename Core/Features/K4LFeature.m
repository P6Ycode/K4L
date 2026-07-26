#import "K4LFeature.h"

K4LFeatureIdentifier const K4LFeatureScreenshotSuppression = @"screenshot.suppression";
K4LFeatureIdentifier const K4LFeatureScreenshotArchive = @"screenshot.archive";
K4LFeatureIdentifier const K4LFeatureSystemRecording = @"recording.system";
K4LFeatureIdentifier const K4LFeatureCameraFrontSubstitution = @"camera.front";
K4LFeatureIdentifier const K4LFeatureCameraRearSubstitution = @"camera.rear";
K4LFeatureIdentifier const K4LFeatureMicrophoneSubstitution = @"audio.microphone";
K4LFeatureIdentifier const K4LFeatureBatteryOverride = @"power.battery";
K4LFeatureIdentifier const K4LFeatureSnapMapBatteryOverride = @"snap-map.battery";
K4LFeatureIdentifier const K4LFeatureLocationSpoof = @"location.spoof";
K4LFeatureIdentifier const K4LFeatureChatGhost = @"ghost.chat";
K4LFeatureIdentifier const K4LFeatureSnapGhost = @"ghost.snap";
K4LFeatureIdentifier const K4LFeatureReplaySuppression = @"ghost.replay";
K4LFeatureIdentifier const K4LFeatureSaveSuppression = @"ghost.save";
K4LFeatureIdentifier const K4LFeatureKeepDeleted = @"ghost.keep-deleted";
K4LFeatureIdentifier const K4LFeatureTypingSuppression = @"presence.typing";
K4LFeatureIdentifier const K4LFeatureChatPresenceSuppression = @"presence.chat";
K4LFeatureIdentifier const K4LFeatureRemixGhost = @"ghost.remix";
K4LFeatureIdentifier const K4LFeatureStoryGhost = @"ghost.story";
K4LFeatureIdentifier const K4LFeatureDisableTapToSave = @"save.disable-tap";
K4LFeatureIdentifier const K4LFeatureSaveMode = @"save.mode";
K4LFeatureIdentifier const K4LFeatureUnsaveMode = @"save.unsave-mode";
K4LFeatureIdentifier const K4LFeatureVoiceNoteSpeed = @"voice-note.speed";
K4LFeatureIdentifier const K4LFeatureVoiceNoteSave = @"voice-note.save";
K4LFeatureIdentifier const K4LFeatureMediaAutoSave = @"media.auto-save";
K4LFeatureIdentifier const K4LFeatureMediaVault = @"media.vault";
K4LFeatureIdentifier const K4LFeatureURLSave = @"media.url-save";
K4LFeatureIdentifier const K4LFeatureCreativeKitUpload = @"send.creative-kit";
K4LFeatureIdentifier const K4LFeatureCropBeforeUpload = @"send.crop";
K4LFeatureIdentifier const K4LFeatureVersionPresentation = @"presentation.version";
K4LFeatureIdentifier const K4LFeatureAlertPresentation = @"presentation.alert";

NSSet<K4LFeatureIdentifier> *K4LAllFeatureIdentifiers(void) {
    static NSSet<K4LFeatureIdentifier> *identifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        identifiers = [NSSet setWithArray:@[
            K4LFeatureScreenshotSuppression,
            K4LFeatureScreenshotArchive,
            K4LFeatureSystemRecording,
            K4LFeatureCameraFrontSubstitution,
            K4LFeatureCameraRearSubstitution,
            K4LFeatureMicrophoneSubstitution,
            K4LFeatureBatteryOverride,
            K4LFeatureSnapMapBatteryOverride,
            K4LFeatureLocationSpoof,
            K4LFeatureChatGhost,
            K4LFeatureSnapGhost,
            K4LFeatureReplaySuppression,
            K4LFeatureSaveSuppression,
            K4LFeatureKeepDeleted,
            K4LFeatureTypingSuppression,
            K4LFeatureChatPresenceSuppression,
            K4LFeatureRemixGhost,
            K4LFeatureStoryGhost,
            K4LFeatureDisableTapToSave,
            K4LFeatureSaveMode,
            K4LFeatureUnsaveMode,
            K4LFeatureVoiceNoteSpeed,
            K4LFeatureVoiceNoteSave,
            K4LFeatureMediaAutoSave,
            K4LFeatureMediaVault,
            K4LFeatureURLSave,
            K4LFeatureCreativeKitUpload,
            K4LFeatureCropBeforeUpload,
            K4LFeatureVersionPresentation,
            K4LFeatureAlertPresentation,
        ]];
    });
    return identifiers;
}

BOOL K4LFeatureIdentifierIsKnown(K4LFeatureIdentifier identifier) {
    return identifier.length > 0 && [K4LAllFeatureIdentifiers() containsObject:identifier];
}

@implementation K4LFeatureSet

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)emptySet {
    return [[self alloc] initWithValidatedIdentifiers:[NSSet set]];
}

+ (nullable instancetype)setWithIdentifiers:(NSSet<K4LFeatureIdentifier> *)identifiers {
    if (![identifiers isSubsetOfSet:K4LAllFeatureIdentifiers()]) {
        return nil;
    }
    return [[self alloc] initWithValidatedIdentifiers:identifiers];
}

- (instancetype)initWithValidatedIdentifiers:(NSSet<K4LFeatureIdentifier> *)identifiers {
    self = [super init];
    if (self) {
        _identifiers = [identifiers copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSSet<Class> *classes = [NSSet setWithObjects:NSSet.class, NSString.class, nil];
    NSSet<NSString *> *identifiers = [coder decodeObjectOfClasses:classes forKey:@"identifiers"];
    if (identifiers == nil || ![identifiers isSubsetOfSet:K4LAllFeatureIdentifiers()]) {
        return nil;
    }
    return [self initWithValidatedIdentifiers:identifiers];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.identifiers forKey:@"identifiers"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)containsFeature:(K4LFeatureIdentifier)feature {
    return [self.identifiers containsObject:feature];
}

- (K4LFeatureSet *)setByAddingFeature:(K4LFeatureIdentifier)feature {
    if (!K4LFeatureIdentifierIsKnown(feature) || [self containsFeature:feature]) {
        return self;
    }
    NSMutableSet<K4LFeatureIdentifier> *updated = [self.identifiers mutableCopy];
    [updated addObject:feature];
    return [[K4LFeatureSet alloc] initWithValidatedIdentifiers:updated];
}

- (K4LFeatureSet *)setByRemovingFeature:(K4LFeatureIdentifier)feature {
    if (![self containsFeature:feature]) {
        return self;
    }
    NSMutableSet<K4LFeatureIdentifier> *updated = [self.identifiers mutableCopy];
    [updated removeObject:feature];
    return [[K4LFeatureSet alloc] initWithValidatedIdentifiers:updated];
}

- (BOOL)isEqual:(id)object {
    return object == self ||
        ([object isKindOfClass:K4LFeatureSet.class] &&
         [self.identifiers isEqualToSet:((K4LFeatureSet *)object).identifiers]);
}

- (NSUInteger)hash {
    return self.identifiers.hash;
}

@end

@implementation K4LFeatureOverrides

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)emptyOverrides {
    return [[self alloc] initWithEnabledFeatures:K4LFeatureSet.emptySet
                                disabledFeatures:K4LFeatureSet.emptySet];
}

+ (nullable instancetype)overridesWithEnabledFeatures:(K4LFeatureSet *)enabledFeatures
                                      disabledFeatures:(K4LFeatureSet *)disabledFeatures {
    if ([enabledFeatures.identifiers intersectsSet:disabledFeatures.identifiers]) {
        return nil;
    }
    return [[self alloc] initWithEnabledFeatures:enabledFeatures
                                disabledFeatures:disabledFeatures];
}

- (instancetype)initWithEnabledFeatures:(K4LFeatureSet *)enabledFeatures
                        disabledFeatures:(K4LFeatureSet *)disabledFeatures {
    self = [super init];
    if (self) {
        _enabledFeatures = enabledFeatures;
        _disabledFeatures = disabledFeatures;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    K4LFeatureSet *enabled = [coder decodeObjectOfClass:K4LFeatureSet.class
                                                forKey:@"enabled"];
    K4LFeatureSet *disabled = [coder decodeObjectOfClass:K4LFeatureSet.class
                                                 forKey:@"disabled"];
    if (enabled == nil || disabled == nil ||
        [enabled.identifiers intersectsSet:disabled.identifiers]) {
        return nil;
    }
    return [self initWithEnabledFeatures:enabled disabledFeatures:disabled];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.enabledFeatures forKey:@"enabled"];
    [coder encodeObject:self.disabledFeatures forKey:@"disabled"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (K4LFeatureOverrideState)stateForFeature:(K4LFeatureIdentifier)feature {
    if ([self.disabledFeatures containsFeature:feature]) {
        return K4LFeatureOverrideStateDisabled;
    }
    if ([self.enabledFeatures containsFeature:feature]) {
        return K4LFeatureOverrideStateEnabled;
    }
    return K4LFeatureOverrideStateInherit;
}

- (BOOL)isEqual:(id)object {
    if (object == self) {
        return YES;
    }
    if (![object isKindOfClass:K4LFeatureOverrides.class]) {
        return NO;
    }
    K4LFeatureOverrides *other = object;
    return [self.enabledFeatures isEqual:other.enabledFeatures] &&
        [self.disabledFeatures isEqual:other.disabledFeatures];
}

- (NSUInteger)hash {
    return self.enabledFeatures.hash ^ self.disabledFeatures.hash;
}

@end

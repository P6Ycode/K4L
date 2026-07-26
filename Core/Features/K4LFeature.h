#import <Foundation/Foundation.h>
#import "../Models/K4LCoreTypes.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSString *K4LFeatureIdentifier NS_TYPED_EXTENSIBLE_ENUM;

FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureScreenshotSuppression;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureScreenshotArchive;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureSystemRecording;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureCameraFrontSubstitution;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureCameraRearSubstitution;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureMicrophoneSubstitution;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureBatteryOverride;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureSnapMapBatteryOverride;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureLocationSpoof;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureChatGhost;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureSnapGhost;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureReplaySuppression;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureSaveSuppression;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureKeepDeleted;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureTypingSuppression;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureChatPresenceSuppression;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureRemixGhost;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureStoryGhost;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureDisableTapToSave;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureSaveMode;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureUnsaveMode;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureVoiceNoteSpeed;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureVoiceNoteSave;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureMediaAutoSave;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureMediaVault;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureURLSave;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureCreativeKitUpload;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureCropBeforeUpload;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureVersionPresentation;
FOUNDATION_EXPORT K4LFeatureIdentifier const K4LFeatureAlertPresentation;

FOUNDATION_EXPORT NSSet<K4LFeatureIdentifier> *K4LAllFeatureIdentifiers(void);
FOUNDATION_EXPORT BOOL K4LFeatureIdentifierIsKnown(K4LFeatureIdentifier identifier);

@interface K4LFeatureSet : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, copy, readonly) NSSet<K4LFeatureIdentifier> *identifiers;

+ (instancetype)emptySet;
+ (nullable instancetype)setWithIdentifiers:(NSSet<K4LFeatureIdentifier> *)identifiers;
- (BOOL)containsFeature:(K4LFeatureIdentifier)feature;
- (K4LFeatureSet *)setByAddingFeature:(K4LFeatureIdentifier)feature;
- (K4LFeatureSet *)setByRemovingFeature:(K4LFeatureIdentifier)feature;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LFeatureOverrides : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, strong, readonly) K4LFeatureSet *enabledFeatures;
@property (nonatomic, strong, readonly) K4LFeatureSet *disabledFeatures;

+ (instancetype)emptyOverrides;
+ (nullable instancetype)overridesWithEnabledFeatures:(K4LFeatureSet *)enabledFeatures
                                      disabledFeatures:(K4LFeatureSet *)disabledFeatures;
- (K4LFeatureOverrideState)stateForFeature:(K4LFeatureIdentifier)feature;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

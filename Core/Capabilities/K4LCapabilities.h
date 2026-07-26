#import <Foundation/Foundation.h>
#import "../Models/K4LCoreTypes.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const K4LPinnedSnapchatBundleIdentifier;
FOUNDATION_EXPORT NSString *const K4LPinnedSnapchatVersion;
FOUNDATION_EXPORT NSString *const K4LPinnedSnapchatBuild;

typedef NS_OPTIONS(NSUInteger, K4LSnapchatCapability) {
    K4LSnapchatCapabilityNone = 0,
    K4LSnapchatCapabilityReplay = 1UL << 0,
    K4LSnapchatCapabilitySaveUnsave = 1UL << 1,
    K4LSnapchatCapabilityStoryReceipts = 1UL << 2,
    K4LSnapchatCapabilityTyping = 1UL << 3,
    K4LSnapchatCapabilityTextReadReceipts = 1UL << 4,
    K4LSnapchatCapabilityMediaViewReceipts = 1UL << 5,
    K4LSnapchatCapabilityPostOpenViewingPolicy = 1UL << 6,
    K4LSnapchatCapabilityPrivateSend = 1UL << 7,
    K4LSnapchatCapabilitySQLTriggers = 1UL << 8,
    K4LSnapchatCapabilityValdiPresence = 1UL << 9,
    K4LSnapchatCapabilityValdiVoiceNoteSpeed = 1UL << 10,
};

typedef NS_OPTIONS(NSUInteger, K4LSQLTrigger) {
    K4LSQLTriggerNone = 0,
    K4LSQLTriggerReplayUpdate = 1UL << 0,
    K4LSQLTriggerSaveUpdate = 1UL << 1,
    K4LSQLTriggerTextRead = 1UL << 2,
    K4LSQLTriggerMediaView = 1UL << 3,
    K4LSQLTriggerTombstone = 1UL << 4,
    K4LSQLTriggerSaveToCameraRollStatus = 1UL << 5,
    K4LSQLTriggerRemixCaptureStatus = 1UL << 6,
    K4LSQLTriggerUpdateConversation = 1UL << 7,
};

typedef NS_OPTIONS(NSUInteger, K4LValdiPatch) {
    K4LValdiPatchNone = 0,
    K4LValdiPatchPresence = 1UL << 0,
    K4LValdiPatchVoiceNoteSpeed = 1UL << 1,
};

@interface K4LSnapchatCapabilities : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *marketingVersion;
@property (nonatomic, copy, readonly) NSString *buildNumber;
@property (nonatomic, readonly) K4LSnapchatCapability capabilities;
@property (nonatomic, readonly) BOOL matchesPinnedBuild;

+ (instancetype)unsupportedCapabilities;
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                        marketingVersion:(NSString *)marketingVersion
                             buildNumber:(NSString *)buildNumber
                            capabilities:(K4LSnapchatCapability)capabilities NS_DESIGNATED_INITIALIZER;
- (BOOL)supportsCapability:(K4LSnapchatCapability)capability;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LDaemonAvailability : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) K4LDaemonStatus status;
@property (nonatomic, readonly) NSUInteger protocolVersion;

+ (instancetype)unknownAvailability;
- (nullable instancetype)initWithStatus:(K4LDaemonStatus)status
                        protocolVersion:(NSUInteger)protocolVersion NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LSQLTriggerState : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) BOOL schemaCompatible;
@property (nonatomic, readonly) K4LSQLTrigger installedTriggers;
@property (nonatomic, readonly) BOOL legacyReadTriggerRemoved;

+ (instancetype)inactiveState;
- (instancetype)initWithSchemaCompatible:(BOOL)schemaCompatible
                       installedTriggers:(K4LSQLTrigger)installedTriggers
                legacyReadTriggerRemoved:(BOOL)legacyReadTriggerRemoved NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LValdiPatchState : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) BOOL buildCompatible;
@property (nonatomic, readonly) K4LValdiPatch appliedPatches;
@property (nonatomic, readonly) K4LValdiPatch restorableOriginals;

+ (instancetype)inactiveState;
- (instancetype)initWithBuildCompatible:(BOOL)buildCompatible
                          appliedPatches:(K4LValdiPatch)appliedPatches
                     restorableOriginals:(K4LValdiPatch)restorableOriginals NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

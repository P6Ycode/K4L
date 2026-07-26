#import "K4LCapabilities.h"

NSString *const K4LPinnedSnapchatBundleIdentifier = @"com.toyopagroup.picaboo";
NSString *const K4LPinnedSnapchatVersion = @"14.15.0";
NSString *const K4LPinnedSnapchatBuild = @"14.15.0.48";

static const K4LSnapchatCapability K4LAllSnapchatCapabilities =
    K4LSnapchatCapabilityReplay |
    K4LSnapchatCapabilitySaveUnsave |
    K4LSnapchatCapabilityStoryReceipts |
    K4LSnapchatCapabilityTyping |
    K4LSnapchatCapabilityTextReadReceipts |
    K4LSnapchatCapabilityMediaViewReceipts |
    K4LSnapchatCapabilityPostOpenViewingPolicy |
    K4LSnapchatCapabilityPrivateSend |
    K4LSnapchatCapabilitySQLTriggers |
    K4LSnapchatCapabilityValdiPresence |
    K4LSnapchatCapabilityValdiVoiceNoteSpeed;

static const K4LSQLTrigger K4LAllSQLTriggers =
    K4LSQLTriggerReplayUpdate |
    K4LSQLTriggerSaveUpdate |
    K4LSQLTriggerTextRead |
    K4LSQLTriggerMediaView |
    K4LSQLTriggerTombstone |
    K4LSQLTriggerSaveToCameraRollStatus |
    K4LSQLTriggerRemixCaptureStatus |
    K4LSQLTriggerUpdateConversation;

static const K4LValdiPatch K4LAllValdiPatches =
    K4LValdiPatchPresence |
    K4LValdiPatchVoiceNoteSpeed;

@implementation K4LSnapchatCapabilities

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)unsupportedCapabilities {
    return [[self alloc] initWithBundleIdentifier:@""
                                marketingVersion:@""
                                     buildNumber:@""
                                    capabilities:K4LSnapchatCapabilityNone];
}

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                        marketingVersion:(NSString *)marketingVersion
                             buildNumber:(NSString *)buildNumber
                            capabilities:(K4LSnapchatCapability)capabilities {
    self = [super init];
    if (self) {
        BOOL matches =
            [bundleIdentifier isEqualToString:K4LPinnedSnapchatBundleIdentifier] &&
            [marketingVersion isEqualToString:K4LPinnedSnapchatVersion] &&
            [buildNumber isEqualToString:K4LPinnedSnapchatBuild];

        _bundleIdentifier = [bundleIdentifier copy];
        _marketingVersion = [marketingVersion copy];
        _buildNumber = [buildNumber copy];
        _matchesPinnedBuild = matches;
        _capabilities = matches ? (capabilities & K4LAllSnapchatCapabilities)
                                : K4LSnapchatCapabilityNone;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *bundle = [coder decodeObjectOfClass:NSString.class forKey:@"bundle"];
    NSString *version = [coder decodeObjectOfClass:NSString.class forKey:@"version"];
    NSString *build = [coder decodeObjectOfClass:NSString.class forKey:@"build"];
    if (bundle == nil || version == nil || build == nil) {
        return nil;
    }
    return [self initWithBundleIdentifier:bundle
                         marketingVersion:version
                              buildNumber:build
                             capabilities:(K4LSnapchatCapability)[coder decodeIntegerForKey:@"capabilities"]];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.bundleIdentifier forKey:@"bundle"];
    [coder encodeObject:self.marketingVersion forKey:@"version"];
    [coder encodeObject:self.buildNumber forKey:@"build"];
    [coder encodeInteger:(NSInteger)self.capabilities forKey:@"capabilities"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)supportsCapability:(K4LSnapchatCapability)capability {
    return self.matchesPinnedBuild &&
        capability != K4LSnapchatCapabilityNone &&
        (self.capabilities & capability) == capability;
}

@end

@implementation K4LDaemonAvailability

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)unknownAvailability {
    return [[self alloc] initWithStatus:K4LDaemonStatusUnknown protocolVersion:0];
}

- (nullable instancetype)initWithStatus:(K4LDaemonStatus)status
                        protocolVersion:(NSUInteger)protocolVersion {
    if (status < K4LDaemonStatusUnknown || status > K4LDaemonStatusRestarting) {
        return nil;
    }
    if (status == K4LDaemonStatusReady && protocolVersion == 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _status = status;
        _protocolVersion = protocolVersion;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSInteger protocolVersion = [coder decodeIntegerForKey:@"protocolVersion"];
    if (protocolVersion < 0) {
        return nil;
    }
    return [self initWithStatus:[coder decodeIntegerForKey:@"status"]
                protocolVersion:(NSUInteger)protocolVersion];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.status forKey:@"status"];
    [coder encodeInteger:(NSInteger)self.protocolVersion forKey:@"protocolVersion"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LSQLTriggerState

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)inactiveState {
    return [[self alloc] initWithSchemaCompatible:NO
                               installedTriggers:K4LSQLTriggerNone
                        legacyReadTriggerRemoved:NO];
}

- (instancetype)initWithSchemaCompatible:(BOOL)schemaCompatible
                       installedTriggers:(K4LSQLTrigger)installedTriggers
                legacyReadTriggerRemoved:(BOOL)legacyReadTriggerRemoved {
    self = [super init];
    if (self) {
        _schemaCompatible = schemaCompatible;
        _installedTriggers = schemaCompatible ? (installedTriggers & K4LAllSQLTriggers)
                                              : K4LSQLTriggerNone;
        _legacyReadTriggerRemoved = schemaCompatible && legacyReadTriggerRemoved;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithSchemaCompatible:[coder decodeBoolForKey:@"schemaCompatible"]
                       installedTriggers:(K4LSQLTrigger)[coder decodeIntegerForKey:@"installedTriggers"]
                legacyReadTriggerRemoved:[coder decodeBoolForKey:@"legacyReadTriggerRemoved"]];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBool:self.schemaCompatible forKey:@"schemaCompatible"];
    [coder encodeInteger:(NSInteger)self.installedTriggers forKey:@"installedTriggers"];
    [coder encodeBool:self.legacyReadTriggerRemoved forKey:@"legacyReadTriggerRemoved"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LValdiPatchState

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)inactiveState {
    return [[self alloc] initWithBuildCompatible:NO
                                  appliedPatches:K4LValdiPatchNone
                             restorableOriginals:K4LValdiPatchNone];
}

- (instancetype)initWithBuildCompatible:(BOOL)buildCompatible
                          appliedPatches:(K4LValdiPatch)appliedPatches
                     restorableOriginals:(K4LValdiPatch)restorableOriginals {
    self = [super init];
    if (self) {
        _buildCompatible = buildCompatible;
        _appliedPatches = buildCompatible ? (appliedPatches & K4LAllValdiPatches)
                                          : K4LValdiPatchNone;
        _restorableOriginals = restorableOriginals & K4LAllValdiPatches;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithBuildCompatible:[coder decodeBoolForKey:@"buildCompatible"]
                          appliedPatches:(K4LValdiPatch)[coder decodeIntegerForKey:@"appliedPatches"]
                     restorableOriginals:(K4LValdiPatch)[coder decodeIntegerForKey:@"restorableOriginals"]];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBool:self.buildCompatible forKey:@"buildCompatible"];
    [coder encodeInteger:(NSInteger)self.appliedPatches forKey:@"appliedPatches"];
    [coder encodeInteger:(NSInteger)self.restorableOriginals forKey:@"restorableOriginals"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

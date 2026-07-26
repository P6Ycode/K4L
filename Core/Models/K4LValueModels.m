#import "K4LValueModels.h"
#import <math.h>

static BOOL K4LTriStateIsValidValue(K4LTriState state) {
    return state >= K4LTriStateUnknown && state <= K4LTriStateEnabled;
}

@implementation K4LLocation

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (nullable instancetype)initWithLatitude:(double)latitude
                               longitude:(double)longitude
                                altitude:(double)altitude
                      horizontalAccuracy:(double)horizontalAccuracy
                        verticalAccuracy:(double)verticalAccuracy
                    restoresAfterRestart:(BOOL)restoresAfterRestart
                               timestamp:(NSDate *)timestamp {
    if (!isfinite(latitude) || !isfinite(longitude) || !isfinite(altitude) ||
        !isfinite(horizontalAccuracy) || !isfinite(verticalAccuracy) ||
        latitude < -90.0 || latitude > 90.0 ||
        longitude < -180.0 || longitude > 180.0 ||
        horizontalAccuracy < 0.0 || verticalAccuracy < 0.0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _latitude = latitude;
        _longitude = longitude;
        _altitude = altitude;
        _horizontalAccuracy = horizontalAccuracy;
        _verticalAccuracy = verticalAccuracy;
        _restoresAfterRestart = restoresAfterRestart;
        _timestamp = [timestamp copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSDate *timestamp = [coder decodeObjectOfClass:NSDate.class forKey:@"timestamp"];
    if (timestamp == nil) {
        return nil;
    }
    return [self initWithLatitude:[coder decodeDoubleForKey:@"latitude"]
                       longitude:[coder decodeDoubleForKey:@"longitude"]
                        altitude:[coder decodeDoubleForKey:@"altitude"]
              horizontalAccuracy:[coder decodeDoubleForKey:@"horizontalAccuracy"]
                verticalAccuracy:[coder decodeDoubleForKey:@"verticalAccuracy"]
            restoresAfterRestart:[coder decodeBoolForKey:@"restoresAfterRestart"]
                       timestamp:timestamp];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeDouble:self.latitude forKey:@"latitude"];
    [coder encodeDouble:self.longitude forKey:@"longitude"];
    [coder encodeDouble:self.altitude forKey:@"altitude"];
    [coder encodeDouble:self.horizontalAccuracy forKey:@"horizontalAccuracy"];
    [coder encodeDouble:self.verticalAccuracy forKey:@"verticalAccuracy"];
    [coder encodeBool:self.restoresAfterRestart forKey:@"restoresAfterRestart"];
    [coder encodeObject:self.timestamp forKey:@"timestamp"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LBatteryState

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)unknownState {
    return [[self alloc] initWithCapacityPercent:-1
                             externallyConnected:K4LTriStateUnknown
                                        charging:K4LTriStateUnknown
                                    fullyCharged:K4LTriStateUnknown
                                powerSourceState:nil];
}

- (nullable instancetype)initWithCapacityPercent:(NSInteger)capacityPercent
                             externallyConnected:(K4LTriState)externallyConnected
                                        charging:(K4LTriState)charging
                                    fullyCharged:(K4LTriState)fullyCharged
                                powerSourceState:(nullable NSString *)powerSourceState {
    if (capacityPercent < -1 || capacityPercent > 100 ||
        !K4LTriStateIsValidValue(externallyConnected) ||
        !K4LTriStateIsValidValue(charging) ||
        !K4LTriStateIsValidValue(fullyCharged)) {
        return nil;
    }

    self = [super init];
    if (self) {
        _capacityPercent = capacityPercent;
        _externallyConnected = externallyConnected;
        _charging = charging;
        _fullyCharged = fullyCharged;
        _powerSourceState = [powerSourceState copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithCapacityPercent:[coder decodeIntegerForKey:@"capacityPercent"]
                     externallyConnected:[coder decodeIntegerForKey:@"externallyConnected"]
                                charging:[coder decodeIntegerForKey:@"charging"]
                            fullyCharged:[coder decodeIntegerForKey:@"fullyCharged"]
                        powerSourceState:[coder decodeObjectOfClass:NSString.class forKey:@"powerSourceState"]];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.capacityPercent forKey:@"capacityPercent"];
    [coder encodeInteger:self.externallyConnected forKey:@"externallyConnected"];
    [coder encodeInteger:self.charging forKey:@"charging"];
    [coder encodeInteger:self.fullyCharged forKey:@"fullyCharged"];
    [coder encodeObject:self.powerSourceState forKey:@"powerSourceState"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LBatteryOverride

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)disabledOverride {
    return [[self alloc] initWithEnabled:NO
                         capacityPercent:-1
                     externallyConnected:K4LTriStateUnknown
                                charging:K4LTriStateUnknown
                            fullyCharged:K4LTriStateUnknown
                        powerSourceState:nil];
}

- (nullable instancetype)initWithEnabled:(BOOL)enabled
                         capacityPercent:(NSInteger)capacityPercent
                     externallyConnected:(K4LTriState)externallyConnected
                                charging:(K4LTriState)charging
                            fullyCharged:(K4LTriState)fullyCharged
                        powerSourceState:(nullable NSString *)powerSourceState {
    if (capacityPercent < -1 || capacityPercent > 100 ||
        !K4LTriStateIsValidValue(externallyConnected) ||
        !K4LTriStateIsValidValue(charging) ||
        !K4LTriStateIsValidValue(fullyCharged)) {
        return nil;
    }

    self = [super init];
    if (self) {
        _enabled = enabled;
        _capacityPercent = capacityPercent;
        _externallyConnected = externallyConnected;
        _charging = charging;
        _fullyCharged = fullyCharged;
        _powerSourceState = [powerSourceState copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithEnabled:[coder decodeBoolForKey:@"enabled"]
                 capacityPercent:[coder decodeIntegerForKey:@"capacityPercent"]
             externallyConnected:[coder decodeIntegerForKey:@"externallyConnected"]
                        charging:[coder decodeIntegerForKey:@"charging"]
                    fullyCharged:[coder decodeIntegerForKey:@"fullyCharged"]
                powerSourceState:[coder decodeObjectOfClass:NSString.class forKey:@"powerSourceState"]];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBool:self.enabled forKey:@"enabled"];
    [coder encodeInteger:self.capacityPercent forKey:@"capacityPercent"];
    [coder encodeInteger:self.externallyConnected forKey:@"externallyConnected"];
    [coder encodeInteger:self.charging forKey:@"charging"];
    [coder encodeInteger:self.fullyCharged forKey:@"fullyCharged"];
    [coder encodeObject:self.powerSourceState forKey:@"powerSourceState"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LMediaSavePolicy

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)disabledPolicy {
    return [[self alloc] initWithDestination:K4LMediaSaveDestinationNone
                            customDirectory:nil
                     createsSenderDirectory:NO
                         createsSenderAlbum:NO
                              retentionDays:0];
}

- (nullable instancetype)initWithDestination:(K4LMediaSaveDestination)destination
                             customDirectory:(nullable NSString *)customDirectory
                      createsSenderDirectory:(BOOL)createsSenderDirectory
                          createsSenderAlbum:(BOOL)createsSenderAlbum
                               retentionDays:(NSUInteger)retentionDays {
    if (destination < K4LMediaSaveDestinationNone ||
        destination > K4LMediaSaveDestinationCustomDirectory) {
        return nil;
    }

    NSString *normalizedDirectory = [customDirectory stringByStandardizingPath];
    if (destination == K4LMediaSaveDestinationCustomDirectory &&
        (normalizedDirectory.length == 0 || ![normalizedDirectory hasPrefix:@"/"])) {
        return nil;
    }
    if (destination != K4LMediaSaveDestinationCustomDirectory &&
        normalizedDirectory.length > 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _destination = destination;
        _customDirectory = [normalizedDirectory copy];
        _createsSenderDirectory = createsSenderDirectory;
        _createsSenderAlbum = createsSenderAlbum;
        _retentionDays = retentionDays;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *directory = [coder decodeObjectOfClass:NSString.class
                                              forKey:@"customDirectory"];
    NSInteger retention = [coder decodeIntegerForKey:@"retentionDays"];
    if (retention < 0) {
        return nil;
    }
    return [self initWithDestination:[coder decodeIntegerForKey:@"destination"]
                     customDirectory:directory
              createsSenderDirectory:[coder decodeBoolForKey:@"createsSenderDirectory"]
                  createsSenderAlbum:[coder decodeBoolForKey:@"createsSenderAlbum"]
                       retentionDays:(NSUInteger)retention];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.destination forKey:@"destination"];
    [coder encodeObject:self.customDirectory forKey:@"customDirectory"];
    [coder encodeBool:self.createsSenderDirectory forKey:@"createsSenderDirectory"];
    [coder encodeBool:self.createsSenderAlbum forKey:@"createsSenderAlbum"];
    [coder encodeInteger:(NSInteger)self.retentionDays forKey:@"retentionDays"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

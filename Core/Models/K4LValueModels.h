#import <Foundation/Foundation.h>
#import "K4LCoreTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface K4LLocation : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;
@property (nonatomic, readonly) double altitude;
@property (nonatomic, readonly) double horizontalAccuracy;
@property (nonatomic, readonly) double verticalAccuracy;
@property (nonatomic, readonly) BOOL restoresAfterRestart;
@property (nonatomic, copy, readonly) NSDate *timestamp;

- (nullable instancetype)initWithLatitude:(double)latitude
                               longitude:(double)longitude
                                altitude:(double)altitude
                      horizontalAccuracy:(double)horizontalAccuracy
                        verticalAccuracy:(double)verticalAccuracy
                    restoresAfterRestart:(BOOL)restoresAfterRestart
                               timestamp:(NSDate *)timestamp NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LBatteryState : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) NSInteger capacityPercent;
@property (nonatomic, readonly) K4LTriState externallyConnected;
@property (nonatomic, readonly) K4LTriState charging;
@property (nonatomic, readonly) K4LTriState fullyCharged;
@property (nonatomic, copy, readonly, nullable) NSString *powerSourceState;

+ (instancetype)unknownState;
- (nullable instancetype)initWithCapacityPercent:(NSInteger)capacityPercent
                             externallyConnected:(K4LTriState)externallyConnected
                                        charging:(K4LTriState)charging
                                    fullyCharged:(K4LTriState)fullyCharged
                                powerSourceState:(nullable NSString *)powerSourceState NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LBatteryOverride : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) NSInteger capacityPercent;
@property (nonatomic, readonly) K4LTriState externallyConnected;
@property (nonatomic, readonly) K4LTriState charging;
@property (nonatomic, readonly) K4LTriState fullyCharged;
@property (nonatomic, copy, readonly, nullable) NSString *powerSourceState;

+ (instancetype)disabledOverride;
- (nullable instancetype)initWithEnabled:(BOOL)enabled
                         capacityPercent:(NSInteger)capacityPercent
                     externallyConnected:(K4LTriState)externallyConnected
                                charging:(K4LTriState)charging
                            fullyCharged:(K4LTriState)fullyCharged
                        powerSourceState:(nullable NSString *)powerSourceState NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LMediaSavePolicy : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) K4LMediaSaveDestination destination;
@property (nonatomic, copy, readonly, nullable) NSString *customDirectory;
@property (nonatomic, readonly) BOOL createsSenderDirectory;
@property (nonatomic, readonly) BOOL createsSenderAlbum;
@property (nonatomic, readonly) NSUInteger retentionDays;

+ (instancetype)disabledPolicy;
- (nullable instancetype)initWithDestination:(K4LMediaSaveDestination)destination
                             customDirectory:(nullable NSString *)customDirectory
                      createsSenderDirectory:(BOOL)createsSenderDirectory
                          createsSenderAlbum:(BOOL)createsSenderAlbum
                               retentionDays:(NSUInteger)retentionDays NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

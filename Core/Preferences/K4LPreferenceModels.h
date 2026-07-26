#import <Foundation/Foundation.h>
#import "../Features/K4LFeature.h"
#import "../Models/K4LValueModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface K4LCategoryPreferences : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) K4LContentCategory category;
@property (nonatomic, strong, readonly) K4LFeatureOverrides *featureOverrides;
@property (nonatomic, strong, readonly, nullable) K4LMediaSavePolicy *mediaSavePolicyOverride;

- (nullable instancetype)initWithCategory:(K4LContentCategory)category
                         featureOverrides:(K4LFeatureOverrides *)featureOverrides
                  mediaSavePolicyOverride:(nullable K4LMediaSavePolicy *)mediaSavePolicyOverride NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LGlobalPreferences : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly, getter=isMasterEnabled) BOOL masterEnabled;
@property (nonatomic, strong, readonly) K4LFeatureSet *enabledFeatures;
@property (nonatomic, strong, readonly) K4LBatteryOverride *batteryOverride;
@property (nonatomic, strong, readonly) K4LMediaSavePolicy *mediaSavePolicy;
@property (nonatomic, copy, readonly) NSDictionary<NSNumber *, K4LCategoryPreferences *> *categoryPreferences;

+ (instancetype)disabledPreferences;
- (nullable instancetype)initWithMasterEnabled:(BOOL)masterEnabled
                               enabledFeatures:(K4LFeatureSet *)enabledFeatures
                               batteryOverride:(K4LBatteryOverride *)batteryOverride
                               mediaSavePolicy:(K4LMediaSavePolicy *)mediaSavePolicy
                           categoryPreferences:(NSDictionary<NSNumber *, K4LCategoryPreferences *> *)categoryPreferences NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LAccountPreferences : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, copy, readonly) NSString *accountIdentifier;
@property (nonatomic, strong, readonly) K4LFeatureOverrides *featureOverrides;
@property (nonatomic, strong, readonly, nullable) K4LLocation *spoofLocation;
@property (nonatomic, strong, readonly, nullable) K4LMediaSavePolicy *mediaSavePolicyOverride;
@property (nonatomic, copy, readonly) NSDictionary<NSNumber *, K4LCategoryPreferences *> *categoryPreferences;

- (nullable instancetype)initWithAccountIdentifier:(NSString *)accountIdentifier
                                  featureOverrides:(K4LFeatureOverrides *)featureOverrides
                                     spoofLocation:(nullable K4LLocation *)spoofLocation
                           mediaSavePolicyOverride:(nullable K4LMediaSavePolicy *)mediaSavePolicyOverride
                               categoryPreferences:(NSDictionary<NSNumber *, K4LCategoryPreferences *> *)categoryPreferences NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LFriendPreferences : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, copy, readonly) NSString *accountIdentifier;
@property (nonatomic, copy, readonly) NSString *friendIdentifier;
@property (nonatomic, strong, readonly) K4LFeatureOverrides *featureOverrides;
@property (nonatomic, strong, readonly, nullable) K4LMediaSavePolicy *mediaSavePolicyOverride;
@property (nonatomic, copy, readonly) NSDictionary<NSNumber *, K4LCategoryPreferences *> *categoryPreferences;

- (nullable instancetype)initWithAccountIdentifier:(NSString *)accountIdentifier
                                  friendIdentifier:(NSString *)friendIdentifier
                                  featureOverrides:(K4LFeatureOverrides *)featureOverrides
                           mediaSavePolicyOverride:(nullable K4LMediaSavePolicy *)mediaSavePolicyOverride
                               categoryPreferences:(NSDictionary<NSNumber *, K4LCategoryPreferences *> *)categoryPreferences NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface K4LPreferenceSnapshot : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) NSUInteger schemaVersion;
@property (nonatomic, strong, readonly) K4LGlobalPreferences *globalPreferences;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, K4LAccountPreferences *> *accountPreferences;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, K4LFriendPreferences *> *friendPreferences;

+ (instancetype)disabledSnapshot;
- (nullable instancetype)initWithSchemaVersion:(NSUInteger)schemaVersion
                             globalPreferences:(K4LGlobalPreferences *)globalPreferences
                            accountPreferences:(NSDictionary<NSString *, K4LAccountPreferences *> *)accountPreferences
                             friendPreferences:(NSDictionary<NSString *, K4LFriendPreferences *> *)friendPreferences NS_DESIGNATED_INITIALIZER;

- (BOOL)isFeatureEnabled:(K4LFeatureIdentifier)feature
                category:(K4LContentCategory)category
       accountIdentifier:(nullable NSString *)accountIdentifier
        friendIdentifier:(nullable NSString *)friendIdentifier;
- (K4LMediaSavePolicy *)mediaSavePolicyForCategory:(K4LContentCategory)category
                                accountIdentifier:(nullable NSString *)accountIdentifier
                                 friendIdentifier:(nullable NSString *)friendIdentifier;
- (nullable K4LLocation *)spoofLocationForAccountIdentifier:(nullable NSString *)accountIdentifier;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

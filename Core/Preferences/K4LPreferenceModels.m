#import "K4LPreferenceModels.h"

static NSString *K4LNormalizeIdentifier(NSString *identifier) {
    return [identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *K4LFriendPreferenceKey(NSString *accountIdentifier, NSString *friendIdentifier) {
    return [NSString stringWithFormat:@"%@\x1F%@", accountIdentifier, friendIdentifier];
}

static BOOL K4LContentCategoryIsValid(K4LContentCategory category) {
    return category >= K4LContentCategoryUnspecified &&
        category <= K4LContentCategoryStranger;
}

static BOOL K4LValidateCategoryPreferences(
    NSDictionary<NSNumber *, K4LCategoryPreferences *> *preferences
) {
    for (NSNumber *key in preferences) {
        K4LCategoryPreferences *value = preferences[key];
        K4LContentCategory category = (K4LContentCategory)key.integerValue;
        if (!K4LContentCategoryIsValid(category) ||
            category == K4LContentCategoryUnspecified ||
            value.category != category) {
            return NO;
        }
    }
    return YES;
}

static K4LFeatureOverrideState K4LCategoryFeatureState(
    NSDictionary<NSNumber *, K4LCategoryPreferences *> *preferences,
    K4LContentCategory category,
    K4LFeatureIdentifier feature
) {
    if (category == K4LContentCategoryUnspecified) {
        return K4LFeatureOverrideStateInherit;
    }
    return [preferences[@(category)].featureOverrides stateForFeature:feature];
}

static K4LMediaSavePolicy *K4LCategoryMediaPolicy(
    NSDictionary<NSNumber *, K4LCategoryPreferences *> *preferences,
    K4LContentCategory category
) {
    if (category == K4LContentCategoryUnspecified) {
        return nil;
    }
    return preferences[@(category)].mediaSavePolicyOverride;
}

@implementation K4LCategoryPreferences

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (nullable instancetype)initWithCategory:(K4LContentCategory)category
                         featureOverrides:(K4LFeatureOverrides *)featureOverrides
                  mediaSavePolicyOverride:(nullable K4LMediaSavePolicy *)mediaSavePolicyOverride {
    if (!K4LContentCategoryIsValid(category) ||
        category == K4LContentCategoryUnspecified) {
        return nil;
    }

    self = [super init];
    if (self) {
        _category = category;
        _featureOverrides = featureOverrides;
        _mediaSavePolicyOverride = mediaSavePolicyOverride;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    K4LFeatureOverrides *overrides =
        [coder decodeObjectOfClass:K4LFeatureOverrides.class forKey:@"overrides"];
    if (overrides == nil) {
        return nil;
    }
    return [self initWithCategory:[coder decodeIntegerForKey:@"category"]
                 featureOverrides:overrides
          mediaSavePolicyOverride:[coder decodeObjectOfClass:K4LMediaSavePolicy.class
                                                      forKey:@"media"]];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.category forKey:@"category"];
    [coder encodeObject:self.featureOverrides forKey:@"overrides"];
    [coder encodeObject:self.mediaSavePolicyOverride forKey:@"media"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LGlobalPreferences

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)disabledPreferences {
    return [[self alloc] initWithMasterEnabled:NO
                              enabledFeatures:K4LFeatureSet.emptySet
                              batteryOverride:K4LBatteryOverride.disabledOverride
                              mediaSavePolicy:K4LMediaSavePolicy.disabledPolicy
                          categoryPreferences:@{}];
}

- (nullable instancetype)initWithMasterEnabled:(BOOL)masterEnabled
                               enabledFeatures:(K4LFeatureSet *)enabledFeatures
                               batteryOverride:(K4LBatteryOverride *)batteryOverride
                               mediaSavePolicy:(K4LMediaSavePolicy *)mediaSavePolicy
                           categoryPreferences:(NSDictionary<NSNumber *, K4LCategoryPreferences *> *)categoryPreferences {
    if (!K4LValidateCategoryPreferences(categoryPreferences)) {
        return nil;
    }

    self = [super init];
    if (self) {
        _masterEnabled = masterEnabled;
        _enabledFeatures = enabledFeatures;
        _batteryOverride = batteryOverride;
        _mediaSavePolicy = mediaSavePolicy;
        _categoryPreferences = [categoryPreferences copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSSet<Class> *categoryClasses =
        [NSSet setWithObjects:NSDictionary.class, NSNumber.class, K4LCategoryPreferences.class, nil];

    K4LFeatureSet *features =
        [coder decodeObjectOfClass:K4LFeatureSet.class forKey:@"features"];
    K4LBatteryOverride *battery =
        [coder decodeObjectOfClass:K4LBatteryOverride.class forKey:@"battery"];
    K4LMediaSavePolicy *media =
        [coder decodeObjectOfClass:K4LMediaSavePolicy.class forKey:@"media"];
    NSDictionary *categories =
        [coder decodeObjectOfClasses:categoryClasses forKey:@"categories"];
    if (features == nil || battery == nil || media == nil || categories == nil) {
        return nil;
    }

    return [self initWithMasterEnabled:[coder decodeBoolForKey:@"masterEnabled"]
                      enabledFeatures:features
                      batteryOverride:battery
                      mediaSavePolicy:media
                  categoryPreferences:categories];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBool:self.masterEnabled forKey:@"masterEnabled"];
    [coder encodeObject:self.enabledFeatures forKey:@"features"];
    [coder encodeObject:self.batteryOverride forKey:@"battery"];
    [coder encodeObject:self.mediaSavePolicy forKey:@"media"];
    [coder encodeObject:self.categoryPreferences forKey:@"categories"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LAccountPreferences

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (nullable instancetype)initWithAccountIdentifier:(NSString *)accountIdentifier
                                  featureOverrides:(K4LFeatureOverrides *)featureOverrides
                                     spoofLocation:(nullable K4LLocation *)spoofLocation
                           mediaSavePolicyOverride:(nullable K4LMediaSavePolicy *)mediaSavePolicyOverride
                               categoryPreferences:(NSDictionary<NSNumber *, K4LCategoryPreferences *> *)categoryPreferences {
    NSString *normalized = K4LNormalizeIdentifier(accountIdentifier);
    if (normalized.length == 0 || !K4LValidateCategoryPreferences(categoryPreferences)) {
        return nil;
    }

    self = [super init];
    if (self) {
        _accountIdentifier = [normalized copy];
        _featureOverrides = featureOverrides;
        _spoofLocation = spoofLocation;
        _mediaSavePolicyOverride = mediaSavePolicyOverride;
        _categoryPreferences = [categoryPreferences copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSSet<Class> *categoryClasses =
        [NSSet setWithObjects:NSDictionary.class, NSNumber.class, K4LCategoryPreferences.class, nil];

    NSString *identifier =
        [coder decodeObjectOfClass:NSString.class forKey:@"accountIdentifier"];
    K4LFeatureOverrides *overrides =
        [coder decodeObjectOfClass:K4LFeatureOverrides.class forKey:@"overrides"];
    NSDictionary *categories =
        [coder decodeObjectOfClasses:categoryClasses forKey:@"categories"];
    if (identifier == nil || overrides == nil || categories == nil) {
        return nil;
    }

    return [self initWithAccountIdentifier:identifier
                          featureOverrides:overrides
                             spoofLocation:[coder decodeObjectOfClass:K4LLocation.class
                                                               forKey:@"location"]
                   mediaSavePolicyOverride:[coder decodeObjectOfClass:K4LMediaSavePolicy.class
                                                               forKey:@"media"]
                       categoryPreferences:categories];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.accountIdentifier forKey:@"accountIdentifier"];
    [coder encodeObject:self.featureOverrides forKey:@"overrides"];
    [coder encodeObject:self.spoofLocation forKey:@"location"];
    [coder encodeObject:self.mediaSavePolicyOverride forKey:@"media"];
    [coder encodeObject:self.categoryPreferences forKey:@"categories"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LFriendPreferences

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (nullable instancetype)initWithAccountIdentifier:(NSString *)accountIdentifier
                                  friendIdentifier:(NSString *)friendIdentifier
                                  featureOverrides:(K4LFeatureOverrides *)featureOverrides
                           mediaSavePolicyOverride:(nullable K4LMediaSavePolicy *)mediaSavePolicyOverride
                               categoryPreferences:(NSDictionary<NSNumber *, K4LCategoryPreferences *> *)categoryPreferences {
    NSString *normalizedAccount = K4LNormalizeIdentifier(accountIdentifier);
    NSString *normalizedFriend = K4LNormalizeIdentifier(friendIdentifier);
    if (normalizedAccount.length == 0 || normalizedFriend.length == 0 ||
        !K4LValidateCategoryPreferences(categoryPreferences)) {
        return nil;
    }

    self = [super init];
    if (self) {
        _accountIdentifier = [normalizedAccount copy];
        _friendIdentifier = [normalizedFriend copy];
        _featureOverrides = featureOverrides;
        _mediaSavePolicyOverride = mediaSavePolicyOverride;
        _categoryPreferences = [categoryPreferences copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSSet<Class> *categoryClasses =
        [NSSet setWithObjects:NSDictionary.class, NSNumber.class, K4LCategoryPreferences.class, nil];

    NSString *account =
        [coder decodeObjectOfClass:NSString.class forKey:@"accountIdentifier"];
    NSString *friend =
        [coder decodeObjectOfClass:NSString.class forKey:@"friendIdentifier"];
    K4LFeatureOverrides *overrides =
        [coder decodeObjectOfClass:K4LFeatureOverrides.class forKey:@"overrides"];
    NSDictionary *categories =
        [coder decodeObjectOfClasses:categoryClasses forKey:@"categories"];
    if (account == nil || friend == nil || overrides == nil || categories == nil) {
        return nil;
    }

    return [self initWithAccountIdentifier:account
                          friendIdentifier:friend
                          featureOverrides:overrides
                   mediaSavePolicyOverride:[coder decodeObjectOfClass:K4LMediaSavePolicy.class
                                                               forKey:@"media"]
                       categoryPreferences:categories];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.accountIdentifier forKey:@"accountIdentifier"];
    [coder encodeObject:self.friendIdentifier forKey:@"friendIdentifier"];
    [coder encodeObject:self.featureOverrides forKey:@"overrides"];
    [coder encodeObject:self.mediaSavePolicyOverride forKey:@"media"];
    [coder encodeObject:self.categoryPreferences forKey:@"categories"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@implementation K4LPreferenceSnapshot

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)disabledSnapshot {
    return [[self alloc] initWithSchemaVersion:1
                             globalPreferences:K4LGlobalPreferences.disabledPreferences
                            accountPreferences:@{}
                             friendPreferences:@{}];
}

- (nullable instancetype)initWithSchemaVersion:(NSUInteger)schemaVersion
                             globalPreferences:(K4LGlobalPreferences *)globalPreferences
                            accountPreferences:(NSDictionary<NSString *, K4LAccountPreferences *> *)accountPreferences
                             friendPreferences:(NSDictionary<NSString *, K4LFriendPreferences *> *)friendPreferences {
    if (schemaVersion == 0) {
        return nil;
    }

    for (NSString *key in accountPreferences) {
        K4LAccountPreferences *value = accountPreferences[key];
        if (![key isEqualToString:value.accountIdentifier]) {
            return nil;
        }
    }

    for (NSString *key in friendPreferences) {
        K4LFriendPreferences *value = friendPreferences[key];
        NSString *expectedKey =
            K4LFriendPreferenceKey(value.accountIdentifier, value.friendIdentifier);
        if (![key isEqualToString:expectedKey]) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        _schemaVersion = schemaVersion;
        _globalPreferences = globalPreferences;
        _accountPreferences = [accountPreferences copy];
        _friendPreferences = [friendPreferences copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSSet<Class> *accountClasses =
        [NSSet setWithObjects:NSDictionary.class, NSString.class, K4LAccountPreferences.class, nil];
    NSSet<Class> *friendClasses =
        [NSSet setWithObjects:NSDictionary.class, NSString.class, K4LFriendPreferences.class, nil];

    K4LGlobalPreferences *global =
        [coder decodeObjectOfClass:K4LGlobalPreferences.class forKey:@"global"];
    NSDictionary *accounts =
        [coder decodeObjectOfClasses:accountClasses forKey:@"accounts"];
    NSDictionary *friends =
        [coder decodeObjectOfClasses:friendClasses forKey:@"friends"];
    if (global == nil || accounts == nil || friends == nil) {
        return nil;
    }

    return [self initWithSchemaVersion:(NSUInteger)[coder decodeIntegerForKey:@"schemaVersion"]
                     globalPreferences:global
                    accountPreferences:accounts
                     friendPreferences:friends];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:(NSInteger)self.schemaVersion forKey:@"schemaVersion"];
    [coder encodeObject:self.globalPreferences forKey:@"global"];
    [coder encodeObject:self.accountPreferences forKey:@"accounts"];
    [coder encodeObject:self.friendPreferences forKey:@"friends"];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isFeatureEnabled:(K4LFeatureIdentifier)feature
                category:(K4LContentCategory)category
       accountIdentifier:(nullable NSString *)accountIdentifier
        friendIdentifier:(nullable NSString *)friendIdentifier {
    if (!self.globalPreferences.masterEnabled ||
        !K4LFeatureIdentifierIsKnown(feature) ||
        !K4LContentCategoryIsValid(category)) {
        return NO;
    }

    NSString *accountKey =
        accountIdentifier.length > 0 ? K4LNormalizeIdentifier(accountIdentifier) : nil;
    NSString *friendKey =
        friendIdentifier.length > 0 ? K4LNormalizeIdentifier(friendIdentifier) : nil;

    K4LFriendPreferences *friend = nil;
    if (accountKey.length > 0 && friendKey.length > 0) {
        friend = self.friendPreferences[K4LFriendPreferenceKey(accountKey, friendKey)];

        K4LFeatureOverrideState categoryState =
            K4LCategoryFeatureState(friend.categoryPreferences, category, feature);
        if (categoryState != K4LFeatureOverrideStateInherit) {
            return categoryState == K4LFeatureOverrideStateEnabled;
        }

        K4LFeatureOverrideState state =
            [friend.featureOverrides stateForFeature:feature];
        if (state != K4LFeatureOverrideStateInherit) {
            return state == K4LFeatureOverrideStateEnabled;
        }
    }

    K4LAccountPreferences *account = nil;
    if (accountKey.length > 0) {
        account = self.accountPreferences[accountKey];

        K4LFeatureOverrideState categoryState =
            K4LCategoryFeatureState(account.categoryPreferences, category, feature);
        if (categoryState != K4LFeatureOverrideStateInherit) {
            return categoryState == K4LFeatureOverrideStateEnabled;
        }

        K4LFeatureOverrideState state =
            [account.featureOverrides stateForFeature:feature];
        if (state != K4LFeatureOverrideStateInherit) {
            return state == K4LFeatureOverrideStateEnabled;
        }
    }

    K4LFeatureOverrideState globalCategoryState =
        K4LCategoryFeatureState(self.globalPreferences.categoryPreferences, category, feature);
    if (globalCategoryState != K4LFeatureOverrideStateInherit) {
        return globalCategoryState == K4LFeatureOverrideStateEnabled;
    }

    return [self.globalPreferences.enabledFeatures containsFeature:feature];
}

- (K4LMediaSavePolicy *)mediaSavePolicyForCategory:(K4LContentCategory)category
                                accountIdentifier:(nullable NSString *)accountIdentifier
                                 friendIdentifier:(nullable NSString *)friendIdentifier {
    if (!K4LContentCategoryIsValid(category)) {
        return K4LMediaSavePolicy.disabledPolicy;
    }

    NSString *accountKey =
        accountIdentifier.length > 0 ? K4LNormalizeIdentifier(accountIdentifier) : nil;
    NSString *friendKey =
        friendIdentifier.length > 0 ? K4LNormalizeIdentifier(friendIdentifier) : nil;

    if (accountKey.length > 0 && friendKey.length > 0) {
        K4LFriendPreferences *friend =
            self.friendPreferences[K4LFriendPreferenceKey(accountKey, friendKey)];

        K4LMediaSavePolicy *categoryPolicy =
            K4LCategoryMediaPolicy(friend.categoryPreferences, category);
        if (categoryPolicy != nil) {
            return categoryPolicy;
        }
        if (friend.mediaSavePolicyOverride != nil) {
            return friend.mediaSavePolicyOverride;
        }
    }

    if (accountKey.length > 0) {
        K4LAccountPreferences *account = self.accountPreferences[accountKey];

        K4LMediaSavePolicy *categoryPolicy =
            K4LCategoryMediaPolicy(account.categoryPreferences, category);
        if (categoryPolicy != nil) {
            return categoryPolicy;
        }
        if (account.mediaSavePolicyOverride != nil) {
            return account.mediaSavePolicyOverride;
        }
    }

    K4LMediaSavePolicy *globalCategoryPolicy =
        K4LCategoryMediaPolicy(self.globalPreferences.categoryPreferences, category);
    return globalCategoryPolicy ?: self.globalPreferences.mediaSavePolicy;
}

- (nullable K4LLocation *)spoofLocationForAccountIdentifier:(nullable NSString *)accountIdentifier {
    NSString *normalized =
        accountIdentifier.length > 0 ? K4LNormalizeIdentifier(accountIdentifier) : nil;
    if (normalized.length == 0) {
        return nil;
    }
    return self.accountPreferences[normalized].spoofLocation;
}

@end

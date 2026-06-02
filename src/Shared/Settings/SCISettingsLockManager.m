#import "SCISettingsLockManager.h"

@implementation SCISettingsLockManager

+ (instancetype)sharedManager {
    static SCISettingsLockManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SCISettingsLockManager alloc] init];
    });
    return instance;
}

- (NSString *)lockEnabledDefaultsKey {
    return @"settings_lock";
}

- (NSString *)keychainService {
    return @"com.socuul.scinsta.settings.passcode";
}

- (NSString *)protectedContentName {
    return @"Settings";
}

- (void)lockSettings {
    [self lockContent];
}

@end

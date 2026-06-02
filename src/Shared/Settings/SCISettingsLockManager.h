#import "../Gallery/SCIGalleryManager.h"

NS_ASSUME_NONNULL_BEGIN

/// Independent Settings passcode lock backed by its own keychain record.
@interface SCISettingsLockManager : SCIGalleryManager

+ (instancetype)sharedManager;
- (void)lockSettings;

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const kSCIPrefInterfaceLiquidGlass;
FOUNDATION_EXPORT NSString * const kSCIPrefInterfaceLiquidGlassTabBarMode;
FOUNDATION_EXPORT NSString * const kSCIPrefInterfaceProgressiveBlur;
FOUNDATION_EXPORT NSString * const kSCIPrefInstantsDisableCameraControl;

#ifdef __cplusplus
extern "C" {
#endif

NSString *SCIPrefActionButtonConfigKey(NSString *topicKey);
NSString *SCIPrefActionButtonDefaultActionKey(NSString *topicKey);
NSString *SCIPrefActionButtonBulkDownloadKey(NSString *topicKey);
NSString *SCIPrefActionButtonBulkCopyKey(NSString *topicKey);
NSString *SCIPrefNotificationKey(NSString *identifier);
NSString *SCIPrefNotificationHapticKey(NSString *identifier);

/// YES on iPhone models that have the hardware Camera Control button
/// (iPhone 16/17 families, excluding iPhone 16e which lacks it).
BOOL SCIDeviceHasCameraControl(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

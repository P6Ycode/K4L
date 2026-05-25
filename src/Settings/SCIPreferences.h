#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const kSCIPrefInterfaceLiquidGlass;

#ifdef __cplusplus
extern "C" {
#endif

NSString *SCIPrefActionButtonConfigKey(NSString *topicKey);
NSString *SCIPrefActionButtonBulkDownloadKey(NSString *topicKey);
NSString *SCIPrefActionButtonBulkCopyKey(NSString *topicKey);
NSString *SCIPrefNotificationKey(NSString *identifier);
NSString *SCIPrefNotificationHapticKey(NSString *identifier);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, SPKSurface) {
    SPKSurfaceGeneralUI = 0,
    SPKSurfaceFeed,
    SPKSurfaceStories,
    SPKSurfaceReels,
    SPKSurfaceMessages,
    SPKSurfaceProfile,
};

#ifdef __cplusplus
extern "C" {
#endif

FOUNDATION_EXPORT void SPKCoreRegisterBootstrapDefaults(void);
FOUNDATION_EXPORT void SPKCoreRegisterDefaults(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *SPKCoreRegisteredDefaults(void);
FOUNDATION_EXPORT void SPKCoreInstallLaunchCriticalHooks(void);
FOUNDATION_EXPORT void SPKCoreInstallSurfaceHooks(SPKSurface surface);
FOUNDATION_EXPORT void SPKCoreShowSettingsIfNeeded(UIWindow *window);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

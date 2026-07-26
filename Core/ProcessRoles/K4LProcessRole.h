#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, K4LProcessRole) {
    K4LProcessRoleUnknown = 0,
    K4LProcessRoleSpringBoard,
    K4LProcessRoleBackBoard,
    K4LProcessRoleScreenshotServices,
    K4LProcessRoleMediaServer,
    K4LProcessRoleAudioMixer,
    K4LProcessRoleCameraCapture,
    K4LProcessRolePower,
    K4LProcessRoleSnapchat,
    K4LProcessRolePreferences,
    K4LProcessRoleDaemon,
    K4LProcessRoleControlHelper,
};

FOUNDATION_EXPORT NSString *K4LProcessRoleName(K4LProcessRole role);
FOUNDATION_EXPORT BOOL K4LProcessRoleIsInjectedProcess(K4LProcessRole role);
FOUNDATION_EXPORT BOOL K4LProcessRoleIsPrivilegedProcess(K4LProcessRole role);

NS_ASSUME_NONNULL_END

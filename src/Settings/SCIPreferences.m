#import "SCIPreferences.h"
#import <sys/sysctl.h>

NSString * const kSCIPrefInterfaceLiquidGlass = @"interface_liquid_glass";
NSString * const kSCIPrefInterfaceLiquidGlassTabBarMode = @"interface_liquid_glass_tabbar_mode";
NSString * const kSCIPrefInterfaceProgressiveBlur = @"interface_progressive_blur";
NSString * const kSCIPrefInstantsDisableCameraControl = @"instants_disable_camera_control";

NSString *SCIPrefActionButtonConfigKey(NSString *topicKey) {
    return [NSString stringWithFormat:@"%@_action_btn_cfg", topicKey ?: @""];
}

NSString *SCIPrefActionButtonDefaultActionKey(NSString *topicKey) {
    return [NSString stringWithFormat:@"%@_action_btn_default_action", topicKey ?: @""];
}

NSString *SCIPrefActionButtonBulkDownloadKey(NSString *topicKey) {
    return [NSString stringWithFormat:@"%@_action_btn_bulk_download_actions", topicKey ?: @""];
}

NSString *SCIPrefActionButtonBulkCopyKey(NSString *topicKey) {
    return [NSString stringWithFormat:@"%@_action_btn_bulk_copy_actions", topicKey ?: @""];
}

NSString *SCIPrefNotificationKey(NSString *identifier) {
    return [NSString stringWithFormat:@"notifs_%@", identifier ?: @""];
}

NSString *SCIPrefNotificationHapticKey(NSString *identifier) {
    return [NSString stringWithFormat:@"notifs_%@_haptic", identifier ?: @""];
}

BOOL SCIDeviceHasCameraControl(void) {
    static BOOL hasCameraControl = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char machine[64] = {0};
        size_t size = sizeof(machine);
        if (sysctlbyname("hw.machine", machine, &size, NULL, 0) != 0 || machine[0] == '\0') {
            return;
        }
        NSString *model = [NSString stringWithUTF8String:machine];

        // Models with the hardware Camera Control button. iPhone 16e (iPhone17,5)
        // is intentionally excluded — it has no Camera Control.
        static NSSet<NSString *> *cameraControlModels;
        cameraControlModels = [NSSet setWithArray:@[
            @"iPhone17,1",  // iPhone 16 Pro
            @"iPhone17,2",  // iPhone 16 Pro Max
            @"iPhone17,3",  // iPhone 16
            @"iPhone17,4",  // iPhone 16 Plus
            @"iPhone18,1",  // iPhone 17 Pro
            @"iPhone18,2",  // iPhone 17 Pro Max
            @"iPhone18,3",  // iPhone 17
            @"iPhone18,4",  // iPhone Air
        ]];
        hasCameraControl = [cameraControlModels containsObject:model];
    });
    return hasCameraControl;
}

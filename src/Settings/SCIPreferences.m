#import "SCIPreferences.h"

NSString * const kSCIPrefInterfaceLiquidGlass = @"interface_liquid_glass";

NSString *SCIPrefActionButtonConfigKey(NSString *topicKey) {
    return [NSString stringWithFormat:@"%@_action_btn_cfg", topicKey ?: @""];
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

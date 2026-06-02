#import "SCIPreferenceAvailability.h"

#import <UIKit/UIKit.h>

#import "SCIPreferences.h"
#import "../App/SCIFlexLoader.h"

static BOOL SCIIsIOSVersionAtLeast(NSString *version) {
    return [[[UIDevice currentDevice] systemVersion] compare:version options:NSNumericSearch] != NSOrderedAscending;
}

BOOL SCIPrefIsAvailable(NSString *key) {
    if (key.length == 0) return YES;

    if ([key isEqualToString:kSCIPrefInterfaceLiquidGlass] ||
        [key isEqualToString:kSCIPrefInterfaceLiquidGlassTabBarMode] ||
        [key isEqualToString:kSCIPrefInterfaceProgressiveBlur]) {
        return SCIIsIOSVersionAtLeast(@"26.0");
    }

    if ([key isEqualToString:@"notifs_pill_liquid_glass"]) {
        return SCIIsIOSVersionAtLeast(@"26.0");
    }

    if ([key isEqualToString:kSCIPrefInstantsDisableCameraControl]) {
        return SCIDeviceHasCameraControl();
    }

    if ([key hasPrefix:@"tools_flex_"]) {
        return SCIFlexIsBundled();
    }

    return YES;
}

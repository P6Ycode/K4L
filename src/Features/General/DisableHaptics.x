#import "../../Utils.h"

%group SCIDisableHapticsHooks

%hook UIImpactFeedbackGenerator
- (void)impactOccurred {
    if (![SCIUtils getBoolPref:@"general_disable_haptics"]) %orig;
}
- (void)impactOccurredWithIntensity:(CGFloat)intensity {
    if (![SCIUtils getBoolPref:@"general_disable_haptics"]) %orig(intensity);
}
%end

%hook UINotificationFeedbackGenerator
- (void)notificationOccurred:(UINotificationFeedbackType)notificationType {
    if (![SCIUtils getBoolPref:@"general_disable_haptics"]) %orig(notificationType);
}
%end

%hook UISelectionFeedbackGenerator
- (void)selectionChanged {
    if (![SCIUtils getBoolPref:@"general_disable_haptics"]) %orig;
}
%end

%hook CHHapticEngine
- (BOOL)startAndReturnError:(NSError **)outError {
    if (![SCIUtils getBoolPref:@"general_disable_haptics"]) {
        return %orig(outError);
    }
    else {
        return NO;
    }
}
%end

%end

void SCIInstallDisableHapticsHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"general_disable_haptics"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIDisableHapticsHooks);
    });
}

#import <UIKit/UIKit.h>

#import "../../Utils.h"
#import "../../Shared/UI/SCIChrome.h"

static NSString * const kSCIInstantsAllowScreenshotPref = @"instants_allow_screenshot";

static BOOL SCIInstantsAllowScreenshotEnabled(void) {
    return [SCIUtils getBoolPref:kSCIInstantsAllowScreenshotPref];
}

static BOOL SCIInstantsViewControllerTreeContainsQuickSnap(UIViewController *controller) {
    if (!controller) return NO;
    if ([NSStringFromClass(controller.class) containsString:@"QuickSnap"]) return YES;
    for (UIViewController *child in controller.childViewControllers) {
        if (SCIInstantsViewControllerTreeContainsQuickSnap(child)) return YES;
    }
    return SCIInstantsViewControllerTreeContainsQuickSnap(controller.presentedViewController);
}

static BOOL SCIInstantsScreenshotBypassActive(void) {
    if (!SCIInstantsAllowScreenshotEnabled()) return NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (SCIInstantsViewControllerTreeContainsQuickSnap(window.rootViewController)) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL SCIInstantsIsScreenshotCoverText(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) return NO;
    NSString *lower = text.lowercaseString;
    return [lower containsString:@"screenshot or record"] ||
           [lower containsString:@"only meant to be viewed once"] ||
           [lower containsString:@"only meant to be replayed once"];
}

static UIView *SCIInstantsTopAncestorBelowWindow(UIView *view) {
    UIView *current = view;
    while (current.superview && ![current.superview isKindOfClass:UIWindow.class]) {
        current = current.superview;
    }
    return current.superview ? current : nil;
}

static UITextField *SCIInstantsSecureTextFieldAncestor(UIView *view) {
    UIView *parent = view.superview;
    while (parent) {
        if ([parent isKindOfClass:UITextField.class]) return (UITextField *)parent;
        parent = parent.superview;
    }
    return nil;
}

%group SCIInstantsAllowScreenshotHooks

%hook UIScreen
- (BOOL)isCaptured {
    if (SCIInstantsScreenshotBypassActive()) return NO;
    return %orig;
}
%end

%hook NSNotificationCenter
- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    if (SCIInstantsScreenshotBypassActive() && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
    %orig;
}

- (void)postNotificationName:(NSNotificationName)name object:(id)object {
    if (SCIInstantsScreenshotBypassActive() && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
    %orig;
}
%end

%hook UITextField
- (void)setSecureTextEntry:(BOOL)secureTextEntry {
    if (secureTextEntry && SCIInstantsScreenshotBypassActive() && !SCIChromeCanvasOwnsSecureField((UITextField *)self)) {
        %orig(NO);
        return;
    }
    %orig;
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (!SCIInstantsScreenshotBypassActive() || !SCIInstantsIsScreenshotCoverText(text)) return;
    UILabel *label = (UILabel *)self;
    UIView *cover = SCIInstantsTopAncestorBelowWindow(label) ?: label.superview ?: label;
    cover.hidden = YES;
    cover.alpha = 0.0;
    label.hidden = YES;
    label.alpha = 0.0;

    UITextField *secureField = SCIInstantsSecureTextFieldAncestor(cover);
    if (secureField.secureTextEntry && !SCIChromeCanvasOwnsSecureField(secureField)) {
        secureField.secureTextEntry = NO;
    }
}
%end

%end

extern "C" void SCIInstallInstantsAllowScreenshotHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIInstantsAllowScreenshotHooks);
        SCILog(@"Instants", @"[SCInsta] Instants allow screenshot hooks installed");
    });
}

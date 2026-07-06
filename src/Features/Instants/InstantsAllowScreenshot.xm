#import <UIKit/UIKit.h>

#import "../../Shared/UI/SPKChrome.h"
#import "../../Utils.h"

static NSString *const kSPKInstantsAllowScreenshotPref = @"instants_allow_screenshot";

static BOOL SPKInstantsAllowScreenshotEnabled(void) {
    return [SPKUtils getBoolPref:kSPKInstantsAllowScreenshotPref];
}

static BOOL SPKInstantsViewControllerTreeContainsQuickSnap(UIViewController *controller) {
    if (!controller)
        return NO;
    if ([NSStringFromClass(controller.class) containsString:@"QuickSnap"])
        return YES;
    for (UIViewController *child in controller.childViewControllers) {
        if (SPKInstantsViewControllerTreeContainsQuickSnap(child))
            return YES;
    }
    return SPKInstantsViewControllerTreeContainsQuickSnap(controller.presentedViewController);
}

static BOOL SPKInstantsScreenshotBypassActive(void) {
    if (!SPKInstantsAllowScreenshotEnabled())
        return NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class])
            continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (SPKInstantsViewControllerTreeContainsQuickSnap(window.rootViewController)) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL SPKInstantsIsScreenshotCoverText(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length == 0)
        return NO;
    NSString *lower = text.lowercaseString;
    return [lower containsString:@"screenshot or record"] ||
           [lower containsString:@"only meant to be viewed once"] ||
           [lower containsString:@"only meant to be replayed once"];
}

static UIView *SPKInstantsTopAncestorBelowWindow(UIView *view) {
    UIView *current = view;
    while (current.superview && ![current.superview isKindOfClass:UIWindow.class]) {
        current = current.superview;
    }
    return current.superview ? current : nil;
}

static UITextField *SPKInstantsSecureTextFieldAncestor(UIView *view) {
    UIView *parent = view.superview;
    while (parent) {
        if ([parent isKindOfClass:UITextField.class])
            return (UITextField *)parent;
        parent = parent.superview;
    }
    return nil;
}

%group SPKInstantsAllowScreenshotHooks

%hook UIScreen
- (BOOL)isCaptured {
    if (SPKInstantsScreenshotBypassActive())
        return NO;
    return %orig;
}
%end

%hook NSNotificationCenter
- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    if (SPKInstantsScreenshotBypassActive() && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification])
        return;
    %orig;
}

- (void)postNotificationName:(NSNotificationName)name object:(id)object {
    if (SPKInstantsScreenshotBypassActive() && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification])
        return;
    %orig;
}
%end

%hook UITextField
- (void)setSecureTextEntry:(BOOL)secureTextEntry {
    if (secureTextEntry && SPKInstantsScreenshotBypassActive() && !SPKChromeCanvasOwnsSecureField((UITextField *)self)) {
        %orig(NO);
        return;
    }
    %orig;
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    // Text check first (cheap string scan, almost always false) — avoids the
    // expensive pref read + VC-tree walk for every label in the app.
    if (!SPKInstantsIsScreenshotCoverText(text) || !SPKInstantsScreenshotBypassActive())
        return;
    UILabel *label = (UILabel *)self;
    UIView *cover = SPKInstantsTopAncestorBelowWindow(label) ?: label.superview ?
                                                                                : label;
    cover.hidden = YES;
    cover.alpha = 0.0;
    label.hidden = YES;
    label.alpha = 0.0;

    UITextField *secureField = SPKInstantsSecureTextFieldAncestor(cover);
    if (secureField.secureTextEntry && !SPKChromeCanvasOwnsSecureField(secureField)) {
        secureField.secureTextEntry = NO;
    }
}
%end

%end

extern "C" void SPKInstallInstantsAllowScreenshotHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKInstantsAllowScreenshotHooks);
        SPKLog(@"Instants", @"[Sparkle] Instants allow screenshot hooks installed");
    });
}

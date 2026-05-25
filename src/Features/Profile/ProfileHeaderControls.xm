#import "../../Utils.h"
#import <objc/runtime.h>

static const void *kSCIProfileHeaderSavedHiddenKey = &kSCIProfileHeaderSavedHiddenKey;
static const void *kSCIProfileHeaderSavedAlphaKey = &kSCIProfileHeaderSavedAlphaKey;

static BOOL SCIProfileShouldHideThreadsButton(UIView *view) {
    if (![SCIUtils getBoolPref:@"profile_hide_threads_btn"]) return NO;
    NSString *identifier = view.accessibilityIdentifier ?: @"";
    NSString *label = view.accessibilityLabel ?: @"";
    if ([identifier isEqualToString:@"profile-app-switch-button"]) return YES;
    if ([label rangeOfString:@"switch to threads" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

static BOOL SCIProfileShouldHideNotesBubble(UIView *view) {
    if (![SCIUtils getBoolPref:@"profile_hide_notes_bubble"]) return NO;
    NSString *className = NSStringFromClass(view.class);
    return [className containsString:@"IGDirectNotesThoughtBubbleView"];
}

static void SCIApplyProfileHeaderVisibility(UIView *view) {
    if (!view) return;
    BOOL shouldHide = SCIProfileShouldHideThreadsButton(view) || SCIProfileShouldHideNotesBubble(view);
    NSNumber *savedHidden = objc_getAssociatedObject(view, kSCIProfileHeaderSavedHiddenKey);
    NSNumber *savedAlpha = objc_getAssociatedObject(view, kSCIProfileHeaderSavedAlphaKey);

    if (shouldHide) {
        if (!savedHidden) {
            objc_setAssociatedObject(view, kSCIProfileHeaderSavedHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, kSCIProfileHeaderSavedAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.hidden = YES;
        view.alpha = 0.0;
        return;
    }

    if (savedHidden || savedAlpha) {
        if (savedHidden) view.hidden = savedHidden.boolValue;
        if (savedAlpha) view.alpha = savedAlpha.doubleValue;
        objc_setAssociatedObject(view, kSCIProfileHeaderSavedHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kSCIProfileHeaderSavedAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%group SCIProfileHeaderControlsHooks

%hook UIView
- (void)didMoveToWindow {
    %orig;
    SCIApplyProfileHeaderVisibility((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    SCIApplyProfileHeaderVisibility((UIView *)self);
}
%end

%end

extern "C" void SCIInstallProfileHeaderControlsHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIProfileHeaderControlsHooks);
    });
}

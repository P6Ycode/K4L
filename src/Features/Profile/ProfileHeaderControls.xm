#import "../../Utils.h"
#import <objc/runtime.h>

static const void *kSCIProfileHeaderSavedHiddenKey = &kSCIProfileHeaderSavedHiddenKey;
static const void *kSCIProfileHeaderSavedAlphaKey = &kSCIProfileHeaderSavedAlphaKey;

// Tracks whether we've ever hidden anything, so the disabled/default case can
// skip the subtree walk entirely (and only pays it once to restore after a
// toggle-off).
static BOOL sSCIProfileControlsEverApplied = NO;

static BOOL SCIProfileViewIsThreadsButton(UIView *view) {
    NSString *identifier = view.accessibilityIdentifier ?: @"";
    if ([identifier isEqualToString:@"profile-app-switch-button"]) return YES;
    NSString *label = view.accessibilityLabel ?: @"";
    if ([label rangeOfString:@"switch to threads" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

static BOOL SCIProfileViewIsNotesBubble(UIView *view) {
    NSString *className = NSStringFromClass(view.class);
    return [className containsString:@"IGDirectNotesThoughtBubbleView"];
}

static void SCIApplyProfileHeaderVisibility(UIView *view, BOOL hideThreads, BOOL hideNotes) {
    if (!view) return;
    BOOL shouldHide = (hideThreads && SCIProfileViewIsThreadsButton(view)) ||
                      (hideNotes && SCIProfileViewIsNotesBubble(view));
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

static void SCIApplyProfileHeaderControlsInTree(UIView *view, BOOL hideThreads, BOOL hideNotes, NSUInteger depth) {
    if (!view || depth > 40) return;
    SCIApplyProfileHeaderVisibility(view, hideThreads, hideNotes);
    for (UIView *sub in view.subviews) {
        SCIApplyProfileHeaderControlsInTree(sub, hideThreads, hideNotes, depth + 1);
    }
}

// Applied only when a profile is on screen — never on the per-view, app-wide layout path
static void SCIApplyProfileHeaderControls(UIViewController *vc) {
    BOOL hideThreads = [SCIUtils getBoolPref:@"profile_hide_threads_btn"];
    BOOL hideNotes = [SCIUtils getBoolPref:@"profile_hide_notes_bubble"];
    if (!hideThreads && !hideNotes && !sSCIProfileControlsEverApplied) return;
    if (hideThreads || hideNotes) sSCIProfileControlsEverApplied = YES;

    SCIApplyProfileHeaderControlsInTree(vc.view, hideThreads, hideNotes, 0);
    UIView *navBar = vc.navigationController.navigationBar;
    if (navBar) SCIApplyProfileHeaderControlsInTree(navBar, hideThreads, hideNotes, 0);
}

%group SCIProfileHeaderControlsHooks

%hook IGProfileViewController
- (void)viewDidLayoutSubviews {
    %orig;
    SCIApplyProfileHeaderControls((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIApplyProfileHeaderControls((UIViewController *)self);
}
%end

%end

extern "C" void SCIInstallProfileHeaderControlsHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIProfileHeaderControlsHooks);
    });
}

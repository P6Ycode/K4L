// Instants (QuickSnap) creation controls.
//
// Three user-facing behaviours:
//   - Disable Instants Creation  -> hard-block capture (photo AND video). The
//                                    shutter is darkened, the whole
//                                    IGCameraCaptureButtonDelegate surface is
//                                    swallowed (so press-and-hold can't record),
//                                    and the hardware Camera Control is disabled.
//   - Confirm Instant Capture     -> let the photo be CAPTURED normally (so the
//                                    exact frame is preserved), then ask for
//                                    confirmation when the user taps Send on the
//                                    post-creation screen. Cancel keeps the
//                                    captured photo on screen so nothing sends and
//                                    the frame isn't lost; confirm sends it.
//   - Skip Camera After Instants  -> skip the camera IG auto-opens after the last
//                                    received Instant is viewed.
//
// Why gate SEND, not CAPTURE, for confirm: the on-screen shutter auto-sends on
// release and the hardware Camera Control capture path is Swift/AVKit-internal
// (no ObjC selector to prompt on — verified via a full class-dump). Gating the
// release/confirm of the *capture* meant the photo was never actually taken, so
// confirming later re-captured a different frame. Instead we let capture happen
// and intercept the post-creation Send button (IGQuickSnapPostCreationView
// -didTapConfirm), which fires after the frame is frozen.

#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>

#import "../../Utils.h"
#import "../../Shared/UI/SCINotificationCenter.h"
#import "../../Shared/Instants/SCIInstantsFrameInjector.h"
#import "../../Settings/SCIPreferences.h"

static NSString * const kSCIQuickSnapDisableCreationPref = @"instants_disable_creation";
static NSString * const kSCIQuickSnapConfirmCapturePref = @"instants_confirm_capture";
static NSString * const kSCIQuickSnapDisableCameraControlPref = @"instants_disable_camera_control";
static NSString * const kSCIQuickSnapSkipCameraAfterViewingPref = @"instants_skip_camera_after_viewing";

typedef void (*SCIQuickSnapVoidIMP)(id, SEL);
typedef void (*SCIQuickSnapVoidOneArgIMP)(id, SEL, id);
typedef void (*SCIQuickSnapVoidLongLongIMP)(id, SEL, long long);
typedef void (*SCIQuickSnapViewAppearIMP)(id, SEL, _Bool);
typedef void (*SCIQuickSnapLayoutIMP)(id, SEL);

// IGCameraCaptureButtonDelegate surface (QuickSnap camera control view) — used to
// hard-block capture in "Disable Creation" mode only.
static SCIQuickSnapVoidIMP orig_captureButtonDidTouchDown = NULL;
static SCIQuickSnapVoidIMP orig_captureButtonDidBeginExpanding = NULL;
static SCIQuickSnapVoidIMP orig_captureButtonDidEndExpanding = NULL;
static SCIQuickSnapVoidIMP orig_captureButtonDidReleaseBeforeExpandingFinished = NULL;
static SCIQuickSnapVoidIMP orig_captureButtonDidReleaseAfterExpandingFinished = NULL;
static SCIQuickSnapVoidIMP orig_captureButtonDidReleaseFromInterruption = NULL;
static SCIQuickSnapVoidIMP orig_captureButtonDidConfirm = NULL;
static SCIQuickSnapLayoutIMP orig_cameraControlViewLayoutSubviews = NULL;

static SCIQuickSnapVoidOneArgIMP orig_quickSnapPeekViewDidSelectCamera = NULL;
static SCIQuickSnapVoidLongLongIMP orig_didTapCameraButtonWithCameraEntryPoint = NULL;
static SCIQuickSnapViewAppearIMP orig_consumptionViewDidAppear = NULL;
static SCIQuickSnapViewAppearIMP orig_consumptionViewDidDisappear = NULL;
static SCIQuickSnapViewAppearIMP orig_creationViewWillAppear = NULL;

// Skip-camera state. We arm a flag when the consumption (viewing) controller is
// the last thing the user saw, and consume it when the creation camera tries to
// appear — instead of relying on a fragile time window. Explicit camera entry
// (tapping the camera button) clears the flag so we never skip a camera the
// user actually asked for.
static BOOL sSCIQuickSnapConsumptionWasVisible = NO;
static BOOL sSCIQuickSnapSkipNextCreation = NO;
static BOOL sSCIQuickSnapExplicitCameraEntry = NO;

static BOOL sSCIQuickSnapSendConfirmVisible = NO;

// Posted by the settings toggle so a visible camera refreshes its darken state
// live (no app or Instants restart needed).
static NSString * const kSCIQuickSnapCreationPrefChangedNotification = @"SCIQuickSnapCreationPrefChangedNotification";

// The currently on-screen camera control view, tracked from its layout pass so a
// live pref change can re-apply the lock state to it immediately.
static __weak UIView *sSCIQuickSnapVisibleControlView = nil;

static BOOL SCIQuickSnapCreationDisabled(void) {
    return [SCIUtils getBoolPref:kSCIQuickSnapDisableCreationPref];
}

static BOOL SCIQuickSnapSendConfirmEnabled(void) {
    /// TODO: investigate — hard-disabled. Confirm Instant Capture cannot gate IG's
    /// new VIDEO Instants pipeline: capture happens regardless of the capture-button
    /// delegate (those callbacks are notification-only; swallowing them only breaks
    /// the shutter UI), and both photo & video auto-send through the undo-send pill /
    /// IGQuickSnapPendingSendManager — whose commit/timer is Swift-internal with
    /// stripped symbols. +isVideoCaptureEnabled: is baked before our %ctor so it
    /// can't be forced off either. The capture-button release gate below is therefore
    /// a no-op for the new flow. Revisit when the undo-pill / pending-send commit can
    /// be intercepted (would need deep ARM64 RE). See memory:
    /// instants-confirm-capture-video-blocked. Restore by returning the pref read.
    return NO;
    // return [SCIUtils getBoolPref:kSCIQuickSnapConfirmCapturePref];
}

static BOOL SCIQuickSnapDisableCameraControlEnabled(void) {
    return [SCIUtils getBoolPref:kSCIQuickSnapDisableCameraControlPref] && SCIDeviceHasCameraControl();
}

static BOOL SCIQuickSnapSkipCameraAfterViewingEnabled(void) {
    return [SCIUtils getBoolPref:kSCIQuickSnapSkipCameraAfterViewingPref];
}

static void SCIQuickSnapNotifyBlocked(void) {
    SCINotify(kSCINotificationInstantsCaptureBlocked,
              @"Instant capture blocked",
              nil,
              @"lock_filled",
              SCINotificationToneInfo);
}

// MARK: - Capture button delegate gate
//
// One handler for the whole IGCameraCaptureButtonDelegate surface.
//   - Disable-Creation: swallow EVERYTHING so neither a tap (photo) nor a
//     press-and-hold (video) can start.
//   - Confirm-Capture: pass the press/expand lifecycle through untouched (so the
//     shutter animates normally), but defer the capture-INITIATING callbacks
//     behind a confirmation. On confirm we run the original; on cancel we do
//     nothing. This gates the release callback, the only viable interception point,
//     since QuickSnap captures-and-sends on release (audience is chosen before the shutter;
//     there is no post-capture review screen).
//
// `isCaptureInitiation` marks the callbacks that actually trigger a photo/video
// send (so we only prompt once, on the meaningful event).
static void SCIQuickSnapHandleCaptureDelegate(id self, SEL _cmd, SCIQuickSnapVoidIMP original, BOOL isCaptureInitiation) {
    if (SCIQuickSnapCreationDisabled()) {
        SCILog(@"General", @"[SCInsta] Blocking Instant capture (%@)", NSStringFromSelector(_cmd));
        if (isCaptureInitiation) SCIQuickSnapNotifyBlocked();
        return;
    }

    if (SCIQuickSnapSendConfirmEnabled() && isCaptureInitiation) {
        if (sSCIQuickSnapSendConfirmVisible) return;
        sSCIQuickSnapSendConfirmVisible = YES;
        // Freeze the live preview on the exact frame the user pressed the shutter
        // on, so confirming sends THAT frame (not a later one) and the preview
        // doesn't keep moving under the alert.
        [SCIInstantsFrameInjector freezeNow];
        id capturedSelf = self;
        SEL capturedSelector = _cmd;
        SCIQuickSnapVoidIMP capturedOriginal = original;
        [SCIUtils showConfirmation:^{
            sSCIQuickSnapSendConfirmVisible = NO;
            // Keep the frozen frame in place through the capture so the sent
            // media is exactly what was confirmed, then resume the live feed.
            if (capturedOriginal) capturedOriginal(capturedSelf, capturedSelector);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [SCIInstantsFrameInjector clearFrozen];
            });
        } cancelHandler:^{
            sSCIQuickSnapSendConfirmVisible = NO;
            [SCIInstantsFrameInjector clearFrozen];
        } title:@"Send Instant?"
          message:@"Capture and send this Instant?"];
        return;
    }

    if (original) original(self, _cmd);
}

static void replaced_captureButtonDidTouchDown(id self, SEL _cmd) {
    SCIQuickSnapHandleCaptureDelegate(self, _cmd, orig_captureButtonDidTouchDown, NO);
}

static void replaced_captureButtonDidBeginExpanding(id self, SEL _cmd) {
    SCIQuickSnapHandleCaptureDelegate(self, _cmd, orig_captureButtonDidBeginExpanding, NO);
}

static void replaced_captureButtonDidEndExpanding(id self, SEL _cmd) {
    SCIQuickSnapHandleCaptureDelegate(self, _cmd, orig_captureButtonDidEndExpanding, NO);
}

static void replaced_captureButtonDidReleaseBeforeExpandingFinished(id self, SEL _cmd) {
    // The primary tap-to-capture (photo) callback.
    SCIQuickSnapHandleCaptureDelegate(self, _cmd, orig_captureButtonDidReleaseBeforeExpandingFinished, YES);
}

static void replaced_captureButtonDidReleaseAfterExpandingFinished(id self, SEL _cmd) {
    // The press-and-hold finish (video) callback.
    SCIQuickSnapHandleCaptureDelegate(self, _cmd, orig_captureButtonDidReleaseAfterExpandingFinished, YES);
}

static void replaced_captureButtonDidReleaseFromInterruption(id self, SEL _cmd) {
    SCIQuickSnapHandleCaptureDelegate(self, _cmd, orig_captureButtonDidReleaseFromInterruption, NO);
}

static void replaced_captureButtonDidConfirm(id self, SEL _cmd) {
    SCIQuickSnapHandleCaptureDelegate(self, _cmd, orig_captureButtonDidConfirm, YES);
}

// MARK: - Hardware Camera Control (iPhone 16/17) — dedicated toggle
//
// The side Camera Control button is routed by the Swift-only
// IGQuickSnapCreationVolumeButtonInteractionController into a system
// AVCaptureEventInteraction whose handler is Swift/AVKit-internal (no ObjC
// selector to hook — verified via a full class-dump). We can't prompt on it, but
// we CAN keep the interaction disabled.
//
// Driven by its own pref (`instants_disable_camera_control`), independent of
// Disable-Creation / Confirm-Capture. Disabling via a single layout-time pass was
// unreliable (IG re-creates/re-enables the interaction after our pass), so we ALSO
// hook AVCaptureEventInteraction -setEnabled: and force it back to NO while the
// QuickSnap camera is on screen and the pref is on. Safe on iOS 15 (class absent).

// Tracks whether the QuickSnap camera UI is currently on screen, so the global
// setEnabled: hook only clamps the interaction in that context (not the main
// Stories/Reels camera).
static BOOL sSCIQuickSnapCameraOnScreen = NO;

static void (*orig_avCaptureEventInteraction_setEnabled)(id, SEL, BOOL) = NULL;
static void replaced_avCaptureEventInteraction_setEnabled(id self, SEL _cmd, BOOL enabled) {
    if (enabled && sSCIQuickSnapCameraOnScreen && SCIQuickSnapDisableCameraControlEnabled()) {
        enabled = NO;
    }
    if (orig_avCaptureEventInteraction_setEnabled) orig_avCaptureEventInteraction_setEnabled(self, _cmd, enabled);
}

static void SCIQuickSnapDisableHardwareCaptureInTree(UIView *root) {
    if (!root) return;
    Class interactionClass = NSClassFromString(@"AVCaptureEventInteraction");
    if (!interactionClass) return;

    BOOL disable = SCIQuickSnapDisableCameraControlEnabled();

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count > 0) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];

        for (id<UIInteraction> interaction in view.interactions) {
            if ([interaction isKindOfClass:interactionClass] &&
                [interaction respondsToSelector:@selector(setEnabled:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(interaction, @selector(setEnabled:), !disable);
            }
        }

        for (UIView *subview in view.subviews) {
            [queue addObject:subview];
        }
    }
}

// MARK: - Darkened shutter (Disable Creation only)

static UIView *SCIQuickSnapFindCaptureButton(UIView *root) {
    if (!root) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count > 0) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(view.class) containsString:@"IGCameraCaptureButton"]) {
            return view;
        }
        for (UIView *subview in view.subviews) {
            [queue addObject:subview];
        }
    }
    return nil;
}



static void SCIQuickSnapApplyLockState(UIView *controlView) {
    UIView *captureButton = SCIQuickSnapFindCaptureButton(controlView);
    if (!captureButton) return;

    if (SCIQuickSnapCreationDisabled()) {
        captureButton.userInteractionEnabled = NO;
        captureButton.alpha = 0.4;
    } else {
        captureButton.userInteractionEnabled = YES;
        captureButton.alpha = 1.0;
    }
}

static void replaced_cameraControlViewLayoutSubviews(id self, SEL _cmd) {
    if (orig_cameraControlViewLayoutSubviews) orig_cameraControlViewLayoutSubviews(self, _cmd);
    if ([self isKindOfClass:[UIView class]]) {
        UIView *controlView = (UIView *)self;
        sSCIQuickSnapVisibleControlView = controlView;
        sSCIQuickSnapCameraOnScreen = (controlView.window != nil);
        SCIQuickSnapApplyLockState(controlView);
        UIView *scope = controlView.window ?: controlView;
        SCIQuickSnapDisableHardwareCaptureInTree(scope);
    }
}

static void (*orig_cameraControlViewWillMoveToWindow)(id, SEL, id) = NULL;
static void replaced_cameraControlViewWillMoveToWindow(id self, SEL _cmd, id window) {
    if (orig_cameraControlViewWillMoveToWindow) orig_cameraControlViewWillMoveToWindow(self, _cmd, window);
    // Track QuickSnap camera presence so the global AVCaptureEventInteraction
    // clamp only applies while the Instants camera is up.
    sSCIQuickSnapCameraOnScreen = (window != nil);
    if (window && [self isKindOfClass:[UIView class]]) {
        UIView *controlView = (UIView *)self;
        sSCIQuickSnapVisibleControlView = controlView;
        SCIQuickSnapApplyLockState(controlView);
        SCIQuickSnapDisableHardwareCaptureInTree(window);
    }
}

// MARK: - Skip camera after viewing

static void SCIDismissQuickSnapCreationController(id controller) {
    if (![controller isKindOfClass:[UIViewController class]]) return;

    UIViewController *viewController = (UIViewController *)controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        UINavigationController *navigationController = viewController.navigationController;
        if (navigationController && navigationController.viewControllers.count > 1) {
            [navigationController popViewControllerAnimated:NO];
        } else {
            [viewController dismissViewControllerAnimated:NO completion:nil];
        }
    });
}

static void SCIMarkQuickSnapExplicitCameraEntry(void) {
    sSCIQuickSnapExplicitCameraEntry = YES;
    sSCIQuickSnapSkipNextCreation = NO;
}

static void replaced_quickSnapPeekViewDidSelectCamera(id self, SEL _cmd, id arg) {
    SCIMarkQuickSnapExplicitCameraEntry();
    if (orig_quickSnapPeekViewDidSelectCamera) orig_quickSnapPeekViewDidSelectCamera(self, _cmd, arg);
}

static void replaced_didTapCameraButtonWithCameraEntryPoint(id self, SEL _cmd, long long point) {
    SCIMarkQuickSnapExplicitCameraEntry();
    if (orig_didTapCameraButtonWithCameraEntryPoint) orig_didTapCameraButtonWithCameraEntryPoint(self, _cmd, point);
}

static void replaced_consumptionViewDidAppear(id self, SEL _cmd, _Bool animated) {
    if (orig_consumptionViewDidAppear) orig_consumptionViewDidAppear(self, _cmd, animated);

    if (SCIQuickSnapSkipCameraAfterViewingEnabled()) {
        sSCIQuickSnapConsumptionWasVisible = YES;
        sSCIQuickSnapSkipNextCreation = YES;
        sSCIQuickSnapExplicitCameraEntry = NO;
    }
}

static void replaced_consumptionViewDidDisappear(id self, SEL _cmd, _Bool animated) {
    if (orig_consumptionViewDidDisappear) orig_consumptionViewDidDisappear(self, _cmd, animated);
    sSCIQuickSnapConsumptionWasVisible = NO;
}

static void replaced_creationViewWillAppear(id self, SEL _cmd, _Bool animated) {
    BOOL shouldSkip = SCIQuickSnapSkipCameraAfterViewingEnabled() &&
                      sSCIQuickSnapSkipNextCreation &&
                      !sSCIQuickSnapExplicitCameraEntry;

    sSCIQuickSnapSkipNextCreation = NO;

    if (shouldSkip) {
        SCILog(@"General", @"[SCInsta] Skipping Instant camera after viewing");
        SCIDismissQuickSnapCreationController(self);
        return;
    }

    if (orig_creationViewWillAppear) orig_creationViewWillAppear(self, _cmd, animated);
}

// MARK: - Install

static void SCIHookInstanceMethod(const char *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    if (!cls || !class_getInstanceMethod(cls, selector)) return;

    MSHookMessageEx(cls, selector, replacement, original);
}

void SCIInstallDisableInstantsCreationHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *cameraControlView = "_TtC34IGQuickSnapCameraControlController28IGQuickSnapCameraControlView";

        // Install the whole surface unconditionally — each handler decides what to
        // do per-mode at call time by reading the live pref. This lets the toggles
        // take effect without an app restart. The hooks only ever fire while the
        // QuickSnap (Instants) camera is on screen, so they're free otherwise.
        SCIHookInstanceMethod(cameraControlView, @selector(captureButtonDidTouchDown),
                              (IMP)replaced_captureButtonDidTouchDown,
                              (IMP *)&orig_captureButtonDidTouchDown);
        SCIHookInstanceMethod(cameraControlView, @selector(captureButtonDidBeginExpanding),
                              (IMP)replaced_captureButtonDidBeginExpanding,
                              (IMP *)&orig_captureButtonDidBeginExpanding);
        SCIHookInstanceMethod(cameraControlView, @selector(captureButtonDidEndExpanding),
                              (IMP)replaced_captureButtonDidEndExpanding,
                              (IMP *)&orig_captureButtonDidEndExpanding);
        SCIHookInstanceMethod(cameraControlView, @selector(captureButtonDidReleaseBeforeExpandingFinished),
                              (IMP)replaced_captureButtonDidReleaseBeforeExpandingFinished,
                              (IMP *)&orig_captureButtonDidReleaseBeforeExpandingFinished);
        SCIHookInstanceMethod(cameraControlView, @selector(captureButtonDidReleaseAfterExpandingFinished),
                              (IMP)replaced_captureButtonDidReleaseAfterExpandingFinished,
                              (IMP *)&orig_captureButtonDidReleaseAfterExpandingFinished);
        SCIHookInstanceMethod(cameraControlView, @selector(captureButtonDidReleaseFromInterruption),
                              (IMP)replaced_captureButtonDidReleaseFromInterruption,
                              (IMP *)&orig_captureButtonDidReleaseFromInterruption);
        SCIHookInstanceMethod(cameraControlView, @selector(captureButtonDidConfirm),
                              (IMP)replaced_captureButtonDidConfirm,
                              (IMP *)&orig_captureButtonDidConfirm);

        // Darken + hardware-disable are driven from the control view layout;
        // SCIQuickSnapApplyLockState no-ops when creation isn't disabled.
        SCIHookInstanceMethod(cameraControlView, @selector(layoutSubviews),
                              (IMP)replaced_cameraControlViewLayoutSubviews,
                              (IMP *)&orig_cameraControlViewLayoutSubviews);
        SCIHookInstanceMethod(cameraControlView, @selector(willMoveToWindow:),
                              (IMP)replaced_cameraControlViewWillMoveToWindow,
                              (IMP *)&orig_cameraControlViewWillMoveToWindow);

        // Robustly keep the hardware Camera Control's AVCaptureEventInteraction
        // disabled while the QuickSnap camera is up and the pref is on — IG may
        // re-enable it after our layout-time pass, so we clamp its setEnabled:.
        Class captureEventInteraction = NSClassFromString(@"AVCaptureEventInteraction");
        if (captureEventInteraction && class_getInstanceMethod(captureEventInteraction, @selector(setEnabled:))) {
            MSHookMessageEx(captureEventInteraction, @selector(setEnabled:),
                            (IMP)replaced_avCaptureEventInteraction_setEnabled,
                            (IMP *)&orig_avCaptureEventInteraction_setEnabled);
        }

        // Live refresh: when the creation pref toggles, re-apply the darken
        // state to the on-screen camera so it updates without leaving Instants.
        [[NSNotificationCenter defaultCenter] addObserverForName:kSCIQuickSnapCreationPrefChangedNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *note) {
            UIView *controlView = sSCIQuickSnapVisibleControlView;
            if (!controlView.window) return;
            SCIQuickSnapApplyLockState(controlView);
            UIView *scope = controlView.window ?: controlView;
            SCIQuickSnapDisableHardwareCaptureInTree(scope);
            [controlView setNeedsLayout];
        }];

        // Explicit camera entry points (clear the skip flag).
        SCIHookInstanceMethod("_TtC30IGQuickSnapPresentationManager30IGQuickSnapPresentationManager",
                              @selector(quickSnapPeekViewDidSelectCamera:),
                              (IMP)replaced_quickSnapPeekViewDidSelectCamera,
                              (IMP *)&orig_quickSnapPeekViewDidSelectCamera);
        SCIHookInstanceMethod("_TtC44IGQuickSnapImmersiveViewerSectionControllers45IGQuickSnapStandaloneHistorySectionController",
                              @selector(didTapCameraButtonWithCameraEntryPoint:),
                              (IMP)replaced_didTapCameraButtonWithCameraEntryPoint,
                              (IMP *)&orig_didTapCameraButtonWithCameraEntryPoint);

        // Viewing (consumption) lifecycle — arm/disarm the skip flag.
        SCIHookInstanceMethod("_TtC26IGQuickSnapConsumptionCore36IGQuickSnapConsumptionViewController",
                              @selector(viewDidAppear:),
                              (IMP)replaced_consumptionViewDidAppear,
                              (IMP *)&orig_consumptionViewDidAppear);
        SCIHookInstanceMethod("_TtC26IGQuickSnapConsumptionCore36IGQuickSnapConsumptionViewController",
                              @selector(viewDidDisappear:),
                              (IMP)replaced_consumptionViewDidDisappear,
                              (IMP *)&orig_consumptionViewDidDisappear);

        // Creation camera appearance — consume the skip flag.
        SCIHookInstanceMethod("_TtC23IGQuickSnapCreationCore33IGQuickSnapCreationViewController",
                              @selector(viewWillAppear:),
                              (IMP)replaced_creationViewWillAppear,
                              (IMP *)&orig_creationViewWillAppear);
    });
}

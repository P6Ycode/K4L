#import <substrate.h>
#import <objc/runtime.h>

#import "../../Utils.h"

static NSString * const kSCIQuickSnapDisableCreationPref = @"msgs_disable_instants_creation";
static NSString * const kSCIQuickSnapConfirmCapturePref = @"msgs_confirm_instants_capture";
static NSString * const kSCIQuickSnapSkipCameraAfterViewingPref = @"msgs_skip_instants_camera_after_viewing";

typedef void (*SCIQuickSnapVoidIMP)(id, SEL);
typedef void (*SCIQuickSnapVoidOneArgIMP)(id, SEL, id);
typedef void (*SCIQuickSnapVoidLongLongIMP)(id, SEL, long long);
typedef void (*SCIQuickSnapViewAppearIMP)(id, SEL, _Bool);

static SCIQuickSnapVoidIMP orig_captureButtonDidConfirm = NULL;
static SCIQuickSnapVoidIMP orig_captureButtonDidReleaseBeforeExpandingFinished = NULL;
static SCIQuickSnapVoidIMP orig_captureButtonDidReleaseAfterExpandingFinished = NULL;
static SCIQuickSnapVoidOneArgIMP orig_quickSnapPeekViewDidSelectCamera = NULL;
static SCIQuickSnapVoidLongLongIMP orig_didTapCameraButtonWithCameraEntryPoint = NULL;
static SCIQuickSnapViewAppearIMP orig_consumptionViewDidAppear = NULL;
static SCIQuickSnapViewAppearIMP orig_creationViewWillAppear = NULL;

static CFAbsoluteTime sSCIQuickSnapLastConsumptionAppearTime = 0;
static CFAbsoluteTime sSCIQuickSnapLastExplicitCameraEntryTime = 0;
static BOOL sSCIQuickSnapCaptureConfirmVisible = NO;

static BOOL SCIQuickSnapCreationDisabled(void) {
    return [SCIUtils getBoolPref:kSCIQuickSnapDisableCreationPref];
}

static BOOL SCIQuickSnapCaptureConfirmEnabled(void) {
    return [SCIUtils getBoolPref:kSCIQuickSnapConfirmCapturePref];
}

static BOOL SCIQuickSnapSkipCameraAfterViewingEnabled(void) {
    return [SCIUtils getBoolPref:kSCIQuickSnapSkipCameraAfterViewingPref];
}

static BOOL SCIQuickSnapHooksWanted(void) {
    return SCIQuickSnapCreationDisabled() || SCIQuickSnapCaptureConfirmEnabled() || SCIQuickSnapSkipCameraAfterViewingEnabled();
}

static void SCIMarkQuickSnapExplicitCameraEntry(void) {
    sSCIQuickSnapLastExplicitCameraEntryTime = CFAbsoluteTimeGetCurrent();
}

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

static BOOL SCIShouldSkipQuickSnapCreationAfterViewing(void) {
    if (!SCIQuickSnapSkipCameraAfterViewingEnabled()) return NO;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (sSCIQuickSnapLastConsumptionAppearTime <= 0) return NO;

    BOOL recentlyViewedInstant = (now - sSCIQuickSnapLastConsumptionAppearTime) <= 3.0;
    BOOL explicitCameraEntry = sSCIQuickSnapLastExplicitCameraEntryTime > 0 &&
                               sSCIQuickSnapLastExplicitCameraEntryTime >= sSCIQuickSnapLastConsumptionAppearTime &&
                               (now - sSCIQuickSnapLastExplicitCameraEntryTime) <= 3.0;

    return recentlyViewedInstant && !explicitCameraEntry;
}

static void SCIHandleQuickSnapCapture(id self, SEL _cmd, SCIQuickSnapVoidIMP original) {
    if (SCIQuickSnapCreationDisabled()) {
        SCILog(@"General", @"[SCInsta] Blocking Instant capture");
        return;
    }

    if (!SCIQuickSnapCaptureConfirmEnabled()) {
        if (original) original(self, _cmd);
        return;
    }

    if (sSCIQuickSnapCaptureConfirmVisible) return;

    sSCIQuickSnapCaptureConfirmVisible = YES;
    id capturedSelf = self;
    SEL capturedSelector = _cmd;
    [SCIUtils showConfirmation:^{
        sSCIQuickSnapCaptureConfirmVisible = NO;
        if (original) original(capturedSelf, capturedSelector);
    } cancelHandler:^{
        sSCIQuickSnapCaptureConfirmVisible = NO;
    } title:@"Confirm Instant Capture"
      message:@"Capture and send this Instant?"];
}

static void replaced_captureButtonDidConfirm(id self, SEL _cmd) {
    SCIHandleQuickSnapCapture(self, _cmd, orig_captureButtonDidConfirm);
}

static void replaced_captureButtonDidReleaseBeforeExpandingFinished(id self, SEL _cmd) {
    SCIHandleQuickSnapCapture(self, _cmd, orig_captureButtonDidReleaseBeforeExpandingFinished);
}

static void replaced_captureButtonDidReleaseAfterExpandingFinished(id self, SEL _cmd) {
    SCIHandleQuickSnapCapture(self, _cmd, orig_captureButtonDidReleaseAfterExpandingFinished);
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
        sSCIQuickSnapLastConsumptionAppearTime = CFAbsoluteTimeGetCurrent();
    }
}

static void replaced_creationViewWillAppear(id self, SEL _cmd, _Bool animated) {
    if (orig_creationViewWillAppear) orig_creationViewWillAppear(self, _cmd, animated);

    if (SCIShouldSkipQuickSnapCreationAfterViewing()) {
        SCILog(@"General", @"[SCInsta] Skipping Instant camera after viewing");
        SCIDismissQuickSnapCreationController(self);
    }
}

static void SCIHookInstanceMethod(const char *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    if (!cls || !class_getInstanceMethod(cls, selector)) return;

    MSHookMessageEx(cls, selector, replacement, original);
}

void SCIInstallDisableInstantsCreationHooksIfEnabled(void) {
    if (!SCIQuickSnapHooksWanted()) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCIHookInstanceMethod("_TtC34IGQuickSnapCameraControlController28IGQuickSnapCameraControlView",
                              @selector(captureButtonDidConfirm),
                              (IMP)replaced_captureButtonDidConfirm,
                              (IMP *)&orig_captureButtonDidConfirm);
        SCIHookInstanceMethod("_TtC34IGQuickSnapCameraControlController28IGQuickSnapCameraControlView",
                              @selector(captureButtonDidReleaseBeforeExpandingFinished),
                              (IMP)replaced_captureButtonDidReleaseBeforeExpandingFinished,
                              (IMP *)&orig_captureButtonDidReleaseBeforeExpandingFinished);
        SCIHookInstanceMethod("_TtC34IGQuickSnapCameraControlController28IGQuickSnapCameraControlView",
                              @selector(captureButtonDidReleaseAfterExpandingFinished),
                              (IMP)replaced_captureButtonDidReleaseAfterExpandingFinished,
                              (IMP *)&orig_captureButtonDidReleaseAfterExpandingFinished);
        SCIHookInstanceMethod("_TtC30IGQuickSnapPresentationManager30IGQuickSnapPresentationManager",
                              @selector(quickSnapPeekViewDidSelectCamera:),
                              (IMP)replaced_quickSnapPeekViewDidSelectCamera,
                              (IMP *)&orig_quickSnapPeekViewDidSelectCamera);
        SCIHookInstanceMethod("_TtC44IGQuickSnapImmersiveViewerSectionControllers45IGQuickSnapStandaloneHistorySectionController",
                              @selector(didTapCameraButtonWithCameraEntryPoint:),
                              (IMP)replaced_didTapCameraButtonWithCameraEntryPoint,
                              (IMP *)&orig_didTapCameraButtonWithCameraEntryPoint);
        SCIHookInstanceMethod("_TtC26IGQuickSnapConsumptionCore36IGQuickSnapConsumptionViewController",
                              @selector(viewDidAppear:),
                              (IMP)replaced_consumptionViewDidAppear,
                              (IMP *)&orig_consumptionViewDidAppear);
        SCIHookInstanceMethod("_TtC23IGQuickSnapCreationCore33IGQuickSnapCreationViewController",
                              @selector(viewWillAppear:),
                              (IMP)replaced_creationViewWillAppear,
                              (IMP *)&orig_creationViewWillAppear);
    });
}

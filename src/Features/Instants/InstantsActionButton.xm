#import <substrate.h>
#import <objc/runtime.h>
#import "../../Utils.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "InstantsResolver.h"

static NSInteger const kSCIInstantsActionButtonTag = 921399;

// MARK: - Anchor Helpers

static UIView *SCIInstantsHeaderOwnedView(UIView *header, NSString *key) {
    if (!header || key.length == 0) return nil;
    id view = nil;
    @try { view = [header valueForKey:key]; } @catch (__unused NSException *e) {}
    if (![view isKindOfClass:UIView.class]) {
        Ivar ivar = class_getInstanceVariable(header.class, key.UTF8String);
        if (ivar) @try { view = object_getIvar(header, ivar); } @catch (__unused NSException *e) {}
    }
    return [view isKindOfClass:UIView.class] ? (UIView *)view : nil;
}

static UIView *SCIInstantsHeaderArchiveButton(UIView *header) {
    UIView *btn = SCIInstantsHeaderOwnedView(header, @"archiveButton");
    if (btn && btn.superview == header && !btn.hidden && btn.alpha >= 0.01) return btn;
    return nil;
}

static UIView *SCIInstantsFallbackRightAnchor(UIView *header, UIView *button) {
    CGFloat halfWidth = header.bounds.size.width / 2.0;
    UIView *anchor = nil;
    CGFloat minX = CGFLOAT_MAX;
    for (UIView *sub in header.subviews) {
        if (sub == button || sub.hidden || sub.alpha < 0.01) continue;
        if (sub.bounds.size.width < 4.0 || sub.bounds.size.height < 4.0) continue;
        if (CGRectGetMidX(sub.frame) < halfWidth) continue;
        if (CGRectGetMinX(sub.frame) < minX) { anchor = sub; minX = CGRectGetMinX(sub.frame); }
    }
    return anchor;
}

// MARK: - Header Visibility

static BOOL SCIInstantsHeaderIsVisible(UIView *header) {
    if (!header || header.hidden || header.alpha < 0.01 || !header.window) return NO;
    if (header.bounds.size.width < 10.0 || header.bounds.size.height < 10.0) return NO;
    return CGRectIntersectsRect([header convertRect:header.bounds toView:header.window], header.window.bounds);
}

/// YES when a snap is actually being consumed (viewed). The action button belongs only
/// on the consumption header, not on the creation/camera header (which hosts the gallery
/// upload button at the same anchor). Detected by the presence of a visible
/// IGQuickSnapImmersiveViewerSingleSnapView in the same window.
static BOOL SCIInstantsHeaderIsConsumption(UIView *header) {
    UIWindow *window = header.window;
    if (!window) return NO;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    NSUInteger idx = 0;
    while (idx < queue.count) {
        UIView *view = queue[idx++];
        if (!view.hidden && view.alpha >= 0.01 && view.window) {
            if ([NSStringFromClass(view.class) containsString:@"IGQuickSnapImmersiveViewerSingleSnapView"]) {
                return YES;
            }
        }
        for (UIView *sub in view.subviews) [queue addObject:sub];
    }
    return NO;
}

// MARK: - Action Context

static SCIActionButtonContext *SCIInstantsActionContext(UIView *header, UIButton *button) {
    SCIActionButtonContext *context = [[SCIActionButtonContext alloc] init];
    context.source = SCIActionButtonSourceInstants;
    context.view = button ?: header;
    context.controller = [SCIUtils viewControllerForAncestralView:header] ?: topMostController();
    context.settingsTitle = SCIActionButtonTopicTitleForSource(SCIActionButtonSourceInstants);
    context.supportedActions = SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceInstants);
    __weak UIView *weakHeader = header;
    __block SCIInstantsResolverResult *resolvedResult = nil;
    __block BOOL clearScheduled = NO;
    void (^scheduleClear)(void) = ^{
        if (clearScheduled) return;
        clearScheduled = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ resolvedResult = nil; clearScheduled = NO; });
    };
    SCIInstantsResolverResult *(^resolve)(NSString *) = ^SCIInstantsResolverResult *(NSString *reason) {
        if (!resolvedResult) { resolvedResult = SCIInstantsResolveForHeader(weakHeader, reason); scheduleClear(); }
        return resolvedResult;
    };
    context.mediaResolver = ^id (__unused SCIActionButtonContext *ctx) {
        SCIInstantsResolverResult *r = resolve(@"media");
        if (!r) return nil;
        // Prefer the directly-resolved active snap (always the on-screen item).
        if (r.activeSnap) return r.activeSnap;
        if (r.snaps.count == 0) return nil;
        NSInteger idx = r.activeIndex;
        return (idx >= 0 && idx < (NSInteger)r.snaps.count) ? r.snaps[idx] : nil;
    };
    context.bulkMediaResolver = ^id (__unused SCIActionButtonContext *ctx) {
        return resolve(@"bulk").snaps ?: @[];
    };
    context.currentIndexResolver = ^NSInteger (__unused SCIActionButtonContext *ctx) {
        SCIInstantsResolverResult *r = resolve(@"index");
        return r ? r.activeIndex : 0;
    };
    return context;
}

// MARK: - Button Placement

/// Frame match used only for deciding whether to reposition. Does NOT consider
/// hidden/alpha — during the iOS 26 menu morph UIKit hides the real button and animates
/// a snapshot, and we must not treat that transient state as "needs replacing".
static BOOL SCIInstantsActionFrameMatches(UIButton *button, CGRect frame) {
    if (![button isKindOfClass:[UIButton class]] || !button.superview) return NO;
    return ABS(CGRectGetMinX(button.frame) - CGRectGetMinX(frame)) < 0.5 &&
           ABS(CGRectGetMinY(button.frame) - CGRectGetMinY(frame)) < 0.5 &&
           ABS(CGRectGetWidth(button.frame) - CGRectGetWidth(frame)) < 0.5 &&
           ABS(CGRectGetHeight(button.frame) - CGRectGetHeight(frame)) < 0.5;
}

static CGRect SCIInstantsButtonFrame(UIView *header, UIButton *button) {
    CGFloat side = 44.0;
    UIView *anchor = SCIInstantsHeaderArchiveButton(header) ?: SCIInstantsFallbackRightAnchor(header, button);
    if (anchor) {
        return CGRectMake(CGRectGetMinX(anchor.frame) - side,
                          CGRectGetMidY(anchor.frame) - side / 2.0, side, side);
    }
    return CGRectMake(header.bounds.size.width - side - 12.0,
                      (header.bounds.size.height - side) / 2.0, side, side);
}

static void SCIInstantsPlaceButton(UIView *header) {
    if (!header) return;

    UIButton *existing = (UIButton *)[header viewWithTag:kSCIInstantsActionButtonTag];

    // CRITICAL (iOS 26 menu morph): if the button already exists, has a menu, is in the
    // header, and is correctly positioned, return immediately and touch NOTHING. During the
    // menu open/close animation UIKit temporarily hides the real button and animates a
    // snapshot; any frame/hidden/alpha write here fights that animation and makes the button
    // flash or disappear. Every other action button (Feed/Profile/Stories/Reels/Audio) uses
    // this same early-return. We must NOT gate this on button.hidden/alpha — those belong to
    // the animation, not us.
    if (existing && existing.menu != nil && existing.superview == header) {
        CGRect expectedFrame = SCIInstantsButtonFrame(header, existing);
        if (SCIInstantsActionFrameMatches(existing, expectedFrame)) {
            return; // Placed and configured — leave it entirely alone.
        }
    }

    if (![SCIUtils getBoolPref:@"instants_action_btn"]) {
        [existing removeFromSuperview]; return;
    }
    if (!SCIInstantsHeaderIsVisible(header)) {
        [existing removeFromSuperview]; return;
    }

    // The action button should appear whenever we're in the consumption viewer.
    // Even if the service cache is empty (all snaps "seen"), the view fallback in
    // the resolver will extract media from the live stack view.
    // Only skip if we're not actually consuming (e.g. creation/camera header).
    if (!SCIInstantsHeaderIsConsumption(header)) {
        [existing removeFromSuperview]; return;
    }

    UIButton *button = existing;
    BOOL isNew = (button == nil);
    if (isNew) {
        button = SCIActionButtonWithTag(header, kSCIInstantsActionButtonTag);
        button.translatesAutoresizingMaskIntoConstraints = YES;
        [header addSubview:button];
        SCIApplyButtonStyle(button, SCIActionButtonSourceInstants);
    }

    // Configure the menu only once per button lifecycle (when created or when the menu is
    // still nil from a prior failed resolve). Do NOT reconfigure on count changes.
    if (button.menu == nil) {
        SCIConfigureActionButton(button, SCIInstantsActionContext(header, button));

        // If configure resulted in no menu (resolver returned nil because the stack view
        // isn't populated yet), schedule a single retry after a short delay.
        if (!button.menu) {
            __weak UIView *weakHeader = header;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIView *strongHeader = weakHeader;
                if (!strongHeader || !strongHeader.window) return;
                UIButton *retryButton = (UIButton *)[strongHeader viewWithTag:kSCIInstantsActionButtonTag];
                if (retryButton && !retryButton.menu) {
                    SCIConfigureActionButton(retryButton, SCIInstantsActionContext(strongHeader, retryButton));
                    retryButton.hidden = NO;
                    retryButton.alpha = 1.0;
                }
            });
        }
    }

    CGRect expectedFrame = SCIInstantsButtonFrame(header, button);
    if (!SCIInstantsActionFrameMatches(button, expectedFrame)) button.frame = expectedFrame;
    button.hidden = NO;
    button.alpha = 1.0;
    [header bringSubviewToFront:button];
}

// MARK: - Hook

typedef void (*SCIInstantsHeaderLayoutIMP)(id, SEL);
static SCIInstantsHeaderLayoutIMP orig_instantsHeaderLayoutSubviews = NULL;

static void replaced_instantsHeaderLayoutSubviews(id self, SEL _cmd) {
    if (orig_instantsHeaderLayoutSubviews) orig_instantsHeaderLayoutSubviews(self, _cmd);
    SCIInstantsPlaceButton((UIView *)self);
}

static void SCIHookInstanceMethod(const char *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!cls || !method) {
        SCILog(@"Instants", @"[SCInsta] Missing hook target %s %@", className, NSStringFromSelector(selector));
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

// MARK: - Retry & Installation

static BOOL sSCIInstantsActionButtonHooksInstalled = NO;
static BOOL sSCIInstantsActionButtonRetryScheduled = NO;

static void SCIInstallInstantsActionButtonHooksAttempt(NSUInteger attempt) {
    if (sSCIInstantsActionButtonHooksInstalled) return;

    Class headerClass = objc_getClass("_TtC45IGQuickSnapNavigationV3HeaderButtonController39IGQuickSnapNavigationV3HeaderButtonView");
    if (!headerClass) {
        if (attempt == 0 || attempt == 5 || attempt == 15 || attempt == 30) {
            SCILog(@"Instants", @"QuickSnap header class missing; retry attempt=%lu", (unsigned long)attempt);
        }
        if (attempt >= 60) {
            SCILog(@"Instants", @"QuickSnap header class still missing after retries; Instants action button inactive");
            return;
        }
        if (!sSCIInstantsActionButtonRetryScheduled) {
            sSCIInstantsActionButtonRetryScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                sSCIInstantsActionButtonRetryScheduled = NO;
                SCIInstallInstantsActionButtonHooksAttempt(attempt + 1);
            });
        }
        return;
    }

    SCIHookInstanceMethod("_TtC45IGQuickSnapNavigationV3HeaderButtonController39IGQuickSnapNavigationV3HeaderButtonView",
                          @selector(layoutSubviews),
                          (IMP)replaced_instantsHeaderLayoutSubviews,
                          (IMP *)&orig_instantsHeaderLayoutSubviews);
    SCIInstallInstantsResolverHooks();
    sSCIInstantsActionButtonHooksInstalled = YES;
    SCILog(@"Instants", @"[SCInsta] Instants action button hooks installed");
}

extern "C" void SCIInstallInstantsActionButtonHooksIfEnabled(void) {
    SCIInstallInstantsActionButtonHooksAttempt(0);
}

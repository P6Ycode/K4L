#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// ---------------------------------------------------------------------------
// Disable feed autoplay — hooks installed at dylib load (%ctor) so they're
// in place before any IGFeedPlaybackStrategy objects are created.
//
// Each init swizzle checks the pref at runtime, so toggling the switch takes
// effect immediately without a restart.
// ---------------------------------------------------------------------------

static id (*orig_feedAutoplayInit1)(id, SEL, BOOL);
static id spk_feedAutoplayInit1(id self, SEL _cmd, BOOL shouldDisable) {
    if ([SPKUtils getBoolPref:@"feed_disable_autoplay"]) shouldDisable = YES;
    return orig_feedAutoplayInit1(self, _cmd, shouldDisable);
}

static id (*orig_feedAutoplayInit2)(id, SEL, BOOL, BOOL);
static id spk_feedAutoplayInit2(id self, SEL _cmd, BOOL shouldDisable, BOOL shouldClearStale) {
    if ([SPKUtils getBoolPref:@"feed_disable_autoplay"]) shouldDisable = YES;
    return orig_feedAutoplayInit2(self, _cmd, shouldDisable, shouldClearStale);
}

static id (*orig_feedAutoplayInit3)(id, SEL, BOOL, BOOL, BOOL);
static id spk_feedAutoplayInit3(id self, SEL _cmd, BOOL shouldDisable, BOOL shouldClearStale, BOOL bypassForVoiceover) {
    if ([SPKUtils getBoolPref:@"feed_disable_autoplay"]) shouldDisable = YES;
    return orig_feedAutoplayInit3(self, _cmd, shouldDisable, shouldClearStale, bypassForVoiceover);
}

static id (*orig_feedAutoplayInit5)(id, SEL, BOOL, BOOL, BOOL, BOOL, id);
static id spk_feedAutoplayInit5(id self, SEL _cmd, BOOL shouldDisable, BOOL shouldClearStale, BOOL bypassForVoiceover, BOOL overrideThresholds, id launcherSet) {
    if ([SPKUtils getBoolPref:@"feed_disable_autoplay"]) shouldDisable = YES;
    return orig_feedAutoplayInit5(self, _cmd, shouldDisable, shouldClearStale, bypassForVoiceover, overrideThresholds, launcherSet);
}

// Carousel tap-to-play: the modern feed video cell receives single-taps via
// this delegate callback, but the Swift implementation skips resume when the
// cell sits inside a carousel. Force retryStartPlayback after orig.
static void (*orig_feedVideoCellSingleTap)(id, SEL, id, id);
static void spk_feedVideoCellSingleTap(id self, SEL _cmd, id overlay, id recognizer) {
    if (orig_feedVideoCellSingleTap) orig_feedVideoCellSingleTap(self, _cmd, overlay, recognizer);
    if (![SPKUtils getBoolPref:@"feed_disable_autoplay"]) return;
    UIView *superview = [(UIView *)self superview];
    if (!superview || !strstr(class_getName([superview class]), "Carousel")) return;
    SEL retrySelector = NSSelectorFromString(@"retryStartPlayback");
    if ([self respondsToSelector:retrySelector]) {
        ((void (*)(id, SEL))objc_msgSend)(self, retrySelector);
    }
}

static void SPKHookFeedPlaybackStrategy(void) {
    Class cls = objc_getClass("IGFeedPlayback.IGFeedPlaybackStrategy");
    if (!cls) cls = objc_getClass("_TtC14IGFeedPlayback22IGFeedPlaybackStrategy");
    if (!cls) return;

    SEL s1 = @selector(initWithShouldDisableAutoplay:);
    if (class_getInstanceMethod(cls, s1)) {
        MSHookMessageEx(cls, s1, (IMP)spk_feedAutoplayInit1, (IMP *)&orig_feedAutoplayInit1);
    }
    SEL s2 = @selector(initWithShouldDisableAutoplay:shouldClearStaleReservation:);
    if (class_getInstanceMethod(cls, s2)) {
        MSHookMessageEx(cls, s2, (IMP)spk_feedAutoplayInit2, (IMP *)&orig_feedAutoplayInit2);
    }
    SEL s3 = @selector(initWithShouldDisableAutoplay:shouldClearStaleReservation:shouldBypassDisabledAutoplayForVoiceover:);
    if (class_getInstanceMethod(cls, s3)) {
        MSHookMessageEx(cls, s3, (IMP)spk_feedAutoplayInit3, (IMP *)&orig_feedAutoplayInit3);
    }
    SEL s5 = @selector(initWithShouldDisableAutoplay:shouldClearStaleReservation:shouldBypassDisabledAutoplayForVoiceover:shouldOverrideDefaultThresholds:launcherSet:);
    if (class_getInstanceMethod(cls, s5)) {
        MSHookMessageEx(cls, s5, (IMP)spk_feedAutoplayInit5, (IMP *)&orig_feedAutoplayInit5);
    }
}

static void SPKHookFeedVideoCell(void) {
    static BOOL hooked = NO;
    if (hooked) return;
    Class cls = objc_getClass("IGModernFeedVideoCell.IGModernFeedVideoCell");
    if (!cls) cls = objc_getClass("IGModernFeedVideoCell");
    if (!cls) return;
    SEL selector = @selector(videoPlayerOverlayControllerDidSingleTap:gestureRecognizer:);
    if (class_getInstanceMethod(cls, selector)) {
        MSHookMessageEx(cls, selector, (IMP)spk_feedVideoCellSingleTap, (IMP *)&orig_feedVideoCellSingleTap);
        hooked = YES;
    }
}

// Install hooks at dylib load time — this is the critical fix. The old
// approach waited for IGTabBarController which was too late; the staged
// hook system (0.35s after didFinishLaunching) was also too late. %ctor
// runs at dylib load, before any IG classes are instantiated.
%ctor {
    SPKHookFeedPlaybackStrategy();
    SPKHookFeedVideoCell();
    // Swift cell class can load after dylib init; retry on main runloop.
    dispatch_async(dispatch_get_main_queue(), ^{ SPKHookFeedVideoCell(); });
}

// Kept for backward compat with SPKStartupHooks.m — now a no-op since
// hooks are already installed by %ctor above.
void SPKInstallDisableFeedAutoplayHooksIfEnabled(void) {
    // Intentionally empty — hooks installed in %ctor.
}

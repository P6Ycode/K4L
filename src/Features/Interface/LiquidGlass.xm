#import <substrate.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "../../Settings/SCIPreferences.h"
#include "../../../modules/SCISideloadFix/fishhook/fishhook.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef BOOL (*SCI_BOOL_MSG)(id self, SEL _cmd);
typedef void (*SCI_VOID_MSG)(id self, SEL _cmd);
typedef void (*SCI_SET_CGFLOAT_MSG)(id self, SEL _cmd, CGFloat value);

static BOOL SCIIsLiquidGlassEnabled(void) {
    return [SCIUtils sci_isLiquidGlassEffectivelyEnabled];
}

// MARK: - UIScrollEdgeEffect declaration
@interface UIScrollEdgeEffect : NSObject
+ (void)hide;
- (BOOL)ig_isHidden;
- (void)ig_setIsHidden:(BOOL)hidden;
@end

// MARK: - Native button experiment

static SCI_BOOL_MSG orig_swizzleToggle_isEnabled;
static BOOL hook_swizzleToggle_isEnabled(id self, SEL _cmd) {
    return SCIIsLiquidGlassEnabled() ? YES : (orig_swizzleToggle_isEnabled ? orig_swizzleToggle_isEnabled(self, _cmd) : NO);
}

static SCI_BOOL_MSG orig_navigationExperiment_isEnabled;
static BOOL hook_navigationExperiment_isEnabled(id self, SEL _cmd) {
    return SCIIsLiquidGlassEnabled() ? YES : (orig_navigationExperiment_isEnabled ? orig_navigationExperiment_isEnabled(self, _cmd) : NO);
}

static SCI_BOOL_MSG orig_navigationExperiment_isHomeFeedHeaderEnabled;
static BOOL hook_navigationExperiment_isHomeFeedHeaderEnabled(id self, SEL _cmd) {
    return SCIIsLiquidGlassEnabled() ? YES : (orig_navigationExperiment_isHomeFeedHeaderEnabled ? orig_navigationExperiment_isHomeFeedHeaderEnabled(self, _cmd) : NO);
}

// MARK: - Native surface feature symbols

static BOOL (*orig_IGFloatingTabBarEnabled)(void);
static BOOL (*orig_IGTabBarDynamicSizingEnabled)(void);
static BOOL (*orig_IGTabBarEnhancedDynamicSizingEnabled)(void);
static BOOL (*orig_IGTabBarHomecomingWithFloatingTabEnabled)(void);
static BOOL (*orig_IGTabBarViewPointFixEnabled)(void);
static NSInteger (*orig_IGTabBarStyleForLauncherSet)(NSInteger launcherSet);

#define SCI_LIQUID_GLASS_BOOL_FISHHOOK(name) \
    static BOOL hook_##name(void) { \
        return SCIIsLiquidGlassEnabled() ? YES : (orig_##name ? orig_##name() : NO); \
    }

SCI_LIQUID_GLASS_BOOL_FISHHOOK(IGFloatingTabBarEnabled)
SCI_LIQUID_GLASS_BOOL_FISHHOOK(IGTabBarDynamicSizingEnabled)
SCI_LIQUID_GLASS_BOOL_FISHHOOK(IGTabBarEnhancedDynamicSizingEnabled)
SCI_LIQUID_GLASS_BOOL_FISHHOOK(IGTabBarHomecomingWithFloatingTabEnabled)
SCI_LIQUID_GLASS_BOOL_FISHHOOK(IGTabBarViewPointFixEnabled)

static NSInteger hook_IGTabBarStyleForLauncherSet(NSInteger launcherSet) {
    return SCIIsLiquidGlassEnabled() ? 1 : (orig_IGTabBarStyleForLauncherSet ? orig_IGTabBarStyleForLauncherSet(launcherSet) : launcherSet);
}

// MARK: - Tab bar scroll state

typedef NS_ENUM(NSInteger, SCILiquidGlassTabBarMode) {
    SCILiquidGlassTabBarModeDefault = 0,
    SCILiquidGlassTabBarModeFixed,
    SCILiquidGlassTabBarModeHide,
};

static SCILiquidGlassTabBarMode SCICurrentLiquidGlassTabBarMode(void) {
    NSString *mode = [SCIUtils getStringPref:kSCIPrefInterfaceLiquidGlassTabBarMode];
    if ([mode isEqualToString:@"fixed"]) return SCILiquidGlassTabBarModeFixed;
    if ([mode isEqualToString:@"hide"]) return SCILiquidGlassTabBarModeHide;
    return SCILiquidGlassTabBarModeDefault;
}

static const void *kSCILiquidGlassTabBarHiddenKey = &kSCILiquidGlassTabBarHiddenKey;

static void SCIApplyLiquidGlassTabBarHiddenState(UIView *bar, BOOL hidden) {
    NSNumber *current = objc_getAssociatedObject(bar, kSCILiquidGlassTabBarHiddenKey);
    if (current && current.boolValue == hidden) return;
    objc_setAssociatedObject(bar, kSCILiquidGlassTabBarHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGFloat dropY = CGRectGetHeight(bar.bounds) + 40.0;
    [UIView animateWithDuration:0.28
                          delay:0.0
         usingSpringWithDamping:0.9
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        bar.transform = hidden ? CGAffineTransformMakeTranslation(0.0, dropY) : CGAffineTransformIdentity;
        bar.alpha = hidden ? 0.0 : 1.0;
    } completion:nil];
}

static void (*orig_tabBar_setScaleProgress)(id self, SEL _cmd, double progress);
static void hook_tabBar_setScaleProgress(id self, SEL _cmd, double progress) {
    SCILiquidGlassTabBarMode mode = SCIIsLiquidGlassEnabled() ? SCICurrentLiquidGlassTabBarMode() : SCILiquidGlassTabBarModeDefault;
    if (mode == SCILiquidGlassTabBarModeFixed) {
        SCIApplyLiquidGlassTabBarHiddenState((UIView *)self, NO);
        progress = 0.0;
    } else if (mode == SCILiquidGlassTabBarModeHide) {
        SCIApplyLiquidGlassTabBarHiddenState((UIView *)self, progress > 0.05);
        progress = 0.0;
    } else {
        SCIApplyLiquidGlassTabBarHiddenState((UIView *)self, NO);
    }
    if (orig_tabBar_setScaleProgress) orig_tabBar_setScaleProgress(self, _cmd, progress);
}

static void (*orig_tabBar_scaleDownWithInteraction)(id self, SEL _cmd, id interaction);
static void hook_tabBar_scaleDownWithInteraction(id self, SEL _cmd, id interaction) {
    SCILiquidGlassTabBarMode mode = SCIIsLiquidGlassEnabled() ? SCICurrentLiquidGlassTabBarMode() : SCILiquidGlassTabBarModeDefault;
    if (mode != SCILiquidGlassTabBarModeDefault) return;
    if (orig_tabBar_scaleDownWithInteraction) orig_tabBar_scaleDownWithInteraction(self, _cmd, interaction);
}

// MARK: - Direct inbox separator workaround

static Class SCIDirectInboxNavigationHeaderViewClass(void) {
    Class cls = objc_getClass("IGDirectInboxNavigationHeaderView");
    if (!cls) {
        cls = objc_getClass("IGDirectInboxNavigationHeaderView.IGDirectInboxNavigationHeaderView");
    }
    return cls;
}

static UIView *SCIDirectInboxHeaderSeparatorView(id headerView) {
    if (![headerView isKindOfClass:UIView.class]) return nil;

    NSArray<UIView *> *subviews = [(UIView *)headerView subviews];
    if (subviews.count <= 1) return nil;

    UIView *candidate = subviews[1];
    if (![candidate isKindOfClass:UIView.class]) return nil;

    CGFloat height = MAX(candidate.bounds.size.height, candidate.frame.size.height);
    return (subviews.count == 2 || height <= 3.0) ? candidate : nil;
}

static void SCIRemoveDirectInboxHeaderSeparator(id headerView) {
    if (!SCIIsLiquidGlassEnabled()) return;
    UIView *separator = SCIDirectInboxHeaderSeparatorView(headerView);
    separator.alpha = 0.0;
    separator.hidden = YES;
    [separator removeFromSuperview];
}

static SCI_VOID_MSG orig_directInboxHeader_layoutSubviews;
static void hook_directInboxHeader_layoutSubviews(id self, SEL _cmd) {
    if (orig_directInboxHeader_layoutSubviews) orig_directInboxHeader_layoutSubviews(self, _cmd);
    SCIRemoveDirectInboxHeaderSeparator(self);
}

static SCI_VOID_MSG orig_directInboxHeader_didMoveToWindow;
static void hook_directInboxHeader_didMoveToWindow(id self, SEL _cmd) {
    if (orig_directInboxHeader_didMoveToWindow) orig_directInboxHeader_didMoveToWindow(self, _cmd);
    SCIRemoveDirectInboxHeaderSeparator(self);
}

static SCI_SET_CGFLOAT_MSG orig_directInboxHeader_setSeparatorAlpha;
static void hook_directInboxHeader_setSeparatorAlpha(id self, SEL _cmd, CGFloat alpha) {
    if (orig_directInboxHeader_setSeparatorAlpha) {
        orig_directInboxHeader_setSeparatorAlpha(self, _cmd, SCIIsLiquidGlassEnabled() ? 0.0 : alpha);
    }
    SCIRemoveDirectInboxHeaderSeparator(self);
}

static void SCIHookInstanceMethodIfPresent(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (cls && class_getInstanceMethod(cls, selector)) {
        MSHookMessageEx(cls, selector, replacement, original);
    }
}

extern "C" void SCIInstallLiquidGlassHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int result = rebind_symbols((struct rebinding[]){
            {"IGFloatingTabBarEnabled", (void *)hook_IGFloatingTabBarEnabled, (void **)&orig_IGFloatingTabBarEnabled},
            {"IGTabBarDynamicSizingEnabled", (void *)hook_IGTabBarDynamicSizingEnabled, (void **)&orig_IGTabBarDynamicSizingEnabled},
            {"IGTabBarEnhancedDynamicSizingEnabled", (void *)hook_IGTabBarEnhancedDynamicSizingEnabled, (void **)&orig_IGTabBarEnhancedDynamicSizingEnabled},
            {"IGTabBarHomecomingWithFloatingTabEnabled", (void *)hook_IGTabBarHomecomingWithFloatingTabEnabled, (void **)&orig_IGTabBarHomecomingWithFloatingTabEnabled},
            {"IGTabBarViewPointFixEnabled", (void *)hook_IGTabBarViewPointFixEnabled, (void **)&orig_IGTabBarViewPointFixEnabled},
            {"IGTabBarStyleForLauncherSet", (void *)hook_IGTabBarStyleForLauncherSet, (void **)&orig_IGTabBarStyleForLauncherSet},
        }, 6);
        SCILog(@"LiquidGlass", @"Surface fishhook result=%d", result);

        Class cls = objc_getClass("IGLiquidGlassSwizzle.IGLiquidGlassSwizzleToggle");
        SCIHookInstanceMethodIfPresent(cls, @selector(isEnabled), (IMP)hook_swizzleToggle_isEnabled, (IMP *)&orig_swizzleToggle_isEnabled);

        cls = objc_getClass("IGLiquidGlassExperimentHelper.IGLiquidGlassNavigationExperimentHelper");
        SCIHookInstanceMethodIfPresent(cls, @selector(isEnabled), (IMP)hook_navigationExperiment_isEnabled, (IMP *)&orig_navigationExperiment_isEnabled);
        SCIHookInstanceMethodIfPresent(cls, @selector(isHomeFeedHeaderEnabled), (IMP)hook_navigationExperiment_isHomeFeedHeaderEnabled, (IMP *)&orig_navigationExperiment_isHomeFeedHeaderEnabled);

        cls = objc_getClass("IGLiquidGlassInteractiveTabBar");
        SCIHookInstanceMethodIfPresent(cls, @selector(setScaleProgress:), (IMP)hook_tabBar_setScaleProgress, (IMP *)&orig_tabBar_setScaleProgress);
        SCIHookInstanceMethodIfPresent(cls, @selector(scaleDownWithInteraction:), (IMP)hook_tabBar_scaleDownWithInteraction, (IMP *)&orig_tabBar_scaleDownWithInteraction);

        cls = SCIDirectInboxNavigationHeaderViewClass();
        SCIHookInstanceMethodIfPresent(cls, @selector(layoutSubviews), (IMP)hook_directInboxHeader_layoutSubviews, (IMP *)&orig_directInboxHeader_layoutSubviews);
        SCIHookInstanceMethodIfPresent(cls, @selector(didMoveToWindow), (IMP)hook_directInboxHeader_didMoveToWindow, (IMP *)&orig_directInboxHeader_didMoveToWindow);
        SCIHookInstanceMethodIfPresent(cls, @selector(setSeparatorAlpha:), (IMP)hook_directInboxHeader_setSeparatorAlpha, (IMP *)&orig_directInboxHeader_setSeparatorAlpha);
    });
}

// MARK: - Progressive Blur Hooks
%group SCIProgressiveBlurHooks
%hook UIScrollEdgeEffect
+ (void)hide {
    // No-op to prevent globally hiding scroll-edge effects
}

- (BOOL)ig_isHidden {
    return NO; // Always show the progressive blur
}

- (void)ig_setIsHidden:(BOOL)hidden {
    %orig(NO); // Intercept and prevent individual hiders
}
%end
%end

extern "C" void SCIInstallProgressiveBlurHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (objc_getClass("UIScrollEdgeEffect")) {
            %init(SCIProgressiveBlurHooks);
            SCILog(@"LiquidGlass", @"SCIProgressiveBlurHooks successfully installed!");
        } else {
            SCILog(@"LiquidGlass", @"UIScrollEdgeEffect class not found at runtime, skipping hooks.");
        }
    });
}

#pragma clang diagnostic pop

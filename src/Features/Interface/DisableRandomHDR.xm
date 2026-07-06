#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

@import UIKit;
@import QuartzCore;

#import "../../Utils.h"

static NSString *const kSPKHDRLogCategory = @"HDR";

// Surfaces whose EDR "glow" we want to remove. Matched as substrings against the
// class name of the layer's owning view and its ancestors.
static NSArray<NSString *> *SPKBlockedSurfaceNeedles(void) {
    static NSArray *needles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[ @"FollowButton" ];
    });
    return needles;
}

// Surfaces we explicitly leave alone (keep HDR). Takes precedence over the
// blocked list, so e.g. the reels video follow button keeps its HDR even though
// its class name contains "FollowButton".
static NSArray<NSString *> *SPKAllowedSurfaceNeedles(void) {
    static NSArray *needles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[ @"IGUnifiedVideoFollowButton" ];
    });
    return needles;
}

#pragma mark - View-chain inspection

// Walks up the superview chain (bounded) building "Cls > Super > ...". Used both
// for matching and for diagnostics.
static NSString *SPKViewChainDescription(UIView *view, NSUInteger maxDepth) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *cursor = view;
    NSUInteger depth = 0;
    while (cursor && depth < maxDepth) {
        [parts addObject:NSStringFromClass([cursor class])];
        cursor = cursor.superview;
        depth++;
    }
    return [parts componentsJoinedByString:@" > "];
}

static BOOL SPKChainMatchesAnyNeedle(UIView *view, NSArray<NSString *> *needles, NSUInteger maxDepth) {
    UIView *cursor = view;
    NSUInteger depth = 0;
    while (cursor && depth < maxDepth) {
        NSString *className = NSStringFromClass([cursor class]);
        for (NSString *needle in needles) {
            if ([className rangeOfString:needle].location != NSNotFound)
                return YES;
        }
        cursor = cursor.superview;
        depth++;
    }
    return NO;
}

#pragma mark - CALayer EDR chokepoint

static const NSUInteger kSPKMaxChainDepth = 10;

static void (*orig_CALayer_ig_setWantsEDR)(id, SEL, BOOL);
static void hooked_CALayer_ig_setWantsEDR(CALayer *self, SEL _cmd, BOOL wants) {
    BOOL forced = wants;

    if (wants) {
        id delegate = self.delegate;
        UIView *view = [delegate isKindOfClass:[UIView class]] ? (UIView *)delegate : nil;

        if (view) {
            BOOL allowed = SPKChainMatchesAnyNeedle(view, SPKAllowedSurfaceNeedles(), kSPKMaxChainDepth);
            BOOL blocked = !allowed && SPKChainMatchesAnyNeedle(view, SPKBlockedSurfaceNeedles(), kSPKMaxChainDepth);

            if (blocked) {
                forced = NO;
                SPKLog(kSPKHDRLogCategory, @"Disabling EDR layer for %@", SPKViewChainDescription(view, kSPKMaxChainDepth));
            }
        }
    }

    if (orig_CALayer_ig_setWantsEDR) {
        orig_CALayer_ig_setWantsEDR(self, _cmd, forced);
    }
}

#pragma mark - Swift Follow Button EDR Hooks

static BOOL SPKIsViewInFeedPost(UIView *view) {
    UIView *walker = view;
    NSInteger depth = 0;
    while (walker && depth < 20) {
        NSString *className = NSStringFromClass([walker class]);
        if ([className isEqualToString:@"IGFeedItemHeaderCell"] ||
            [className isEqualToString:@"_TtC25IGFeedItemHeaderCellSwift25IGFeedItemHeaderCellSwift"] ||
            [className rangeOfString:@"FeedItemHeader"].location != NSNotFound) {
            return YES;
        }
        walker = walker.superview;
        depth++;
    }
    return NO;
}

static BOOL (*orig_swiftFollowButton_edr)(id, SEL);
static BOOL hooked_swiftFollowButton_edr(id self, SEL _cmd) {
    if ([SPKUtils getBoolPref:@"interface_disable_random_hdr"]) {
        if ([self isKindOfClass:[UIView class]] && SPKIsViewInFeedPost((UIView *)self)) {
            return NO;
        }
    }
    return orig_swiftFollowButton_edr ? orig_swiftFollowButton_edr(self, _cmd) : YES;
}

static BOOL (*orig_swiftFollowButton_isEdr)(id, SEL);
static BOOL hooked_swiftFollowButton_isEdr(id self, SEL _cmd) {
    if ([SPKUtils getBoolPref:@"interface_disable_random_hdr"]) {
        if ([self isKindOfClass:[UIView class]] && SPKIsViewInFeedPost((UIView *)self)) {
            return NO;
        }
    }
    return orig_swiftFollowButton_isEdr ? orig_swiftFollowButton_isEdr(self, _cmd) : YES;
}

static void (*orig_swiftFollowButton_setEdr)(id, SEL, BOOL);
static void hooked_swiftFollowButton_setEdr(id self, SEL _cmd, BOOL edr) {
    BOOL forced = edr;
    if (edr && [SPKUtils getBoolPref:@"interface_disable_random_hdr"]) {
        if ([self isKindOfClass:[UIView class]] && SPKIsViewInFeedPost((UIView *)self)) {
            forced = NO;
        }
    }
    if (orig_swiftFollowButton_setEdr) {
        orig_swiftFollowButton_setEdr(self, _cmd, forced);
    }
}

#pragma mark - Install

static void SPKHookSelector(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || ![cls instancesRespondToSelector:selector])
        return;
    MSHookMessageEx(cls, selector, replacement, original);
}

extern "C" void SPKInstallDisableRandomHDRHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"interface_disable_random_hdr"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1. Foundational EDR toggle on CALayer
        Class layerCls = objc_getClass("CALayer");
        if (layerCls && [layerCls instancesRespondToSelector:@selector(ig_setWantsExtendedDynamicRangeContent:)]) {
            SPKHookSelector(layerCls,
                            @selector(ig_setWantsExtendedDynamicRangeContent:),
                            (IMP)hooked_CALayer_ig_setWantsEDR,
                            (IMP *)&orig_CALayer_ig_setWantsEDR);
            SPKLog(kSPKHDRLogCategory, @"Hooked CALayer ig_setWantsExtendedDynamicRangeContent:");
        } else {
            SPKWarnLog(kSPKHDRLogCategory, @"CALayer ig_setWantsExtendedDynamicRangeContent: unavailable");
        }

        // 2. Swift FollowButton EDR property hooks
        Class followButtonCls = objc_getClass("_TtC14IGFollowButton14IGFollowButton");
        if (followButtonCls) {
            SPKHookSelector(followButtonCls, @selector(edr), (IMP)hooked_swiftFollowButton_edr, (IMP *)&orig_swiftFollowButton_edr);
            SPKHookSelector(followButtonCls, @selector(isEdr), (IMP)hooked_swiftFollowButton_isEdr, (IMP *)&orig_swiftFollowButton_isEdr);
            SPKHookSelector(followButtonCls, @selector(setEdr:), (IMP)hooked_swiftFollowButton_setEdr, (IMP *)&orig_swiftFollowButton_setEdr);
            SPKLog(kSPKHDRLogCategory, @"Hooked _TtC14IGFollowButton14IGFollowButton EDR properties");
        } else {
            SPKWarnLog(kSPKHDRLogCategory, @"_TtC14IGFollowButton14IGFollowButton class unavailable");
        }

        // 3. Legacy FollowButton EDR property hooks (fallback)
        Class legacyFollowButtonCls = objc_getClass("IGFollowButton");
        if (legacyFollowButtonCls) {
            SPKHookSelector(legacyFollowButtonCls, @selector(edr), (IMP)hooked_swiftFollowButton_edr, (IMP *)&orig_swiftFollowButton_edr);
            SPKHookSelector(legacyFollowButtonCls, @selector(isEdr), (IMP)hooked_swiftFollowButton_isEdr, (IMP *)&orig_swiftFollowButton_isEdr);
            SPKHookSelector(legacyFollowButtonCls, @selector(setEdr:), (IMP)hooked_swiftFollowButton_setEdr, (IMP *)&orig_swiftFollowButton_setEdr);
            SPKLog(kSPKHDRLogCategory, @"Hooked IGFollowButton EDR properties");
        }
    });
}

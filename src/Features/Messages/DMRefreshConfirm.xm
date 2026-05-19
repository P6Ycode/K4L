#import <objc/message.h>
#import <substrate.h>
#import <UIKit/UIKit.h>

#import "../../Utils.h"

static void (*orig_inboxRefreshControlArg)(id, SEL, id) = NULL;
static void (*orig_inboxRefreshNoArg)(id, SEL) = NULL;
static BOOL sSCIDMRefreshBypassing = NO;
static BOOL sSCIDMRefreshAlertVisible = NO;

static UIRefreshControl *SCIDMRefreshControlInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:UIRefreshControl.class]) return (UIRefreshControl *)view;
    if ([view respondsToSelector:@selector(refreshControl)]) {
        UIRefreshControl *refreshControl = ((UIRefreshControl *(*)(id, SEL))objc_msgSend)(view, @selector(refreshControl));
        if ([refreshControl isKindOfClass:UIRefreshControl.class]) return refreshControl;
    }
    for (UIView *subview in view.subviews) {
        UIRefreshControl *found = SCIDMRefreshControlInView(subview);
        if (found) return found;
    }
    return nil;
}

static void SCIDMEndRefreshIfNeeded(id self, id arg) {
    UIRefreshControl *refreshControl = [arg isKindOfClass:UIRefreshControl.class] ? (UIRefreshControl *)arg : nil;
    if (!refreshControl && [self isKindOfClass:UIViewController.class]) {
        refreshControl = SCIDMRefreshControlInView(((UIViewController *)self).view);
    }
    if (!refreshControl) return;

    Ivar stateIvar = class_getInstanceVariable([refreshControl class], "_refreshState");
    if (stateIvar) {
        ptrdiff_t off = ivar_getOffset(stateIvar);
        *(NSInteger *)((char *)(__bridge void *)refreshControl + off) = 0;
    }
    Ivar animIvar = class_getInstanceVariable([refreshControl class], "_swiftAnimationInfo");
    if (animIvar) object_setIvar(refreshControl, animIvar, nil);
    if ([refreshControl respondsToSelector:@selector(endRefreshing)]) [refreshControl endRefreshing];

    SEL didEnd = NSSelectorFromString(@"refreshControlDidEndFinishLoadingAnimation:");
    if ([self respondsToSelector:didEnd]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, didEnd, refreshControl);
    }

    UIScrollView *scroll = nil;
    UIView *cur = refreshControl.superview;
    while (cur) {
        if ([cur isKindOfClass:UIScrollView.class]) { scroll = (UIScrollView *)cur; break; }
        cur = cur.superview;
    }
    if (!scroll) return;

    CGFloat idleInset = scroll.contentInset.top;
    SEL idleSel = NSSelectorFromString(@"idleTopContentInsetForRefreshControl:");
    if ([self respondsToSelector:idleSel]) {
        idleInset = ((CGFloat (*)(id, SEL, id))objc_msgSend)(self, idleSel, refreshControl);
    }
    UIEdgeInsets insets = scroll.contentInset;
    insets.top = idleInset;
    [UIView animateWithDuration:0.25 animations:^{
        scroll.contentInset = insets;
        CGPoint offset = scroll.contentOffset;
        if (offset.y < -idleInset) offset.y = -idleInset;
        scroll.contentOffset = offset;
    }];
}

static void SCIConfirmDMRefresh(id self, id arg, void (^confirmBlock)(void)) {
    if (sSCIDMRefreshBypassing || ![SCIUtils getBoolPref:@"dm_refresh_confirm"]) {
        if (confirmBlock) confirmBlock();
        return;
    }
    SCIDMEndRefreshIfNeeded(self, arg);
    if (sSCIDMRefreshAlertVisible) return;
    sSCIDMRefreshAlertVisible = YES;
    [SCIUtils showConfirmation:^{
        sSCIDMRefreshAlertVisible = NO;
        sSCIDMRefreshBypassing = YES;
        if (confirmBlock) confirmBlock();
        sSCIDMRefreshBypassing = NO;
    } cancelHandler:^{
        sSCIDMRefreshAlertVisible = NO;
        SCIDMEndRefreshIfNeeded(self, arg);
    } title:@"Confirm Messages Refresh"
      message:@"Are you sure you want to refresh your inbox?"];
}

static void replaced_inboxRefreshControlArg(id self, SEL _cmd, id arg) {
    SCIConfirmDMRefresh(self, arg, ^{
        if (orig_inboxRefreshControlArg) orig_inboxRefreshControlArg(self, _cmd, arg);
    });
}

static void replaced_inboxRefreshNoArg(id self, SEL _cmd) {
    SCIConfirmDMRefresh(self, nil, ^{
        if (orig_inboxRefreshNoArg) orig_inboxRefreshNoArg(self, _cmd);
    });
}

static BOOL SCIHookDMRefreshArgSelector(Class cls, SEL selector) {
    if (!cls || !class_getInstanceMethod(cls, selector)) return NO;
    MSHookMessageEx(cls, selector, (IMP)replaced_inboxRefreshControlArg, (IMP *)&orig_inboxRefreshControlArg);
    return YES;
}

static BOOL SCIHookDMRefreshNoArgSelector(Class cls, SEL selector) {
    if (!cls || !class_getInstanceMethod(cls, selector)) return NO;
    MSHookMessageEx(cls, selector, (IMP)replaced_inboxRefreshNoArg, (IMP *)&orig_inboxRefreshNoArg);
    return YES;
}

extern "C" void SCIInstallDMRefreshConfirmHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<Class> *classes = [NSMutableArray array];
        for (NSString *className in @[@"IGDirectInboxViewController",
                                      @"IGDirectInboxContainerViewController",
                                      @"IGDirectInboxListViewController",
                                      @"IGDirectInboxViewControllerImpl"]) {
            Class cls = NSClassFromString(className);
            if (cls) [classes addObject:cls];
        }
        BOOL hookedNoArg = NO;
        BOOL hookedArg = NO;
        for (Class cls in classes) {
            if (!hookedNoArg) {
                hookedNoArg = SCIHookDMRefreshNoArgSelector(cls, NSSelectorFromString(@"_pullToRefreshIfPossible"));
            }
            if (!hookedArg) {
                hookedArg = SCIHookDMRefreshArgSelector(cls, NSSelectorFromString(@"refreshControlDidRefresh:")) ||
                            SCIHookDMRefreshArgSelector(cls, NSSelectorFromString(@"refreshControlValueChanged:")) ||
                            SCIHookDMRefreshArgSelector(cls, NSSelectorFromString(@"_didPullToRefresh:"));
            }
        }
    });
}

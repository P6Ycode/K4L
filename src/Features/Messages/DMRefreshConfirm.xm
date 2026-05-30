#import <objc/message.h>
#import <substrate.h>
#import <UIKit/UIKit.h>

#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static void (*orig_inboxRefreshControlArg)(id, SEL, id) = NULL;
static void (*orig_inboxRefreshNoArg)(id, SEL) = NULL;
static void (*orig_networkingCoordinatorPullToRefreshIfPossible)(id, SEL) = NULL;
static BOOL (*orig_executePullToRefreshWithParams)(id, SEL, id, BOOL) = NULL;
static BOOL sSCIDMRefreshBypassing = NO;
static BOOL sSCIDMRefreshAlertVisible = NO;

static IGRefreshControl *SCIDMFindIGRefreshControl(id self, id arg) {
    // Check if arg is an IGRefreshControl
    Class igRefreshControlClass = NSClassFromString(@"IGRefreshControl");
    if (arg && igRefreshControlClass && [arg isKindOfClass:igRefreshControlClass]) return (IGRefreshControl *)arg;

    // Try to get _refreshControl ivar from the view controller
    if ([self isKindOfClass:[UIViewController class]]) {
        Ivar ivar = class_getInstanceVariable([self class], "_refreshControl");
        if (ivar) {
            id control = object_getIvar(self, ivar);
            if (igRefreshControlClass && [control isKindOfClass:igRefreshControlClass]) return (IGRefreshControl *)control;
        }
    }

    return nil;
}

static void SCIDMEndRefreshIfNeeded(id self, id arg) {
    IGRefreshControl *refreshControl = SCIDMFindIGRefreshControl(self, arg);
    if (refreshControl) {
        [refreshControl finishLoading];
        return;
    }

    // Fallback: try UIRefreshControl in view hierarchy (older IG versions)
    UIRefreshControl *uiRefreshControl = nil;
    if ([arg isKindOfClass:UIRefreshControl.class]) {
        uiRefreshControl = (UIRefreshControl *)arg;
    } else if ([self isKindOfClass:UIViewController.class]) {
        UIView *view = ((UIViewController *)self).view;
        if ([view respondsToSelector:@selector(refreshControl)]) {
            id rc = ((UIRefreshControl *(*)(id, SEL))objc_msgSend)(view, @selector(refreshControl));
            if ([rc isKindOfClass:UIRefreshControl.class]) uiRefreshControl = rc;
        }
    }
    if (!uiRefreshControl) return;

    if ([uiRefreshControl respondsToSelector:@selector(endRefreshing)]) [uiRefreshControl endRefreshing];

    SEL didEnd = NSSelectorFromString(@"refreshControlDidEndFinishLoadingAnimation:");
    if ([self respondsToSelector:didEnd]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, didEnd, uiRefreshControl);
    }
}

static void SCIConfirmDMRefresh(id self, id arg, void (^confirmBlock)(void)) {
    if (sSCIDMRefreshBypassing || ![SCIUtils getBoolPref:@"msgs_confirm_refresh"]) {
        if (confirmBlock) confirmBlock();
        return;
    }
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
    } title:@"Confirm Inbox Refresh"
      message:@"Refreshing your inbox will reload direct messages from the server."];
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

static void replaced_networkingCoordinatorPullToRefreshIfPossible(id self, SEL _cmd) {
    SCIConfirmDMRefresh(self, nil, ^{
        if (orig_networkingCoordinatorPullToRefreshIfPossible) orig_networkingCoordinatorPullToRefreshIfPossible(self, _cmd);
    });
}

static BOOL replaced_executePullToRefreshWithParams(id self, SEL _cmd, id params, BOOL rightNow) {
    if (sSCIDMRefreshBypassing || ![SCIUtils getBoolPref:@"msgs_confirm_refresh"]) {
        return orig_executePullToRefreshWithParams ? orig_executePullToRefreshWithParams(self, _cmd, params, rightNow) : NO;
    }

    if (sSCIDMRefreshAlertVisible) return NO;

    sSCIDMRefreshAlertVisible = YES;
    [SCIUtils showConfirmation:^{
        sSCIDMRefreshAlertVisible = NO;
        sSCIDMRefreshBypassing = YES;
        if (orig_executePullToRefreshWithParams) orig_executePullToRefreshWithParams(self, _cmd, params, rightNow);
        sSCIDMRefreshBypassing = NO;
    } cancelHandler:^{
        sSCIDMRefreshAlertVisible = NO;
        SCIDMEndRefreshIfNeeded(self, nil);
    } title:@"Confirm Inbox Refresh"
      message:@"Refreshing your inbox will reload direct messages from the server."];

    return NO;
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
                hookedNoArg = SCIHookDMRefreshNoArgSelector(cls, NSSelectorFromString(@"pullToRefreshIfPossible")) ||
                              SCIHookDMRefreshNoArgSelector(cls, NSSelectorFromString(@"_pullToRefreshIfPossible"));
            }
            if (!hookedArg) {
                hookedArg = SCIHookDMRefreshArgSelector(cls, NSSelectorFromString(@"refreshControlDidRefresh:")) ||
                            SCIHookDMRefreshArgSelector(cls, NSSelectorFromString(@"refreshControlValueChanged:")) ||
                            SCIHookDMRefreshArgSelector(cls, NSSelectorFromString(@"_didPullToRefresh:"));
            }
        }

        Class networkingCoordinatorClass = NSClassFromString(@"_TtC23IGDirectInboxNetworking34IGDirectInboxNetworkingCoordinator");
        if (networkingCoordinatorClass && class_getInstanceMethod(networkingCoordinatorClass, NSSelectorFromString(@"pullToRefreshIfPossible"))) {
            MSHookMessageEx(networkingCoordinatorClass,
                            NSSelectorFromString(@"pullToRefreshIfPossible"),
                            (IMP)replaced_networkingCoordinatorPullToRefreshIfPossible,
                            (IMP *)&orig_networkingCoordinatorPullToRefreshIfPossible);
        }

        Class pullToRefreshCoordinatorClass = NSClassFromString(@"IGDirectInboxDjangoPullToRefreshCoordinator");
        if (pullToRefreshCoordinatorClass && class_getInstanceMethod(pullToRefreshCoordinatorClass, NSSelectorFromString(@"executePullToRefreshWithParams:rightNow:"))) {
            MSHookMessageEx(pullToRefreshCoordinatorClass,
                            NSSelectorFromString(@"executePullToRefreshWithParams:rightNow:"),
                            (IMP)replaced_executePullToRefreshWithParams,
                            (IMP *)&orig_executePullToRefreshWithParams);
        }
    });
}

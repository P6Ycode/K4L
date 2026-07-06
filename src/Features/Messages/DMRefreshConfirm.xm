#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <substrate.h>

#import "../../InstagramHeaders.h"
#import "../../Utils.h"

static void (*orig_inboxRefreshControlArg)(id, SEL, id) = NULL;
static void (*orig_inboxRefreshNoArg)(id, SEL) = NULL;
static void (*orig_networkingCoordinatorPullToRefreshIfPossible)(id, SEL) = NULL;
static BOOL (*orig_executePullToRefreshWithParams)(id, SEL, id, BOOL) = NULL;
static BOOL sSPKDMRefreshBypassing = NO;
static BOOL sSPKDMRefreshAlertVisible = NO;

static IGRefreshControl *SPKDMFindIGRefreshControl(id self, id arg) {
    // Check if arg is an IGRefreshControl
    Class igRefreshControlClass = NSClassFromString(@"IGRefreshControl");
    if (arg && igRefreshControlClass && [arg isKindOfClass:igRefreshControlClass])
        return (IGRefreshControl *)arg;

    // Try to get _refreshControl ivar from the view controller
    if ([self isKindOfClass:[UIViewController class]]) {
        Ivar ivar = class_getInstanceVariable([self class], "_refreshControl");
        if (ivar) {
            id control = object_getIvar(self, ivar);
            if (igRefreshControlClass && [control isKindOfClass:igRefreshControlClass])
                return (IGRefreshControl *)control;
        }
    }

    return nil;
}

static void SPKDMEndRefreshIfNeeded(id self, id arg) {
    IGRefreshControl *refreshControl = SPKDMFindIGRefreshControl(self, arg);
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
            id rc = ((UIRefreshControl * (*)(id, SEL)) objc_msgSend)(view, @selector(refreshControl));
            if ([rc isKindOfClass:UIRefreshControl.class])
                uiRefreshControl = rc;
        }
    }
    if (!uiRefreshControl)
        return;

    if ([uiRefreshControl respondsToSelector:@selector(endRefreshing)])
        [uiRefreshControl endRefreshing];

    SEL didEnd = NSSelectorFromString(@"refreshControlDidEndFinishLoadingAnimation:");
    if ([self respondsToSelector:didEnd]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, didEnd, uiRefreshControl);
    }
}

static void SPKConfirmDMRefresh(id self, id arg, void (^confirmBlock)(void)) {
    if (sSPKDMRefreshBypassing || ![SPKUtils getBoolPref:@"msgs_confirm_refresh"]) {
        if (confirmBlock)
            confirmBlock();
        return;
    }
    if (sSPKDMRefreshAlertVisible)
        return;
    sSPKDMRefreshAlertVisible = YES;
    [SPKUtils
        showConfirmation:^{
            sSPKDMRefreshAlertVisible = NO;
            sSPKDMRefreshBypassing = YES;
            if (confirmBlock)
                confirmBlock();
            sSPKDMRefreshBypassing = NO;
        }
        cancelHandler:^{
            sSPKDMRefreshAlertVisible = NO;
            SPKDMEndRefreshIfNeeded(self, arg);
        }
        title:@"Confirm Inbox Refresh"
        message:@"Refreshing your inbox reloads direct messages from the server. Any unsent messages kept in chats will be lost."];
}

static void replaced_inboxRefreshControlArg(id self, SEL _cmd, id arg) {
    SPKConfirmDMRefresh(self, arg, ^{
        if (orig_inboxRefreshControlArg)
            orig_inboxRefreshControlArg(self, _cmd, arg);
    });
}

static void replaced_inboxRefreshNoArg(id self, SEL _cmd) {
    SPKConfirmDMRefresh(self, nil, ^{
        if (orig_inboxRefreshNoArg)
            orig_inboxRefreshNoArg(self, _cmd);
    });
}

static void replaced_networkingCoordinatorPullToRefreshIfPossible(id self, SEL _cmd) {
    SPKConfirmDMRefresh(self, nil, ^{
        if (orig_networkingCoordinatorPullToRefreshIfPossible)
            orig_networkingCoordinatorPullToRefreshIfPossible(self, _cmd);
    });
}

static BOOL replaced_executePullToRefreshWithParams(id self, SEL _cmd, id params, BOOL rightNow) {
    if (sSPKDMRefreshBypassing || ![SPKUtils getBoolPref:@"msgs_confirm_refresh"]) {
        return orig_executePullToRefreshWithParams ? orig_executePullToRefreshWithParams(self, _cmd, params, rightNow) : NO;
    }

    if (sSPKDMRefreshAlertVisible)
        return NO;

    sSPKDMRefreshAlertVisible = YES;
    [SPKUtils
        showConfirmation:^{
            sSPKDMRefreshAlertVisible = NO;
            sSPKDMRefreshBypassing = YES;
            if (orig_executePullToRefreshWithParams)
                orig_executePullToRefreshWithParams(self, _cmd, params, rightNow);
            sSPKDMRefreshBypassing = NO;
        }
        cancelHandler:^{
            sSPKDMRefreshAlertVisible = NO;
            SPKDMEndRefreshIfNeeded(self, nil);
        }
        title:@"Confirm Inbox Refresh"
        message:@"Refreshing your inbox reloads direct messages from the server. Any unsent messages kept in chats will be lost."];

    return NO;
}

static BOOL SPKHookDMRefreshArgSelector(Class cls, SEL selector) {
    if (!cls || !class_getInstanceMethod(cls, selector))
        return NO;
    MSHookMessageEx(cls, selector, (IMP)replaced_inboxRefreshControlArg, (IMP *)&orig_inboxRefreshControlArg);
    return YES;
}

static BOOL SPKHookDMRefreshNoArgSelector(Class cls, SEL selector) {
    if (!cls || !class_getInstanceMethod(cls, selector))
        return NO;
    MSHookMessageEx(cls, selector, (IMP)replaced_inboxRefreshNoArg, (IMP *)&orig_inboxRefreshNoArg);
    return YES;
}

extern "C" void SPKInstallDMRefreshConfirmHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<Class> *classes = [NSMutableArray array];
        for (NSString *className in @[ @"IGDirectInboxViewController",
                                       @"IGDirectInboxContainerViewController",
                                       @"IGDirectInboxListViewController",
                                       @"IGDirectInboxViewControllerImpl" ]) {
            Class cls = NSClassFromString(className);
            if (cls)
                [classes addObject:cls];
        }
        BOOL hookedNoArg = NO;
        BOOL hookedArg = NO;
        for (Class cls in classes) {
            if (!hookedNoArg) {
                hookedNoArg = SPKHookDMRefreshNoArgSelector(cls, NSSelectorFromString(@"pullToRefreshIfPossible")) ||
                              SPKHookDMRefreshNoArgSelector(cls, NSSelectorFromString(@"_pullToRefreshIfPossible"));
            }
            if (!hookedArg) {
                hookedArg = SPKHookDMRefreshArgSelector(cls, NSSelectorFromString(@"refreshControlDidRefresh:")) ||
                            SPKHookDMRefreshArgSelector(cls, NSSelectorFromString(@"refreshControlValueChanged:")) ||
                            SPKHookDMRefreshArgSelector(cls, NSSelectorFromString(@"_didPullToRefresh:"));
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

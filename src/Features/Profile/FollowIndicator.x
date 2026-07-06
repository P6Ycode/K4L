// Shows whether the current profile user follows you.

#import "../../InstagramHeaders.h"
#import "../../Networking/SPKInstagramAPI.h"
#import "../../Utils.h"
#import "../General/CaptureHiding.h"
#import <objc/runtime.h>

static NSInteger const kSPKFollowBadgeTag = 99788;
static const void *kSPKFollowStatusAssocKey = &kSPKFollowStatusAssocKey;

static NSString *SPKPKFromUserObject(id userObject) {
    if (!userObject)
        return nil;
    Ivar pkIvar = NULL;
    for (Class cls = [userObject class]; cls && !pkIvar; cls = class_getSuperclass(cls)) {
        pkIvar = class_getInstanceVariable(cls, "_pk");
    }
    if (!pkIvar)
        return nil;
    id pk = object_getIvar(userObject, pkIvar);
    return pk ? [pk description] : nil;
}

static NSString *SPKCurrentUserPK(void) {
    @try {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;
            for (UIWindow *window in scene.windows) {
                id session = [window valueForKey:@"userSession"];
                if (!session)
                    continue;
                id user = [session valueForKey:@"user"];
                if (!user)
                    continue;
                NSString *pk = SPKPKFromUserObject(user);
                if (pk.length > 0)
                    return pk;
            }
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static NSNumber *SPKGetFollowStatusForController(id controller) {
    return objc_getAssociatedObject(controller, kSPKFollowStatusAssocKey);
}

static void SPKSetFollowStatusForController(id controller, NSNumber *status) {
    objc_setAssociatedObject(controller, kSPKFollowStatusAssocKey, status, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *SPKProfileStatContainer(UIViewController *controller) {
    if (!controller.view)
        return nil;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:controller.view];
    while (stack.count > 0) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];

        if ([NSStringFromClass([view class]) containsString:@"StatButtonContainerView"]) {
            return view;
        }

        [stack addObjectsFromArray:view.subviews];
    }
    return nil;
}

static void SPKRenderFollowBadge(UIViewController *controller) {
    NSNumber *status = SPKGetFollowStatusForController(controller);
    if (!status)
        return;

    UIView *container = SPKProfileStatContainer(controller);
    if (!container)
        return;

    // Remove our previous wrapper (direct child only; the capture canvas may
    // have re-parented the inner label, so match on the wrapper's tag).
    for (UIView *sub in [container.subviews copy]) {
        if (sub.tag == kSPKCaptureFollowIndicatorTag)
            [sub removeFromSuperview];
    }

    BOOL followsYou = status.boolValue;
    UILabel *badge = [[UILabel alloc] init];
    badge.tag = kSPKFollowBadgeTag;
    badge.text = followsYou ? @"FOLLOWING YOU" : @"NOT FOLLOWING YOU";
    badge.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    badge.textColor = followsYou
                          ? [UIColor colorWithRed:0.30 green:0.75 blue:0.40 alpha:1.0]
                          : [UIColor colorWithRed:0.85 green:0.30 blue:0.30 alpha:1.0];
    [badge sizeToFit];

    CGFloat xOrigin = 0.0;
    for (UIView *subview in container.subviews) {
        if (!subview.isHidden && CGRectGetWidth(subview.frame) > 0.0) {
            xOrigin = CGRectGetMinX(subview.frame);
            break;
        }
    }

    CGFloat badgeWidth = CGRectGetWidth(badge.bounds);
    CGFloat badgeHeight = CGRectGetHeight(badge.bounds);
    badge.frame = CGRectMake(0.0, 0.0, badgeWidth, badgeHeight);

    // Wrap the label in a capture-hidden container so it disappears from
    // screenshots/recordings when "Hide UI on Capture" is enabled. The capture
    // hooks redirect the wrapper's subviews into a secure canvas; a bare
    // UILabel's own text can't be hidden that way. When the pref is off the
    // wrapper is a plain passthrough.
    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectMake(xOrigin,
                                                               CGRectGetHeight(container.bounds) - badgeHeight - 2.0,
                                                               badgeWidth,
                                                               badgeHeight)];
    wrapper.tag = kSPKCaptureFollowIndicatorTag;
    [wrapper addSubview:badge];
    [container addSubview:wrapper];
}

%group SPKFollowIndicatorHooks

%hook IGProfileViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![SPKUtils getBoolPref:@"profile_follow_indicator"])
        return;

    NSNumber *cachedStatus = SPKGetFollowStatusForController(self);
    if (cachedStatus) {
        SPKRenderFollowBadge((UIViewController *)self);
        return;
    }

    id profileUser = nil;
    @try {
        profileUser = [(id)self valueForKey:@"user"];
    } @catch (__unused NSException *exception) {
    }
    if (!profileUser)
        return;

    NSString *profilePK = SPKPKFromUserObject(profileUser);
    NSString *currentUserPK = SPKCurrentUserPK();
    if (profilePK.length == 0 || currentUserPK.length == 0 || [profilePK isEqualToString:currentUserPK]) {
        return;
    }

    NSString *path = [NSString stringWithFormat:@"friendships/show/%@/", profilePK];
    __weak UIViewController *weakController = (UIViewController *)self;
    [SPKInstagramAPI sendRequestWithMethod:@"GET"
                                      path:path
                                      body:nil
                                completion:^(NSDictionary *response, NSError *error) {
                                    if (error || !response)
                                        return;
                                    BOOL followsYou = [response[@"followed_by"] boolValue];
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        UIViewController *strongController = weakController;
                                        if (!strongController)
                                            return;
                                        SPKSetFollowStatusForController(strongController, @(followsYou));
                                        SPKRenderFollowBadge(strongController);
                                    });
                                }];
}

- (void)viewDidLayoutSubviews {
    %orig;
    if ([SPKUtils getBoolPref:@"profile_follow_indicator"]) {
        SPKRenderFollowBadge((UIViewController *)self);
    }
}

%end

%end

void SPKInstallFollowIndicatorHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"profile_follow_indicator"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKFollowIndicatorHooks);
    });
}

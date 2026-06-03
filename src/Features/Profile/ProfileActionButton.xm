#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Downloader/Download.h"
#import "../../Shared/MediaPreview/SCIFullScreenMediaPlayer.h"
#import "../../Shared/Gallery/SCIGalleryFile.h"
#import "../../Shared/Gallery/SCIGalleryOriginController.h"
#import "../../Shared/Gallery/SCIGallerySaveMetadata.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../../AssetUtils.h"

static NSString * const kSCIProfileActionButtonDefaultKey = @"profile_action_btn_default_action";
static NSString * const kSCIProfileActionButtonDefaultCopyInfoKey = @"profile_action_btn_default_copy_info_action";
static NSString * const kSCIProfileActionNone = @"none";
static NSString * const kSCIProfileActionCopyInfo = @"copy_info";
static NSString * const kSCIProfileActionViewPicture = @"view_picture";
static NSString * const kSCIProfileActionSharePicture = @"share_picture";
static NSString * const kSCIProfileActionSavePictureToGallery = @"save_picture_gallery";
static NSString * const kSCIProfileActionOpenSettings = @"profile_settings";
static NSString * const kSCIProfileCopyInfoID = @"id";
static NSString * const kSCIProfileCopyInfoUsername = @"username";
static NSString * const kSCIProfileCopyInfoName = @"name";
static NSString * const kSCIProfileCopyInfoBio = @"bio";
static NSString * const kSCIProfileCopyInfoLink = @"link";
static CGFloat const kSCIProfileActionButtonWidth = 24.0;
static CGFloat const kSCIProfileActionButtonHeight = 44.0;
static CGFloat const kSCIProfileActionIconPointSize = 24.0;
static CGFloat const kSCIProfileActionMenuIconPointSize = 22.0;
static const void *kSCIProfileHeaderActionButtonAssocKey = &kSCIProfileHeaderActionButtonAssocKey;
static const void *kSCIProfileHeaderTitleViewKey = &kSCIProfileHeaderTitleViewKey;
static const void *kSCIProfileLastExpectedFrameKey = &kSCIProfileLastExpectedFrameKey;
static const void *kSCIProfileTitleIsCenteredKey = &kSCIProfileTitleIsCenteredKey;
static NSInteger const kSCIProfileActionButtonMaxInstallAttempts = 6;

static UIImage *SCIProfileMenuIcon(NSString *resourceName) {
    return [SCIAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
                                   pointSize:kSCIProfileActionMenuIconPointSize];
}

static id SCIProfileSafeValue(id target, NSString *key) {
    if (!target || key.length == 0) return nil;
    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static NSString *SCIProfileStringValue(id value) {
    if (!value) return nil;
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value length] > 0 ? value : nil;
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *stringValue = [value stringValue];
        return stringValue.length > 0 ? stringValue : nil;
    }
    return nil;
}

static NSNumber *SCIProfileNumberValue(id value) {
    if (!value) return nil;
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value respondsToSelector:@selector(integerValue)]) return @([value integerValue]);
    return nil;
}

static id SCIProfileResolvedUserFromObject(id object, NSInteger depth) {
    if (!object || depth > 3) return nil;

    for (NSString *key in @[@"userGQL", @"profileUser", @"profileController.userGQL", @"profileController.profileUser", @"profileController.user", @"user"]) {
        id value = nil;
        if ([key containsString:@"."]) {
            id current = object;
            for (NSString *part in [key componentsSeparatedByString:@"."]) {
                current = SCIProfileSafeValue(current, part);
                if (!current) break;
            }
            value = current;
        } else {
            value = SCIProfileSafeValue(object, key);
        }
        if (value) return value;
    }

    for (NSString *key in @[@"delegate", @"viewController", @"_viewController", @"nextResponder"]) {
        id nested = SCIProfileSafeValue(object, key);
        if (nested && nested != object) {
            id resolved = SCIProfileResolvedUserFromObject(nested, depth + 1);
            if (resolved) return resolved;
        }
    }

    if ([object isKindOfClass:[UIView class]]) {
        UIViewController *controller = [SCIUtils nearestViewControllerForView:(UIView *)object];
        if (controller && controller != object) {
            id resolved = SCIProfileResolvedUserFromObject(controller, depth + 1);
            if (resolved) return resolved;
        }
    }

    return nil;
}

static NSString *SCIProfileUsername(id user) {
    return SCIProfileStringValue(SCIProfileSafeValue(user, @"username"));
}

static NSString *SCIProfileUserPK(id user) {
    NSString *pk = SCIProfileStringValue(SCIProfileSafeValue(user, @"pk"));
    if (pk.length == 0) pk = SCIProfileStringValue(SCIProfileSafeValue(user, @"id"));
    if (pk.length == 0) pk = [SCIUtils pkFromIGUser:user];
    return pk;
}

static NSString *SCIProfileFullName(id user) {
    NSString *name = SCIProfileStringValue(SCIProfileSafeValue(user, @"fullName"));
    if (name.length == 0) name = SCIProfileStringValue(SCIProfileSafeValue(user, @"full_name"));
    if (name.length == 0) name = SCIProfileStringValue(SCIProfileSafeValue(user, @"name"));
    return name;
}

static NSString *SCIProfileBiography(id user) {
    NSString *bio = SCIProfileStringValue(SCIProfileSafeValue(user, @"biography"));
    if (bio.length == 0) bio = SCIProfileStringValue(SCIProfileSafeValue(user, @"bio"));
    return bio;
}

static NSURL *SCIProfileURL(id user) {
    NSString *username = SCIProfileUsername(user);
    if (username.length == 0) return nil;
    NSString *encoded = [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    if (encoded.length == 0) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/", encoded]];
}

static UIViewController *SCIProfileSourceController(id sourceObject, UIView *sourceView) {
    if ([sourceObject isKindOfClass:[UIViewController class]]) {
        return (UIViewController *)sourceObject;
    }
    UIViewController *controller = nil;
    id value = SCIProfileSafeValue(sourceObject, @"viewController");
    if ([value isKindOfClass:[UIViewController class]]) {
        controller = (UIViewController *)value;
    }
    if (!controller) {
        value = SCIProfileSafeValue(sourceObject, @"_viewController");
        if ([value isKindOfClass:[UIViewController class]]) {
            controller = (UIViewController *)value;
        }
    }
    if (!controller && sourceView) {
        controller = [SCIUtils nearestViewControllerForView:sourceView];
    }
    return controller;
}

@interface SCIProfileHeaderActionButton : SCIActionMenuButton
@property (nonatomic, weak) id sourceObject;
@property (nonatomic, assign) BOOL sciDidConfigure;
@property (nonatomic, assign) BOOL fallbackToCurrentUser;
@end

static void SCIConfigureProfileActionButton(SCIProfileHeaderActionButton *button);

@implementation SCIProfileHeaderActionButton

- (CGSize)sizeThatFits:(CGSize)size {
    (void)size;
    return CGSizeMake(kSCIProfileActionButtonWidth, kSCIProfileActionButtonHeight);
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(kSCIProfileActionButtonWidth, kSCIProfileActionButtonHeight);
}

- (void)setFrame:(CGRect)frame {
    frame.size.width = kSCIProfileActionButtonWidth;
    frame.size.height = kSCIProfileActionButtonHeight;
    [super setFrame:frame];
}

- (void)setBounds:(CGRect)bounds {
    bounds.size.width = kSCIProfileActionButtonWidth;
    bounds.size.height = kSCIProfileActionButtonHeight;
    [super setBounds:bounds];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && !self.sciDidConfigure) {
        self.sciDidConfigure = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIConfigureProfileActionButton(self);
        });
    }
}

- (void)setSourceObject:(id)sourceObject {
    _sourceObject = sourceObject;
    _sciDidConfigure = NO;
    if (self.window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIConfigureProfileActionButton(self);
        });
    }
}

- (void)setMenu:(UIMenu *)menu {
    [super setMenu:menu];
    self.sciDidConfigure = YES;
}

@end

static SCIActionButtonContext *SCIProfileActionContext(SCIProfileHeaderActionButton *button) {
    SCIActionButtonContext *context = [[SCIActionButtonContext alloc] init];
    __weak SCIProfileHeaderActionButton *weakButton = button;
    context.source = SCIActionButtonSourceProfile;
    context.view = button;
    context.controller = SCIProfileSourceController(button.sourceObject ?: button, button);
    context.settingsTitle = SCIActionButtonTopicTitleForSource(SCIActionButtonSourceProfile);
    context.supportedActions = SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceProfile);
    context.mediaResolver = ^id (__unused SCIActionButtonContext *resolvedContext) {
        SCIProfileHeaderActionButton *strongButton = weakButton;
        id user = SCIProfileResolvedUserFromObject(strongButton.sourceObject ?: strongButton, 0);
        if (!user && strongButton.fallbackToCurrentUser) {
            user = SCIProfileSafeValue([SCIUtils activeUserSession], @"user");
        }
        return user;
    };
    context.visibilityResolver = ^BOOL(__unused SCIActionButtonContext *resolvedContext,
                                       NSString *identifier,
                                       __unused id media,
                                       NSArray *entries,
                                       __unused NSInteger currentIndex) {
        if ([identifier isEqualToString:kSCIActionProfileCopyInfo]) return YES;
        if ([identifier isEqualToString:kSCIActionOpenTopicSettings]) return YES;
        return entries.count > 0;
    };
    return context;
}

static void SCIConfigureProfileActionButton(SCIProfileHeaderActionButton *button) {
    if (!button) return;

    id user = SCIProfileResolvedUserFromObject(button.sourceObject ?: button, 0);
    if (!user && button.fallbackToCurrentUser) {
        user = SCIProfileSafeValue([SCIUtils activeUserSession], @"user");
    }
    if (!user) {
        button.hidden = YES;
        return;
    }

    button.hidden = NO;
    SCIApplyButtonStyle(button, SCIActionButtonSourceProfile);
    SCIConfigureActionButton(button, SCIProfileActionContext(button));
}

static SCIProfileHeaderActionButton *SCIProfileBuildHeaderActionButton(id sourceObject) {
    SCIProfileHeaderActionButton *button = [[SCIProfileHeaderActionButton alloc] initWithSymbol:@""
                                                                                       pointSize:kSCIProfileActionIconPointSize
                                                                                        diameter:kSCIProfileActionButtonWidth];
    button.accessibilityIdentifier = @"scinsta-profile-action-button";
    button.translatesAutoresizingMaskIntoConstraints = YES;
    button.frame = CGRectMake(0.0, 0.0, kSCIProfileActionButtonWidth, kSCIProfileActionButtonHeight);
    button.bounds = CGRectMake(0.0, 0.0, kSCIProfileActionButtonWidth, kSCIProfileActionButtonHeight);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsZero;
    button.imageEdgeInsets = UIEdgeInsetsZero;
    button.tintColor = [UIColor labelColor];
    SCIApplyButtonStyle(button, SCIActionButtonSourceProfile);
    button.sourceObject = sourceObject;
    return button;
}

static SCIProfileHeaderActionButton *SCIProfileGetOrCreateActionButton(UIView *headerView) {
    SCIProfileHeaderActionButton *button = objc_getAssociatedObject(headerView, kSCIProfileHeaderActionButtonAssocKey);
    if (![button isKindOfClass:[SCIProfileHeaderActionButton class]]) {
        button = SCIProfileBuildHeaderActionButton(headerView);
        objc_setAssociatedObject(headerView,
                                 kSCIProfileHeaderActionButtonAssocKey,
                                 button,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (button.sourceObject != headerView) {
        button.sourceObject = headerView;
    }
    return button;
}

static CGRect SCIProfileGetLeftmostRightButtonFrame(UIView *view, UIView *headerView, CGRect currentFrame) {
    if (!view || !headerView) return currentFrame;
    if ([view.accessibilityIdentifier isEqualToString:@"scinsta-profile-action-button"]) return currentFrame;
    if (view.hidden || view.alpha <= 0.01) return currentFrame;

    UIView *titleView = objc_getAssociatedObject(headerView, kSCIProfileHeaderTitleViewKey);
    if (titleView && (view == titleView || [view isDescendantOfView:titleView])) {
        return currentFrame;
    }

    BOOL isLeafOrControl = (view.subviews.count == 0) || 
                           [view isKindOfClass:[UIControl class]] || 
                           [view isKindOfClass:[UIButton class]] || 
                           [view isKindOfClass:[UILabel class]] || 
                           [view isKindOfClass:[UIImageView class]];

    if (isLeafOrControl && view != headerView) {
        CGRect rect = [view convertRect:view.bounds toView:headerView];
        CGFloat w = CGRectGetWidth(headerView.bounds);
        if (rect.size.width > 2.0 && rect.size.height > 2.0 &&
            CGRectIntersectsRect(headerView.bounds, rect) &&
            rect.origin.x >= (w * 0.5 + 10.0)) {
            if (CGRectIsEmpty(currentFrame) || rect.origin.x < currentFrame.origin.x) {
                currentFrame = rect;
            }
        }
    }

    for (UIView *subview in view.subviews) {
        currentFrame = SCIProfileGetLeftmostRightButtonFrame(subview, headerView, currentFrame);
    }
    return currentFrame;
}

static CGRect SCIProfileGetAnyButtonFrame(UIView *view, UIView *headerView, CGRect currentFrame) {
    if (!view || !headerView) return currentFrame;
    if ([view.accessibilityIdentifier isEqualToString:@"scinsta-profile-action-button"]) return currentFrame;
    if (view.hidden || view.alpha <= 0.01) return currentFrame;

    UIView *titleView = objc_getAssociatedObject(headerView, kSCIProfileHeaderTitleViewKey);
    if (titleView && (view == titleView || [view isDescendantOfView:titleView])) {
        return currentFrame;
    }

    BOOL isLeafOrControl = (view.subviews.count == 0) || 
                           [view isKindOfClass:[UIControl class]] || 
                           [view isKindOfClass:[UIButton class]] || 
                           [view isKindOfClass:[UILabel class]] || 
                           [view isKindOfClass:[UIImageView class]];

    if (isLeafOrControl && view != headerView) {
        CGRect rect = [view convertRect:view.bounds toView:headerView];
        if (rect.size.width > 2.0 && rect.size.height > 2.0 && CGRectIntersectsRect(headerView.bounds, rect)) {
            return rect;
        }
    }

    for (UIView *subview in view.subviews) {
        CGRect found = SCIProfileGetAnyButtonFrame(subview, headerView, currentFrame);
        if (!CGRectIsEmpty(found)) return found;
    }
    return currentFrame;
}

static BOOL SCIProfileIsOwnProfile(id headerView) {
    id user = SCIProfileResolvedUserFromObject(headerView, 0);
    if (!user) return NO;
    NSString *profilePK = SCIProfileUserPK(user);
    NSString *currentUserPK = [SCIUtils currentUserPK];
    if (profilePK.length > 0 && currentUserPK.length > 0 && [profilePK isEqualToString:currentUserPK]) {
        return YES;
    }
    return NO;
}

static void SCIProfilePlaceActionButton(UIView *headerView, BOOL titleIsCentered) {
    if (![SCIUtils getBoolPref:@"profile_action_btn"]) {
        SCIProfileHeaderActionButton *button = objc_getAssociatedObject(headerView, kSCIProfileHeaderActionButtonAssocKey);
        if (button) {
            button.hidden = YES;
            [button removeFromSuperview];
            objc_setAssociatedObject(button, kSCIProfileLastExpectedFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    BOOL ownProfile = titleIsCentered || SCIProfileIsOwnProfile(headerView);
    
    // Completely remove the action button from the own profile
    if (ownProfile) {
        SCIProfileHeaderActionButton *button = objc_getAssociatedObject(headerView, kSCIProfileHeaderActionButtonAssocKey);
        if (button) {
            button.hidden = YES;
            [button removeFromSuperview];
            objc_setAssociatedObject(button, kSCIProfileLastExpectedFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    
    // For other profiles: manual positioning on the right side
    SCIProfileHeaderActionButton *button = SCIProfileGetOrCreateActionButton(headerView);
    button.fallbackToCurrentUser = NO;
    
    SCIConfigureProfileActionButton(button);

    if (button.hidden) {
        [button removeFromSuperview];
        objc_setAssociatedObject(button, kSCIProfileLastExpectedFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (button.superview != headerView) {
        [headerView addSubview:button];
    }

    CGFloat w = CGRectGetWidth(headerView.bounds);
    CGFloat h = CGRectGetHeight(headerView.bounds);
    if (w < 60.0 || h < 20.0) return;

    CGFloat btnW = kSCIProfileActionButtonWidth;
    CGFloat btnH = kSCIProfileActionButtonHeight;
    
    CGFloat x;
    CGFloat centerY;
    
    // Other profiles: place on RIGHT side relative to existing buttons
    CGRect anchorFrame = SCIProfileGetLeftmostRightButtonFrame(headerView, headerView, CGRectZero);
    
    if (!CGRectIsEmpty(anchorFrame)) {
        if (anchorFrame.size.width <= 30.0) {
            // Icon buttons (like Bell, More, Share) - space using center-to-center distance (44pt)
            CGFloat centerSpacing = 44.0;
            x = CGRectGetMidX(anchorFrame) - centerSpacing - (btnW * 0.5);
        } else {
            // Text buttons (like Follow) - space relative to the visual left edge with a clean gap
            CGFloat spacing = 10.0;
            x = anchorFrame.origin.x - spacing - btnW;
        }
        centerY = CGRectGetMidY(anchorFrame);
    } else {
        CGRect anyBtnFrame = SCIProfileGetAnyButtonFrame(headerView, headerView, CGRectZero);
        if (!CGRectIsEmpty(anyBtnFrame)) {
            centerY = CGRectGetMidY(anyBtnFrame);
        } else {
            centerY = h - 22.0;
        }
        x = w - btnW - 12.0;
    }
    
    CGFloat y = centerY - btnH * 0.5;
    CGRect expectedFrame = CGRectMake(floor(x), floor(y), btnW, btnH);
    
    NSValue *lastVal = objc_getAssociatedObject(button, kSCIProfileLastExpectedFrameKey);
    CGRect lastFrame = lastVal ? [lastVal CGRectValue] : CGRectZero;
    
    if (button.superview == headerView && CGRectEqualToRect(expectedFrame, lastFrame)) {
        return; // Avoid layout churn and layout resetting mid-animation
    }
    
    button.frame = expectedFrame;
    objc_setAssociatedObject(button, kSCIProfileLastExpectedFrameKey, [NSValue valueWithCGRect:expectedFrame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [headerView bringSubviewToFront:button];
}

static void (*orig_profileHeaderConfigure)(id, SEL, id, id, id, BOOL);

static void hooked_configureProfileHeaderView(id self, SEL _cmd, id titleView, id leftButtons, id rightButtons, BOOL titleIsCentered) {
    // For own profile, inject our button into leftButtons array
    BOOL ownProfile = titleIsCentered || SCIProfileIsOwnProfile(self);
    
    if (ownProfile && [SCIUtils getBoolPref:@"profile_action_btn"]) {
        // Create our button as a proper UIBarButtonItem or view for injection
        SCIProfileHeaderActionButton *button = SCIProfileGetOrCreateActionButton((UIView *)self);
        button.fallbackToCurrentUser = YES;
        SCIConfigureProfileActionButton(button);
        
        if (!button.hidden) {
            // Inject into leftButtons array (after the + button)
            if ([leftButtons isKindOfClass:[NSArray class]]) {
                NSMutableArray *modifiedLeftButtons = [leftButtons mutableCopy];
                [modifiedLeftButtons addObject:button];
                leftButtons = [modifiedLeftButtons copy];
            } else if (leftButtons == nil) {
                leftButtons = @[button];
            }
        }
    }
    
    orig_profileHeaderConfigure(self, _cmd, titleView, leftButtons, rightButtons, titleIsCentered);
    
    // Save titleView so our layout scanner can ignore it and its subviews
    objc_setAssociatedObject(self, kSCIProfileHeaderTitleViewKey, titleView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Save titleIsCentered state for use in layoutSubviews
    objc_setAssociatedObject(self, kSCIProfileTitleIsCenteredKey, @(titleIsCentered), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    UIView *header = (UIView *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SCIProfilePlaceActionButton(header, titleIsCentered);
    });
}

static void (*orig_profileHeaderLayoutSubviews)(id, SEL);

static void hooked_profileHeaderLayoutSubviews(id self, SEL _cmd) {
    if (orig_profileHeaderLayoutSubviews) orig_profileHeaderLayoutSubviews(self, _cmd);
    if ([self isKindOfClass:[UIView class]]) {
        // Use saved titleIsCentered state from configure hook
        NSNumber *savedTitleIsCentered = objc_getAssociatedObject(self, kSCIProfileTitleIsCenteredKey);
        BOOL titleIsCentered = savedTitleIsCentered ? savedTitleIsCentered.boolValue : NO;
        SCIProfilePlaceActionButton((UIView *)self, titleIsCentered);
    }
}

static BOOL hooksInstalled = NO;
static BOOL retryScheduled = NO;
static NSInteger installAttempts = 0;

extern "C" void SCIInstallProfileActionButtonHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"profile_action_btn"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (hooksInstalled) return;

        installAttempts += 1;
        Class headerClass = objc_getClass("IGProfileNavigationSwift.IGProfileNavigationHeaderView");
        if (!headerClass) headerClass = objc_getClass("_TtC24IGProfileNavigationSwift29IGProfileNavigationHeaderView");
        if (!headerClass) headerClass = objc_getClass("IGProfileNavigationHeaderView");
        if (!headerClass) {
            SCILog(@"ProfileBtn", @"Install target unavailable attempt=%ld", (long)installAttempts);
            if (!retryScheduled && installAttempts < kSCIProfileActionButtonMaxInstallAttempts) {
                retryScheduled = YES;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    @synchronized([SCIProfileHeaderActionButton class]) {
                        retryScheduled = NO;
                    }
                    SCIInstallProfileActionButtonHooksIfEnabled();
                });
            }
            return;
        }

        BOOL configureHooked = NO;
        BOOL layoutHooked = NO;
        SEL configureSelector = @selector(configureWithTitleView:leftButtons:rightButtons:titleIsCentered:);
        if ([headerClass instancesRespondToSelector:configureSelector]) {
            MSHookMessageEx(headerClass, configureSelector, (IMP)hooked_configureProfileHeaderView, (IMP *)&orig_profileHeaderConfigure);
            configureHooked = YES;
        }

        SEL layoutSelector = @selector(layoutSubviews);
        if ([headerClass instancesRespondToSelector:layoutSelector]) {
            MSHookMessageEx(headerClass, layoutSelector, (IMP)hooked_profileHeaderLayoutSubviews, (IMP *)&orig_profileHeaderLayoutSubviews);
            layoutHooked = YES;
        }

        hooksInstalled = configureHooked || layoutHooked;
        SCILog(@"ProfileBtn", @"Install class=%@ configure=%@ layout=%@ installed=%@",
               NSStringFromClass(headerClass),
               configureHooked ? @"YES" : @"NO",
               layoutHooked ? @"YES" : @"NO",
               hooksInstalled ? @"YES" : @"NO");
    });
}

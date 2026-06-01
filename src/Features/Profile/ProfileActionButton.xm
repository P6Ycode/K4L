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
static CGFloat const kSCIProfileLegacyActionButtonRightGap = 24.0;
static const void *kSCIProfileHeaderActionButtonAssocKey = &kSCIProfileHeaderActionButtonAssocKey;

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

    for (NSString *key in @[@"user", @"userGQL", @"profileUser", @"profileController.user", @"profileController.userGQL"]) {
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
        return SCIProfileResolvedUserFromObject(strongButton.sourceObject ?: strongButton, 0);
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
    if (!user) {
        button.hidden = YES;
        return;
    }

    button.hidden = NO;
    SCIApplyButtonStyle(button, SCIActionButtonSourceProfile);
    SCIConfigureActionButton(button, SCIProfileActionContext(button));
}

static id SCIProfileNavigationButtonWrapperForView(UIView *view, id sampleWrapper) {
    Class wrapperClass = NSClassFromString(@"IGProfileNavigationHeaderViewButtonSwift.IGProfileNavigationHeaderViewButton");
    if (!wrapperClass || !view) return nil;

    NSInteger type = 0;
    id typeValue = SCIProfileSafeValue(sampleWrapper, @"type");
    if ([typeValue respondsToSelector:@selector(integerValue)]) {
        type = [typeValue integerValue];
    }

    id wrapper = [wrapperClass alloc];
    SEL initSelector = @selector(initWithType:view:);
    if (![wrapper respondsToSelector:initSelector]) return nil;
    return ((id (*)(id, SEL, NSInteger, id))objc_msgSend)(wrapper, initSelector, type, view);
}

static BOOL SCIProfileButtonsContainSCInstaButton(NSArray *buttons) {
    for (id wrapper in buttons) {
        UIView *view = SCIProfileSafeValue(wrapper, @"view");
        if ([view.accessibilityIdentifier isEqualToString:@"scinsta-profile-action-button"]) {
            return YES;
        }
    }
    return NO;
}

static void (*orig_profileHeaderConfigure)(id, SEL, id, id, id, BOOL);
static void (*orig_profileHeaderLayoutSubviews)(id, SEL);

static SCIProfileHeaderActionButton *SCIProfileBuildHeaderActionButton(id sourceObject) {
    SCIProfileHeaderActionButton *button = [[SCIProfileHeaderActionButton alloc] initWithSymbol:@""
                                                                                      pointSize:kSCIProfileActionIconPointSize
                                                                                       diameter:kSCIProfileActionButtonHeight];
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

static NSArray *SCIProfilePatchedRightButtons(id self, NSArray *leftButtons, NSArray *rightButtons) {
    if (![SCIUtils getBoolPref:@"profile_action_btn"]) return rightButtons;
    if (SCIProfileButtonsContainSCInstaButton(rightButtons)) return rightButtons;
    if (SCIProfileResolvedUserFromObject(self, 0) == nil) return rightButtons;

    SCIProfileHeaderActionButton *button = objc_getAssociatedObject(self, kSCIProfileHeaderActionButtonAssocKey);
    if (![button isKindOfClass:[SCIProfileHeaderActionButton class]]) {
        button = SCIProfileBuildHeaderActionButton(self);
        objc_setAssociatedObject(self,
                                 kSCIProfileHeaderActionButtonAssocKey,
                                 button,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (button.sourceObject != self) {
        button.sourceObject = self;
    }
    SCIConfigureProfileActionButton(button);

    id sample = rightButtons.firstObject ?: leftButtons.firstObject;
    id wrapper = SCIProfileNavigationButtonWrapperForView(button, sample);
    if (!wrapper) return rightButtons;

    NSMutableArray *patched = rightButtons ? [rightButtons mutableCopy] : [NSMutableArray array];
    [patched insertObject:wrapper atIndex:0];
    return patched;
}

static void hooked_configureProfileHeaderView(id self, SEL _cmd, id titleView, id leftButtons, id rightButtons, BOOL titleIsCentered) {
    if (titleIsCentered) {
        orig_profileHeaderConfigure(self, _cmd, titleView, leftButtons, rightButtons, titleIsCentered);
        return;
    }

    NSArray *leftArray = [leftButtons isKindOfClass:[NSArray class]] ? (NSArray *)leftButtons : @[];
    NSArray *rightArray = [rightButtons isKindOfClass:[NSArray class]] ? (NSArray *)rightButtons : @[];
    NSArray *patchedRight = SCIProfilePatchedRightButtons(self, leftArray, rightArray);
    orig_profileHeaderConfigure(self, _cmd, titleView, leftButtons, patchedRight, titleIsCentered);
}

static SCIProfileHeaderActionButton *SCIProfileExistingLegacyActionButton(UIView *container) {
    for (UIView *subview in container.subviews) {
        if ([subview.accessibilityIdentifier isEqualToString:@"scinsta-profile-action-button"] &&
            [subview isKindOfClass:[SCIProfileHeaderActionButton class]]) {
            return (SCIProfileHeaderActionButton *)subview;
        }
    }
    return nil;
}

static BOOL SCIProfileViewTreeContainsActionButton(UIView *view) {
    if ([view.accessibilityIdentifier isEqualToString:@"scinsta-profile-action-button"]) return YES;
    for (UIView *subview in view.subviews) {
        if (SCIProfileViewTreeContainsActionButton(subview)) return YES;
    }
    return NO;
}

static UIView *SCIProfileLegacyMoreButtonInContainer(UIView *container) {
    UIView *best = nil;
    CGFloat bestMinX = -CGFLOAT_MAX;
    for (UIView *subview in container.subviews) {
        NSString *className = NSStringFromClass(subview.class);
        if (![className isEqualToString:@"IGNavigationBarButtonView"]) continue;
        CGFloat minX = CGRectGetMinX(subview.frame);
        if (!best || minX > bestMinX) {
            best = subview;
            bestMinX = minX;
        }
    }
    return best;
}

static UIView *SCIProfileLegacyButtonContainer(UIView *headerView) {
    if (SCIProfileLegacyMoreButtonInContainer(headerView)) return headerView;
    for (UIView *subview in headerView.subviews) {
        if (SCIProfileLegacyMoreButtonInContainer(subview)) return subview;
    }
    return nil;
}

static CGFloat SCIProfileLegacyRightClusterMinX(UIView *container) {
    CGFloat midX = CGRectGetMidX(container.bounds);
    CGFloat minX = CGFLOAT_MAX;
    for (UIView *subview in container.subviews) {
        if ([subview.accessibilityIdentifier isEqualToString:@"scinsta-profile-action-button"]) continue;

        NSString *className = NSStringFromClass(subview.class);
        BOOL isNavigationButton = [className isEqualToString:@"IGNavigationBarButtonView"] ||
                                  [className isEqualToString:@"IGBadgedNavigationButton"];
        if (!isNavigationButton) continue;
        if (CGRectGetMidX(subview.frame) < midX) continue;
        minX = MIN(minX, CGRectGetMinX(subview.frame));
    }
    return minX == CGFLOAT_MAX ? 0.0 : minX;
}

static CGRect SCIProfileLegacyActionButtonFrame(UIView *container, UIView *moreButton) {
    CGFloat y = CGRectGetMinY(moreButton.frame);
    CGFloat rightClusterMinX = SCIProfileLegacyRightClusterMinX(container);
    CGFloat x = rightClusterMinX - kSCIProfileActionButtonWidth - kSCIProfileLegacyActionButtonRightGap;
    if (x < 0.0) x = CGRectGetMinX(moreButton.frame) - kSCIProfileActionButtonWidth - kSCIProfileLegacyActionButtonRightGap;
    if (x < 0.0) x = 0.0;
    return CGRectMake(floor(x),
                      floor(y),
                      kSCIProfileActionButtonWidth,
                      kSCIProfileActionButtonHeight);
}

static BOOL SCIProfileActionFrameMatches(SCIProfileHeaderActionButton *button, CGRect frame) {
    if (![button isKindOfClass:[SCIProfileHeaderActionButton class]] || button.hidden || !button.superview) return NO;
    return ABS(CGRectGetMinX(button.frame) - CGRectGetMinX(frame)) < 0.5 &&
           ABS(CGRectGetMinY(button.frame) - CGRectGetMinY(frame)) < 0.5 &&
           ABS(CGRectGetWidth(button.frame) - CGRectGetWidth(frame)) < 0.5 &&
           ABS(CGRectGetHeight(button.frame) - CGRectGetHeight(frame)) < 0.5;
}

static void SCIProfileLayoutLegacyActionButton(SCIProfileHeaderActionButton *button, UIView *container, UIView *moreButton) {
    button.frame = SCIProfileLegacyActionButtonFrame(container, moreButton);
}

static void SCIProfileInstallLegacyActionButtonIfNeeded(UIView *headerView) {
    if (![SCIUtils getBoolPref:@"profile_action_btn"]) return;
    if (SCIProfileResolvedUserFromObject(headerView, 0) == nil) return;

    UIView *container = SCIProfileLegacyButtonContainer(headerView);
    UIView *moreButton = container ? SCIProfileLegacyMoreButtonInContainer(container) : nil;
    if (!container || !moreButton) return;

    SCIProfileHeaderActionButton *button = SCIProfileExistingLegacyActionButton(container);
    if (!button && SCIProfileViewTreeContainsActionButton(headerView)) return;
    CGRect expectedFrame = SCIProfileLegacyActionButtonFrame(container, moreButton);
    if (button && button.sourceObject == headerView && SCIProfileActionFrameMatches(button, expectedFrame)) return;
    if (!button) {
        button = SCIProfileBuildHeaderActionButton(headerView);
        [container addSubview:button];
    } else {
        button.sourceObject = headerView;
    }

    SCIProfileLayoutLegacyActionButton(button, container, moreButton);
    SCIConfigureProfileActionButton(button);
}

static void hooked_profileHeaderLayoutSubviews(id self, SEL _cmd) {
    if (orig_profileHeaderLayoutSubviews) orig_profileHeaderLayoutSubviews(self, _cmd);
    if ([self isKindOfClass:[UIView class]]) {
        SCIProfileInstallLegacyActionButtonIfNeeded((UIView *)self);
    }
}

extern "C" void SCIInstallProfileActionButtonHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"profile_action_btn"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class headerClass = objc_getClass("IGProfileNavigationSwift.IGProfileNavigationHeaderView");
        if (!headerClass) headerClass = objc_getClass("IGProfileNavigationHeaderView");
        if (!headerClass) return;

        SEL configureSelector = @selector(configureWithTitleView:leftButtons:rightButtons:titleIsCentered:);
        if ([headerClass instancesRespondToSelector:configureSelector]) {
            MSHookMessageEx(headerClass, configureSelector, (IMP)hooked_configureProfileHeaderView, (IMP *)&orig_profileHeaderConfigure);
        }

        SEL layoutSelector = @selector(layoutSubviews);
        if ([headerClass instancesRespondToSelector:layoutSelector]) {
            MSHookMessageEx(headerClass, layoutSelector, (IMP)hooked_profileHeaderLayoutSubviews, (IMP *)&orig_profileHeaderLayoutSubviews);
        }
    });
}

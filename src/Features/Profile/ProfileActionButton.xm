#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../Utils.h"
#import "../../InstagramHeaders.h"

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
static CGFloat const kSCIProfileActionButtonWidth = 44.0;
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
@property (nonatomic, strong) UIVisualEffectView *sciGlassView;
@property (nonatomic, assign) BOOL sciGlassUnavailable;
@property (nonatomic, strong) CADisplayLink *sciGlassSyncLink;
@end

static void SCIConfigureProfileActionButton(SCIProfileHeaderActionButton *button);
static void SCIProfileUpdateGlass(SCIProfileHeaderActionButton *button, UIView *headerView);

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
    // The Liquid Glass bubble fades with scroll offset, which doesn't always
    // re-run the header's layoutSubviews (e.g. scrolling back up to the top). A
    // display link keeps our bubble's alpha tracking IG's continuously while the
    // button is on screen; it's paused as soon as we leave the window.
    if (self.window) {
        [self sciStartGlassSync];
    } else {
        [self sciStopGlassSync];
    }
}

- (void)sciStartGlassSync {
    if (self.sciGlassUnavailable || self.sciGlassSyncLink) return;
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(sciGlassSyncTick:)];
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.sciGlassSyncLink = link;
}

- (void)sciStopGlassSync {
    [self.sciGlassSyncLink invalidate];
    self.sciGlassSyncLink = nil;
}

- (void)sciGlassSyncTick:(CADisplayLink *)link {
    UIView *header = self.superview;
    if (!self.window || ![header isKindOfClass:[UIView class]]) {
        [self sciStopGlassSync];
        return;
    }
    if (self.sciGlassUnavailable) {
        [self sciStopGlassSync];
        return;
    }
    SCIProfileUpdateGlass(self, header);
}

- (void)dealloc {
    [_sciGlassSyncLink invalidate];
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

static void SCIProfileCollectTrailingControls(UIView *view, UIView *headerView, NSMutableArray<NSValue *> *out) {
    if (!view || !headerView) return;
    if ([view.accessibilityIdentifier isEqualToString:@"scinsta-profile-action-button"]) return;
    if (view.hidden) return;

    UIView *titleView = objc_getAssociatedObject(headerView, kSCIProfileHeaderTitleViewKey);
    if (titleView && (view == titleView || [view isDescendantOfView:titleView])) {
        return;
    }

    // We anchor only to real controls (the More / Follow / bell buttons). Bare
    // labels (the username) and image views (the verified badge) are intentionally
    // ignored so they can never become the anchor.
    BOOL isControl = ([view isKindOfClass:[UIControl class]] ||
                      [view isKindOfClass:[UIButton class]]) &&
                     ![view isKindOfClass:[UILabel class]];

    if (isControl && view != headerView) {
        CGFloat w = CGRectGetWidth(headerView.bounds);

        // Prefer the control's tight wrapper (its superview) as the slot. On iOS 26
        // the More and Follow buttons live as alpha-crossfaded siblings inside an
        // IGNavigationBarButtonView wrapper, and IG animates THAT wrapper's frame to
        // match whichever button is active. The buttons' own alpha is unreliable
        // mid-crossfade, so anchoring to the wrapper avoids the dead-zone where no
        // button reads as visible and the action button freezes / overlaps Follow.
        UIView *slot = view;
        UIView *superview = view.superview;
        if (superview && superview != headerView) {
            CGRect superRect = [superview convertRect:superview.bounds toView:headerView];
            if (superRect.size.width > 2.0 && superRect.size.width < w * 0.40) {
                slot = superview; // tight per-button wrapper
            }
        }

        // If we couldn't fall back to a stable wrapper, ignore a control that is
        // currently invisible (the inactive crossfade button in an un-wrapped layout).
        if (slot == view && view.alpha <= 0.01) {
            return;
        }

        CGRect rect = [slot convertRect:slot.bounds toView:headerView];
        if (rect.size.width > 2.0 && rect.size.height > 2.0 &&
            CGRectIntersectsRect(headerView.bounds, rect) &&
            rect.origin.x >= (w * 0.5 + 10.0)) {
            [out addObject:[NSValue valueWithCGRect:rect]];
        }
        return; // don't descend into a control's internals
    }

    for (UIView *subview in view.subviews) {
        SCIProfileCollectTrailingControls(subview, headerView, out);
    }
}

// Resolve the anchor we place the action button to the left of: the leftmost
// control belonging to the far-right nav cluster. Controls far to the left of
// the rightmost edge (the verified badge sitting next to the username, a
// re-centered title, etc.) are rejected so the button always tracks the real
// "..." / bell trailing buttons.
static CGRect SCIProfileGetTrailingAnchorFrame(UIView *headerView) {
    if (!headerView) return CGRectZero;

    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    SCIProfileCollectTrailingControls(headerView, headerView, frames);
    if (frames.count == 0) return CGRectZero;

    CGFloat trailingEdge = -CGFLOAT_MAX;
    for (NSValue *value in frames) {
        trailingEdge = MAX(trailingEdge, CGRectGetMaxX(value.CGRectValue));
    }

    CGFloat const clusterWidth = 140.0; // room for ~3 icon buttons next to "..."
    CGRect anchor = CGRectZero;
    for (NSValue *value in frames) {
        CGRect rect = value.CGRectValue;
        if (CGRectGetMaxX(rect) < trailingEdge - clusterWidth) continue;
        if (CGRectIsEmpty(anchor) || rect.origin.x < anchor.origin.x) {
            anchor = rect;
        }
    }
    return anchor;
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

// MARK: - Liquid glass background (iOS 26)

// IG's nav buttons render a Liquid Glass "bubble" behind the icon that fades in
// with scroll (alpha 0 flush -> 1 collapsed). That fade lives on the private
// IGLiquidGlass *TouchForwardingVisualEffectView*. We mirror its alpha so our
// overlay button matches. Returns < 0 when no glass exists (iOS < 26 / flush).
static void SCIProfileAccumulateGlassAlpha(UIView *view, CGFloat *maxAlpha) {
    if (!view) return;
    if ([NSStringFromClass([view class]) containsString:@"TouchForwardingVisualEffectView"]) {
        CGFloat alpha = view.alpha;
        if (alpha > *maxAlpha) *maxAlpha = alpha;
    }
    for (UIView *subview in view.subviews) {
        SCIProfileAccumulateGlassAlpha(subview, maxAlpha);
    }
}

static CGFloat SCIProfileHeaderGlassProgress(UIView *headerView) {
    CGFloat maxAlpha = -1.0;
    SCIProfileAccumulateGlassAlpha(headerView, &maxAlpha);
    return maxAlpha;
}

// A UIGlassEffect-backed circle. UIGlassEffect ships in the iOS 26 SDK only, so
// we instantiate it at runtime; on older systems the class is absent and we
// return nil (the button stays a bare icon, which already matches pre-26 IG).
static UIVisualEffectView *SCIProfileMakeGlassBackground(void) {
    Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
    if (!glassEffectClass) return nil;

    UIVisualEffect *effect = nil;
    @try {
        effect = [[glassEffectClass alloc] init];
        // Reactive glass: stretches / highlights on touch like IG's own buttons.
        [effect setValue:@YES forKey:@"interactive"];
        // Default glass reads as clear. Tint it with IG's primary text colour
        // inverted: that's light in light mode / dark in dark mode (so it reads like
        // IG's fill) and is the exact opposite of the icon colour, keeping the glyph
        // legible. Opacity is easy to tune if it reads too strong/weak on device.
        UIColor *tint = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            UIColor *primary = [[SCIUtils SCIColor_InstagramPrimaryText] resolvedColorWithTraitCollection:traits];
            // Take only IG's hue; the primary text colour is fully opaque, so its
            // own alpha is ignored (NULL) in favour of our own light tint strength.
            CGFloat r = 0.0, g = 0.0, b = 0.0;
            [primary getRed:&r green:&g blue:&b alpha:NULL];
            return [UIColor colorWithRed:(1.0 - r) green:(1.0 - g) blue:(1.0 - b) alpha:0.5];
        }];
        [effect setValue:tint forKey:@"tintColor"];
    } @catch (__unused NSException *exception) {
    }
    if (![effect isKindOfClass:[UIVisualEffect class]]) return nil;

    UIVisualEffectView *glassView = [[UIVisualEffectView alloc] initWithEffect:effect];
    glassView.userInteractionEnabled = NO;
    glassView.clipsToBounds = YES;
    glassView.layer.cornerCurve = kCACornerCurveContinuous;
    glassView.accessibilityIdentifier = @"scinsta-profile-action-glass";
    return glassView;
}

static void SCIProfileUpdateGlass(SCIProfileHeaderActionButton *button, UIView *headerView) {
    if (!button || button.sciGlassUnavailable) return;

    UIVisualEffectView *glassView = button.sciGlassView;
    if (!glassView) {
        glassView = SCIProfileMakeGlassBackground();
        if (!glassView) {
            button.sciGlassUnavailable = YES; // iOS < 26: don't retry every layout
            return;
        }
        button.sciGlassView = glassView;
    }

    // Host the glass INSIDE the chrome canvas (the same secure CanvasView the icon
    // lives in) so "hide UI on capture" redacts the bubble too. iconView.superview
    // is that content container; fall back to the button before the canvas attaches.
    UIView *host = button.iconView.superview ?: button;
    if (glassView.superview != host) {
        [host insertSubview:glassView atIndex:0];
    }
    [host sendSubviewToBack:glassView]; // stay behind the icon (and bubble)

    CGRect bounds = host.bounds;
    glassView.frame = bounds;
    glassView.layer.cornerRadius = MIN(bounds.size.width, bounds.size.height) / 2.0;

    CGFloat progress = SCIProfileHeaderGlassProgress(headerView);
    glassView.alpha = progress > 0.0 ? MIN(progress, 1.0) : 0.0;
}

// MARK: - Long-username overlap

static UIView *SCIProfileFindTitleView(UIView *view) {
    if ([view.accessibilityIdentifier isEqualToString:@"scinsta-profile-action-button"]) return nil;
    if ([NSStringFromClass([view class]) containsString:@"TitleView"]) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        UIView *found = SCIProfileFindTitleView(subview);
        if (found) return found;
    }
    return nil;
}

static UILabel *SCIProfileFindUsernameLabel(UIView *view) {
    if ([view isKindOfClass:[UILabel class]] && [(UILabel *)view text].length > 0) {
        return (UILabel *)view;
    }
    for (UIView *subview in view.subviews) {
        UILabel *found = SCIProfileFindUsernameLabel(subview);
        if (found) return found;
    }
    return nil;
}

// Because our button is an overlay (not in IG's rightButtons array), IG sizes the
// username with no knowledge of it, so a long name runs under the button. We clamp
// the title view (and its label) so it ends before us and truncates with "…",
// mirroring IG's native behaviour when a trailing button is present. Runs after
// IG's own layout each pass, so short names are left untouched / auto-reset.
static void SCIProfileClampTitleToButton(UIView *headerView, SCIProfileHeaderActionButton *button) {
    if (!headerView || !button || button.hidden) return;

    CGRect buttonInHeader = [button convertRect:button.bounds toView:headerView];
    if (CGRectGetMinX(buttonInHeader) <= 1.0) return; // not positioned yet
    CGFloat limitX = CGRectGetMinX(buttonInHeader) - 8.0; // clean gap before our button

    UIView *titleView = SCIProfileFindTitleView(headerView);
    if (!titleView) return;

    CGRect titleInHeader = [titleView convertRect:titleView.bounds toView:headerView];
    CGFloat titleOverflow = CGRectGetMaxX(titleInHeader) - limitX;
    if (titleOverflow > 0.0) {
        CGRect frame = titleView.frame;
        frame.size.width = MAX(0.0, frame.size.width - titleOverflow);
        titleView.frame = frame;
        titleView.clipsToBounds = YES;
    }

    UILabel *label = SCIProfileFindUsernameLabel(titleView);
    if (label) {
        CGRect labelInHeader = [label convertRect:label.bounds toView:headerView];
        CGFloat labelOverflow = CGRectGetMaxX(labelInHeader) - limitX;
        if (labelOverflow > 0.0) {
            CGRect frame = label.frame;
            frame.size.width = MAX(0.0, frame.size.width - labelOverflow);
            label.frame = frame;
            label.lineBreakMode = NSLineBreakByTruncatingTail;
        }
    }
}

static void SCIProfilePlaceActionButton(UIView *headerView, BOOL titleIsCentered, BOOL reconfigure) {
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

    // Rebuilding the menu/context is expensive; only do it when explicitly asked
    // (initial configure / source change) or before the button has ever been set
    // up. High-frequency triggers (layout, scroll-collapse) just reposition.
    if (reconfigure || !button.sciDidConfigure) {
        SCIConfigureProfileActionButton(button);
    }

    if (button.hidden) {
        [button removeFromSuperview];
        objc_setAssociatedObject(button, kSCIProfileLastExpectedFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (button.superview != headerView) {
        [headerView addSubview:button];
    }

    // Keep the Liquid Glass bubble in sync with IG's buttons every layout pass.
    // Done before any early-return below so the bubble still fades while our
    // position is stable (the glass alpha changes with scroll, our frame may not).
    SCIProfileUpdateGlass(button, headerView);

    // Stop long usernames from running under the button (IG can't reserve space
    // for an overlay). Runs every pass since IG re-expands the title each layout.
    SCIProfileClampTitleToButton(headerView, button);

    CGFloat w = CGRectGetWidth(headerView.bounds);
    CGFloat h = CGRectGetHeight(headerView.bounds);
    if (w < 60.0 || h < 20.0) return;

    CGFloat btnW = kSCIProfileActionButtonWidth;
    CGFloat btnH = kSCIProfileActionButtonHeight;

    CGFloat x;
    CGFloat centerY;

    // Other profiles: place on RIGHT side relative to existing buttons
    CGRect anchorFrame = SCIProfileGetTrailingAnchorFrame(headerView);
    BOOL placedFromAnchor = NO;

    if (!CGRectIsEmpty(anchorFrame)) {
        // Sit a clean 10pt gap to the left of the anchor's visual left edge. This
        // gives the same edge-to-edge spacing IG uses between its own 44pt nav
        // buttons, for both icon anchors (More/bell) and wide text anchors (Follow).
        CGFloat spacing = 10.0;
        x = anchorFrame.origin.x - spacing - btnW;
        centerY = CGRectGetMidY(anchorFrame);

        // Guard: a non-own profile's action button always belongs on the right side.
        // If the resolved anchor would drag the button into the left/center half
        // (e.g. the username re-centered in the nav bar during a scroll), reject it
        // and fall back to a clean right-edge placement instead of jumping to center.
        placedFromAnchor = (x >= w * 0.5);
    }

    NSValue *lastVal = objc_getAssociatedObject(button, kSCIProfileLastExpectedFrameKey);
    CGRect lastFrame = lastVal ? [lastVal CGRectValue] : CGRectZero;

    if (!placedFromAnchor) {
        // No trailing control resolved on the right this pass. This happens during
        // the scroll/collapse animation where the "..." button momentarily leaves
        // the header's bounds. If we've already placed the button against a real
        // anchor, keep that good frame — otherwise a transient miss would snap it
        // to the top-right fallback and stick there once layout stops firing.
        if (lastVal) {
            return;
        }
        CGRect anyBtnFrame = SCIProfileGetAnyButtonFrame(headerView, headerView, CGRectZero);
        if (!CGRectIsEmpty(anyBtnFrame) && CGRectGetMidX(anyBtnFrame) >= w * 0.5) {
            centerY = CGRectGetMidY(anyBtnFrame);
        } else {
            centerY = h - 22.0;
        }
        x = w - btnW - 12.0;
    }

    CGFloat y = centerY - btnH * 0.5;
    CGRect expectedFrame = CGRectMake(floor(x), floor(y), btnW, btnH);

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
        SCIProfilePlaceActionButton(header, titleIsCentered, YES);
    });
}

static void SCIProfileReplaceActionButtonFromHeader(id headerSelf) {
    if (![headerSelf isKindOfClass:[UIView class]]) return;
    // Use saved titleIsCentered state from configure hook
    NSNumber *savedTitleIsCentered = objc_getAssociatedObject(headerSelf, kSCIProfileTitleIsCenteredKey);
    BOOL titleIsCentered = savedTitleIsCentered ? savedTitleIsCentered.boolValue : NO;
    SCIProfilePlaceActionButton((UIView *)headerSelf, titleIsCentered, NO);
}

static void (*orig_profileHeaderLayoutSubviews)(id, SEL);

static void hooked_profileHeaderLayoutSubviews(id self, SEL _cmd) {
    if (orig_profileHeaderLayoutSubviews) orig_profileHeaderLayoutSubviews(self, _cmd);
    SCIProfileReplaceActionButtonFromHeader(self);
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

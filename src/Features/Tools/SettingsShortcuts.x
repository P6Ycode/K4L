#import <objc/runtime.h>
#import <substrate.h>

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Settings/SCISettingsViewController.h"
#import "../../Shared/Gallery/SCIGalleryViewController.h"

static const void *kSCIHomeTabSettingsLongPressAssocKey = &kSCIHomeTabSettingsLongPressAssocKey;
static const void *kSCIGalleryTabLongPressAssocKey = &kSCIGalleryTabLongPressAssocKey;
static const void *kSCIProfileMoreSettingsLongPressAssocKey = &kSCIProfileMoreSettingsLongPressAssocKey;
static const NSTimeInterval kSCIHomeTabLongPressDuration = 0.5;
static const NSTimeInterval kSCIGalleryTabLongPressDuration = 0.65;
static const NSTimeInterval kSCIProfileMoreSettingsLongPressDuration = 0.5;
static NSInteger const kSCIProfileMoreShortcutMaxInstallAttempts = 6;
static NSString * const kSCIGalleryQuickAccessDisabledValue = @"none";

@interface IGTabBarButton (SCIQuickActions)
- (void)sci_addLongPressWithAction:(SEL)action marker:(const void *)marker minimumDuration:(NSTimeInterval)minimumDuration;
- (void)sci_removeProfileAccountPickerLongPressIfNeeded;
- (void)handleHomeTabLongPress:(UILongPressGestureRecognizer *)sender;
- (void)handleDirectInboxTabLongPress:(UILongPressGestureRecognizer *)sender;
@end

@interface SCISettingsShortcutTarget : NSObject
+ (instancetype)sharedTarget;
- (void)handleProfileMoreLongPress:(UILongPressGestureRecognizer *)sender;
@end

@implementation SCISettingsShortcutTarget
+ (instancetype)sharedTarget {
    static SCISettingsShortcutTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [SCISettingsShortcutTarget new];
    });
    return target;
}

- (void)handleProfileMoreLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    SCILog(@"General", @"[SCInsta] Tweak settings gesture activated");
    [SCIUtils showSettingsVC:sender.view.window];
}
@end

static BOOL SCIIsProfileMoreButton(UIView *view) {
    return [view.accessibilityIdentifier isEqualToString:@"profile-more-button"];
}

static void SCIAddProfileSettingsLongPressToView(UIView *view) {
    if (!view) return;
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if (![gesture isKindOfClass:[UILongPressGestureRecognizer class]]) continue;
        if (objc_getAssociatedObject(gesture, kSCIProfileMoreSettingsLongPressAssocKey)) {
            return;
        }
    }

    SCILog(@"General", @"[SCInsta] Adding tweak settings long press gesture recognizer to %@ id=%@ label=%@",
           NSStringFromClass(view.class),
           view.accessibilityIdentifier,
           view.accessibilityLabel);

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:[SCISettingsShortcutTarget sharedTarget]
                                                                                            action:@selector(handleProfileMoreLongPress:)];
    longPress.minimumPressDuration = kSCIProfileMoreSettingsLongPressDuration;
    longPress.cancelsTouchesInView = YES;
    longPress.delaysTouchesBegan = YES;
    longPress.delaysTouchesEnded = YES;

    for (UIGestureRecognizer *existing in view.gestureRecognizers) {
        [existing requireGestureRecognizerToFail:longPress];
    }

    [view addGestureRecognizer:longPress];
    objc_setAssociatedObject(longPress, kSCIProfileMoreSettingsLongPressAssocKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void (*orig_sciProfileMoreDidMoveToWindow)(id, SEL);
static void SCIHookedProfileMoreDidMoveToWindow(id self, SEL _cmd) {
    if (orig_sciProfileMoreDidMoveToWindow) orig_sciProfileMoreDidMoveToWindow(self, _cmd);
    if ([self isKindOfClass:[UIView class]] && SCIIsProfileMoreButton((UIView *)self)) {
        SCIAddProfileSettingsLongPressToView((UIView *)self);
    }
}

static void (*orig_sciProfileMoreLayoutSubviews)(id, SEL);
static void SCIHookedProfileMoreLayoutSubviews(id self, SEL _cmd) {
    if (orig_sciProfileMoreLayoutSubviews) orig_sciProfileMoreLayoutSubviews(self, _cmd);
    if ([self isKindOfClass:[UIView class]] && SCIIsProfileMoreButton((UIView *)self)) {
        SCIAddProfileSettingsLongPressToView((UIView *)self);
    }
}

static BOOL SCIProfileMoreShortcutHooksInstalled = NO;
static BOOL SCIProfileMoreShortcutRetryScheduled = NO;
static NSInteger SCIProfileMoreShortcutInstallAttempts = 0;

static void SCIInstallProfileMoreShortcutHooks(void) {
    if (SCIProfileMoreShortcutHooksInstalled) return;

    SCIProfileMoreShortcutInstallAttempts += 1;
    Class buttonClass = objc_getClass("IGProfileNavigation.IGBadgedNavigationButton");
    if (!buttonClass) buttonClass = objc_getClass("_TtC19IGProfileNavigation24IGBadgedNavigationButton");
    if (!buttonClass) buttonClass = objc_getClass("IGBadgedNavigationButton");
    if (!buttonClass) {
        SCILog(@"General", @"[SCInsta] Profile more settings shortcut hook target unavailable attempt=%ld",
               (long)SCIProfileMoreShortcutInstallAttempts);
        if (!SCIProfileMoreShortcutRetryScheduled &&
            SCIProfileMoreShortcutInstallAttempts < kSCIProfileMoreShortcutMaxInstallAttempts) {
            SCIProfileMoreShortcutRetryScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SCIProfileMoreShortcutRetryScheduled = NO;
                SCIInstallProfileMoreShortcutHooks();
            });
        }
        return;
    }

    MSHookMessageEx(buttonClass, @selector(didMoveToWindow), (IMP)SCIHookedProfileMoreDidMoveToWindow, (IMP *)&orig_sciProfileMoreDidMoveToWindow);
    MSHookMessageEx(buttonClass, @selector(layoutSubviews), (IMP)SCIHookedProfileMoreLayoutSubviews, (IMP *)&orig_sciProfileMoreLayoutSubviews);
    SCIProfileMoreShortcutHooksInstalled = YES;
    SCILog(@"General", @"[SCInsta] Profile more settings shortcut hooks class=%@", NSStringFromClass(buttonClass));
}

static NSString *SCIGalleryShortcutTabIdentifier(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *identifier = [defaults stringForKey:@"gallery_quick_access_tab"];
    if (identifier.length == 0) {
        identifier = kSCIGalleryQuickAccessDisabledValue;
    }
    if ([identifier isEqualToString:kSCIGalleryQuickAccessDisabledValue]) return identifier;

    NSString *target = identifier;
    BOOL usesClassicTabOrdering = [[[NSUserDefaults standardUserDefaults] stringForKey:@"interface_nav_order"] isEqualToString:@"classic"];
    if (usesClassicTabOrdering && [target isEqualToString:@"direct-inbox-tab"]) return @"camera-tab";
    if (!usesClassicTabOrdering && [target isEqualToString:@"camera-tab"]) return @"direct-inbox-tab";
    return target;
}

static BOOL SCITabIdentifierMatchesGalleryShortcut(NSString *identifier, NSString *label) {
    NSString *target = SCIGalleryShortcutTabIdentifier();
    if ([target isEqualToString:kSCIGalleryQuickAccessDisabledValue]) return NO;

    NSString *candidate = [NSString stringWithFormat:@"%@ %@", identifier ?: @"", label ?: @""].lowercaseString;
    if ([identifier isEqualToString:target]) return YES;
    if ([target isEqualToString:@"mainfeed-tab"] && ([candidate containsString:@"mainfeed"] || [candidate containsString:@"home"])) return YES;
    if ([target isEqualToString:@"reels-tab"] && ([candidate containsString:@"clips"] || [candidate containsString:@"reels"])) return YES;
    if ([target isEqualToString:@"camera-tab"] && [candidate containsString:@"create"]) return YES;
    if ([target isEqualToString:@"direct-inbox-tab"] && ([candidate containsString:@"direct"] ||
                                                         [candidate containsString:@"inbox"] ||
                                                         [candidate containsString:@"message"])) return YES;
    if ([target isEqualToString:@"profile-tab"] && ([candidate containsString:@"profile"] ||
                                                    [candidate containsString:@"tab_avatar"])) return YES;
    return NO;
}

static BOOL SCIShouldReplaceProfileTabLongPress(NSString *identifier, NSString *label) {
    return [SCIGalleryShortcutTabIdentifier() isEqualToString:@"profile-tab"] &&
           [identifier isEqualToString:@"profile-tab"] &&
           [(label ?: @"") isEqualToString:@"Profile"];
}

// Show SCInsta tweak settings by holding on the settings/more icon under profile for ~1 second
	%group SCISettingsShortcutsHooks

	// Quick access to tweak settings by holding on home tab button
%hook IGTabBarButton
- (void)didMoveToSuperview {
    %orig;

    NSString *identifier = self.accessibilityIdentifier ?: @"";
    NSString *label = self.accessibilityLabel ?: @"";
    if ([identifier isEqualToString:@"mainfeed-tab"] && [SCIUtils getBoolPref:@"tools_settings_shortcut"]) {
        if (![SCIGalleryShortcutTabIdentifier() isEqualToString:@"mainfeed-tab"]) {
            [self sci_addLongPressWithAction:@selector(handleHomeTabLongPress:) marker:kSCIHomeTabSettingsLongPressAssocKey minimumDuration:kSCIHomeTabLongPressDuration];
        }
    }
    if (SCITabIdentifierMatchesGalleryShortcut(identifier, label)) {
        if (SCIShouldReplaceProfileTabLongPress(identifier, label)) {
            [self sci_removeProfileAccountPickerLongPressIfNeeded];
        }
        [self sci_addLongPressWithAction:@selector(handleDirectInboxTabLongPress:) marker:kSCIGalleryTabLongPressAssocKey minimumDuration:kSCIGalleryTabLongPressDuration];
    }
}

%new - (void)sci_addLongPressWithAction:(SEL)action marker:(const void *)marker minimumDuration:(NSTimeInterval)minimumDuration {
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        if (![gesture isKindOfClass:[UILongPressGestureRecognizer class]]) continue;
        if (objc_getAssociatedObject(gesture, marker)) {
            return;
        }
    }

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:action];
    longPress.minimumPressDuration = minimumDuration;
    BOOL shouldCancel = (marker == kSCIGalleryTabLongPressAssocKey || marker == kSCIHomeTabSettingsLongPressAssocKey);
    longPress.cancelsTouchesInView = shouldCancel;
    longPress.delaysTouchesBegan = shouldCancel;
    longPress.delaysTouchesEnded = shouldCancel;

    for (UIGestureRecognizer *existing in self.gestureRecognizers) {
        [existing requireGestureRecognizerToFail:longPress];
    }

    [self addGestureRecognizer:longPress];
    objc_setAssociatedObject(longPress, marker, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new - (void)sci_removeProfileAccountPickerLongPressIfNeeded {
    for (UIGestureRecognizer *gesture in [self.gestureRecognizers copy]) {
        if (![gesture isKindOfClass:[UILongPressGestureRecognizer class]]) continue;
        if (objc_getAssociatedObject(gesture, kSCIGalleryTabLongPressAssocKey)) continue;

        UILongPressGestureRecognizer *longPress = (UILongPressGestureRecognizer *)gesture;
        if (fabs(longPress.minimumPressDuration - 0.5) > 0.01) continue;

        [self removeGestureRecognizer:gesture];
    }
}

%new - (void)handleHomeTabLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    [SCIUtils showSettingsVC:[self window]];
}

%new - (void)handleDirectInboxTabLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    [SCIGalleryViewController presentGallery];
}
%end

%end

	void SCIInstallSettingsShortcutsHooksIfNeeded(void) {
	    static dispatch_once_t onceToken;
	    dispatch_once(&onceToken, ^{
	        %init(SCISettingsShortcutsHooks);
            SCIInstallProfileMoreShortcutHooks();
	    });
	}

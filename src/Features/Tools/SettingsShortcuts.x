#import <objc/runtime.h>
#import <substrate.h>

#import "../../InstagramHeaders.h"
#import "../../Settings/SPKSettingsViewController.h"
#import "../../Shared/Gallery/SPKGalleryViewController.h"
#import "../../Utils.h"

static const void *kSPKHomeTabSettingsLongPressAssocKey = &kSPKHomeTabSettingsLongPressAssocKey;
static const void *kSPKGalleryTabLongPressAssocKey = &kSPKGalleryTabLongPressAssocKey;
static const void *kSPKProfileMoreSettingsLongPressAssocKey = &kSPKProfileMoreSettingsLongPressAssocKey;
static const NSTimeInterval kSPKHomeTabLongPressDuration = 0.5;
static const NSTimeInterval kSPKGalleryTabLongPressDuration = 0.65;
static const NSTimeInterval kSPKProfileMoreSettingsLongPressDuration = 0.5;
static NSInteger const kSPKProfileMoreShortcutMaxInstallAttempts = 6;
static NSString *const kSPKGalleryQuickAccessDisabledValue = @"none";

@interface IGTabBarButton (SPKQuickActions)
- (void)spk_addLongPressWithAction:(SEL)action marker:(const void *)marker minimumDuration:(NSTimeInterval)minimumDuration;
- (void)spk_removeProfileAccountPickerLongPressIfNeeded;
- (void)handleHomeTabLongPress:(UILongPressGestureRecognizer *)sender;
- (void)handleDirectInboxTabLongPress:(UILongPressGestureRecognizer *)sender;
@end

@interface SPKSettingsShortcutTarget : NSObject
+ (instancetype)sharedTarget;
- (void)handleProfileMoreLongPress:(UILongPressGestureRecognizer *)sender;
@end

@implementation SPKSettingsShortcutTarget
+ (instancetype)sharedTarget {
    static SPKSettingsShortcutTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [SPKSettingsShortcutTarget new];
    });
    return target;
}

- (void)handleProfileMoreLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan)
        return;

    SPKLog(@"General", @"[Sparkle] Tweak settings gesture activated");
    [SPKUtils showSettingsVC:sender.view.window];
}
@end

static BOOL SPKIsProfileMoreButton(UIView *view) {
    return [view.accessibilityIdentifier isEqualToString:@"profile-more-button"];
}

static void SPKAddProfileSettingsLongPressToView(UIView *view) {
    if (!view)
        return;
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if (![gesture isKindOfClass:[UILongPressGestureRecognizer class]])
            continue;
        if (objc_getAssociatedObject(gesture, kSPKProfileMoreSettingsLongPressAssocKey)) {
            return;
        }
    }

    SPKLog(@"General", @"[Sparkle] Adding tweak settings long press gesture recognizer to %@ id=%@ label=%@",
           NSStringFromClass(view.class),
           view.accessibilityIdentifier,
           view.accessibilityLabel);

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:[SPKSettingsShortcutTarget sharedTarget]
                                                                                            action:@selector(handleProfileMoreLongPress:)];
    longPress.minimumPressDuration = kSPKProfileMoreSettingsLongPressDuration;
    longPress.cancelsTouchesInView = YES;
    longPress.delaysTouchesBegan = YES;
    longPress.delaysTouchesEnded = YES;

    for (UIGestureRecognizer *existing in view.gestureRecognizers) {
        [existing requireGestureRecognizerToFail:longPress];
    }

    [view addGestureRecognizer:longPress];
    objc_setAssociatedObject(longPress, kSPKProfileMoreSettingsLongPressAssocKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void (*orig_spkProfileMoreDidMoveToWindow)(id, SEL);
static void SPKHookedProfileMoreDidMoveToWindow(id self, SEL _cmd) {
    if (orig_spkProfileMoreDidMoveToWindow)
        orig_spkProfileMoreDidMoveToWindow(self, _cmd);
    if ([self isKindOfClass:[UIView class]] && SPKIsProfileMoreButton((UIView *)self)) {
        SPKAddProfileSettingsLongPressToView((UIView *)self);
    }
}

static void (*orig_spkProfileMoreLayoutSubviews)(id, SEL);
static void SPKHookedProfileMoreLayoutSubviews(id self, SEL _cmd) {
    if (orig_spkProfileMoreLayoutSubviews)
        orig_spkProfileMoreLayoutSubviews(self, _cmd);
    if ([self isKindOfClass:[UIView class]] && SPKIsProfileMoreButton((UIView *)self)) {
        SPKAddProfileSettingsLongPressToView((UIView *)self);
    }
}

static BOOL SPKProfileMoreShortcutHooksInstalled = NO;
static BOOL SPKProfileMoreShortcutRetryScheduled = NO;
static NSInteger SPKProfileMoreShortcutInstallAttempts = 0;

static void SPKInstallProfileMoreShortcutHooks(void) {
    if (SPKProfileMoreShortcutHooksInstalled)
        return;

    SPKProfileMoreShortcutInstallAttempts += 1;
    Class buttonClass = objc_getClass("IGProfileNavigation.IGBadgedNavigationButton");
    if (!buttonClass)
        buttonClass = objc_getClass("_TtC19IGProfileNavigation24IGBadgedNavigationButton");
    if (!buttonClass)
        buttonClass = objc_getClass("IGBadgedNavigationButton");
    if (!buttonClass) {
        SPKLog(@"General", @"[Sparkle] Profile more settings shortcut hook target unavailable attempt=%ld",
               (long)SPKProfileMoreShortcutInstallAttempts);
        if (!SPKProfileMoreShortcutRetryScheduled &&
            SPKProfileMoreShortcutInstallAttempts < kSPKProfileMoreShortcutMaxInstallAttempts) {
            SPKProfileMoreShortcutRetryScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SPKProfileMoreShortcutRetryScheduled = NO;
                SPKInstallProfileMoreShortcutHooks();
            });
        }
        return;
    }

    MSHookMessageEx(buttonClass, @selector(didMoveToWindow), (IMP)SPKHookedProfileMoreDidMoveToWindow, (IMP *)&orig_spkProfileMoreDidMoveToWindow);
    MSHookMessageEx(buttonClass, @selector(layoutSubviews), (IMP)SPKHookedProfileMoreLayoutSubviews, (IMP *)&orig_spkProfileMoreLayoutSubviews);
    SPKProfileMoreShortcutHooksInstalled = YES;
    SPKLog(@"General", @"[Sparkle] Profile more settings shortcut hooks class=%@", NSStringFromClass(buttonClass));
}

static NSString *SPKGalleryShortcutTabIdentifier(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *identifier = [defaults stringForKey:@"gallery_quick_access_tab"];
    if (identifier.length == 0) {
        identifier = kSPKGalleryQuickAccessDisabledValue;
    }
    if ([identifier isEqualToString:kSPKGalleryQuickAccessDisabledValue])
        return identifier;

    NSString *target = identifier;
    BOOL usesClassicTabOrdering = [[[NSUserDefaults standardUserDefaults] stringForKey:@"interface_nav_order"] isEqualToString:@"classic"];
    if (usesClassicTabOrdering && [target isEqualToString:@"direct-inbox-tab"])
        return @"camera-tab";
    if (!usesClassicTabOrdering && [target isEqualToString:@"camera-tab"])
        return @"direct-inbox-tab";
    return target;
}

static BOOL SPKTabButtonMatchesTarget(NSString *identifier, NSString *label, NSString *target) {
    if (target.length == 0 || [target isEqualToString:kSPKGalleryQuickAccessDisabledValue])
        return NO;

    NSString *candidate = [NSString stringWithFormat:@"%@ %@", identifier ?: @"", label ?: @""].lowercaseString;
    if ([identifier isEqualToString:target])
        return YES;
    if ([target isEqualToString:@"mainfeed-tab"] && ([candidate containsString:@"mainfeed"] || [candidate containsString:@"home"]))
        return YES;
    if ([target isEqualToString:@"reels-tab"] && ([candidate containsString:@"clips"] || [candidate containsString:@"reels"]))
        return YES;
    if ([target isEqualToString:@"camera-tab"] && [candidate containsString:@"create"])
        return YES;
    if ([target isEqualToString:@"explore-tab"] && ([candidate containsString:@"explore"] || [candidate containsString:@"search"]))
        return YES;
    if ([target isEqualToString:@"direct-inbox-tab"] && ([candidate containsString:@"direct"] ||
                                                         [candidate containsString:@"inbox"] ||
                                                         [candidate containsString:@"message"]))
        return YES;
    if ([target isEqualToString:@"profile-tab"] && ([candidate containsString:@"profile"] ||
                                                    [candidate containsString:@"tab_avatar"]))
        return YES;
    return NO;
}

static BOOL SPKTabIdentifierMatchesGalleryShortcut(NSString *identifier, NSString *label) {
    return SPKTabButtonMatchesTarget(identifier, label, SPKGalleryShortcutTabIdentifier());
}

// Maps a canonical tab identifier to its "Hide Tabs" preference so we can tell,
// up front, whether that tab's button will exist in the bar at all.
static BOOL SPKTabHiddenForIdentifier(NSString *identifier) {
    if ([identifier isEqualToString:@"mainfeed-tab"])
        return [SPKUtils getBoolPref:@"interface_hide_feed_tab"];
    if ([identifier isEqualToString:@"reels-tab"])
        return [SPKUtils getBoolPref:@"interface_hide_reels_tab"];
    if ([identifier isEqualToString:@"direct-inbox-tab"])
        return [SPKUtils getBoolPref:@"interface_hide_msgs_tab"];
    if ([identifier isEqualToString:@"camera-tab"])
        return [SPKUtils getBoolPref:@"interface_hide_create_tab"];
    if ([identifier isEqualToString:@"explore-tab"])
        return [SPKUtils getBoolPref:@"interface_hide_explore_tab"];
    if ([identifier isEqualToString:@"profile-tab"])
        return [SPKUtils getBoolPref:@"interface_hide_profile_tab"];
    return NO;
}

// Settings-access safeguard: the tab the Quick Settings long-press should live on.
// Normally the Home tab, but if Home is hidden — or claimed by the Gallery
// shortcut — we fall back to the highest-priority *visible* tab that the Gallery
// shortcut isn't already using, so the user can never hide their way out of
// reaching Sparkle Settings. Ordered to avoid tabs with their own long-press
// (profile account switcher, explore clipboard opener) unless nothing else is
// left. As an absolute last resort (only one tab visible and the Gallery
// shortcut wants it) Settings wins, since lockout is the worse outcome.
static NSString *SPKResolvedSettingsShortcutTabIdentifier(void) {
    if (![SPKUtils getBoolPref:@"tools_settings_shortcut"])
        return nil;

    NSArray<NSString *> *priority = @[ @"mainfeed-tab", @"reels-tab", @"direct-inbox-tab", @"camera-tab", @"explore-tab", @"profile-tab" ];
    NSString *galleryTarget = SPKGalleryShortcutTabIdentifier();

    for (NSString *identifier in priority) {
        if (SPKTabHiddenForIdentifier(identifier))
            continue;
        if ([identifier isEqualToString:galleryTarget])
            continue;
        return identifier;
    }
    for (NSString *identifier in priority) {
        if (SPKTabHiddenForIdentifier(identifier))
            continue;
        return identifier;
    }
    return nil;
}

static BOOL SPKShouldReplaceProfileTabLongPress(NSString *identifier, NSString *label) {
    return [SPKGalleryShortcutTabIdentifier() isEqualToString:@"profile-tab"] &&
           [identifier isEqualToString:@"profile-tab"] &&
           [(label ?: @"") isEqualToString:@"Profile"];
}

// Show Sparkle tweak settings by holding on the settings/more icon under profile for ~1 second
%group SPKSettingsShortcutsHooks

// Quick access to tweak settings by holding on home tab button
%hook IGTabBarButton
- (void)didMoveToSuperview {
    %orig;

    NSString *identifier = self.accessibilityIdentifier ?: @"";
    NSString *label = self.accessibilityLabel ?: @"";

    NSString *settingsHost = SPKResolvedSettingsShortcutTabIdentifier();
    BOOL hostsSettings = settingsHost && SPKTabButtonMatchesTarget(identifier, label, settingsHost);
    if (hostsSettings) {
        [self spk_addLongPressWithAction:@selector(handleHomeTabLongPress:) marker:kSPKHomeTabSettingsLongPressAssocKey minimumDuration:kSPKHomeTabLongPressDuration];
    }

    BOOL matchesGallery = SPKTabIdentifierMatchesGalleryShortcut(identifier, label);
    // Only skip the Gallery shortcut here when Settings was forced onto this exact
    // button (last-resort case where the only visible tab is the Gallery's tab) —
    // Settings access takes priority.
    BOOL settingsTookGalleryTab = hostsSettings && [settingsHost isEqualToString:SPKGalleryShortcutTabIdentifier()];
    if (matchesGallery && !settingsTookGalleryTab) {
        if (SPKShouldReplaceProfileTabLongPress(identifier, label)) {
            [self spk_removeProfileAccountPickerLongPressIfNeeded];
        }
        [self spk_addLongPressWithAction:@selector(handleDirectInboxTabLongPress:) marker:kSPKGalleryTabLongPressAssocKey minimumDuration:kSPKGalleryTabLongPressDuration];
    }
}

%new - (void)spk_addLongPressWithAction:(SEL)action marker:(const void *)marker minimumDuration:(NSTimeInterval)minimumDuration {
for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
    if (![gesture isKindOfClass:[UILongPressGestureRecognizer class]])
        continue;
    if (objc_getAssociatedObject(gesture, marker)) {
        return;
    }
}

UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:action];
longPress.minimumPressDuration = minimumDuration;
BOOL shouldCancel = (marker == kSPKGalleryTabLongPressAssocKey || marker == kSPKHomeTabSettingsLongPressAssocKey);
longPress.cancelsTouchesInView = shouldCancel;
longPress.delaysTouchesBegan = shouldCancel;
longPress.delaysTouchesEnded = shouldCancel;

for (UIGestureRecognizer *existing in self.gestureRecognizers) {
    [existing requireGestureRecognizerToFail:longPress];
}

[self addGestureRecognizer:longPress];
objc_setAssociatedObject(longPress, marker, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new - (void)spk_removeProfileAccountPickerLongPressIfNeeded {
for (UIGestureRecognizer *gesture in [self.gestureRecognizers copy]) {
    if (![gesture isKindOfClass:[UILongPressGestureRecognizer class]])
        continue;
    if (objc_getAssociatedObject(gesture, kSPKGalleryTabLongPressAssocKey))
        continue;

    UILongPressGestureRecognizer *longPress = (UILongPressGestureRecognizer *)gesture;
    if (fabs(longPress.minimumPressDuration - 0.5) > 0.01)
        continue;

    [self removeGestureRecognizer:gesture];
}
}

%new - (void)handleHomeTabLongPress:(UILongPressGestureRecognizer *)sender {
if (sender.state != UIGestureRecognizerStateBegan)
    return;

[SPKUtils showSettingsVC:[self window]];
}

%new - (void)handleDirectInboxTabLongPress:(UILongPressGestureRecognizer *)sender {
if (sender.state != UIGestureRecognizerStateBegan)
    return;

[SPKGalleryViewController presentGallery];
}
%end

%end

void SPKInstallSettingsShortcutsHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKSettingsShortcutsHooks);
        SPKInstallProfileMoreShortcutHooks();
    });
}

#import <objc/runtime.h>

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Settings/SCISettingsViewController.h"
#import "../../Shared/Gallery/SCIGalleryViewController.h"

static const void *kSCIHomeTabSettingsLongPressAssocKey = &kSCIHomeTabSettingsLongPressAssocKey;
static const void *kSCIGalleryTabLongPressAssocKey = &kSCIGalleryTabLongPressAssocKey;
static const void *kSCIProfileMoreSettingsLongPressAssocKey = &kSCIProfileMoreSettingsLongPressAssocKey;
static const NSTimeInterval kSCIHomeTabLongPressDuration = 0.3;
static const NSTimeInterval kSCIGalleryTabLongPressDuration = 0.65;
static const NSTimeInterval kSCIProfileMoreSettingsLongPressDuration = 0.85;
static NSString * const kSCIGalleryQuickAccessDisabledValue = @"none";

@interface IGBadgedNavigationButton (SCISettingsShortcuts)
- (void)sci_addSettingsLongPressGestureRecognizer;
- (void)sci_handleSettingsLongPress:(UILongPressGestureRecognizer *)sender;
@end

@interface IGTabBarButton (SCIQuickActions)
- (void)sci_addLongPressWithAction:(SEL)action marker:(const void *)marker minimumDuration:(NSTimeInterval)minimumDuration;
- (void)sci_removeProfileAccountPickerLongPressIfNeeded;
- (void)handleHomeTabLongPress:(UILongPressGestureRecognizer *)sender;
- (void)handleDirectInboxTabLongPress:(UILongPressGestureRecognizer *)sender;
@end

static NSString *SCIGalleryShortcutTabIdentifier(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *identifier = [defaults stringForKey:@"gallery_long_press_tab"];
    if (identifier.length == 0) {
        /// TODO: remove
        identifier = [defaults boolForKey:@"header_long_press_gallery"] ? @"direct-inbox-tab" : kSCIGalleryQuickAccessDisabledValue;
    }
    if ([identifier isEqualToString:kSCIGalleryQuickAccessDisabledValue]) return identifier;

    NSString *target = identifier;
    BOOL usesClassicTabOrdering = [[[NSUserDefaults standardUserDefaults] stringForKey:@"nav_icon_ordering"] isEqualToString:@"classic"];
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

%hook IGBadgedNavigationButton
- (void)didMoveToWindow {
    %orig;

    if ([self.accessibilityIdentifier isEqualToString:@"profile-more-button"]) {
        [self sci_addSettingsLongPressGestureRecognizer];
    }

    return;
}

%new - (void)sci_addSettingsLongPressGestureRecognizer {
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        if (![gesture isKindOfClass:[UILongPressGestureRecognizer class]]) continue;
        if (objc_getAssociatedObject(gesture, kSCIProfileMoreSettingsLongPressAssocKey)) {
            return;
        }
    }

    NSLog(@"[SCInsta] Adding tweak settings long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sci_handleSettingsLongPress:)];
    longPress.minimumPressDuration = kSCIProfileMoreSettingsLongPressDuration;
    longPress.cancelsTouchesInView = NO;
    longPress.delaysTouchesBegan = NO;
    longPress.delaysTouchesEnded = NO;

    for (UIGestureRecognizer *existing in self.gestureRecognizers) {
        [existing requireGestureRecognizerToFail:longPress];
    }

    [self addGestureRecognizer:longPress];
    objc_setAssociatedObject(longPress, kSCIProfileMoreSettingsLongPressAssocKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new - (void)sci_handleSettingsLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    
    NSLog(@"[SCInsta] Tweak settings gesture activated");

    [SCIUtils showSettingsVC:[self window]];
}
%end

// Quick access to tweak settings by holding on home tab button
%hook IGTabBarButton
- (void)didMoveToSuperview {
    %orig;

    NSString *identifier = self.accessibilityIdentifier ?: @"";
    NSString *label = self.accessibilityLabel ?: @"";
    if ([identifier isEqualToString:@"mainfeed-tab"] && [SCIUtils getBoolPref:@"settings_shortcut"]) {
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
    BOOL opensGallery = marker == kSCIGalleryTabLongPressAssocKey;
    longPress.cancelsTouchesInView = opensGallery;
    longPress.delaysTouchesBegan = opensGallery;
    longPress.delaysTouchesEnded = opensGallery;

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
    });
}

#import "../../Utils.h"
#import <objc/message.h>

static NSString *SPKSelectorForLaunchTabPreference(NSString *preference) {
    if ([preference isEqualToString:@"feed"])
        return @"_timelineButtonPressed";
    if ([preference isEqualToString:@"reels"])
        return @"_discoverVideoButtonPressed";
    if ([preference isEqualToString:@"inbox"])
        return @"_directInboxButtonPressed";
    if ([preference isEqualToString:@"explore"])
        return @"_exploreButtonPressed";
    if ([preference isEqualToString:@"profile"])
        return @"_profileButtonPressed";
    return nil;
}

BOOL isSurfaceShown(IGMainAppSurfaceIntent *surface) {
    BOOL isShown = YES;

    // Feed
    if ([[surface tabStringFromSurfaceIntent] isEqualToString:@"FEED"] && [SPKUtils getBoolPref:@"interface_hide_feed_tab"]) {
        isShown = NO;
    }

    // Reels
    else if ([[surface tabStringFromSurfaceIntent] isEqualToString:@"CLIPS"] && [SPKUtils getBoolPref:@"interface_hide_reels_tab"]) {
        isShown = NO;
    }

    // Messages
    else if ([[surface tabStringFromSurfaceIntent] isEqualToString:@"DIRECT"] && [SPKUtils getBoolPref:@"interface_hide_msgs_tab"]) {
        isShown = NO;
    }

    // Explore
    else if ([[surface tabStringFromSurfaceIntent] isEqualToString:@"SEARCH"] && [SPKUtils getBoolPref:@"interface_hide_explore_tab"]) {
        isShown = NO;
    }

    // Profile
    else if ([[surface tabStringFromSurfaceIntent] isEqualToString:@"PROFILE"] && [SPKUtils getBoolPref:@"interface_hide_profile_tab"]) {
        isShown = NO;
    }

    // Create
    else if ([(NSNumber *)[surface valueForKey:@"_subtype"] unsignedIntegerValue] == 3 && [SPKUtils getBoolPref:@"interface_hide_create_tab"]) {
        isShown = NO;
    }

    return isShown;
}

NSArray *filterSurfacesArray(NSArray *surfaces) {
    NSMutableArray *filteredSurfaces = [NSMutableArray array];

    for (IGMainAppSurfaceIntent *surface in surfaces) {
        if (![surface isKindOfClass:%c(IGMainAppSurfaceIntent)])
            break;

        if (isSurfaceShown(surface)) {
            [filteredSurfaces addObject:surface];
        }
    }

    return filteredSurfaces;
}

///////////////////////////////////////////////

%group SPKNavigationHooks

%hook IGTabBarControllerSwipeCoordinator
- (id)initWithSurfaces:(id)surfaces parentViewController:(id)controller enableHaptics:(_Bool)haptics launcherSet:(id)set {
    // Removes the surface from the main swipeable app collection view
    return %orig(filterSurfacesArray(surfaces), controller, haptics, set);
}
%end

%hook IGTabBarController
- (void)viewWillAppear:(BOOL)animated {
    %orig;

    static BOOL appliedLaunchTab = NO;
    if (appliedLaunchTab)
        return;
    appliedLaunchTab = YES;

    NSString *selectorName = SPKSelectorForLaunchTabPreference([SPKUtils getStringPref:@"interface_launch_tab"]);
    SEL selector = selectorName.length > 0 ? NSSelectorFromString(selectorName) : nil;
    if (selector && [self respondsToSelector:selector]) {
        ((void (*)(id, SEL))objc_msgSend)(self, selector);
    }
}

- (void)_layoutTabBar {
    // Prevents the wrong icon from being shown as selected because of mismatched surface array indexes
    NSArray *_tabBarSurfaces = [SPKUtils getIvarForObj:self name:"_tabBarSurfaces"];

    [SPKUtils setIvarForObj:self name:"_tabBarSurfaces" value:filterSurfacesArray(_tabBarSurfaces)];

    %orig;
}

- (id)_buttonForTabBarSurface:(id)surface {
    // Prevents the button from being added to the tab bar
    id button = %orig(surface);

    if (!isSurfaceShown(surface)) {
        return nil;
    }

    return button;
}
%end

// Demangled name: IGNavConfiguration.IGNavConfiguration
%hook _TtC18IGNavConfiguration18IGNavConfiguration
- (NSInteger)tabOrdering {

    if ([[SPKUtils getStringPref:@"interface_nav_order"] isEqualToString:@"classic"])
        return 0;
    else if ([[SPKUtils getStringPref:@"interface_nav_order"] isEqualToString:@"standard"])
        return 1;
    else if ([[SPKUtils getStringPref:@"interface_nav_order"] isEqualToString:@"alternate"])
        return 2;

    return %orig;
}
- (void)setTabOrdering:(NSInteger)arg1 {
    return;
}

- (BOOL)isTabSwipingEnabled {

    if ([[SPKUtils getStringPref:@"interface_swipe_tabs"] isEqualToString:@"enabled"])
        return YES;
    else if ([[SPKUtils getStringPref:@"interface_swipe_tabs"] isEqualToString:@"disabled"])
        return NO;

    return %orig;
}
- (void)setIsTabSwipingEnabled:(BOOL)arg1 {
    return;
}
%end

%hook IGHomeFeedHeaderView
- (void)didMoveToWindow {
    %orig;

    if ([SPKUtils getBoolPref:@"interface_hide_msgs_tab"]) {
        // IG 436+ is a Swift class: the DM button is the `directButton` @property
        // (KVC-safe). `rightButton` is a bare Swift ivar on 436 (KVC throws) but the
        // KVC key on older ObjC builds — resolve via selector first, guard the rest.
        UIView *msgsButton = nil;
        for (NSString *key in @[ @"directButton", @"rightButton" ]) {
            SEL getter = NSSelectorFromString(key);
            if (![self respondsToSelector:getter])
                continue;
            id candidate = ((id (*)(id, SEL))objc_msgSend)(self, getter);
            if ([candidate isKindOfClass:[UIView class]]) {
                msgsButton = candidate;
                break;
            }
        }
        if (msgsButton) {
            SPKLog(@"General", @"[Sparkle] Hiding messages tab (on feed)");

            [msgsButton removeFromSuperview];
        }
    }
}
%end

%end

extern "C" void SPKInstallNavigationHooksIfNeeded(void) {
    BOOL shouldInstall = ![[SPKUtils getStringPref:@"interface_nav_order"] isEqualToString:@"default"] ||
                         ![[SPKUtils getStringPref:@"interface_launch_tab"] isEqualToString:@"default"] ||
                         ![[SPKUtils getStringPref:@"interface_swipe_tabs"] isEqualToString:@"default"] ||
                         [SPKUtils getBoolPref:@"interface_hide_feed_tab"] ||
                         [SPKUtils getBoolPref:@"interface_hide_reels_tab"] ||
                         [SPKUtils getBoolPref:@"interface_hide_msgs_tab"] ||
                         [SPKUtils getBoolPref:@"interface_hide_explore_tab"] ||
                         [SPKUtils getBoolPref:@"interface_hide_profile_tab"] ||
                         [SPKUtils getBoolPref:@"interface_hide_create_tab"];
    if (!shouldInstall)
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKNavigationHooks,
                       IGHomeFeedHeaderView = SPKResolveIGClass(@"IGHomeFeedHeader.IGHomeFeedHeaderView", @"IGHomeFeedHeaderView"));
    });
}

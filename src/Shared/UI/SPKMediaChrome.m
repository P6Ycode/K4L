#import "SPKMediaChrome.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"

CGFloat const SPKMediaChromeTopBarContentHeight = 44.0;

static CGFloat const kSPKMediaChromeTopIconPointSize = 24.0;
static CGFloat const kSPKMediaChromeBottomIconPointSize = 24.0;

UIBlurEffect *SPKMediaChromeBlurEffect(void) {
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

void SPKApplyMediaChromeNavigationBar(UINavigationBar *bar) {
    if (!bar) {
        return;
    }

    // Neutral, non-blue bar tint on every OS version (including iOS 26, where the
    // back chevron and any system-tinted items would otherwise use the accent).
    bar.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];

    // Sparkle's custom back chevron (the same glyph used to back out of a Gallery
    // folder), applied to every navigation state so the system blue chevron with
    // the previous screen's title never shows.
    UIImage *chevron = [SPKAssetUtils instagramIconNamed:@"chevron_left"
                                               pointSize:24.0
                                           renderingMode:UIImageRenderingModeAlwaysTemplate];

    if (@available(iOS 26.0, *)) {
        // iOS 26 Liquid Glass manages the bar background (and adapts on scroll) on
        // its own — don't reconfigure it, just swap the chevron on copies of the
        // existing appearances so the glass look is preserved.
        UINavigationBarAppearance *standard = [bar.standardAppearance copy] ?: [[UINavigationBarAppearance alloc] init];
        UINavigationBarAppearance *scrollEdge = [(bar.scrollEdgeAppearance ?: bar.standardAppearance) copy] ?: standard;
        UINavigationBarAppearance *compact = [(bar.compactAppearance ?: bar.standardAppearance) copy] ?: standard;
        if (chevron) {
            [standard setBackIndicatorImage:chevron transitionMaskImage:chevron];
            [scrollEdge setBackIndicatorImage:chevron transitionMaskImage:chevron];
            [compact setBackIndicatorImage:chevron transitionMaskImage:chevron];
        }
        bar.standardAppearance = standard;
        bar.scrollEdgeAppearance = scrollEdge;
        bar.compactAppearance = compact;
        return;
    }

    // iOS 18 and lower: opaque material only while content scrolls behind the bar
    // (standard/compact), transparent at the scroll edge, a neutral non-blue tint,
    // and the custom chevron in every state.
    UINavigationBarAppearance *opaque = [[UINavigationBarAppearance alloc] init];
    [opaque configureWithDefaultBackground];
    UINavigationBarAppearance *transparent = [[UINavigationBarAppearance alloc] init];
    [transparent configureWithTransparentBackground];
    if (chevron) {
        [opaque setBackIndicatorImage:chevron transitionMaskImage:chevron];
        [transparent setBackIndicatorImage:chevron transitionMaskImage:chevron];
    }
    bar.standardAppearance = opaque;
    bar.compactAppearance = opaque;
    bar.scrollEdgeAppearance = transparent;
}

// Match iOS 26's title-less back button on iOS 18 and lower (it already does this
// natively on iOS 26). The back button shown on a pushed controller is derived
// from the previous controller's navigation item, so applying it to every
// controller in the stack covers every transition, including back to the root.
static void SPKApplyMediaChromeBackButtonDisplayMode(UIViewController *viewController) {
    if (@available(iOS 26.0, *)) return;
    viewController.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
}

@implementation SPKChromeNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    SPKApplyMediaChromeNavigationBar(self.navigationBar);
    for (UIViewController *viewController in self.viewControllers) {
        SPKApplyMediaChromeBackButtonDisplayMode(viewController);
    }
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    SPKApplyMediaChromeBackButtonDisplayMode(viewController);
    [super pushViewController:viewController animated:animated];
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    for (UIViewController *viewController in viewControllers) {
        SPKApplyMediaChromeBackButtonDisplayMode(viewController);
    }
    [super setViewControllers:viewControllers animated:animated];
}

@end

UILabel *SPKMediaChromeTitleLabel(NSString *text) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text ?: @"";
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    label.textColor = [UIColor labelColor];
    label.textAlignment = NSTextAlignmentCenter;
    [label sizeToFit];
    return label;
}

UIImage *SPKMediaChromeTopIcon(NSString *resourceName) {
    return [SPKAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
                                   pointSize:kSPKMediaChromeTopIconPointSize];
}

UIImage *SPKMediaChromeBottomIcon(NSString *resourceName) {
    return [SPKAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
                                   pointSize:kSPKMediaChromeBottomIconPointSize];
}

static UIImage *SPKMediaChromeNormalizedTopIcon(NSString *resourceName) {
    UIImage *source = SPKMediaChromeTopIcon(resourceName);
    if (!source) {
        return nil;
    }

    CGSize canvasSize = CGSizeMake(kSPKMediaChromeTopIconPointSize, kSPKMediaChromeTopIconPointSize);
    CGSize sourceSize = source.size;
    if (sourceSize.width <= 0.0 || sourceSize.height <= 0.0) {
        return [source imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }

    CGFloat scale = MIN(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height);
    CGSize drawSize = CGSizeMake(sourceSize.width * scale, sourceSize.height * scale);
    CGRect drawRect = CGRectMake((canvasSize.width - drawSize.width) / 2.0,
                                 (canvasSize.height - drawSize.height) / 2.0,
                                 drawSize.width,
                                 drawSize.height);

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvasSize];
    UIImage *normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        (void)context;
        [source drawInRect:CGRectIntegral(drawRect)];
    }];
    return [normalized imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIImage *SPKMediaChromeTopBarIcon(NSString *resourceName) {
    return SPKMediaChromeNormalizedTopIcon(resourceName);
}

UIBarButtonItem *SPKMediaChromeTopBarButtonItem(NSString *resourceName, id target, SEL action) {
    return SPKMediaChromeTopBarButtonItemWithStyle(resourceName,
                                                  target,
                                                  action,
                                                  UIBarButtonItemStylePlain,
                                                  [SPKUtils SPKColor_InstagramPrimaryText],
                                                  nil);
}

UIBarButtonItem *SPKMediaChromeTopBarButtonItemWithTint(NSString *resourceName, id target, SEL action, UIColor *tintColor, NSString *accessibilityLabel) {
    return SPKMediaChromeTopBarButtonItemWithStyle(resourceName, target, action, UIBarButtonItemStylePlain, tintColor, accessibilityLabel);
}

UIBarButtonItem *SPKMediaChromeTopBarButtonItemWithStyle(NSString *resourceName, id target, SEL action, UIBarButtonItemStyle style, UIColor *tintColor, NSString *accessibilityLabel) {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:SPKMediaChromeTopBarIcon(resourceName)
                                                             style:style
                                                            target:target
                                                            action:action];
    item.tintColor = tintColor ?: [SPKUtils SPKColor_InstagramPrimaryText];
    item.accessibilityLabel = accessibilityLabel;
    return item;
}

UIBarButtonItem *SPKMediaChromeTopBarMenuButtonItem(NSString *resourceName, UIMenu *menu, NSString *accessibilityLabel) {
    return SPKMediaChromeTopBarMenuButtonItemWithTint(resourceName, menu, [SPKUtils SPKColor_InstagramPrimaryText], accessibilityLabel);
}

// A real (not custom-view) bar button item that opens `menu` on tap and honors
// `style`, so a menu-backed "Done" looks identical to a plain Done button
// (prominent glass on iOS 26, bold/tinted otherwise). Use this instead of the
// custom-UIButton variant when you don't need forced menu-element ordering.
UIBarButtonItem *SPKMediaChromeTopBarMenuBarButtonItemWithStyle(NSString *resourceName, UIMenu *menu, UIBarButtonItemStyle style, UIColor *tintColor, NSString *accessibilityLabel) {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:SPKMediaChromeTopBarIcon(resourceName) menu:menu];
    item.style = style;
    item.tintColor = tintColor ?: [SPKUtils SPKColor_InstagramPrimaryText];
    item.accessibilityLabel = accessibilityLabel;
    return item;
}

UIBarButtonItem *SPKMediaChromeTopBarMenuButtonItemWithTint(NSString *resourceName, UIMenu *menu, UIColor *tintColor, NSString *accessibilityLabel) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:SPKMediaChromeTopBarIcon(resourceName) forState:UIControlStateNormal];
    button.tintColor = tintColor ?: [SPKUtils SPKColor_InstagramPrimaryText];
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    // Force the menu to keep the order we declare (navigation first, destructive last)
    // instead of iOS reordering by proximity/priority — which on iOS 26 floated the
    // destructive group to the top depending on how the popover opened.
    if (@available(iOS 16.0, *)) {
        button.preferredMenuElementOrder = UIContextMenuConfigurationElementOrderFixed;
    }
    button.accessibilityLabel = accessibilityLabel;
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:button];
    item.accessibilityLabel = accessibilityLabel;
    return item;
}

void SPKMediaChromeSetLeadingTopBarItems(UINavigationItem *navigationItem, NSArray<UIBarButtonItem *> *items) {
    if (!navigationItem) {
        return;
    }
    if (@available(iOS 16.0, *)) {
        navigationItem.leftBarButtonItems = nil;
        navigationItem.leftBarButtonItem = nil;
        navigationItem.leadingItemGroups = items.count > 0
            ? @[ [UIBarButtonItemGroup fixedGroupWithRepresentativeItem:nil items:items] ]
            : @[];
        return;
    }
    navigationItem.leftBarButtonItems = items.count > 0 ? items : nil;
    navigationItem.leftBarButtonItem = nil;
}

void SPKMediaChromeSetTrailingTopBarItems(UINavigationItem *navigationItem, NSArray<UIBarButtonItem *> *items) {
    if (!navigationItem) {
        return;
    }
    if (@available(iOS 16.0, *)) {
        navigationItem.rightBarButtonItems = nil;
        navigationItem.rightBarButtonItem = nil;
        navigationItem.trailingItemGroups = items.count > 0
            ? @[ [UIBarButtonItemGroup fixedGroupWithRepresentativeItem:nil items:items] ]
            : @[];
        return;
    }
    navigationItem.rightBarButtonItems = items.count > 0 ? items : nil;
    navigationItem.rightBarButtonItem = nil;
}

#pragma mark - Bottom Toolbar

UIImage *SPKMediaChromeBottomBarIcon(NSString *resourceName) {
    UIImage *icon = SPKMediaChromeBottomIcon(resourceName);
    return [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIBarButtonItem *SPKMediaChromeBottomBarButtonItem(NSString *resourceName, NSString *accessibilityLabel, id target, SEL action) {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:SPKMediaChromeBottomBarIcon(resourceName)
                                                             style:UIBarButtonItemStylePlain
                                                            target:target
                                                            action:action];
    item.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
    item.accessibilityLabel = accessibilityLabel;
    return item;
}

static UIBarButtonItem *SPKMediaChromeFlexibleSpace(void) {
    return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
}

static UIBarButtonItem *SPKMediaChromeFixedSpace(CGFloat width) {
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    space.width = width;
    return space;
}

NSArray<UIBarButtonItem *> *SPKMediaChromeBottomToolbarItems(NSArray<UIBarButtonItem *> *contentItems) {
    if (contentItems.count == 0) {
        return @[];
    }

    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];

    if (@available(iOS 26.0, *)) {
        // Keep the content items adjacent so they share a single Liquid Glass
        // capsule, and center the capsule with a flexible spacer on each end.
        [items addObject:SPKMediaChromeFlexibleSpace()];
        [items addObjectsFromArray:contentItems];
        [items addObject:SPKMediaChromeFlexibleSpace()];
        return items;
    }

    // Legacy: distribute evenly across a standard full-width bottom bar.
    [items addObject:SPKMediaChromeFlexibleSpace()];
    for (UIBarButtonItem *item in contentItems) {
        [items addObject:item];
        [items addObject:SPKMediaChromeFlexibleSpace()];
    }
    return items;
}

NSArray<UIBarButtonItem *> *SPKMediaChromeBottomToolbarItemsWithTrailingGroup(NSArray<UIBarButtonItem *> *primaryItems, NSArray<UIBarButtonItem *> *trailingItems) {
    if (trailingItems.count == 0) {
        return SPKMediaChromeBottomToolbarItems(primaryItems);
    }
    if (primaryItems.count == 0) {
        return SPKMediaChromeBottomToolbarItems(trailingItems);
    }

    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];

    if (@available(iOS 26.0, *)) {
        // Both groups stay centered (flexible spacers on the outer ends) while a
        // fixed gap between them splits the glass background into two capsules.
        [items addObject:SPKMediaChromeFlexibleSpace()];
        [items addObjectsFromArray:primaryItems];
        [items addObject:SPKMediaChromeFixedSpace(8.0)];
        [items addObjectsFromArray:trailingItems];
        [items addObject:SPKMediaChromeFlexibleSpace()];
        return items;
    }

    // Legacy: a single evenly-distributed bar containing every item.
    NSMutableArray<UIBarButtonItem *> *combined = [NSMutableArray arrayWithArray:primaryItems];
    [combined addObjectsFromArray:trailingItems];
    return SPKMediaChromeBottomToolbarItems(combined);
}

void SPKMediaChromeConfigureBottomToolbar(UIToolbar *toolbar) {
    if (!toolbar) {
        return;
    }
    toolbar.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
    toolbar.translucent = YES;
}

void SPKMediaChromeSetBarsMaterialActive(UINavigationController *navigationController, BOOL active) {
    if (!navigationController) {
        return;
    }
    // iOS 26+ Liquid Glass adapts on its own; leave the system appearance alone.
    if (@available(iOS 26.0, *)) {
        return;
    }

    UIColor *tint = [SPKUtils SPKColor_InstagramPrimaryText];

    UINavigationBarAppearance *navAppearance = [[UINavigationBarAppearance alloc] init];
    if (active) {
        [navAppearance configureWithDefaultBackground];
    } else {
        [navAppearance configureWithTransparentBackground];
    }
    UINavigationBar *navBar = navigationController.navigationBar;
    navBar.standardAppearance = navAppearance;
    navBar.scrollEdgeAppearance = navAppearance;
    navBar.compactAppearance = navAppearance;
    navBar.tintColor = tint;

    UIToolbarAppearance *toolbarAppearance = [[UIToolbarAppearance alloc] init];
    if (active) {
        [toolbarAppearance configureWithDefaultBackground];
    } else {
        [toolbarAppearance configureWithTransparentBackground];
    }
    UIToolbar *toolbar = navigationController.toolbar;
    toolbar.standardAppearance = toolbarAppearance;
    toolbar.scrollEdgeAppearance = toolbarAppearance;
    toolbar.compactAppearance = toolbarAppearance;
    toolbar.tintColor = tint;
}

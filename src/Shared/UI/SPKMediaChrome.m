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
    (void)bar;
}

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
    return SPKMediaChromeTopBarButtonItemWithTint(resourceName,
                                                 target,
                                                 action,
                                                 [SPKUtils SPKColor_InstagramPrimaryText],
                                                 nil);
}

UIBarButtonItem *SPKMediaChromeTopBarButtonItemWithTint(NSString *resourceName, id target, SEL action, UIColor *tintColor, NSString *accessibilityLabel) {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:SPKMediaChromeTopBarIcon(resourceName)
                                                             style:UIBarButtonItemStylePlain
                                                            target:target
                                                            action:action];
    item.tintColor = tintColor ?: [SPKUtils SPKColor_InstagramPrimaryText];
    item.accessibilityLabel = accessibilityLabel;
    return item;
}

UIBarButtonItem *SPKMediaChromeTopBarMenuButtonItem(NSString *resourceName, UIMenu *menu, NSString *accessibilityLabel) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:SPKMediaChromeTopBarIcon(resourceName) forState:UIControlStateNormal];
    button.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
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

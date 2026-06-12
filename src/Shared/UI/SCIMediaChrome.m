#import "SCIMediaChrome.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"

CGFloat const SCIMediaChromeTopBarContentHeight = 44.0;

static CGFloat const kSCIMediaChromeTopIconPointSize = 24.0;
static CGFloat const kSCIMediaChromeBottomIconPointSize = 24.0;

UIBlurEffect *SCIMediaChromeBlurEffect(void) {
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

void SCIApplyMediaChromeNavigationBar(UINavigationBar *bar) {
    (void)bar;
}

UILabel *SCIMediaChromeTitleLabel(NSString *text) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text ?: @"";
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    label.textColor = [UIColor labelColor];
    label.textAlignment = NSTextAlignmentCenter;
    [label sizeToFit];
    return label;
}

UIImage *SCIMediaChromeTopIcon(NSString *resourceName) {
    return [SCIAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
                                   pointSize:kSCIMediaChromeTopIconPointSize];
}

UIImage *SCIMediaChromeBottomIcon(NSString *resourceName) {
    return [SCIAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
                                   pointSize:kSCIMediaChromeBottomIconPointSize];
}

static UIImage *SCIMediaChromeNormalizedTopIcon(NSString *resourceName) {
    UIImage *source = SCIMediaChromeTopIcon(resourceName);
    if (!source) {
        return nil;
    }

    CGSize canvasSize = CGSizeMake(kSCIMediaChromeTopIconPointSize, kSCIMediaChromeTopIconPointSize);
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

UIImage *SCIMediaChromeTopBarIcon(NSString *resourceName) {
    return SCIMediaChromeNormalizedTopIcon(resourceName);
}

UIBarButtonItem *SCIMediaChromeTopBarButtonItem(NSString *resourceName, id target, SEL action) {
    return SCIMediaChromeTopBarButtonItemWithTint(resourceName,
                                                 target,
                                                 action,
                                                 [SCIUtils SCIColor_InstagramPrimaryText],
                                                 nil);
}

UIBarButtonItem *SCIMediaChromeTopBarButtonItemWithTint(NSString *resourceName, id target, SEL action, UIColor *tintColor, NSString *accessibilityLabel) {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:SCIMediaChromeTopBarIcon(resourceName)
                                                             style:UIBarButtonItemStylePlain
                                                            target:target
                                                            action:action];
    item.tintColor = tintColor ?: [SCIUtils SCIColor_InstagramPrimaryText];
    item.accessibilityLabel = accessibilityLabel;
    return item;
}

UIBarButtonItem *SCIMediaChromeTopBarMenuButtonItem(NSString *resourceName, UIMenu *menu, NSString *accessibilityLabel) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:SCIMediaChromeTopBarIcon(resourceName) forState:UIControlStateNormal];
    button.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
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

void SCIMediaChromeSetLeadingTopBarItems(UINavigationItem *navigationItem, NSArray<UIBarButtonItem *> *items) {
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

void SCIMediaChromeSetTrailingTopBarItems(UINavigationItem *navigationItem, NSArray<UIBarButtonItem *> *items) {
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

UIImage *SCIMediaChromeBottomBarIcon(NSString *resourceName) {
    UIImage *icon = SCIMediaChromeBottomIcon(resourceName);
    return [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIBarButtonItem *SCIMediaChromeBottomBarButtonItem(NSString *resourceName, NSString *accessibilityLabel, id target, SEL action) {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:SCIMediaChromeBottomBarIcon(resourceName)
                                                             style:UIBarButtonItemStylePlain
                                                            target:target
                                                            action:action];
    item.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    item.accessibilityLabel = accessibilityLabel;
    return item;
}

static UIBarButtonItem *SCIMediaChromeFlexibleSpace(void) {
    return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
}

static UIBarButtonItem *SCIMediaChromeFixedSpace(CGFloat width) {
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    space.width = width;
    return space;
}

NSArray<UIBarButtonItem *> *SCIMediaChromeBottomToolbarItems(NSArray<UIBarButtonItem *> *contentItems) {
    if (contentItems.count == 0) {
        return @[];
    }

    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];

    if (@available(iOS 26.0, *)) {
        // Keep the content items adjacent so they share a single Liquid Glass
        // capsule, and center the capsule with a flexible spacer on each end.
        [items addObject:SCIMediaChromeFlexibleSpace()];
        [items addObjectsFromArray:contentItems];
        [items addObject:SCIMediaChromeFlexibleSpace()];
        return items;
    }

    // Legacy: distribute evenly across a standard full-width bottom bar.
    [items addObject:SCIMediaChromeFlexibleSpace()];
    for (UIBarButtonItem *item in contentItems) {
        [items addObject:item];
        [items addObject:SCIMediaChromeFlexibleSpace()];
    }
    return items;
}

NSArray<UIBarButtonItem *> *SCIMediaChromeBottomToolbarItemsWithTrailingGroup(NSArray<UIBarButtonItem *> *primaryItems, NSArray<UIBarButtonItem *> *trailingItems) {
    if (trailingItems.count == 0) {
        return SCIMediaChromeBottomToolbarItems(primaryItems);
    }
    if (primaryItems.count == 0) {
        return SCIMediaChromeBottomToolbarItems(trailingItems);
    }

    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];

    if (@available(iOS 26.0, *)) {
        // Both groups stay centered (flexible spacers on the outer ends) while a
        // fixed gap between them splits the glass background into two capsules.
        [items addObject:SCIMediaChromeFlexibleSpace()];
        [items addObjectsFromArray:primaryItems];
        [items addObject:SCIMediaChromeFixedSpace(8.0)];
        [items addObjectsFromArray:trailingItems];
        [items addObject:SCIMediaChromeFlexibleSpace()];
        return items;
    }

    // Legacy: a single evenly-distributed bar containing every item.
    NSMutableArray<UIBarButtonItem *> *combined = [NSMutableArray arrayWithArray:primaryItems];
    [combined addObjectsFromArray:trailingItems];
    return SCIMediaChromeBottomToolbarItems(combined);
}

void SCIMediaChromeConfigureBottomToolbar(UIToolbar *toolbar) {
    if (!toolbar) {
        return;
    }
    toolbar.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    toolbar.translucent = YES;
}

void SCIMediaChromeSetBarsMaterialActive(UINavigationController *navigationController, BOOL active) {
    if (!navigationController) {
        return;
    }
    // iOS 26+ Liquid Glass adapts on its own; leave the system appearance alone.
    if (@available(iOS 26.0, *)) {
        return;
    }

    UIColor *tint = [SCIUtils SCIColor_InstagramPrimaryText];

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
    if (@available(iOS 15.0, *)) {
        toolbar.compactAppearance = toolbarAppearance;
    }
    toolbar.tintColor = tint;
}

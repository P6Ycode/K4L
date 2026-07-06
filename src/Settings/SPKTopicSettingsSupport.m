#import "SPKTopicSettingsSupport.h"
#import "../Shared/UI/SPKNotificationCenter.h"
#import "SPKActionButtonDefaultActionPickerViewController.h"
#import "SPKBulkActionMenuEditViewController.h"
#import "SPKEditActionsListViewController.h"
#import "SPKPreferences.h"

#import "../AssetUtils.h"
#import "../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../Shared/ActionButton/SPKActionDescriptor.h"
#import "../Utils.h"

CGFloat const SPKSettingsCellIconPointSize = 24.0;

NSDictionary *SPKTopicSection(NSString *header, NSArray *rows, NSString *footer) {
    NSMutableDictionary *section = [@{
        @"header" : header ?: @"",
        @"rows" : rows ?: @[]
    } mutableCopy];

    if (footer.length > 0) {
        section[@"footer"] = footer;
    }

    return [section copy];
}

UIImage *SPKSettingsIcon(NSString *name) {
    return [SPKAssetUtils instagramIconNamed:name pointSize:SPKSettingsCellIconPointSize];
}

UIImage *SPKSettingsSystemIcon(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIImage *symbol = [SPKAssetUtils resolvedImageNamed:name
                                              pointSize:pointSize
                                                 weight:weight
                                                 source:SPKResolvedImageSourceSystemSymbol
                                          renderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!symbol)
        return nil;

    // SF Symbols size by cap-height, so a wide/tall glyph (e.g.
    // button.vertical.right.press) renders to a larger bounding box than the
    // IG asset icons, which are a fixed square. Aspect-fit the symbol into the
    // same square canvas so it lines up with the other settings rows.
    CGFloat side = SPKSettingsCellIconPointSize;
    CGSize canvasSize = CGSizeMake(side, side);
    CGSize sourceSize = symbol.size;
    if (sourceSize.width <= 0.0 || sourceSize.height <= 0.0) {
        return symbol;
    }

    CGFloat scale = MIN(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height);
    CGSize drawSize = CGSizeMake(sourceSize.width * scale, sourceSize.height * scale);
    CGRect drawRect = CGRectMake((canvasSize.width - drawSize.width) / 2.0,
                                 (canvasSize.height - drawSize.height) / 2.0,
                                 drawSize.width,
                                 drawSize.height);

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvasSize format:format];
    UIImage *normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext *_Nonnull context) {
        (void)context;
        [symbol drawInRect:CGRectIntegral(drawRect)];
    }];
    return [normalized imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

SPKSetting *SPKSettingApplyIconTint(SPKSetting *setting, UIColor *tintColor) {
    setting.iconTintColor = tintColor;
    return setting;
}

static UIImage *SPKSelectedMenuIconInMenu(UIMenu *menu) {
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:[UIMenu class]]) {
            UIImage *icon = SPKSelectedMenuIconInMenu((UIMenu *)element);
            if (icon)
                return icon;
            continue;
        }

        if (![element isKindOfClass:[UICommand class]])
            continue;
        UICommand *command = (UICommand *)element;
        NSDictionary *propertyList = command.propertyList;
        NSString *defaultsKey = propertyList[@"defaultsKey"];
        NSString *value = propertyList[@"value"];
        NSString *iconName = propertyList[@"iconName"];
        if (defaultsKey.length == 0 || value.length == 0 || iconName.length == 0)
            continue;

        // Read through the namespaced accessor so the selected-icon lookup
        // matches how menuChanged: writes (per-account effective key). A raw
        // standardUserDefaults read misses the value when per-account prefs are
        // enabled, leaving the cell stuck on its fallback icon.
        NSString *saved = [SPKUtils getStringPref:defaultsKey];
        if ([saved isEqualToString:value]) {
            return SPKSettingsIcon(iconName);
        }
    }

    return nil;
}

SPKSetting *SPKSettingApplySelectedMenuIcon(SPKSetting *setting, UIImage *fallbackIcon) {
    __weak SPKSetting *weakSetting = setting;
    setting.iconProvider = ^UIImage * {
        SPKSetting *strongSetting = weakSetting;
        if (!strongSetting)
            return fallbackIcon;
        return SPKSelectedMenuIconInMenu(strongSetting.baseMenu) ?: fallbackIcon ?
                                                                                 : strongSetting.icon;
    };
    return setting;
}

SPKSetting *SPKTopicNavigationSetting(NSString *title, NSString *iconName, CGFloat iconSize, NSArray *sections) {
    CGFloat resolvedIconSize = iconSize > 0.0 ? iconSize : SPKSettingsCellIconPointSize;
    return SPKSettingApplyIconTint([SPKSetting navigationCellWithTitle:title
                                                              subtitle:@""
                                                                  icon:[SPKAssetUtils instagramIconNamed:iconName pointSize:resolvedIconSize]
                                                           navSections:sections],
                                   [SPKUtils SPKColor_InstagramPrimaryText]);
}

SPKSetting *SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSource source) {
    SPKSetting *setting = [SPKSetting navigationCellWithTitle:@"Default Tap Action"
                                                     subtitle:@""
                                                         icon:SPKSettingsIcon(@"action")
                                               viewController:[[SPKActionButtonDefaultActionPickerViewController alloc] initWithSource:source]];
    setting.accessoryTextProvider = ^NSString * {
        return SPKActionButtonDefaultActionTitleForSource(source);
    };
    setting.iconProvider = ^UIImage * {
        return SPKSettingsIcon(SPKActionButtonDefaultActionIconNameForSource(source));
    };
    return setting;
}

static UICommand *SPKMenuCommand(NSString *title, NSString *imageName, NSString *fallback, NSString *defaultsKey, NSString *value, BOOL requiresRestart) {
    NSMutableDictionary *propertyList = [@{
        @"defaultsKey" : defaultsKey,
        @"value" : value
    } mutableCopy];

    if (requiresRestart) {
        propertyList[@"requiresRestart"] = @YES;
    }
    if (imageName.length > 0) {
        propertyList[@"iconName"] = imageName;
    }

    UIImage *image = [SPKAssetUtils resolvedImageNamed:imageName
                                    fallbackSystemName:fallback
                                             pointSize:22.0
                                                weight:UIImageSymbolWeightRegular
                                                source:(imageName.length > 0 ? SPKResolvedImageSourceInstagramIcon : SPKResolvedImageSourceSystemSymbol)
                                         renderingMode:UIImageRenderingModeAlwaysTemplate];

    return [UICommand commandWithTitle:title
                                 image:image
                                action:@selector(menuChanged:)
                          propertyList:[propertyList copy]];
}

SPKSetting *SPKActionButtonConfigurationNavigationSetting(SPKActionButtonSource source, NSString *topicTitle, NSArray<NSString *> *supportedActions, NSArray<SPKActionMenuSection *> *defaultSections) {
    SPKEditActionsListViewController *controller = [[SPKEditActionsListViewController alloc] initWithSource:source topicTitle:topicTitle];
    (void)supportedActions;
    (void)defaultSections;
    return [SPKSetting navigationCellWithTitle:@"Configure Actions"
                                      subtitle:@""
                                          icon:SPKSettingsIcon(@"slider")
                                viewController:controller];
}

UIMenu *SPKReelsTapControlMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Default", nil, nil, @"reels_tap_control", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
                         SPKMenuCommand(@"Pause/Play", nil, nil, @"reels_tap_control", @"pause", YES),
                         SPKMenuCommand(@"Mute/Unmute", nil, nil, @"reels_tap_control", @"mute", YES)
                     ]]
    ]];
}

UIMenu *SPKMainFeedModeMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"For You", @"heart", nil, @"feed_mode", @"default", YES),
        SPKMenuCommand(@"Following", @"users", nil, @"feed_mode", @"following", YES)
    ]];
}

UIMenu *SPKNavigationIconOrderingMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Default", nil, nil, @"interface_nav_order", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
                         SPKMenuCommand(@"Classic", nil, nil, @"interface_nav_order", @"classic", YES),
                         SPKMenuCommand(@"Standard", nil, nil, @"interface_nav_order", @"standard", YES),
                         SPKMenuCommand(@"Alternate", nil, nil, @"interface_nav_order", @"alternate", YES)
                     ]]
    ]];
}

UIMenu *SPKLaunchTabMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Default", nil, nil, @"interface_launch_tab", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
                         SPKMenuCommand(@"Feed", @"home", nil, @"interface_launch_tab", @"feed", YES),
                         SPKMenuCommand(@"Reels", @"reels", nil, @"interface_launch_tab", @"reels", YES),
                         SPKMenuCommand(@"Messages", @"messages", nil, @"interface_launch_tab", @"inbox", YES),
                         SPKMenuCommand(@"Explore", @"search", nil, @"interface_launch_tab", @"explore", YES),
                         SPKMenuCommand(@"Profile", @"user_circle", nil, @"interface_launch_tab", @"profile", YES)
                     ]]
    ]];
}

UIMenu *SPKSwipeBetweenTabsMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Default", nil, nil, @"interface_swipe_tabs", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
                         SPKMenuCommand(@"Enabled", nil, nil, @"interface_swipe_tabs", @"enabled", YES),
                         SPKMenuCommand(@"Disabled", nil, nil, @"interface_swipe_tabs", @"disabled", YES)
                     ]]
    ]];
}

UIMenu *SPKLiquidGlassTabBarStateMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Default", nil, nil, kSPKPrefInterfaceLiquidGlassTabBarMode, @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
                         SPKMenuCommand(@"Fixed", nil, nil, kSPKPrefInterfaceLiquidGlassTabBarMode, @"fixed", YES),
                         SPKMenuCommand(@"Hide on Scroll", nil, nil, kSPKPrefInterfaceLiquidGlassTabBarMode, @"hide", YES)
                     ]]
    ]];
}

UIMenu *SPKSwipeCloseCommentsDirectionMenu(void) {
    static NSString *const kSPKSwipeCloseCommentsDirectionKey = @"general_comments_swipe_close_direction";
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Both", @"left_right", nil, kSPKSwipeCloseCommentsDirectionKey, @"both", NO),
        SPKMenuCommand(@"Left", @"arrow_left", nil, kSPKSwipeCloseCommentsDirectionKey, @"left", NO),
        SPKMenuCommand(@"Right", @"arrow_right", nil, kSPKSwipeCloseCommentsDirectionKey, @"right", NO)
    ]];
}

UIMenu *SPKCacheAutoClearMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Never", nil, nil, @"general_cache_auto_clear", @"never", NO),
        SPKMenuCommand(@"Always", nil, nil, @"general_cache_auto_clear", @"always", NO),
        SPKMenuCommand(@"Daily", nil, nil, @"general_cache_auto_clear", @"daily", NO),
        SPKMenuCommand(@"Weekly", nil, nil, @"general_cache_auto_clear", @"weekly", NO),
        SPKMenuCommand(@"Monthly", nil, nil, @"general_cache_auto_clear", @"monthly", NO)
    ]];
}

UIMenu *SPKNotificationProgressSubtitleStyleMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Both", nil, nil, kSPKNotificationProgressSubtitleStyleKey, @"both", NO),
        SPKMenuCommand(@"Percent", nil, nil, kSPKNotificationProgressSubtitleStyleKey, @"percent", NO),
        SPKMenuCommand(@"Bytes", nil, nil, kSPKNotificationProgressSubtitleStyleKey, @"bytes", NO),
        SPKMenuCommand(@"Off", nil, nil, kSPKNotificationProgressSubtitleStyleKey, @"off", NO)
    ]];
}

UIMenu *SPKNotificationPillPositionMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Top", nil, nil, kSPKNotificationPillPositionKey, @"top", NO),
        SPKMenuCommand(@"Bottom", nil, nil, kSPKNotificationPillPositionKey, @"bottom", NO)
    ]];
}

UIMenu *SPKMediaVideoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Default", nil, nil, @"downloads_video_quality", @"high_ignore_dash", NO),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
                         SPKMenuCommand(@"Always Ask", nil, nil, @"downloads_video_quality", @"always_ask", NO),
                         SPKMenuCommand(@"High", nil, nil, @"downloads_video_quality", @"high", NO),
                         SPKMenuCommand(@"Medium", nil, nil, @"downloads_video_quality", @"medium", NO),
                         SPKMenuCommand(@"Low", nil, nil, @"downloads_video_quality", @"low", NO)
                     ]]
    ]];
}

UIMenu *SPKMediaPhotoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Always Ask", nil, nil, @"downloads_photo_quality", @"always_ask", NO),
        SPKMenuCommand(@"High", nil, nil, @"downloads_photo_quality", @"high", NO),
        SPKMenuCommand(@"Low", nil, nil, @"downloads_photo_quality", @"low", NO)
    ]];
}

UIMenu *SPKGalleryShortcutTargetMenu(void) {
    NSString *const kGalleryLongPressTabKey = @"gallery_quick_access_tab";
    NSString *const kGalleryQuickAccessDisabledValue = @"none";

    NSMutableArray<UIMenuElement *> *commands = [NSMutableArray array];

    NSArray<NSDictionary *> *items = @[
        @{@"title" : @"None", @"value" : kGalleryQuickAccessDisabledValue, @"icon" : @"circle_off"},
        @{@"title" : @"Home", @"value" : @"mainfeed-tab", @"icon" : @"home"},
        @{@"title" : @"Reels", @"value" : @"reels-tab", @"icon" : @"reels"}
    ];

    NSMutableArray *allItems = [items mutableCopy];
    if ([SPKUtils tabOrderSetTo:@"classic"]) {
        [allItems addObject:@{@"title" : @"Create", @"value" : @"camera-tab", @"icon" : @"plus"}];
    } else {
        [allItems addObject:@{@"title" : @"Messages", @"value" : @"direct-inbox-tab", @"icon" : @"messages"}];
    }
    [allItems addObject:@{@"title" : @"Profile", @"value" : @"profile-tab", @"icon" : @"user_circle"}];

    for (NSDictionary *item in allItems) {
        NSString *title = item[@"title"];
        NSString *value = item[@"value"];
        NSString *iconName = item[@"icon"];

        [commands addObject:SPKMenuCommand(title, iconName, nil, kGalleryLongPressTabKey, value, YES)];
    }

    return [UIMenu menuWithChildren:commands];
}

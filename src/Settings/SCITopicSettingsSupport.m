#import "SCITopicSettingsSupport.h"
#import "../Shared/UI/SCINotificationCenter.h"
#import "SCIActionButtonDefaultActionPickerViewController.h"
#import "SCIEditActionsListViewController.h"
#import "SCIBulkActionMenuEditViewController.h"
#import "SCIPreferences.h"

#import "../AssetUtils.h"
#import "../Utils.h"
#import "../Shared/ActionButton/SCIActionDescriptor.h"
#import "../Shared/ActionButton/SCIActionButtonConfiguration.h"

CGFloat const SCISettingsCellIconPointSize = 24.0;

NSDictionary *SCITopicSection(NSString *header, NSArray *rows, NSString *footer) {
    NSMutableDictionary *section = [@{
        @"header": header ?: @"",
        @"rows": rows ?: @[]
    } mutableCopy];

    if (footer.length > 0) {
        section[@"footer"] = footer;
    }

    return [section copy];
}

UIImage *SCISettingsIcon(NSString *name) {
    return [SCIAssetUtils instagramIconNamed:name pointSize:SCISettingsCellIconPointSize];
}

UIImage *SCISettingsSystemIcon(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIImage *symbol = [SCIAssetUtils resolvedImageNamed:name
                                              pointSize:pointSize
                                                 weight:weight
                                                 source:SCIResolvedImageSourceSystemSymbol
                                          renderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!symbol) return nil;

    // SF Symbols size by cap-height, so a wide/tall glyph (e.g.
    // button.vertical.right.press) renders to a larger bounding box than the
    // IG asset icons, which are a fixed square. Aspect-fit the symbol into the
    // same square canvas so it lines up with the other settings rows.
    CGFloat side = SCISettingsCellIconPointSize;
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
    UIImage *normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        (void)context;
        [symbol drawInRect:CGRectIntegral(drawRect)];
    }];
    return [normalized imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

SCISetting *SCISettingApplyIconTint(SCISetting *setting, UIColor *tintColor) {
    setting.iconTintColor = tintColor;
    return setting;
}

static UIImage *SCISelectedMenuIconInMenu(UIMenu *menu) {
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:[UIMenu class]]) {
            UIImage *icon = SCISelectedMenuIconInMenu((UIMenu *)element);
            if (icon) return icon;
            continue;
        }

        if (![element isKindOfClass:[UICommand class]]) continue;
        UICommand *command = (UICommand *)element;
        NSDictionary *propertyList = command.propertyList;
        NSString *defaultsKey = propertyList[@"defaultsKey"];
        NSString *value = propertyList[@"value"];
        NSString *iconName = propertyList[@"iconName"];
        if (defaultsKey.length == 0 || value.length == 0 || iconName.length == 0) continue;

        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey];
        if ([saved isEqualToString:value]) {
            return SCISettingsIcon(iconName);
        }
    }

    return nil;
}

SCISetting *SCISettingApplySelectedMenuIcon(SCISetting *setting, UIImage *fallbackIcon) {
    __weak SCISetting *weakSetting = setting;
    setting.iconProvider = ^UIImage *{
        SCISetting *strongSetting = weakSetting;
        if (!strongSetting) return fallbackIcon;
        return SCISelectedMenuIconInMenu(strongSetting.baseMenu) ?: fallbackIcon ?: strongSetting.icon;
    };
    return setting;
}

SCISetting *SCITopicNavigationSetting(NSString *title, NSString *iconName, CGFloat iconSize, NSArray *sections) {
    CGFloat resolvedIconSize = iconSize > 0.0 ? iconSize : SCISettingsCellIconPointSize;
    return SCISettingApplyIconTint([SCISetting navigationCellWithTitle:title
                                                              subtitle:@""
                                                                  icon:[SCIAssetUtils instagramIconNamed:iconName pointSize:resolvedIconSize]
                                                           navSections:sections],
                                   [SCIUtils SCIColor_InstagramPrimaryText]);
}

SCISetting *SCIActionButtonDefaultActionNavigationSetting(SCIActionButtonSource source) {
    SCISetting *setting = [SCISetting navigationCellWithTitle:@"Default Tap Action"
                                                    subtitle:@""
                                                        icon:SCISettingsIcon(@"action")
                                              viewController:[[SCIActionButtonDefaultActionPickerViewController alloc] initWithSource:source]];
    setting.accessoryTextProvider = ^NSString *{
        return SCIActionButtonDefaultActionTitleForSource(source);
    };
    setting.iconProvider = ^UIImage *{
        return SCISettingsIcon(SCIActionButtonDefaultActionIconNameForSource(source));
    };
    return setting;
}

static UICommand *SCIMenuCommand(NSString *title, NSString *imageName, NSString *fallback, NSString *defaultsKey, NSString *value, BOOL requiresRestart) {
    NSMutableDictionary *propertyList = [@{
        @"defaultsKey": defaultsKey,
        @"value": value
    } mutableCopy];

    if (requiresRestart) {
        propertyList[@"requiresRestart"] = @YES;
    }
    if (imageName.length > 0) {
        propertyList[@"iconName"] = imageName;
    }

    UIImage *image = [SCIAssetUtils resolvedImageNamed:imageName
                                    fallbackSystemName:fallback
                                             pointSize:22.0
                                                weight:UIImageSymbolWeightRegular
                                                source:(imageName.length > 0 ? SCIResolvedImageSourceInstagramIcon : SCIResolvedImageSourceSystemSymbol)
                                         renderingMode:UIImageRenderingModeAlwaysTemplate];

    return [UICommand commandWithTitle:title
                                 image:image
                                action:@selector(menuChanged:)
                          propertyList:[propertyList copy]];
}

SCISetting *SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSource source, NSString *topicTitle, NSArray<NSString *> *supportedActions, NSArray<SCIActionMenuSection *> *defaultSections) {
    SCIEditActionsListViewController *controller = [[SCIEditActionsListViewController alloc] initWithSource:source topicTitle:topicTitle];
    (void)supportedActions;
    (void)defaultSections;
    return [SCISetting navigationCellWithTitle:@"Configure Actions"
                                      subtitle:@""
                                          icon:SCISettingsIcon(@"slider")
                                viewController:controller];
}

UIMenu *SCIReelsTapControlMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Default", nil, nil, @"reels_tap_control", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SCIMenuCommand(@"Pause/Play", nil, nil, @"reels_tap_control", @"pause", YES),
            SCIMenuCommand(@"Mute/Unmute", nil, nil, @"reels_tap_control", @"mute", YES)
        ]]
    ]];
}

UIMenu *SCIMainFeedModeMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"For You", @"heart", nil, @"main_feed_mode", @"default", YES),
        SCIMenuCommand(@"Following", @"users", nil, @"main_feed_mode", @"following", YES)
    ]];
}

UIMenu *SCINavigationIconOrderingMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Default", nil, nil, @"interface_nav_order", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SCIMenuCommand(@"Classic", nil, nil, @"interface_nav_order", @"classic", YES),
            SCIMenuCommand(@"Standard", nil, nil, @"interface_nav_order", @"standard", YES),
            SCIMenuCommand(@"Alternate", nil, nil, @"interface_nav_order", @"alternate", YES)
        ]]
    ]];
}

UIMenu *SCILaunchTabMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Default", nil, nil, @"interface_launch_tab", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SCIMenuCommand(@"Feed", @"home", nil, @"interface_launch_tab", @"feed", YES),
            SCIMenuCommand(@"Reels", @"reels", nil, @"interface_launch_tab", @"reels", YES),
            SCIMenuCommand(@"Messages", @"messages", nil, @"interface_launch_tab", @"inbox", YES),
            SCIMenuCommand(@"Explore", @"search", nil, @"interface_launch_tab", @"explore", YES),
            SCIMenuCommand(@"Profile", @"user_circle", nil, @"interface_launch_tab", @"profile", YES)
        ]]
    ]];
}

UIMenu *SCISwipeBetweenTabsMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Default", nil, nil, @"interface_swipe_tabs", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SCIMenuCommand(@"Enabled", nil, nil, @"interface_swipe_tabs", @"enabled", YES),
            SCIMenuCommand(@"Disabled", nil, nil, @"interface_swipe_tabs", @"disabled", YES)
        ]]
    ]];
}

UIMenu *SCILiquidGlassTabBarStateMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Default", nil, nil, kSCIPrefInterfaceLiquidGlassTabBarMode, @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SCIMenuCommand(@"Fixed", nil, nil, kSCIPrefInterfaceLiquidGlassTabBarMode, @"fixed", YES),
            SCIMenuCommand(@"Hide on Scroll", nil, nil, kSCIPrefInterfaceLiquidGlassTabBarMode, @"hide", YES)
        ]]
    ]];
}

UIMenu *SCISwipeCloseCommentsDirectionMenu(void) {
    static NSString * const kSCISwipeCloseCommentsDirectionKey = @"general_comments_swipe_close_direction";
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Both", @"left_right", nil, kSCISwipeCloseCommentsDirectionKey, @"both", NO),
        SCIMenuCommand(@"Left", @"arrow_left", nil, kSCISwipeCloseCommentsDirectionKey, @"left", NO),
        SCIMenuCommand(@"Right", @"arrow_right", nil, kSCISwipeCloseCommentsDirectionKey, @"right", NO)
    ]];
}

UIMenu *SCICacheAutoClearMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Never", nil, nil, @"general_cache_auto_clear", @"never", NO),
        SCIMenuCommand(@"Always", nil, nil, @"general_cache_auto_clear", @"always", NO),
        SCIMenuCommand(@"Daily", nil, nil, @"general_cache_auto_clear", @"daily", NO),
        SCIMenuCommand(@"Weekly", nil, nil, @"general_cache_auto_clear", @"weekly", NO),
        SCIMenuCommand(@"Monthly", nil, nil, @"general_cache_auto_clear", @"monthly", NO)
    ]];
}

UIMenu *SCINotificationProgressSubtitleStyleMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Both", nil, nil, kSCINotificationProgressSubtitleStyleKey, @"both", NO),
        SCIMenuCommand(@"Percent", nil, nil, kSCINotificationProgressSubtitleStyleKey, @"percent", NO),
        SCIMenuCommand(@"Bytes", nil, nil, kSCINotificationProgressSubtitleStyleKey, @"bytes", NO),
        SCIMenuCommand(@"Off", nil, nil, kSCINotificationProgressSubtitleStyleKey, @"off", NO)
    ]];
}

UIMenu *SCINotificationPillPositionMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Top", nil, nil, kSCINotificationPillPositionKey, @"top", NO),
        SCIMenuCommand(@"Bottom", nil, nil, kSCINotificationPillPositionKey, @"bottom", NO)
    ]];
}

UIMenu *SCIMediaVideoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Default", nil, nil, @"downloads_video_quality", @"high_ignore_dash", NO),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SCIMenuCommand(@"Always Ask", nil, nil, @"downloads_video_quality", @"always_ask", NO),
            SCIMenuCommand(@"High", nil, nil, @"downloads_video_quality", @"high", NO),
            SCIMenuCommand(@"Medium", nil, nil, @"downloads_video_quality", @"medium", NO),
            SCIMenuCommand(@"Low", nil, nil, @"downloads_video_quality", @"low", NO)
        ]]
    ]];
}

UIMenu *SCIMediaPhotoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Always Ask", nil, nil, @"downloads_photo_quality", @"always_ask", NO),
        SCIMenuCommand(@"High", nil, nil, @"downloads_photo_quality", @"high", NO),
        SCIMenuCommand(@"Low", nil, nil, @"downloads_photo_quality", @"low", NO)
    ]];
}

UIMenu *SCIGalleryShortcutTargetMenu(void) {
    NSString * const kGalleryLongPressTabKey = @"gallery_quick_access_tab";
    NSString * const kGalleryQuickAccessDisabledValue = @"none";

    NSMutableArray<UIMenuElement *> *commands = [NSMutableArray array];

    NSArray<NSDictionary *> *items = @[
        @{@"title": @"None", @"value": kGalleryQuickAccessDisabledValue, @"icon": @"circle_off"},
        @{@"title": @"Home", @"value": @"mainfeed-tab", @"icon": @"home"},
        @{@"title": @"Reels", @"value": @"reels-tab", @"icon": @"reels"}
    ];

    NSMutableArray *allItems = [items mutableCopy];
    if ([SCIUtils tabOrderSetTo:@"classic"]) {
        [allItems addObject:@{@"title": @"Create", @"value": @"camera-tab", @"icon": @"plus"}];
    } else {
        [allItems addObject:@{@"title": @"Messages", @"value": @"direct-inbox-tab", @"icon": @"messages"}];
    }
    [allItems addObject:@{@"title": @"Profile", @"value": @"profile-tab", @"icon": @"user_circle"}];

    for (NSDictionary *item in allItems) {
        NSString *title = item[@"title"];
        NSString *value = item[@"value"];
        NSString *iconName = item[@"icon"];

        [commands addObject:SCIMenuCommand(title, iconName, nil, kGalleryLongPressTabKey, value, YES)];
    }

    return [UIMenu menuWithChildren:commands];
}

NSArray *SCIDevExampleSections(void) {
    return @[
        SCITopicSection(@"_ Example", @[
            [SCISetting staticCellWithTitle:@"Static Cell" subtitle:@"" icon:SCISettingsSystemIcon(@"tablecells", SCISettingsCellIconPointSize, UIImageSymbolWeightRegular)],
            [SCISetting switchCellWithTitle:@"Switch Cell" subtitle:@"Tap the switch" defaultsKey:@"test_switch_cell"],
            [SCISetting switchCellWithTitle:@"Switch Cell (Restart)" subtitle:@"Tap the switch" defaultsKey:@"test_switch_cell_restart" requiresRestart:YES],
            [SCISetting stepperCellWithTitle:@"Stepper Cell" subtitle:@"I have %@%@" defaultsKey:@"test_stepper_cell" min:-10 max:1000 step:5.5 label:@"$" singularLabel:@"$"],
            SCISettingApplyIconTint([SCISetting linkCellWithTitle:@"Link Cell" subtitle:@"Using icon" icon:SCISettingsSystemIcon(@"link", SCISettingsCellIconPointSize, UIImageSymbolWeightRegular) url:@"https://google.com"], [UIColor systemTealColor]),
            [SCISetting linkCellWithTitle:@"Link Cell" subtitle:@"Using image" imageUrl:@"https://i.imgur.com/c9CbytZ.png" url:@"https://google.com"],
            [SCISetting buttonCellWithTitle:@"Button Cell" subtitle:@"" icon:SCISettingsSystemIcon(@"oval.inset.filled", SCISettingsCellIconPointSize, UIImageSymbolWeightRegular) action:^(void) { [SCIUtils showConfirmation:^(void){} title:@"Run Example Action?" message:@"Are you sure you want to run this example settings action?"]; }],
            [SCISetting menuCellWithTitle:@"Menu Cell" subtitle:@"Change the value on the right" menu:[UIMenu menuWithChildren:@[
                [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
                    SCIMenuCommand(@"ABC", nil, nil, @"test_menu_cell", @"abc", NO),
                    SCIMenuCommand(@"123", nil, nil, @"test_menu_cell", @"123", NO)
                ]],
                SCIMenuCommand(@"Requires Restart", nil, nil, @"test_menu_cell", @"requires_restart", YES)
            ]]],
            [SCISetting navigationCellWithTitle:@"Navigation Cell" subtitle:@"" icon:SCISettingsSystemIcon(@"rectangle.stack", SCISettingsCellIconPointSize, UIImageSymbolWeightRegular) navSections:@[SCITopicSection(@"", @[], nil)]]
        ], @"_ Example")
    ];
}

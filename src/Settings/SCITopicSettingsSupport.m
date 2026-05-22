#import "SCITopicSettingsSupport.h"
#import "SCIEditActionsListViewController.h"
#import "SCIBulkActionMenuEditViewController.h"

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
    return [SCIAssetUtils resolvedImageNamed:name
                                   pointSize:pointSize
                                      weight:weight
                                      source:SCIResolvedImageSourceSystemSymbol
                               renderingMode:UIImageRenderingModeAlwaysTemplate];
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

static NSString *SCIActionButtonDisplayTitle(NSString *identifier, NSString *topicTitle) {
    return SCIActionDescriptorDisplayTitle(identifier, topicTitle);
}

UIMenu *SCIActionButtonDefaultActionMenu(NSString *defaultsKey, NSString *topicTitle, NSArray<NSString *> *supportedActions) {
    NSMutableArray<UIMenuElement *> *commands = [NSMutableArray array];

    NSMutableOrderedSet<NSString *> *supportedSet = [NSMutableOrderedSet orderedSet];
    for (NSString *identifier in supportedActions ?: @[]) {
        if ([identifier isKindOfClass:[NSString class]] && identifier.length > 0) {
            [supportedSet addObject:identifier];
        }
    }

    NSArray<NSArray<NSString *> *> *groups = @[
        @[kSCIActionDownloadLibrary, kSCIActionDownloadShare, kSCIActionDownloadGallery],
        @[kSCIActionExpand, kSCIActionViewThumbnail],
        @[kSCIActionCopyMedia, kSCIActionCopyDownloadLink, kSCIActionCopyCaption, kSCIActionProfileCopyInfo],
        @[kSCIActionOpenTopicSettings, kSCIActionRepost]
    ];

    for (NSInteger groupIndex = 0; groupIndex < (NSInteger)groups.count; groupIndex++) {
        NSArray<NSString *> *group = groups[groupIndex];
        NSMutableArray<UIMenuElement *> *groupCommands = [NSMutableArray array];
        for (NSString *identifier in group) {
            if (![supportedSet containsObject:identifier]) continue;
            [groupCommands addObject:SCIMenuCommand(SCIActionButtonDisplayTitle(identifier, topicTitle),
                                                    SCIActionDescriptorIconName(identifier),
                                                    nil,
                                                    defaultsKey,
                                                    identifier,
                                                    NO)];
        }
        if (groupIndex == (NSInteger)groups.count - 1) {
            [groupCommands addObject:SCIMenuCommand(@"None", @"action", nil, defaultsKey, kSCIActionNone, NO)];
        }
        if (groupCommands.count == 0) continue;
        [commands addObject:[UIMenu menuWithTitle:@""
                                            image:nil
                                       identifier:nil
                                          options:UIMenuOptionsDisplayInline
                                         children:groupCommands]];
    }

    if (commands.count == 0) {
        [commands addObject:SCIMenuCommand(@"None", @"action", nil, defaultsKey, kSCIActionNone, NO)];
    }

    return [UIMenu menuWithChildren:commands];
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

UIMenu *SCINavigationIconOrderingMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Default", nil, nil, @"nav_icon_ordering", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SCIMenuCommand(@"Classic", nil, nil, @"nav_icon_ordering", @"classic", YES),
            SCIMenuCommand(@"Standard", nil, nil, @"nav_icon_ordering", @"standard", YES),
            SCIMenuCommand(@"Alternate", nil, nil, @"nav_icon_ordering", @"alternate", YES)
        ]]
    ]];
}

UIMenu *SCISwipeBetweenTabsMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Default", nil, nil, @"swipe_nav_tabs", @"default", YES),
        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SCIMenuCommand(@"Enabled", nil, nil, @"swipe_nav_tabs", @"enabled", YES),
            SCIMenuCommand(@"Disabled", nil, nil, @"swipe_nav_tabs", @"disabled", YES)
        ]]
    ]];
}

UIMenu *SCISwipeCloseCommentsDirectionMenu(void) {
    static NSString * const kSCISwipeCloseCommentsDirectionKey = @"comments_swipe_to_close_direction";
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Both", @"left_right", nil, kSCISwipeCloseCommentsDirectionKey, @"both", NO),
        SCIMenuCommand(@"Left", @"arrow_left", nil, kSCISwipeCloseCommentsDirectionKey, @"left", NO),
        SCIMenuCommand(@"Right", @"arrow_right", nil, kSCISwipeCloseCommentsDirectionKey, @"right", NO)
    ]];
}

UIMenu *SCICacheAutoClearMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Never", nil, nil, @"cache_auto_clear_mode", @"never", NO),
        SCIMenuCommand(@"Always", nil, nil, @"cache_auto_clear_mode", @"always", NO),
        SCIMenuCommand(@"Daily", nil, nil, @"cache_auto_clear_mode", @"daily", NO),
        SCIMenuCommand(@"Weekly", nil, nil, @"cache_auto_clear_mode", @"weekly", NO),
        SCIMenuCommand(@"Monthly", nil, nil, @"cache_auto_clear_mode", @"monthly", NO)
    ]];
}

UIMenu *SCIMediaVideoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Always Ask", nil, nil, @"media_video_quality_default", @"always_ask", NO),
        SCIMenuCommand(@"High", nil, nil, @"media_video_quality_default", @"high", NO),
        SCIMenuCommand(@"High (Ignore Dash)", nil, nil, @"media_video_quality_default", @"high_ignore_dash", NO),
        SCIMenuCommand(@"Medium", nil, nil, @"media_video_quality_default", @"medium", NO),
        SCIMenuCommand(@"Low", nil, nil, @"media_video_quality_default", @"low", NO)
    ]];
}

UIMenu *SCIMediaPhotoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIMenuCommand(@"Always Ask", nil, nil, @"media_photo_quality_default", @"always_ask", NO),
        SCIMenuCommand(@"High", nil, nil, @"media_photo_quality_default", @"high", NO),
        SCIMenuCommand(@"Low", nil, nil, @"media_photo_quality_default", @"low", NO)
    ]];
}

UIMenu *SCIGalleryShortcutTargetMenu(void) {
    NSString * const kGalleryLongPressTabKey = @"gallery_long_press_tab";
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

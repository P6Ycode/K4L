#import "SCIGallerySettingsProvider.h"
#import "../SCITopicSettingsSupport.h"
#import "../SCISetting.h"

#import "../../Utils.h"
#import "../../Shared/Gallery/SCIGallerySettingsViewController.h"
#import "../../Shared/Gallery/SCIGalleryViewController.h"

static NSString * const kSCIGalleryQuickAccessDisabledValue = @"none";
/// TODO: remove
static NSString * const kSCIGalleryLegacyQuickAccessEnabledKey = @"header_long_press_gallery";
static NSString * const kSCIGalleryLongPressTabKey = @"gallery_long_press_tab";

/// TODO: remove
static void SCIMigrateLegacyGalleryQuickAccessSettingIfNeeded(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *existingValue = [defaults stringForKey:kSCIGalleryLongPressTabKey];
    BOOL usesClassic = [SCIUtils tabOrderSetTo:@"classic"];
    if (existingValue.length > 0) {
        if (usesClassic && [existingValue isEqualToString:@"direct-inbox-tab"]) {
            [defaults setObject:@"camera-tab" forKey:kSCIGalleryLongPressTabKey];
        } else if (!usesClassic && [existingValue isEqualToString:@"camera-tab"]) {
            [defaults setObject:@"direct-inbox-tab" forKey:kSCIGalleryLongPressTabKey];
        }
        return;
    }

    BOOL enabled = [defaults objectForKey:kSCIGalleryLegacyQuickAccessEnabledKey] && [defaults boolForKey:kSCIGalleryLegacyQuickAccessEnabledKey];
    NSString *value = enabled ? (usesClassic ? @"camera-tab" : @"direct-inbox-tab") : kSCIGalleryQuickAccessDisabledValue;
    [defaults setObject:value forKey:kSCIGalleryLongPressTabKey];
}


@implementation SCIGallerySettingsProvider

+ (SCISetting *)rootSetting {
    /// TODO: remove
    SCIMigrateLegacyGalleryQuickAccessSettingIfNeeded();

    return SCITopicNavigationSetting(@"Gallery", @"media", 24.0, @[
        SCITopicSection(@"Access", @[
            [SCISetting buttonCellWithTitle:@"Open Gallery"
                                   subtitle:@""
                                       icon:SCISettingsIcon(@"media")
                                     action:^(void) {
                [SCIGalleryViewController presentGallery];
            }],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Quick Gallery Access" icon:SCISettingsIcon(@"circle_off") menu:SCIGalleryShortcutTargetMenu()], SCISettingsIcon(@"circle_off"))
        ], @"Choose the tab that opens Gallery on long press. None disables the action."),
        SCITopicSection(@"Browsing", @[
            [SCISetting switchCellWithTitle:@"Show Favorites at Top"
                                       icon:SCISettingsIcon(@"heart")
                                defaultsKey:@"show_favorites_at_top"]
        ], @"Pin favorites above other files in the current sort and folder context."),
        SCITopicSection(@"Lock & Maintenance", @[
            [SCISetting navigationCellWithTitle:@"Gallery Settings"
                                       subtitle:nil
                                           icon:SCISettingsIcon(@"settings")
                                 viewController:[[SCIGallerySettingsViewController alloc] init]]
        ], @"Manage passcode, import files, view storage, and delete with options.")
    ]);
}

@end

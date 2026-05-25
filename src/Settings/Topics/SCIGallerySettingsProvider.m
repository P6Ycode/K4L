#import "SCIGallerySettingsProvider.h"
#import "../SCITopicSettingsSupport.h"
#import "../SCISetting.h"

#import "../../Utils.h"
#import "../../Shared/Gallery/SCIGallerySettingsViewController.h"
#import "../../Shared/Gallery/SCIGalleryViewController.h"

@implementation SCIGallerySettingsProvider

+ (SCISetting *)rootSetting {
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
                                defaultsKey:@"gallery_show_favorites_top"]
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

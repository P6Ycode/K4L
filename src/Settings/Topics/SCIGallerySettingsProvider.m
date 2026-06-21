#import "SCIGallerySettingsProvider.h"
#import "../SCITopicSettingsSupport.h"
#import "../SCISetting.h"

#import "../../Utils.h"
#import "../../Shared/Gallery/SCIGallerySettingsViewController.h"
#import "../../Shared/Gallery/SCIGalleryViewController.h"

@implementation SCIGallerySettingsProvider

+ (SCISetting *)rootSetting {
    SCISetting *gallerySettings = [SCISetting navigationCellWithTitle:@"Gallery Settings"
                                                             subtitle:nil
                                                                 icon:SCISettingsIcon(@"settings")
                                                       viewController:[[SCIGallerySettingsViewController alloc] init]];
    gallerySettings.searchSectionsProvider = ^NSArray *{
        return [SCIGallerySettingsViewController searchSections];
    };

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
        SCITopicSection(@"Trimming", @[
            [SCISetting switchCellWithTitle:@"Ask to Replace Original"
                                       icon:SCISettingsIcon(@"trim")
                                defaultsKey:@"trim_gallery_prompt_replace"]
        ], @"When you trim a Gallery item, ask whether to replace the original or save a copy. Off always saves a copy and keeps the original."),
        SCITopicSection(@"Lock & Maintenance", @[
            gallerySettings
        ], @"Manage passcode, import files, view storage, and delete with options.")
    ]);
}

@end

#import "SPKGallerySettingsProvider.h"
#import "../SPKTopicSettingsSupport.h"
#import "../SPKSetting.h"

#import "../../Utils.h"
#import "../../Shared/Gallery/SPKGallerySettingsViewController.h"
#import "../../Shared/Gallery/SPKGalleryViewController.h"

@implementation SPKGallerySettingsProvider

+ (SPKSetting *)rootSetting {
    SPKSetting *gallerySettings = [SPKSetting navigationCellWithTitle:@"Gallery Settings"
                                                             subtitle:nil
                                                                 icon:SPKSettingsIcon(@"settings")
                                                       viewController:[[SPKGallerySettingsViewController alloc] init]];
    gallerySettings.searchSectionsProvider = ^NSArray *{
        return [SPKGallerySettingsViewController searchSections];
    };

    return SPKTopicNavigationSetting(@"Gallery", @"media", 24.0, @[
        SPKTopicSection(@"Access", @[
            [SPKSetting buttonCellWithTitle:@"Open Gallery"
                                   subtitle:@""
                                       icon:SPKSettingsIcon(@"media")
                                     action:^(void) {
                [SPKGalleryViewController presentGallery];
            }],
            SPKSettingApplySelectedMenuIcon([SPKSetting menuCellWithTitle:@"Quick Gallery Access" icon:SPKSettingsIcon(@"circle_off") menu:SPKGalleryShortcutTargetMenu()], SPKSettingsIcon(@"circle_off"))
        ], @"Choose the tab that opens Gallery on long press. None disables the action."),
        SPKTopicSection(@"Browsing", @[
            [SPKSetting switchCellWithTitle:@"Show Favorites at Top"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"gallery_show_favorites_top"]
        ], @"Pin favorites above other files in the current sort and folder context."),
        SPKTopicSection(@"Editing", @[
            [SPKSetting switchCellWithTitle:@"Ask to Replace Original"
                                       icon:SPKSettingsIcon(@"trim")
                                defaultsKey:@"trim_gallery_prompt_replace"]
        ], @"When you trim or edit a Gallery item, ask whether to replace the original or save a copy. Off always saves a copy and keeps the original."),
        SPKTopicSection(@"Lock & Maintenance", @[
            gallerySettings
        ], @"Manage passcode, import files, view storage, and delete with options.")
    ]);
}

@end

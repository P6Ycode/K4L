#import "SCIProfileSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"

static NSString * const kSCIProfileActionNone = @"none";
static NSString * const kSCIProfileActionCopyInfo = @"copy_info";
static NSString * const kSCIProfileActionViewPicture = @"view_picture";
static NSString * const kSCIProfileActionSharePicture = @"share_picture";
static NSString * const kSCIProfileActionSavePictureToGallery = @"save_picture_gallery";
static NSString * const kSCIProfileActionOpenSettings = @"profile_settings";
static NSString * const kSCIProfileDefaultCopyInfoKey = @"action_button_profile_default_copy_info_action";
static NSString * const kSCIProfileCopyInfoID = @"id";
static NSString * const kSCIProfileCopyInfoUsername = @"username";
static NSString * const kSCIProfileCopyInfoName = @"name";
static NSString * const kSCIProfileCopyInfoBio = @"bio";
static NSString * const kSCIProfileCopyInfoLink = @"link";
static CGFloat const kSCIProfileSettingsMenuIconPointSize = 22.0;

static UIImage *SCIProfileSettingsMenuIcon(NSString *resourceName) {
    return [SCIAssetUtils instagramIconNamed:resourceName pointSize:kSCIProfileSettingsMenuIconPointSize];
}

static UICommand *SCIProfileActionDefaultCommand(NSString *title, NSString *resourceName, NSString *value) {
    UIImage *image = SCIProfileSettingsMenuIcon(resourceName);
    return [UICommand commandWithTitle:title
                                 image:image
                                action:@selector(menuChanged:)
                          propertyList:@{
        @"defaultsKey": @"action_button_profile_default_action",
        @"value": value,
        @"iconName": resourceName
    }];
}

static UIMenu *SCIProfileActionDefaultMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIProfileActionDefaultCommand(@"None", @"action", kSCIProfileActionNone),
        SCIProfileActionDefaultCommand(@"Copy Info", @"copy", kSCIProfileActionCopyInfo),
        SCIProfileActionDefaultCommand(@"View Picture", @"photo", kSCIProfileActionViewPicture),
        SCIProfileActionDefaultCommand(@"Share Picture", @"share", kSCIProfileActionSharePicture),
        SCIProfileActionDefaultCommand(@"Save to Gallery", @"media", kSCIProfileActionSavePictureToGallery),
        SCIProfileActionDefaultCommand(@"Profile Settings", @"settings", kSCIProfileActionOpenSettings)
    ]];
}

static UICommand *SCIProfileDefaultCopyInfoCommand(NSString *title, NSString *resourceName, NSString *value) {
    UIImage *image = SCIProfileSettingsMenuIcon(resourceName);
    return [UICommand commandWithTitle:title
                                 image:image
                                action:@selector(menuChanged:)
                          propertyList:@{
        @"defaultsKey": kSCIProfileDefaultCopyInfoKey,
        @"value": value,
        @"iconName": resourceName
    }];
}

static UIMenu *SCIProfileDefaultCopyInfoMenu(void) {
    return [UIMenu menuWithChildren:@[
        SCIProfileDefaultCopyInfoCommand(@"ID", @"key", kSCIProfileCopyInfoID),
        SCIProfileDefaultCopyInfoCommand(@"Username", @"username", kSCIProfileCopyInfoUsername),
        SCIProfileDefaultCopyInfoCommand(@"Name", @"text", kSCIProfileCopyInfoName),
        SCIProfileDefaultCopyInfoCommand(@"Bio", @"caption", kSCIProfileCopyInfoBio),
        SCIProfileDefaultCopyInfoCommand(@"Profile Link", @"link", kSCIProfileCopyInfoLink)
    ]];
}

@implementation SCIProfileSettingsProvider

+ (SCISetting *)rootSetting {
    return SCITopicNavigationSetting(@"Profile", @"user_circle", 24.0, @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Profile Action Button" icon:SCISettingsIcon(@"action") defaultsKey:@"action_button_profile_enabled"],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Default Tap Action" icon:SCISettingsIcon(@"action") menu:SCIActionButtonDefaultActionMenu(@"action_button_profile_default_action", @"Profile", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceProfile))], SCISettingsIcon(@"action")),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceProfile, @"Profile", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceProfile), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceProfile)),
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Copy Info Default" icon:SCISettingsIcon(@"copy") menu:SCIProfileDefaultCopyInfoMenu()], SCISettingsIcon(@"copy"))
        ], @"Choose what tapping the action button does. Copy Info Default controls what gets copied when Default Tap Action is Copy Info."),
        SCITopicSection(@"Profile Picture", @[
            [SCISetting switchCellWithTitle:@"Long Press to Expand" icon:SCISettingsIcon(@"expand") defaultsKey:@"profile_photo_zoom"]
        ], @"Long press a profile picture to open it expanded."),
        SCITopicSection(@"Indicators", @[
            [SCISetting switchCellWithTitle:@"Show Following Indicator" icon:SCISettingsIcon(@"user_check") defaultsKey:@"follow_indicator"],
            [SCISetting switchCellWithTitle:@"Hide Notes Bubble" icon:SCISettingsIcon(@"notes") defaultsKey:@"hide_profile_notes_bubble"],
            [SCISetting switchCellWithTitle:@"Hide Threads Button" icon:SCISettingsIcon(@"threads") defaultsKey:@"hide_profile_threads_button"]
        ], nil),
        SCITopicSection(@"Confirmation", @[
            [SCISetting switchCellWithTitle:@"Confirm Follow" icon:SCISettingsIcon(@"user_follow") defaultsKey:@"follow_confirm"],
            [SCISetting switchCellWithTitle:@"Confirm Unfollow" icon:SCISettingsIcon(@"user_unfollow") defaultsKey:@"unfollow_confirm"]
        ], @"Shows confirmation alerts before the enabled profile actions are performed.")
    ]);
}

@end

#import "SCIInstantsSettingsProvider.h"

#import "../SCITopicSettingsSupport.h"
#import "../SCISettingsViewController.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../../Utils.h"

static NSString * const kSCIInstantsActionButtonEnabledKey = @"instants_action_btn";

static NSArray *SCIInstantsSettingsSections(void);

@interface SCIInstantsSettingsViewController : SCISettingsViewController
@end

@implementation SCIInstantsSettingsViewController
- (instancetype)init {
    return [super initWithTitle:@"Instants" sections:SCIInstantsSettingsSections() reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self replaceSections:SCIInstantsSettingsSections()];
}
@end

static NSArray *SCIInstantsSettingsSections(void) {
    return @[
        SCITopicSection(@"Action Button", @[
            [SCISetting switchCellWithTitle:@"Instants Action Button" icon:SCISettingsIcon(@"action") defaultsKey:kSCIInstantsActionButtonEnabledKey],
            SCIActionButtonDefaultActionNavigationSetting(SCIActionButtonSourceInstants),
            SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSourceInstants, @"Instants", SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceInstants), SCIActionButtonDefaultSectionsForSource(SCIActionButtonSourceInstants))
        ], @"Choose what tapping the action button does. Long press opens the full menu."),
        SCITopicSection(@"Privacy", @[
            [SCISetting switchCellWithTitle:@"Allow Screenshots" icon:SCISettingsIcon(@"warning") defaultsKey:@"instants_allow_screenshot"],
        ], @"Bypass screenshot and screen recording detection in the Instants viewer."),
        SCITopicSection(@"Creation", @[
            [SCISetting switchCellWithTitle:@"Disable Instants Creation" icon:SCISettingsIcon(@"instants") defaultsKey:@"instants_disable_creation"],
            [SCISetting switchCellWithTitle:@"Skip Camera After Instants" icon:SCISettingsIcon(@"camera") defaultsKey:@"instants_skip_camera_after_viewing"],
            [SCISetting switchCellWithTitle:@"Upload from Gallery" icon:SCISettingsIcon(@"media") defaultsKey:@"instants_upload_from_gallery"],
        ], @"1. Blocks the Instant shutter button without disabling received Instants.\n"
           @"2. Skips the camera page Instagram opens after viewing the last Instant.\n"
           @"3. Adds a gallery button to the Instants camera to upload from Photos, Files, or Gallery."),
        SCITopicSection(@"Confirmation", @[
            [SCISetting switchCellWithTitle:@"Confirm Instant Capture" icon:SCISettingsIcon(@"instants_burst") defaultsKey:@"instants_confirm_capture"],
            [SCISetting switchCellWithTitle:@"Confirm Instant Reaction" icon:SCISettingsIcon(@"reactions") defaultsKey:@"instants_confirm_reaction"],
        ], @"Shows confirmation alerts before the selected Instant actions are sent."),
    ];
}

@implementation SCIInstantsSettingsProvider

+ (SCISetting *)rootSetting {
    SCISetting *setting = [SCISetting navigationCellWithTitle:@"Instants"
                                                     subtitle:@""
                                                         icon:SCISettingsIcon(@"instants")
                                               viewController:[[SCIInstantsSettingsViewController alloc] init]];
    setting.searchSectionsProvider = ^NSArray *{
        return SCIInstantsSettingsSections();
    };
    return SCISettingApplyIconTint(setting, [SCIUtils SCIColor_InstagramPrimaryText]);
}

@end

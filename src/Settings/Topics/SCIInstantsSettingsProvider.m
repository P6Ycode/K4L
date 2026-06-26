#import "SCIInstantsSettingsProvider.h"
#include <UIKit/UIKit.h>

#import "../SCITopicSettingsSupport.h"
#import "../SCISettingsViewController.h"
#import "../SCIPreferenceAvailability.h"
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
            ({  SCISetting *s = [SCISetting switchCellWithTitle:@"Disable Instants Creation" icon:SCISettingsIcon(@"instants") defaultsKey:@"instants_disable_creation"];
                s.switchChangeHandler = ^(BOOL isOn) {
                    SCIPreferenceSetObject(@(isOn), @"instants_disable_creation");
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"SCIQuickSnapCreationPrefChangedNotification" object:nil];
                };
                s;
            }),
            [SCISetting switchCellWithTitle:@"Skip Camera After Instants" icon:SCISettingsIcon(@"camera") defaultsKey:@"instants_skip_camera_after_viewing"],
            ({  BOOL cameraControlAvailable = SCIPrefIsAvailable(@"instants_disable_camera_control");
                SCISetting *s = [SCISetting switchCellWithTitle:@"Disable Camera Control"
                                                       subtitle:cameraControlAvailable ? @"" : @"Requires an iPhone with Camera Control"
                                                           icon:SCISettingsSystemIcon(@"button.vertical.right.press", SCISettingsCellIconPointSize, UIImageSymbolWeightSemibold)
                                                    defaultsKey:@"instants_disable_camera_control"];
                s;
            }),
            [SCISetting switchCellWithTitle:@"Upload from Gallery" icon:SCISettingsIcon(@"media") defaultsKey:@"instants_upload_from_gallery"],
        ], @"1. Blocks Instant capture (photo and video) without disabling received Instants. The shutter is darkened.\n"
           @"2. Skips the camera page Instagram opens after viewing the last Instant.\n"
           @"3. Stops the hardware Camera Control button (iPhone 16/17) from taking an Instant.\n"
           @"4. Adds a gallery button to the Instants camera to upload from Photos, Files, or Gallery."),
        SCITopicSection(@"Confirmation", @[
            ({
                SCISetting *s = [SCISetting switchCellWithTitle:@"Confirm Instant Capture"
                                                           icon:SCISettingsIcon(@"instants_burst")
                                                    defaultsKey:@"instants_confirm_capture"];
                s.enabledProvider = ^BOOL{ return NO; };
                s;
            }),
            [SCISetting switchCellWithTitle:@"Confirm Instant Reaction" icon:SCISettingsIcon(@"reactions") defaultsKey:@"instants_confirm_reaction"],
        ], @"1. Asks for confirmation when you send a captured Instant. Temporarily unavailable.\n"
           @"2. Shows a confirmation alert before an Instant reaction is sent."),
    ];
}

@implementation SCIInstantsSettingsProvider

+ (UIViewController *)makeSettingsViewController {
    return [[SCIInstantsSettingsViewController alloc] init];
}

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

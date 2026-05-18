#import "SCIToolsSettingsProvider.h"
#include <UIKit/UIKit.h>

#import "../SCITopicSettingsSupport.h"
#import "SCIInterfaceSettingsProvider.h"
#import "../SCISettingsTransferManager.h"
#import "../../App/SCIFlexLoader.h"
#import "../../Utils.h"

@interface SCISettingsTransferSelectionViewController : SCISettingsViewController
@property (nonatomic, assign) BOOL importMode;
@property (nonatomic, assign) BOOL includeSettings;
@property (nonatomic, assign) BOOL includeGallery;
- (instancetype)initWithImportMode:(BOOL)importMode;
@end

@implementation SCISettingsTransferSelectionViewController

- (instancetype)initWithImportMode:(BOOL)importMode {
    if ((self = [super initWithTitle:(importMode ? @"Import" : @"Export") sections:@[] reduceMargin:NO])) {
        _importMode = importMode;
        _includeSettings = YES;
        _includeGallery = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:(self.importMode ? @"Import" : @"Export")
                                                                              style:(UIBarButtonItemStyle)2 // done/prominent
                                                                             target:self
                                                                             action:@selector(runTransfer)];
    [self rebuildSections];
    [self updateActionEnabled];
}

- (void)rebuildSections {
    SCISetting *settingsRow = [SCISetting buttonCellWithTitle:@"Settings" subtitle:@"SCInsta preferences" icon:nil action:^{
        self.includeSettings = !self.includeSettings;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    settingsRow.userInfo = @{@"checkmarked": @(self.includeSettings)};

    SCISetting *galleryRow = [SCISetting buttonCellWithTitle:@"Gallery" subtitle:@"Gallery media and metadata" icon:nil action:^{
        self.includeGallery = !self.includeGallery;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    galleryRow.userInfo = @{@"checkmarked": @(self.includeGallery)};

    NSArray *sections = @[SCITopicSection(@"", @[settingsRow, galleryRow], self.importMode ? @"A restart prompt appears after a successful import." : nil)];
    [self replaceSections:sections];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    SCISetting *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (row.userInfo[@"checkmarked"]) {
        BOOL checked = [row.userInfo[@"checkmarked"] boolValue];
        cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)updateActionEnabled {
    self.navigationItem.rightBarButtonItem.enabled = self.includeSettings || self.includeGallery;
}

- (void)runTransfer {
    if (!(self.includeSettings || self.includeGallery)) return;
    UIViewController *presenter = self.navigationController ?: self;
    if (self.importMode) {
        [[SCISettingsTransferManager sharedManager] importFromController:presenter includeSettings:self.includeSettings includeGallery:self.includeGallery];
    } else {
        [[SCISettingsTransferManager sharedManager] exportFromController:presenter includeSettings:self.includeSettings includeGallery:self.includeGallery];
    }
}

@end

static NSArray *SCIManageSettingsDataSections(void) {
    return @[
        SCITopicSection(@"", @[
            SCISettingApplyIconTint([SCISetting navigationCellWithTitle:@"Export"
                                                                subtitle:@"Choose settings, Gallery, or both"
                                                                    icon:SCISettingsIcon(@"arrow_up")
                                                          viewController:[[SCISettingsTransferSelectionViewController alloc] initWithImportMode:NO]],
                                  [SCIUtils SCIColor_InstagramPrimaryText]),
            SCISettingApplyIconTint([SCISetting navigationCellWithTitle:@"Import"
                                                                subtitle:@"Choose settings, Gallery, or both"
                                                                    icon:SCISettingsIcon(@"arrow_down")
                                                          viewController:[[SCISettingsTransferSelectionViewController alloc] initWithImportMode:YES]],
                                  [SCIUtils SCIColor_InstagramPrimaryText])
        ], nil),
        SCITopicSection(@"Reset", @[
            SCISettingApplyIconTint([SCISetting buttonCellWithTitle:@"Reset All Settings"
                                                            subtitle:@"Restore every preference to its default value"
                                                                icon:SCISettingsIcon(@"arrow_ccw")
                                                              action:^(void) {
                UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
                UIViewController *presenter = scene.windows.firstObject.rootViewController;
                while (presenter.presentedViewController) presenter = presenter.presentedViewController;
                [[SCISettingsTransferManager sharedManager] resetAllSettingsFromController:presenter];
            }], [SCIUtils SCIColor_InstagramPrimaryText])
        ], nil)
    ];
}

@implementation SCIToolsSettingsProvider

+ (SCISetting *)rootSetting {
    BOOL flexInstalled = SCIFlexIsBundled();
    NSString *flexFooter = flexInstalled
        ? @"The first time FLEX is opened in a session it can take a moment to initialize."
        : @"FLEX not installed. Rebuild with \"--flex\" flag or install libFLEX.dylib to enable these options.";
    SCISetting *flexGesture = [SCISetting switchCellWithTitle:@"Three-finger Gesture" defaultsKey:@"flex_instagram"];
    SCISetting *flexLaunch = [SCISetting switchCellWithTitle:@"Open on App Launch" defaultsKey:@"flex_app_launch"];
    SCISetting *flexFocus = [SCISetting switchCellWithTitle:@"Open on App Focus" defaultsKey:@"flex_app_start"];
    if (!flexInstalled) {
        flexGesture.userInfo = @{@"enabled": @NO};
        flexLaunch.userInfo = @{@"enabled": @NO};
        flexFocus.userInfo = @{@"enabled": @NO};
    }
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        SCITopicSection(@"FLEX", @[flexGesture, flexLaunch, flexFocus], [NSString stringWithFormat:@"Three-finger gesture opens FLEX after holding three fingers anywhere for 1.5 seconds. %@", flexFooter]),
        SCITopicSection(@"Tweak", @[
            [SCISetting switchCellWithTitle:@"Quick Settings Access" defaultsKey:@"settings_shortcut" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Show Settings on App Launch" defaultsKey:@"tweak_settings_app_launch"],
            [SCISetting switchCellWithTitle:@"Disable All Settings" defaultsKey:@"tweak_master_disabled" requiresRestart:YES],
            [SCISetting buttonCellWithTitle:@"Reset Onboarding Completion State" subtitle:@"" icon:nil action:^(void) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SCInstaFirstRun"];
                [SCIUtils showRestartConfirmation];
            }]
        ], @"Quick Settings Access opens settings when long pressing the Home tab."),
        SCITopicSection(@"Instagram", @[
            [SCISetting switchCellWithTitle:@"Disable Safe Mode" defaultsKey:@"disable_safe_mode"]
        ], @"Makes Instagram not reset settings after subsequent crashes. Use at your own risk."),
        SCITopicSection(@"Backup & Transfer", @[
            [SCISetting navigationCellWithTitle:@"Manage Settings & Data" subtitle:@"" icon:SCISettingsIcon(@"cloud") navSections:SCIManageSettingsDataSections()]
        ], nil),
        SCITopicSection(@"Liquid Glass", @[
            [SCISetting switchCellWithTitle:@"Enable Liquid Glass Buttons" defaultsKey:@"liquid_glass_buttons" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Enable Liquid Glass Surfaces" defaultsKey:@"liquid_glass_surfaces" requiresRestart:YES],
            [SCIInterfaceSettingsProvider experimentalLiquidGlassSetting]
        ], @"Experimental controls. Buttons affect in-app buttons; surfaces affect menus and related Instagram liquid-glass override defaults. Restart Instagram after changes.")
    ]];

    [sections addObjectsFromArray:SCIDevExampleSections()];

    return SCITopicNavigationSetting(@"Tools", @"toolbox", 24.0, sections);
}

@end

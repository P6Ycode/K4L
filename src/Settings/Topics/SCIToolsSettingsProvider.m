#import "SCIToolsSettingsProvider.h"
#include <UIKit/UIKit.h>

#import "../SCITopicSettingsSupport.h"
#import "SCIInterfaceSettingsProvider.h"
#import "../SCISettingsTransferManager.h"
#import "../../App/SCIFlexLoader.h"
#import "../../App/SCIStabilityGuard.h"
#import "../../Utils.h"
#import "../../AssetUtils.h"
#import "../../Shared/Gallery/SCIGalleryLockViewController.h"
#import "../../Shared/Settings/SCISettingsLockManager.h"
#import "../../Shared/UI/SCIIGAlertPresenter.h"

@interface SCISettingsTransferSelectionViewController : SCISettingsViewController
@property (nonatomic, assign) BOOL importMode;
@property (nonatomic, assign) BOOL includeSettings;
@property (nonatomic, assign) BOOL includeGallery;
@property (nonatomic, assign) BOOL includeDeletedMessages;
@property (nonatomic, assign) BOOL includeProfileAnalyzer;
- (instancetype)initWithImportMode:(BOOL)importMode;
@end

@implementation SCISettingsTransferSelectionViewController

- (instancetype)initWithImportMode:(BOOL)importMode {
    if ((self = [super initWithTitle:(importMode ? @"Import" : @"Export") sections:@[] reduceMargin:NO])) {
        _importMode = importMode;
        _includeSettings = YES;
        _includeGallery = YES;
        _includeDeletedMessages = YES;
        _includeProfileAnalyzer = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupTransferActionItem];
    [self rebuildSections];
    [self updateActionEnabled];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setupTransferActionItem];
    [self updateActionEnabled];
}

- (void)setupTransferActionItem {
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[SCIAssetUtils instagramIconNamed:(self.importMode ? @"arrow_down" : @"arrow_up")]
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(runTransfer)];
    self.navigationItem.rightBarButtonItem.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
}

- (void)rebuildSections {
    SCISetting *settingsRow = [SCISetting buttonCellWithTitle:@"Settings" subtitle:@"" icon:SCISettingsIcon(@"settings") action:^{
        self.includeSettings = !self.includeSettings;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    settingsRow.userInfo = @{@"checkmarked": @(self.includeSettings)};

    SCISetting *galleryRow = [SCISetting buttonCellWithTitle:@"Gallery" subtitle:@"" icon:SCISettingsIcon(@"media") action:^{
        self.includeGallery = !self.includeGallery;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    galleryRow.userInfo = @{@"checkmarked": @(self.includeGallery)};

    SCISetting *deletedMessagesRow = [SCISetting buttonCellWithTitle:@"Deleted Messages" subtitle:@"" icon:SCISettingsIcon(@"messages") action:^{
        self.includeDeletedMessages = !self.includeDeletedMessages;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    deletedMessagesRow.userInfo = @{@"checkmarked": @(self.includeDeletedMessages)};

    SCISetting *profileAnalyzerRow = [SCISetting buttonCellWithTitle:@"Profile Analyzer" subtitle:@"" icon:SCISettingsIcon(@"profile_analyzer") action:^{
        self.includeProfileAnalyzer = !self.includeProfileAnalyzer;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    profileAnalyzerRow.userInfo = @{@"checkmarked": @(self.includeProfileAnalyzer)};

    NSArray *sections = @[SCITopicSection(@"", @[settingsRow, galleryRow, deletedMessagesRow, profileAnalyzerRow], self.importMode ? @"A restart prompt appears after a successful import." : nil)];
    [self replaceSections:sections];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    SCISetting *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (row.userInfo[@"checkmarked"]) {
        BOOL checked = [row.userInfo[@"checkmarked"] boolValue];
        if (checked) {
            UIImageView *checkmarkView = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"circle_check_filled"]];
            checkmarkView.tintColor = [SCIUtils SCIColor_Primary];
            cell.accessoryView = checkmarkView;
        } else {
            cell.accessoryView = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }
    return cell;
}

- (void)updateActionEnabled {
    self.navigationItem.rightBarButtonItem.enabled = self.includeSettings || self.includeGallery || self.includeDeletedMessages || self.includeProfileAnalyzer;
}

- (void)runTransfer {
    if (!(self.includeSettings || self.includeGallery || self.includeDeletedMessages || self.includeProfileAnalyzer)) return;
    UIViewController *presenter = self.navigationController ?: self;
    if (self.importMode) {
        [[SCISettingsTransferManager sharedManager] importFromController:presenter includeSettings:self.includeSettings includeGallery:self.includeGallery includeDeletedMessages:self.includeDeletedMessages includeProfileAnalyzer:self.includeProfileAnalyzer];
    } else {
        [[SCISettingsTransferManager sharedManager] exportFromController:presenter includeSettings:self.includeSettings includeGallery:self.includeGallery includeDeletedMessages:self.includeDeletedMessages includeProfileAnalyzer:self.includeProfileAnalyzer];
    }
}

@end

static UIViewController *SCISettingsLockPresenter(void) {
    UIViewController *presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}

static void SCISettingsLockReloadPresenter(UIViewController *presenter) {
    if ([presenter isKindOfClass:SCISettingsViewController.class]) {
        [((SCISettingsViewController *)presenter).tableView reloadData];
    }
}

static NSDictionary *SCISettingsLockSection(void) {
    SCISetting *lockSwitch = [SCISetting switchCellWithTitle:@"Settings Passcode Lock"
                                                        icon:SCISettingsIcon(@"lock")
                                                 defaultsKey:@""];
    lockSwitch.switchValueProvider = ^BOOL{
        return [SCISettingsLockManager sharedManager].isLockEnabled;
    };
    lockSwitch.switchChangeHandler = ^(BOOL enabled) {
        SCISettingsLockManager *currentManager = [SCISettingsLockManager sharedManager];
        UIViewController *presenter = SCISettingsLockPresenter();
        if (enabled && !currentManager.isLockEnabled) {
            [SCIGalleryLockViewController presentMode:SCIGalleryLockModeSetPasscode
                                           forManager:currentManager
                                   fromViewController:presenter
                                           completion:^(__unused BOOL success) {
                SCISettingsLockReloadPresenter(presenter);
            }];
            return;
        }
        if (!enabled && currentManager.isLockEnabled) {
            [SCIIGAlertPresenter presentAlertFromViewController:presenter
                                                         title:@"Disable Settings Passcode"
                                                       message:@"SCInsta Settings will no longer require authentication to open."
                                                       actions:@[
                [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:^{
                    SCISettingsLockReloadPresenter(presenter);
                }],
                [SCIIGAlertAction actionWithTitle:@"Disable" style:SCIIGAlertActionStyleDestructive handler:^{
                    [currentManager removePasscode];
                    SCISettingsLockReloadPresenter(presenter);
                }],
            ]];
        }
    };

    SCISetting *changePasscode = [SCISetting buttonCellWithTitle:@"Change Settings Passcode"
                                                        subtitle:nil
                                                            icon:SCISettingsIcon(@"key")
                                                          action:^{
        [SCIGalleryLockViewController presentMode:SCIGalleryLockModeChangePasscode
                                       forManager:[SCISettingsLockManager sharedManager]
                               fromViewController:SCISettingsLockPresenter()
                                       completion:^(__unused BOOL success) {}];
    }];
    changePasscode.enabledProvider = ^BOOL{
        return [SCISettingsLockManager sharedManager].isLockEnabled;
    };

    return SCITopicSection(@"Settings Lock", @[lockSwitch, changePasscode], @"Require the independent Settings passcode or biometrics when opening SCInsta Settings, including topic sheets.");
}

static NSArray *SCIManageSettingsDataSections(void) {
    SCISetting *resetAllSettings = [SCISetting buttonCellWithTitle:@"Reset All Settings"
                                                         subtitle:@""
                                                             icon:SCISettingsIcon(@"arrow_ccw")
                                                           action:^(void) {
        UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
        UIViewController *presenter = scene.windows.firstObject.rootViewController;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        [[SCISettingsTransferManager sharedManager] resetAllSettingsFromController:presenter];
    }];
    resetAllSettings.tintColor = [SCIUtils SCIColor_InstagramDestructive];
    resetAllSettings.iconTintColor = [SCIUtils SCIColor_InstagramDestructive];

    return @[
        SCITopicSection(@"", @[
            SCISettingApplyIconTint([SCISetting navigationCellWithTitle:@"Export"
                                                                subtitle:@""
                                                                    icon:SCISettingsIcon(@"arrow_up")
                                                          viewController:[[SCISettingsTransferSelectionViewController alloc] initWithImportMode:NO]],
                                  [SCIUtils SCIColor_InstagramPrimaryText]),
            SCISettingApplyIconTint([SCISetting navigationCellWithTitle:@"Import"
                                                                subtitle:@""
                                                                    icon:SCISettingsIcon(@"arrow_down")
                                                          viewController:[[SCISettingsTransferSelectionViewController alloc] initWithImportMode:YES]],
                                  [SCIUtils SCIColor_InstagramPrimaryText])
        ], @"Choose to export or import settings, Gallery media, unsent messages logs, and Profile Analyzer data."),
        SCITopicSection(@"Reset", @[
            resetAllSettings
        ], @"Restore every preference to its default value.")
    ];
}

@implementation SCIToolsSettingsProvider

+ (SCISetting *)rootSetting {
    BOOL flexInstalled = SCIFlexIsBundled();
    NSString *flexFooter = flexInstalled
        ? @"The first time FLEX is opened in a session it can take a moment to initialize."
        : @"FLEX not installed. Rebuild with \"--flex\" flag or install libFLEX.dylib to enable these options.";
    SCISetting *flexGesture = [SCISetting switchCellWithTitle:@"Five-finger Hold" defaultsKey:@"tools_flex_instagram"];
    SCISetting *flexLaunch = [SCISetting switchCellWithTitle:@"Open on App Launch" defaultsKey:@"tools_flex_app_launch"];
    SCISetting *flexFocus = [SCISetting switchCellWithTitle:@"Open on App Focus" defaultsKey:@"tools_flex_app_start"];
    SCISetting *flexOpen = [SCISetting buttonCellWithTitle:@"Open FLEX Now" subtitle:@"" icon:nil action:^(void) {
        SCIFlexShowExplorer(@"settings");
    }];
    if (!flexInstalled) {
        flexGesture.userInfo = @{@"enabled": @NO};
        flexLaunch.userInfo = @{@"enabled": @NO};
        flexFocus.userInfo = @{@"enabled": @NO};
        flexOpen.userInfo = @{@"enabled": @NO};
    }
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        SCITopicSection(@"FLEX", @[flexOpen, flexGesture, flexLaunch, flexFocus], [NSString stringWithFormat:@"Open FLEX directly here, or enable five-finger hold to open it from Instagram. %@", flexFooter]),
        SCITopicSection(@"Tweak", @[
            [SCISetting switchCellWithTitle:@"Quick Settings Access" defaultsKey:@"tools_settings_shortcut" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Show Settings on App Launch" defaultsKey:@"tools_open_settings_on_launch"],
            [SCISetting switchCellWithTitle:@"Disable All Settings" defaultsKey:@"tools_disable_all" requiresRestart:YES],
            [SCISetting buttonCellWithTitle:@"Reset Onboarding Completion State" subtitle:@"" icon:nil action:^(void) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"app_first_run"];
                [SCIUtils showRestartConfirmation];
            }]
        ], @"Quick Settings Access opens settings when long pressing the Home tab."),
        SCISettingsLockSection(),
        SCITopicSection(@"Instagram", @[
            [SCISetting switchCellWithTitle:@"Hide TestFlight Popup" defaultsKey:@"tools_hide_testflight_popup" requiresRestart:YES],
            [SCISetting switchCellWithTitle:@"Disable Safe Mode" defaultsKey:@"tools_disable_safe_mode"],
            [SCISetting buttonCellWithTitle:@"Reset Safe Startup Mode" subtitle:@"" icon:nil action:^(void) {
                SCIStabilityGuardReset();
                [SCIUtils showRestartConfirmation];
            }],
        ], @"1. Suppresses the Instagram Beta update popup in TestFlight builds.\n"
           @"2. Makes Instagram not reset settings after subsequent crashes. Use at your own risk.\n"
           @"3. Clears failed-launch counters and temporary hook suppression."),
        SCITopicSection(@"Backup & Transfer", @[
            [SCISetting navigationCellWithTitle:@"Manage Settings & Data" subtitle:@"" icon:SCISettingsIcon(@"cloud") navSections:SCIManageSettingsDataSections()]
        ], nil)
    ]];

    [sections addObjectsFromArray:SCIDevExampleSections()];

    return SCITopicNavigationSetting(@"Tools", @"toolbox", 24.0, sections);
}

@end

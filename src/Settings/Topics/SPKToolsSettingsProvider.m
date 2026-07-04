#import "SPKToolsSettingsProvider.h"
#include <UIKit/UIKit.h>

#import "../SPKTopicSettingsSupport.h"
#import "SPKInterfaceSettingsProvider.h"
#import "../SPKSettingsTransferManager.h"
#import "../../App/SPKFlexLoader.h"
#import "../../App/SPKStabilityGuard.h"
#import "../../Utils.h"
#import "../../AssetUtils.h"
#import "../../Shared/Gallery/SPKGalleryLockViewController.h"
#import "../../Shared/Settings/SPKSettingsLockManager.h"
#import "../../Shared/UI/SPKIGAlertPresenter.h"

@interface SPKSettingsTransferSelectionViewController : SPKSettingsViewController
@property (nonatomic, assign) BOOL importMode;
@property (nonatomic, assign) BOOL includeSettings;
@property (nonatomic, assign) BOOL includeGallery;
@property (nonatomic, assign) BOOL includeDeletedMessages;
@property (nonatomic, assign) BOOL includeProfileAnalyzer;
- (instancetype)initWithImportMode:(BOOL)importMode;
@end

@implementation SPKSettingsTransferSelectionViewController

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
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[SPKAssetUtils instagramIconNamed:(self.importMode ? @"arrow_down" : @"arrow_up")]
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(runTransfer)];
    self.navigationItem.rightBarButtonItem.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
}

- (void)rebuildSections {
    SPKSetting *settingsRow = [SPKSetting buttonCellWithTitle:@"Settings" subtitle:@"" icon:SPKSettingsIcon(@"settings") action:^{
        self.includeSettings = !self.includeSettings;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    settingsRow.userInfo = @{@"checkmarked": @(self.includeSettings)};

    SPKSetting *galleryRow = [SPKSetting buttonCellWithTitle:@"Gallery" subtitle:@"" icon:SPKSettingsIcon(@"sparkle_gallery") action:^{
        self.includeGallery = !self.includeGallery;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    galleryRow.userInfo = @{@"checkmarked": @(self.includeGallery)};

    SPKSetting *deletedMessagesRow = [SPKSetting buttonCellWithTitle:@"Messages Logs" subtitle:@"" icon:SPKSettingsIcon(@"channels") action:^{
        self.includeDeletedMessages = !self.includeDeletedMessages;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    deletedMessagesRow.userInfo = @{@"checkmarked": @(self.includeDeletedMessages)};

    SPKSetting *profileAnalyzerRow = [SPKSetting buttonCellWithTitle:@"Profile Analyzer" subtitle:@"" icon:SPKSettingsIcon(@"profile_analyzer") action:^{
        self.includeProfileAnalyzer = !self.includeProfileAnalyzer;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    profileAnalyzerRow.userInfo = @{@"checkmarked": @(self.includeProfileAnalyzer)};

    NSString *footer = self.importMode
        ? @"Preferences are restored, replacing your current values for the imported scope. Gallery, messages and analyzer data are merged in — existing items are never deleted. A restart prompt appears only when preferences change."
        : nil;
    NSArray *sections = @[SPKTopicSection(@"", @[settingsRow, galleryRow, deletedMessagesRow, profileAnalyzerRow], footer)];
    [self replaceSections:sections];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    SPKSetting *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (row.userInfo[@"checkmarked"]) {
        BOOL checked = [row.userInfo[@"checkmarked"] boolValue];
        if (checked) {
            UIImageView *checkmarkView = [[UIImageView alloc] initWithImage:[SPKAssetUtils instagramIconNamed:@"circle_check_filled"]];
            checkmarkView.tintColor = [SPKUtils SPKColor_InstagramBlue];
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
        [[SPKSettingsTransferManager sharedManager] importFromController:presenter includeSettings:self.includeSettings includeGallery:self.includeGallery includeDeletedMessages:self.includeDeletedMessages includeProfileAnalyzer:self.includeProfileAnalyzer];
    } else {
        [[SPKSettingsTransferManager sharedManager] exportFromController:presenter includeSettings:self.includeSettings includeGallery:self.includeGallery includeDeletedMessages:self.includeDeletedMessages includeProfileAnalyzer:self.includeProfileAnalyzer];
    }
}

@end

static UIViewController *SPKSettingsLockPresenter(void) {
    UIViewController *presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}

static void SPKSettingsLockReloadPresenter(UIViewController *presenter) {
    if ([presenter isKindOfClass:SPKSettingsViewController.class]) {
        [((SPKSettingsViewController *)presenter).tableView reloadData];
    }
}

static NSDictionary *SPKSettingsLockSection(void) {
    SPKSetting *lockSwitch = [SPKSetting switchCellWithTitle:@"Settings Passcode Lock"
                                                        icon:SPKSettingsIcon(@"lock")
                                                 defaultsKey:@""];
    lockSwitch.switchValueProvider = ^BOOL{
        return [SPKSettingsLockManager sharedManager].isLockEnabled;
    };
    lockSwitch.switchChangeHandler = ^(BOOL enabled) {
        SPKSettingsLockManager *currentManager = [SPKSettingsLockManager sharedManager];
        UIViewController *presenter = SPKSettingsLockPresenter();
        if (enabled && !currentManager.isLockEnabled) {
            [SPKGalleryLockViewController presentMode:SPKGalleryLockModeSetPasscode
                                           forManager:currentManager
                                   fromViewController:presenter
                                           completion:^(__unused BOOL success) {
                SPKSettingsLockReloadPresenter(presenter);
            }];
            return;
        }
        if (!enabled && currentManager.isLockEnabled) {
            [SPKIGAlertPresenter presentAlertFromViewController:presenter
                                                         title:@"Disable Settings Passcode"
                                                       message:@"Sparkle Settings will no longer require authentication to open."
                                                       actions:@[
                [SPKIGAlertAction actionWithTitle:@"Cancel" style:SPKIGAlertActionStyleCancel handler:^{
                    SPKSettingsLockReloadPresenter(presenter);
                }],
                [SPKIGAlertAction actionWithTitle:@"Disable" style:SPKIGAlertActionStyleDestructive handler:^{
                    [currentManager removePasscode];
                    SPKSettingsLockReloadPresenter(presenter);
                }],
            ]];
        }
    };

    SPKSetting *changePasscode = [SPKSetting buttonCellWithTitle:@"Change Settings Passcode"
                                                        subtitle:nil
                                                            icon:SPKSettingsIcon(@"key")
                                                          action:^{
        [SPKGalleryLockViewController presentMode:SPKGalleryLockModeChangePasscode
                                       forManager:[SPKSettingsLockManager sharedManager]
                               fromViewController:SPKSettingsLockPresenter()
                                       completion:^(__unused BOOL success) {}];
    }];
    changePasscode.enabledProvider = ^BOOL{
        return [SPKSettingsLockManager sharedManager].isLockEnabled;
    };

    return SPKTopicSection(@"Settings Lock", @[lockSwitch, changePasscode], @"Require the independent Settings passcode or biometrics when opening Sparkle Settings, including topic sheets.");
}

static NSArray *SPKManageSettingsDataSections(void) {
    SPKSetting *resetAllSettings = [SPKSetting buttonCellWithTitle:@"Reset All Settings"
                                                         subtitle:@""
                                                             icon:SPKSettingsIcon(@"arrow_ccw")
                                                           action:^(void) {
        UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
        UIViewController *presenter = scene.windows.firstObject.rootViewController;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        [[SPKSettingsTransferManager sharedManager] resetAllSettingsFromController:presenter];
    }];
    resetAllSettings.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    resetAllSettings.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    return @[
        SPKTopicSection(@"", @[
            SPKSettingApplyIconTint([SPKSetting navigationCellWithTitle:@"Export"
                                                                subtitle:@""
                                                                    icon:SPKSettingsIcon(@"arrow_up")
                                                          viewController:[[SPKSettingsTransferSelectionViewController alloc] initWithImportMode:NO]],
                                  [SPKUtils SPKColor_InstagramPrimaryText]),
            SPKSettingApplyIconTint([SPKSetting navigationCellWithTitle:@"Import"
                                                                subtitle:@""
                                                                    icon:SPKSettingsIcon(@"arrow_down")
                                                          viewController:[[SPKSettingsTransferSelectionViewController alloc] initWithImportMode:YES]],
                                  [SPKUtils SPKColor_InstagramPrimaryText])
        ], @"Choose to export or import settings, Gallery media, unsent messages logs, and Profile Analyzer data."),
        SPKTopicSection(@"Reset", @[
            resetAllSettings
        ], @"Restore every preference to its default value.")
    ];
}

@implementation SPKToolsSettingsProvider

+ (SPKSetting *)rootSetting {
    BOOL flexInstalled = SPKFlexIsBundled();
    NSString *flexFooter = flexInstalled
        ? @"The first time FLEX is opened in a session it can take a moment to initialize."
        : @"FLEX is not installed. Rebuild with \"--flex\" flag or install \"libFLEX.dylib\" to enable these options.";
    SPKSetting *flexGesture = [SPKSetting switchCellWithTitle:@"Three-finger Hold" defaultsKey:@"tools_flex_instagram"];
    SPKSetting *flexLaunch = [SPKSetting switchCellWithTitle:@"Open on App Launch" defaultsKey:@"tools_flex_app_launch"];
    SPKSetting *flexFocus = [SPKSetting switchCellWithTitle:@"Open on App Focus" defaultsKey:@"tools_flex_app_start"];
    SPKSetting *flexOpen = [SPKSetting buttonCellWithTitle:@"Open FLEX Now" subtitle:@"" icon:nil action:^(void) {
        SPKFlexShowExplorer(@"settings");
    }];
    if (!flexInstalled) {
        flexGesture.userInfo = @{@"enabled": @NO};
        flexLaunch.userInfo = @{@"enabled": @NO};
        flexFocus.userInfo = @{@"enabled": @NO};
        flexOpen.userInfo = @{@"enabled": @NO};
    }
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        SPKTopicSection(@"FLEX", @[flexOpen, flexGesture, flexLaunch, flexFocus], flexFooter),
        SPKTopicSection(@"Tweak", @[
            [SPKSetting switchCellWithTitle:@"Quick Settings Access" defaultsKey:@"tools_settings_shortcut" requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Show Settings on App Launch" defaultsKey:@"tools_open_settings_on_launch"],
            [SPKSetting switchCellWithTitle:@"Disable All Settings" defaultsKey:@"tools_disable_all" requiresRestart:YES],
            [SPKSetting buttonCellWithTitle:@"Reset Onboarding Completion State" subtitle:@"" icon:nil action:^(void) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"app_first_run"];
                [SPKUtils showRestartConfirmation];
            }],
            [SPKSetting buttonCellWithTitle:@"Reset Safe Startup Mode" subtitle:@"" icon:nil action:^(void) {
                SPKStabilityGuardReset();
                [SPKUtils showRestartConfirmation];
            }],
        ], @"1. Quick Settings Access opens settings when long pressing the Home tab or the next visible tab if the Home tab is hidden.\n"
           @"5. Reset Safe Startup Mode clears failed-launch counters and temporary hook suppression."),
        SPKSettingsLockSection(),
        SPKTopicSection(@"Instagram", @[
            [SPKSetting switchCellWithTitle:@"Hide TestFlight Popup" defaultsKey:@"tools_hide_testflight_popup" requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Fix Duplicate Notifications" defaultsKey:@"tools_fix_duplicate_notifications"],
            [SPKSetting switchCellWithTitle:@"Disable Safe Mode" defaultsKey:@"tools_disable_safe_mode"],
        ], @"1. Suppresses the Instagram Beta update popup.\n"
           @"2. Drops the duplicate in-app banner sideloaded Instagram posts while the notification extension is already delivering the same push. Only acts while the app is foregrounded.\n"
           @"3. Makes Instagram not reset settings after subsequent crashes. Use at your own risk."),
        SPKTopicSection(@"Backup & Transfer", @[
            [SPKSetting navigationCellWithTitle:@"Manage Settings & Data" subtitle:@"" icon:SPKSettingsIcon(@"cloud") navSections:SPKManageSettingsDataSections()]
        ], nil)
    ]];

    return SPKTopicNavigationSetting(@"Tools", @"toolbox", 24.0, sections);
}

@end

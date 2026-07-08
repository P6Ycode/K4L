#import "SPKToolsSettingsProvider.h"
#include <UIKit/UIKit.h>

#import "../../App/SPKFlexLoader.h"
#import "../../App/SPKStabilityGuard.h"
#import "../../AssetUtils.h"
#import "../../Shared/Gallery/SPKGalleryLockViewController.h"
#import "../../Shared/Settings/SPKSettingsLockManager.h"
#import "../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../Utils.h"
#import "../SPKSettingsViewController.h"
#import "../SPKTopicSettingsSupport.h"
#import "SPKInterfaceSettingsProvider.h"

static UIViewController *SPKSettingsLockPresenter(void) {
    UIViewController *presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (presenter.presentedViewController)
        presenter = presenter.presentedViewController;
    return presenter;
}

static void SPKSettingsLockReloadPresenter(UIViewController *presenter) {
    // `presenter` is the topmost presented VC, which is usually the navigation
    // controller wrapping the settings page rather than the page itself. Reload
    // whichever SPKSettingsViewController is actually on screen so the Change
    // Passcode row greys/ungreys with the lock toggle.
    SPKSettingsViewController *settingsVC = nil;
    if ([presenter isKindOfClass:SPKSettingsViewController.class]) {
        settingsVC = (SPKSettingsViewController *)presenter;
    } else if ([presenter isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)presenter).topViewController;
        if ([top isKindOfClass:SPKSettingsViewController.class])
            settingsVC = (SPKSettingsViewController *)top;
    }
    [settingsVC.tableView reloadData];
}

static NSDictionary *SPKSettingsLockSection(void) {
    SPKSetting *lockSwitch = [SPKSetting switchCellWithTitle:@"Settings Passcode Lock"
                                                        icon:SPKSettingsIcon(@"lock")
                                                 defaultsKey:@""];
    lockSwitch.switchValueProvider = ^BOOL {
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
                                                            [SPKIGAlertAction actionWithTitle:@"Cancel"
                                                                                        style:SPKIGAlertActionStyleCancel
                                                                                      handler:^{
                                                                                          SPKSettingsLockReloadPresenter(presenter);
                                                                                      }],
                                                            [SPKIGAlertAction actionWithTitle:@"Disable"
                                                                                        style:SPKIGAlertActionStyleDestructive
                                                                                      handler:^{
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
                                                                                             completion:^(__unused BOOL success){
                                                                                             }];
                                                          }];
    changePasscode.enabledProvider = ^BOOL {
        return [SPKSettingsLockManager sharedManager].isLockEnabled;
    };

    return SPKTopicSection(@"Settings Lock", @[ lockSwitch, changePasscode ], @"Require the independent Settings passcode or biometrics when opening Sparkle Settings, including topic sheets.");
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
    SPKSetting *flexOpen = [SPKSetting buttonCellWithTitle:@"Open FLEX Now"
                                                  subtitle:@""
                                                      icon:nil
                                                    action:^(void) {
                                                        SPKFlexShowExplorer(@"settings");
                                                    }];
    if (!flexInstalled) {
        flexGesture.userInfo = @{@"enabled" : @NO};
        flexLaunch.userInfo = @{@"enabled" : @NO};
        flexFocus.userInfo = @{@"enabled" : @NO};
        flexOpen.userInfo = @{@"enabled" : @NO};
    }
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        SPKTopicSection(@"FLEX", @[ flexOpen, flexGesture, flexLaunch, flexFocus ], flexFooter),
        SPKTopicSection(@"Tweak", @[
            [SPKSetting switchCellWithTitle:@"Quick Settings Access"
                                defaultsKey:@"tools_settings_shortcut"
                            requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Show Settings on App Launch"
                                defaultsKey:@"tools_open_settings_on_launch"],
            [SPKSetting switchCellWithTitle:@"Disable All Settings"
                                defaultsKey:@"tools_disable_all"
                            requiresRestart:YES],
            [SPKSetting buttonCellWithTitle:@"Reset Onboarding Completion State"
                                   subtitle:@""
                                       icon:nil
                                     action:^(void) {
                                         [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"app_first_run"];
                                         [SPKUtils showRestartConfirmation];
                                     }],
            [SPKSetting buttonCellWithTitle:@"Reset Safe Startup Mode"
                                   subtitle:@""
                                       icon:nil
                                     action:^(void) {
                                         SPKStabilityGuardReset();
                                         [SPKUtils showRestartConfirmation];
                                     }],
        ],
                        @"1. Quick Settings Access opens settings when long pressing the Home tab or the next visible tab if the Home tab is hidden.\n"
                        @"5. Reset Safe Startup Mode clears failed-launch counters and temporary hook suppression."),
        SPKSettingsLockSection(),
        SPKTopicSection(@"Instagram", @[
            [SPKSetting switchCellWithTitle:@"Hide TestFlight Popup"
                                defaultsKey:@"tools_hide_testflight_popup"
                            requiresRestart:YES],
            [SPKSetting switchCellWithTitle:@"Fix Duplicate Notifications"
                                defaultsKey:@"tools_fix_duplicate_notifications"],
            [SPKSetting switchCellWithTitle:@"Disable Safe Mode"
                                defaultsKey:@"tools_disable_safe_mode"],
        ],
                        @"1. Suppresses the Instagram Beta update popup.\n"
                        @"2. Drops the duplicate in-app banner sideloaded Instagram posts while the notification extension is already delivering the same push. Only acts while the app is foregrounded.\n"
                        @"3. Makes Instagram not reset settings after subsequent crashes. Use at your own risk."),
    ]];

    return SPKTopicNavigationSetting(@"Tools", @"toolbox", 24.0, sections);
}

@end

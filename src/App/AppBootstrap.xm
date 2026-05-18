#import "../InstagramHeaders.h"
#import "../Tweak.h"
#import "../Utils.h"
#import "SCICore.h"
#import "SCIFlexLoader.h"
#import "SCIStabilityGuard.h"
#import "SCIStartupProfiler.h"

static BOOL sSCIAppDidBecomeActive = NO;
static BOOL sSCIStagedHooksFinished = NO;
static BOOL sSCIStabilityCompletionScheduled = NO;

static void SCIMarkLaunchStableIfReady(void) {
    if (!sSCIAppDidBecomeActive || !sSCIStagedHooksFinished || sSCIStabilityCompletionScheduled) {
        return;
    }
    sSCIStabilityCompletionScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIStabilityGuardMarkHooksFinished();
    });
}

static void SCIScheduleHookPhase(NSTimeInterval delay, NSString *name, dispatch_block_t block, BOOL finalPhase) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIStartupMark([NSString stringWithFormat:@"%@ hooks begin", name]);
        if (block) block();
        SCIStartupMark([NSString stringWithFormat:@"%@ hooks installed", name]);
        if (finalPhase) {
            sSCIStagedHooksFinished = YES;
            SCIMarkLaunchStableIfReady();
        }
    });
}

static void SCIScheduleStagedFeatureHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCIScheduleHookPhase(0.25, @"general UI", ^{
            SCICoreInstallSurfaceHooks(SCISurfaceGeneralUI);
        }, NO);
        SCIScheduleHookPhase(0.35, @"feed", ^{
            SCICoreInstallSurfaceHooks(SCISurfaceFeed);
        }, NO);
        SCIScheduleHookPhase(0.45, @"stories", ^{
            SCICoreInstallSurfaceHooks(SCISurfaceStories);
        }, NO);
        SCIScheduleHookPhase(0.55, @"reels", ^{
            SCICoreInstallSurfaceHooks(SCISurfaceReels);
        }, NO);
        SCIScheduleHookPhase(0.65, @"messages", ^{
            SCICoreInstallSurfaceHooks(SCISurfaceMessages);
        }, NO);
        SCIScheduleHookPhase(0.75, @"profile", ^{
            SCICoreInstallSurfaceHooks(SCISurfaceProfile);
        }, YES);
    });
}

%hook IGInstagramAppDelegate
- (_Bool)application:(UIApplication *)application willFinishLaunchingWithOptions:(id)arg2 {
    SCIStartupMark(@"willFinishLaunching begin");
    SCICoreRegisterBootstrapDefaults();
    SCIStabilityGuardBeginLaunch();
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [SCIUtils sci_normalizeLiquidGlassPreferences];

    if ([SCIUtils getBoolPref:@"liquid_glass_buttons"]) {
        [defaults setValue:@(YES) forKey:@"instagram.override.project.lucent.navigation"];
    } else {
        [defaults setValue:@(NO) forKey:@"instagram.override.project.lucent.navigation"];
    }

    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) {
        [defaults setBool:YES forKey:@"liquid_glass_override_enabled"];
        [defaults setBool:YES forKey:@"IGLiquidGlassOverrideEnabled"];
    } else {
        [defaults setBool:NO forKey:@"liquid_glass_override_enabled"];
        [defaults setBool:NO forKey:@"IGLiquidGlassOverrideEnabled"];
    }
    [SCIUtils applyLiquidGlassNavigationExperimentOverride];
    SCICoreInstallLaunchCriticalHooks();
    SCIStartupMark(@"launch critical hooks installed");

    return %orig;
}

- (_Bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)arg2 {
    SCIStartupMark(@"didFinishLaunching begin");
    BOOL result = %orig;
    SCIStartupMark(@"didFinishLaunching orig returned");
    SCIScheduleStagedFeatureHooks();

    double openDelay = [SCIUtils getBoolPref:@"tweak_settings_app_launch"] ? 0.0 : 5.0;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(openDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (
            ![[[NSUserDefaults standardUserDefaults] objectForKey:@"SCInstaFirstRun"] isEqualToString:SCIVersionString]
            || [SCIUtils getBoolPref:@"tweak_settings_app_launch"]
        ) {
            SCILog(@"Bootstrap", @"First run, initializing");
            SCILog(@"Bootstrap", @"Displaying SCInsta first-time settings modal");
            SCICoreShowSettingsIfNeeded([self window]);
        }
    });
    if ([SCIUtils getBoolPref:@"flex_app_launch"]) {
        SCIFlexShowExplorer(@"launch");
    }

    return result;
}

- (void)applicationDidBecomeActive:(id)arg1 {
    %orig;
    sSCIAppDidBecomeActive = YES;
    SCIMarkLaunchStableIfReady();

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [SCIUtils evaluateAutomaticCacheClearIfNeeded];
    });

    if ([SCIUtils getBoolPref:@"flex_app_start"]) {
        SCIFlexShowExplorer(@"focus");
    }
}
%end

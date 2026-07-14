#import "../InstagramHeaders.h"
#import "../Tweak.h"
#import "../Utils.h"
#import "SPKCore.h"
#import "SPKFlexLoader.h"
#import "SPKStabilityGuard.h"
#import "SPKStartupProfiler.h"

static BOOL sSPKAppDidBecomeActive = NO;
static BOOL sSPKStagedHooksFinished = NO;
static BOOL sSPKStabilityCompletionScheduled = NO;
static BOOL sSPKSafeModeAlertScheduled = NO;

// Safe mode suppresses every feature hook, which is indistinguishable from
// Sparkle being broken unless we say so. Explain it once per launch, and keep
// explaining on later launches until the user turns it off — a missed alert
// otherwise leaves them stuck with a silently inert tweak.
static void SPKPresentSafeModeAlertIfNeeded(void) {
    if (sSPKSafeModeAlertScheduled || !SPKStabilityGuardIsSafeStartupMode()) {
        return;
    }
    sSPKSafeModeAlertScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPKStabilityGuardPresentSafeModeAlertIfNeeded();
    });
}

static void SPKMarkLaunchStableIfReady(void) {
    if (!sSPKAppDidBecomeActive || !sSPKStagedHooksFinished || sSPKStabilityCompletionScheduled) {
        return;
    }
    sSPKStabilityCompletionScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPKStabilityGuardMarkHooksFinished();
    });
}

static void SPKScheduleHookPhase(NSTimeInterval delay, NSString *name, dispatch_block_t block, BOOL finalPhase) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPKStartupMark([NSString stringWithFormat:@"%@ hooks begin", name]);
        if (block)
            block();
        SPKStartupMark([NSString stringWithFormat:@"%@ hooks installed", name]);
        if (finalPhase) {
            sSPKStagedHooksFinished = YES;
            SPKMarkLaunchStableIfReady();
        }
    });
}

static void SPKScheduleStagedFeatureHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SPKScheduleHookPhase(0.25, @"general UI", ^{
            SPKCoreInstallSurfaceHooks(SPKSurfaceGeneralUI);
        },
                             NO);
        SPKScheduleHookPhase(0.35, @"feed", ^{
            SPKCoreInstallSurfaceHooks(SPKSurfaceFeed);
        },
                             NO);
        SPKScheduleHookPhase(0.45, @"stories", ^{
            SPKCoreInstallSurfaceHooks(SPKSurfaceStories);
        },
                             NO);
        SPKScheduleHookPhase(0.55, @"reels", ^{
            SPKCoreInstallSurfaceHooks(SPKSurfaceReels);
        },
                             NO);
        SPKScheduleHookPhase(0.65, @"messages", ^{
            SPKCoreInstallSurfaceHooks(SPKSurfaceMessages);
        },
                             NO);
        SPKScheduleHookPhase(0.75, @"profile", ^{
            SPKCoreInstallSurfaceHooks(SPKSurfaceProfile);
        },
                             YES);
    });
}

%hook IGInstagramAppDelegate
- (_Bool)application:(UIApplication *)application willFinishLaunchingWithOptions:(id)arg2 {
    SPKStartupMark(@"willFinishLaunching begin");
    SPKCoreRegisterBootstrapDefaults();
    SPKStabilityGuardBeginLaunch();
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setBool:[SPKUtils spk_isLiquidGlassEffectivelyEnabled]
               forKey:@"instagram.override.project.lucent.navigation"];
    [defaults removeObjectForKey:@"liquid_glass_override_enabled"];
    [defaults removeObjectForKey:@"IGLiquidGlassOverrideEnabled"];
    SPKCoreInstallLaunchCriticalHooks();
    SPKStartupMark(@"launch critical hooks installed");

    return %orig;
}

- (_Bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)arg2 {
    SPKStartupMark(@"didFinishLaunching begin");
    BOOL result = %orig;
    SPKStartupMark(@"didFinishLaunching orig returned");
    SPKScheduleStagedFeatureHooks();

    double openDelay = [SPKUtils getBoolPref:@"tools_open_settings_on_launch"] ? 0.0 : 5.0;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(openDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (SPKCoreOnboardingPending() || SPKCoreWhatsNewPending() || [SPKUtils getBoolPref:@"tools_open_settings_on_launch"]) {
            SPKLog(@"Bootstrap", @"Intro sheet pending or launch-open enabled; presenting settings");
            SPKCoreShowSettingsIfNeeded([self window]);
        }
    });
    if ([SPKUtils getBoolPref:@"tools_flex_app_launch"]) {
        SPKFlexShowExplorer(@"launch");
    }

    return result;
}

- (void)applicationDidBecomeActive:(id)arg1 {
    %orig;
    sSPKAppDidBecomeActive = YES;
    SPKMarkLaunchStableIfReady();
    SPKPresentSafeModeAlertIfNeeded();

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [SPKUtils evaluateAutomaticCacheClearIfNeeded];
    });

    if ([SPKUtils getBoolPref:@"tools_flex_app_start"]) {
        SPKFlexShowExplorer(@"focus");
    }
}
%end

// SCIStabilityGuard — a launch failsafe.
//
// Each launch records a start timestamp. If a launch never reaches the "stable"
// mark (set ~5s after the app is active and all staged hooks installed) and the
// next launch starts within kSCIStabilityRecentLaunchWindow, it's counted as an
// incomplete launch. After kSCIStabilityFailureThreshold consecutive incomplete
// launches the tweak enters *safe startup mode*: feature hooks are suppressed
// (only Settings access remains) and Liquid Glass is disabled, so a hook that
// crashes Instagram on launch can't lock the user out permanently. The user can
// clear this from Tools > "Reset Safe Startup Mode" (SCIStabilityGuardReset).
#import "SCIStabilityGuard.h"

#import "../Utils.h"

static NSString *const kSCIStabilityLaunchStartedAtKey = @"app_launch_started_at";
static NSString *const kSCIStabilityLaunchCompletedAtKey = @"app_launch_completed_at";
static NSString *const kSCIStabilityFailedLaunchCountKey = @"app_failed_launch_count";
static NSString *const kSCISafeStartupModeKey = @"app_safe_startup";
static NSString *const kSCISafeStartupReasonKey = @"app_safe_startup_reason";

static NSTimeInterval const kSCIStabilityRecentLaunchWindow = 300.0;
static NSInteger const kSCIStabilityFailureThreshold = 2;

static NSTimeInterval SCINow(void) {
    return [NSDate date].timeIntervalSince1970;
}

void SCIStabilityGuardBeginLaunch(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval now = SCINow();
    NSTimeInterval previousStart = [defaults doubleForKey:kSCIStabilityLaunchStartedAtKey];
    NSInteger failedLaunches = [defaults integerForKey:kSCIStabilityFailedLaunchCountKey];

    if (previousStart > 0.0) {
        BOOL recentIncompleteLaunch = (now - previousStart) <= kSCIStabilityRecentLaunchWindow;
        failedLaunches = recentIncompleteLaunch ? failedLaunches + 1 : 0;
        [defaults setInteger:failedLaunches forKey:kSCIStabilityFailedLaunchCountKey];

        if (recentIncompleteLaunch && failedLaunches >= kSCIStabilityFailureThreshold) {
            [defaults setBool:YES forKey:kSCISafeStartupModeKey];
            [defaults setObject:@"Repeated incomplete launches" forKey:kSCISafeStartupReasonKey];
            SCIWarnLog(@"Stability", @"Entering safe startup mode after %ld incomplete launches", (long)failedLaunches);
        } else if (recentIncompleteLaunch) {
            SCIWarnLog(@"Stability", @"Detected incomplete previous launch; count=%ld", (long)failedLaunches);
        }
    }

    [defaults setDouble:now forKey:kSCIStabilityLaunchStartedAtKey];

    if ([defaults boolForKey:kSCISafeStartupModeKey]) {
        NSString *reason = [defaults stringForKey:kSCISafeStartupReasonKey] ?: @"unknown";
        SCIWarnLog(@"Stability", @"Safe startup mode active: %@", reason);
    } else {
        SCILog(@"Stability", @"Launch guard armed");
    }
    [defaults synchronize];
}

void SCIStabilityGuardMarkHooksFinished(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kSCIStabilityLaunchStartedAtKey];
    [defaults setInteger:0 forKey:kSCIStabilityFailedLaunchCountKey];
    [defaults setDouble:SCINow() forKey:kSCIStabilityLaunchCompletedAtKey];
    [defaults synchronize];
    SCILog(@"Stability", @"Launch marked stable");
}

BOOL SCIStabilityGuardIsSafeStartupMode(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSCISafeStartupModeKey];
}

void SCIStabilityGuardReset(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kSCIStabilityLaunchStartedAtKey];
    [defaults removeObjectForKey:kSCIStabilityFailedLaunchCountKey];
    [defaults removeObjectForKey:kSCISafeStartupModeKey];
    [defaults removeObjectForKey:kSCISafeStartupReasonKey];
    [defaults removeObjectForKey:kSCIStabilityLaunchCompletedAtKey];
    [defaults synchronize];
    SCILog(@"Stability", @"Safe startup state reset");
}

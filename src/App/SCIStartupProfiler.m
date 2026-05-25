#import "SCIStartupProfiler.h"
#import "../Utils.h"

#if STARTUP_PROFILING

#import <CoreFoundation/CoreFoundation.h>

static CFAbsoluteTime sSCIStartupStartTime;

static BOOL SCIStartupProfilingEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id override = [defaults objectForKey:@"app_startup_profiling"];
    return override == nil || [defaults boolForKey:@"app_startup_profiling"];
}

__attribute__((constructor))
static void SCIStartupProfilerConstructor(void) {
    sSCIStartupStartTime = CFAbsoluteTimeGetCurrent();
    if (SCIStartupProfilingEnabled()) {
        SCILog(@"General", @"[SCInsta][startup] +0.000s constructor entry");
    }
}

void SCIStartupMark(NSString *event) {
    if (!SCIStartupProfilingEnabled()) {
        return;
    }

    if (sSCIStartupStartTime <= 0.0) {
        sSCIStartupStartTime = CFAbsoluteTimeGetCurrent();
    }

    NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - sSCIStartupStartTime;
    SCILog(@"General", @"[SCInsta][startup] +%.3fs %@", elapsed, event ?: @"mark");
}

#endif

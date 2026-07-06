#import "../../InstagramHeaders.h"
#import "../../Utils.h"

// Remove suggested threads posts (carousel, under suggested posts in feed)
%group SPKHideThreadsHooks

%hook BKBloksViewHelper
- (id)initWithObjectSet:(id)arg1 bloksData:(id)arg2 delegate:(id)arg3 {
    if ([SPKUtils getBoolPref:@"feed_hide_suggested_threads"]) {
        SPKLog(@"General", @"[Sparkle] Hiding threads posts");

        return nil;
    }

    return %orig;
}
%end

%end

void SPKInstallHideThreadsHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"feed_hide_suggested_threads"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKHideThreadsHooks);
    });
}

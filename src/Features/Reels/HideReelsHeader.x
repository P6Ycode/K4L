#import "../../Utils.h"

%group SPKHideReelsHeaderHooks

%hook IGSundialViewerNavigationBarOld
- (void)didMoveToWindow {
    %orig;

    if ([SPKUtils getBoolPref:@"reels_hide_header"]) {
        SPKLog(@"General", @"[Sparkle] Hiding reels header");

        [self removeFromSuperview];
    }
}
%end

%end

void SPKInstallHideReelsHeaderHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"reels_hide_header"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKHideReelsHeaderHooks);
    });
}

#import "../../Utils.h"

%group SCIHideReelsHeaderHooks

%hook IGSundialViewerNavigationBarOld
- (void)didMoveToWindow {
    %orig;

    if ([SCIUtils getBoolPref:@"reels_hide_header"]) {
        SCILog(@"General", @"[SCInsta] Hiding reels header");

        [self removeFromSuperview];
    }
}
%end

%end

void SCIInstallHideReelsHeaderHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"reels_hide_header"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIHideReelsHeaderHooks);
    });
}

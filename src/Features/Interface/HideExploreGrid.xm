#import "../../InstagramHeaders.h"
#import "../../Utils.h"

%group SPKHideExploreGridHooks

%hook IGExploreGridViewController
- (void)viewDidLoad {
    if ([SPKUtils getBoolPref:@"interface_hide_explore_grid"]) {
        SPKLog(@"General", @"[Sparkle] Hiding explore grid");

        [[self view] removeFromSuperview];

        return;
    }

    return %orig;
}
%end

%hook IGExploreViewController
- (void)viewDidLoad {
    %orig;

    if ([SPKUtils getBoolPref:@"interface_hide_explore_grid"]) {
        SPKLog(@"General", @"[Sparkle] Hiding explore grid");

        IGShimmeringGridView *shimmeringGridView = MSHookIvar<IGShimmeringGridView *>(self, "_shimmeringGridView");
        if (shimmeringGridView != nil) {
            [shimmeringGridView removeFromSuperview];
        }
    }
}
%end

%end

extern "C" void SPKInstallHideExploreGridHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"interface_hide_explore_grid"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKHideExploreGridHooks);
    });
}

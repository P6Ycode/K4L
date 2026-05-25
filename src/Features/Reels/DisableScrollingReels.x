#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%group SCIDisableScrollingReelsHooks

%hook IGUnifiedVideoCollectionView
- (void)didMoveToWindow {
    %orig;

    if ([SCIUtils getBoolPref:@"reels_disable_scrolling"]) {
        SCILog(@"General", @"[SCInsta] Disabling scrolling reels");
        
        self.scrollEnabled = false;
    }
}

- (void)setScrollEnabled:(BOOL)arg1 {
    if ([SCIUtils getBoolPref:@"reels_disable_scrolling"]) {
        SCILog(@"General", @"[SCInsta] Disabling scrolling reels");
        
        return %orig(NO);
    }

    return %orig;
}
%end

// Disable auto-scrolling reels
%hook _TtC19IGSundialAutoScroll19IGSundialAutoScroll
- (void)setIsEnabled:(BOOL)enabled {
    if ([SCIUtils getBoolPref:@"reels_disable_scrolling"]) {
        %orig(NO);
    }
    else {
        %orig(enabled);
    }
}
%end

%end

void SCIInstallDisableScrollingReelsHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"reels_disable_scrolling"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIDisableScrollingReelsHooks);
    });
}

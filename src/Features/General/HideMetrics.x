#import "../../Utils.h"

%group SCIHideMetricsHooks

%hook IGSundialViewerVerticalUFI
- (void)setNumLikes:(NSInteger)num {
    return %orig([SCIUtils getBoolPref:@"reels_hide_like_count"] ? 0 : num);
}
- (void)setNumReshares:(NSInteger)num {
    return %orig([SCIUtils getBoolPref:@"reels_hide_reshare_count"] ? 0 : num);
}
- (void)setNumComments:(NSInteger)num {
    return %orig([SCIUtils getBoolPref:@"reels_hide_comment_count"] ? 0 : num);
}
- (void)setNumReposts:(NSInteger)num {
    return %orig([SCIUtils getBoolPref:@"reels_hide_repost_count"] ? 0 : num);
}
- (void)setNumSaves:(NSInteger)num {
    return %orig([SCIUtils getBoolPref:@"reels_hide_save_count"] ? 0 : num);
}
%end

%hook IGUFIButtonWithCountsView
- (void)setCountString:(id)string showButton:(BOOL)showButton {
    return %orig([SCIUtils getBoolPref:@"feed_hide_metrics"] ? @"" : string, showButton);
}
%end

%end

void SCIInstallHideMetricsHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"feed_hide_metrics"] &&
        ![SCIUtils getBoolPref:@"reels_hide_like_count"] &&
        ![SCIUtils getBoolPref:@"reels_hide_reshare_count"] &&
        ![SCIUtils getBoolPref:@"reels_hide_comment_count"] &&
        ![SCIUtils getBoolPref:@"reels_hide_repost_count"] &&
        ![SCIUtils getBoolPref:@"reels_hide_save_count"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIHideMetricsHooks);
    });
}

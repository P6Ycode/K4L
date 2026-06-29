#import "../../Utils.h"

%group SPKHideMetricsHooks

%hook IGSundialViewerVerticalUFI
- (void)setNumLikes:(NSInteger)num {
    return %orig([SPKUtils getBoolPref:@"reels_hide_like_count"] ? 0 : num);
}
- (void)setNumReshares:(NSInteger)num {
    return %orig([SPKUtils getBoolPref:@"reels_hide_reshare_count"] ? 0 : num);
}
- (void)setNumComments:(NSInteger)num {
    return %orig([SPKUtils getBoolPref:@"reels_hide_comment_count"] ? 0 : num);
}
- (void)setNumReposts:(NSInteger)num {
    return %orig([SPKUtils getBoolPref:@"reels_hide_repost_count"] ? 0 : num);
}
- (void)setNumSaves:(NSInteger)num {
    return %orig([SPKUtils getBoolPref:@"reels_hide_save_count"] ? 0 : num);
}
%end

%hook IGUFIButtonWithCountsView
- (void)setCountString:(id)string showButton:(BOOL)showButton {
    if ([self.superview isKindOfClass:%c(IGUFIInteractionCountsView)]) {
        IGUFIInteractionCountsView *countsView = (IGUFIInteractionCountsView *)self.superview;
        UIView *likesView = [countsView valueForKey:@"_likesView"];
        UIView *commentsView = [countsView valueForKey:@"_commentsView"];
        UIView *repostView = [countsView valueForKey:@"_repostView"];
        UIView *sendView = [countsView valueForKey:@"_sendView"];
        
        if (self == likesView && [SPKUtils getBoolPref:@"feed_hide_like_count"]) {
            return %orig(@"", showButton);
        } else if (self == commentsView && [SPKUtils getBoolPref:@"feed_hide_comment_count"]) {
            return %orig(@"", showButton);
        } else if (self == repostView && [SPKUtils getBoolPref:@"feed_hide_repost_count"]) {
            return %orig(@"", showButton);
        } else if (self == sendView && [SPKUtils getBoolPref:@"feed_hide_reshare_count"]) {
            return %orig(@"", showButton);
        }
    }
    return %orig(string, showButton);
}
%end

%end

void SPKInstallHideMetricsHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"feed_hide_like_count"] &&
        ![SPKUtils getBoolPref:@"feed_hide_comment_count"] &&
        ![SPKUtils getBoolPref:@"feed_hide_repost_count"] &&
        ![SPKUtils getBoolPref:@"feed_hide_reshare_count"] &&
        ![SPKUtils getBoolPref:@"reels_hide_like_count"] &&
        ![SPKUtils getBoolPref:@"reels_hide_reshare_count"] &&
        ![SPKUtils getBoolPref:@"reels_hide_comment_count"] &&
        ![SPKUtils getBoolPref:@"reels_hide_repost_count"] &&
        ![SPKUtils getBoolPref:@"reels_hide_save_count"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKHideMetricsHooks);
    });
}

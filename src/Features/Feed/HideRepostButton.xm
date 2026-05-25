#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static inline BOOL SCIHideFeedRepostEnabled(void) {
    return [SCIUtils getBoolPref:@"feed_hide_repost_btn"];
}

static inline BOOL SCIHideReelsRepostEnabled(void) {
    return [SCIUtils getBoolPref:@"reels_hide_repost_btn"];
}

static void SCIHideFeedRepostButtons(id view) {
    if (!SCIHideFeedRepostEnabled()) return;

    for (NSString *ivarName in @[@"_repostView", @"_undoRepostButton"]) {
        id candidate = [SCIUtils getIvarForObj:view name:ivarName.UTF8String];
        if ([candidate isKindOfClass:[UIView class]]) {
            ((UIView *)candidate).hidden = YES;
        }
    }
}

%group SCIHideRepostButtonHooks

%hook IGUFIInteractionCountsView
- (void)updateUFIWithButtonsConfig:(id)config interactionCountProvider:(id)provider {
    %orig(config, provider);
    SCIHideFeedRepostButtons(self);
}
%end

%hook IGSundialViewerUFIViewModel
- (BOOL)shouldShowRepostButton {
    if (SCIHideReelsRepostEnabled()) {
        return NO;
    }

    return %orig;
}
%end

%end

extern "C" void SCIInstallHideRepostButtonHooksIfEnabled(void) {
    if (!SCIHideFeedRepostEnabled() && !SCIHideReelsRepostEnabled()) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIHideRepostButtonHooks);
    });
}

#import "../../Utils.h"
#import "../../Tweak.h"

static inline BOOL SPKUnlimitedReplayEnabled(void) {
    return [SPKUtils getBoolPref:@"msgs_manual_visual_seen"];
}

static inline BOOL SPKShouldPassThroughManualDirectSeen(id message) {
    return (message && SPKPendingDirectVisualMessageToMarkSeen && message == SPKPendingDirectVisualMessageToMarkSeen);
}

%group SPKDisableDMStorySeenHooks

%hook IGDirectVisualMessageViewerEventHandler
- (void)visualMessageViewerController:(id)arg1 didBeginPlaybackForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 {
    if (!SPKUnlimitedReplayEnabled()) {
        return %orig;
    }

    if (SPKShouldPassThroughManualDirectSeen(arg2)) {
        return %orig;
    }
}

- (void)visualMessageViewerController:(id)arg1 didEndPlaybackForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 mediaCurrentTime:(CGFloat)arg4 forNavType:(NSInteger)arg5 {
    if (!SPKUnlimitedReplayEnabled()) {
        return %orig;
    }

    if (SPKShouldPassThroughManualDirectSeen(arg2)) {
        return %orig;
    }
}
%end

%end

void SPKInstallDisableDMStorySeenHooksIfNeeded(void) {
    if (![SPKUtils getBoolPref:@"msgs_manual_visual_seen"]) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKDisableDMStorySeenHooks);
    });
}

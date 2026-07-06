#import "../../Utils.h"

%group SPKStickerInteractConfirmHooks

%hook IGStoryViewerTapTarget
- (void)_didTap:(id)arg1 forEvent:(id)arg2 {
    if ([SPKUtils getBoolPref:@"stories_confirm_sticker"]) {
        SPKLog(@"General", @"[Sparkle] Confirm sticker interact triggered");

        [SPKUtils
            showConfirmation:^(void) {
                %orig;
            }
                       title:@"Confirm Sticker Interaction"
                     message:@"Are you sure you want to interact with this story sticker?"];
    } else {
        return %orig;
    }
}
%end

%end

void SPKInstallStickerInteractConfirmHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"stories_confirm_sticker"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKStickerInteractConfirmHooks);
    });
}

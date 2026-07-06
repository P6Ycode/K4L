#import "../../Utils.h"

%group SPKPostCommentConfirmHooks

%hook IGCommentComposer.IGCommentComposerController
- (void)onSendButtonTap {
    if ([SPKUtils getBoolPref:@"feed_confirm_post_comment"]) {
        SPKLog(@"General", @"[Sparkle] Confirm post comment triggered");

        [SPKUtils
            showConfirmation:^(void) {
                %orig;
            }
                       title:@"Confirm Comment Post"
                     message:@"Are you sure you want to post this comment?"];
    } else {
        return %orig;
    }
}
%end

%end

void SPKInstallPostCommentConfirmHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"feed_confirm_post_comment"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKPostCommentConfirmHooks);
    });
}

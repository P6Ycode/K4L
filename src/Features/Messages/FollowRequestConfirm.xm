#import "../../Utils.h"

%group SPKFollowRequestConfirmHooks

%hook IGPendingRequestView
- (void)_onApproveButtonTapped {
    if ([SPKUtils getBoolPref:@"msgs_confirm_follow_request"]) {
        SPKLog(@"General", @"[Sparkle] Confirm follow request triggered");

        [SPKUtils
            showConfirmation:^(void) {
                %orig;
            }
                       title:@"Confirm Accept Request"
                     message:@"Are you sure you want to accept this follow request?"];
    } else {
        return %orig;
    }
}
- (void)_onIgnoreButtonTapped {
    if ([SPKUtils getBoolPref:@"msgs_confirm_follow_request"]) {
        SPKLog(@"General", @"[Sparkle] Confirm follow request triggered");

        [SPKUtils
            showConfirmation:^(void) {
                %orig;
            }
                       title:@"Confirm Decline Request"
                     message:@"Are you sure you want to decline this follow request?"];
    } else {
        return %orig;
    }
}
%end

%end

extern "C" void SPKInstallFollowRequestConfirmHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"msgs_confirm_follow_request"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKFollowRequestConfirmHooks);
    });
}

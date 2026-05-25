#import "../../Utils.h"

%group SCIFollowRequestConfirmHooks

%hook IGPendingRequestView
- (void)_onApproveButtonTapped {
    if ([SCIUtils getBoolPref:@"msgs_confirm_follow_request"]) {
        SCILog(@"General", @"[SCInsta] Confirm follow request triggered");

        [SCIUtils showConfirmation:^(void) { %orig; }
                                 title:@"Confirm Accept Request"
                               message:@"Are you sure you want to accept this follow request?"];
    } else {
        return %orig;
    }
}
- (void)_onIgnoreButtonTapped {
    if ([SCIUtils getBoolPref:@"msgs_confirm_follow_request"]) {
        SCILog(@"General", @"[SCInsta] Confirm follow request triggered");

        [SCIUtils showConfirmation:^(void) { %orig; }
                                 title:@"Confirm Decline Request"
                               message:@"Are you sure you want to decline this follow request?"];
    } else {
        return %orig;
    }
}
%end

%end

extern "C" void SCIInstallFollowRequestConfirmHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"msgs_confirm_follow_request"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIFollowRequestConfirmHooks);
    });
}

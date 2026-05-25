#import "../../Utils.h"

static NSString * const kSCIAudioCallConfirmKey = @"msgs_confirm_audio_call";
static NSString * const kSCIVideoCallConfirmKey = @"msgs_confirm_video_call";

static BOOL SCIShouldConfirmCall(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

%group SCICallConfirmHooks

%hook IGDirectThreadCallButtonsCoordinator
// Voice Call
- (void)_didTapAudioButton {
    if (SCIShouldConfirmCall(kSCIAudioCallConfirmKey)) {
        SCILog(@"General", @"[SCInsta] Call confirm triggered");

        [SCIUtils showConfirmation:^(void) { %orig; }
                                 title:@"Confirm Audio Call"
                               message:@"Are you sure you want to start an audio call?"];
    } else {
        return %orig;
    }
}

- (void)_didTapAudioButton:(id)arg1 {
    if (SCIShouldConfirmCall(kSCIAudioCallConfirmKey)) {
        SCILog(@"General", @"[SCInsta] Call confirm triggered");

        [SCIUtils showConfirmation:^(void) { %orig; }
                                 title:@"Confirm Audio Call"
                               message:@"Are you sure you want to start an audio call?"];
    } else {
        return %orig;
    }
}

// Video Call
- (void)_didTapVideoButton {
    if (SCIShouldConfirmCall(kSCIVideoCallConfirmKey)) {
        SCILog(@"General", @"[SCInsta] Call confirm triggered");

        [SCIUtils showConfirmation:^(void) { %orig; }
                                 title:@"Confirm Video Call"
                               message:@"Are you sure you want to start a video call?"];
    } else {
        return %orig;
    }
}

- (void)_didTapVideoButton:(id)arg1 {
    if (SCIShouldConfirmCall(kSCIVideoCallConfirmKey)) {
        SCILog(@"General", @"[SCInsta] Call confirm triggered");

        [SCIUtils showConfirmation:^(void) { %orig; }
                                 title:@"Confirm Video Call"
                               message:@"Are you sure you want to start a video call?"];
    } else {
        return %orig;
    }
}
%end

%end

void SCIInstallCallConfirmHooksIfEnabled(void) {
    if (!SCIShouldConfirmCall(kSCIAudioCallConfirmKey) && !SCIShouldConfirmCall(kSCIVideoCallConfirmKey)) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCICallConfirmHooks);
    });
}

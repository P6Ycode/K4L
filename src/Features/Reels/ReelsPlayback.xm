#import "../../Utils.h"

%group SCIReelsPlaybackHooks

%hook IGSundialPlaybackControlsTestConfiguration
- (id)initWithLauncherSet:(id)set
                     tapToPauseEnabled:(_Bool)tapPauseEnabled
      combineSingleTapPlaybackControls:(_Bool)controls
        isVideoPreviewThumbnailEnabled:(_Bool)previewThumbEnabled
                minScrubberDurationSec:(long long)minSec
         seekResumeScrubberCooldownSec:(double)seekSec
          tapResumeScrubberCooldownSec:(double)tapSec
    persistentScrubberMinVideoDuration:(long long)duration
        isScrubberForShortVideoEnabled:(_Bool)shortScrubberEnabled
{
    _Bool userTapPauseEnabled = tapPauseEnabled;
    if ([[SCIUtils getStringPref:@"reels_tap_control"] isEqualToString:@"pause"]) userTapPauseEnabled = true;
    else if ([[SCIUtils getStringPref:@"reels_tap_control"] isEqualToString:@"mute"]) userTapPauseEnabled = false;

    long long userMinSec = minSec;
    long long userDuration = duration;
    _Bool userShortScrubberEnabled = shortScrubberEnabled;
    if ([SCIUtils getBoolPref:@"reels_show_scrubber"]) {
        userMinSec = 0;
        userDuration = 0;
        userShortScrubberEnabled = true;
    }

    return %orig(set, userTapPauseEnabled, controls, previewThumbEnabled, userMinSec, seekSec, tapSec, userDuration, userShortScrubberEnabled);
}
%end

%hook IGSundialFeedViewController
- (void)_refreshReelsWithParamsForNetworkRequest:(NSInteger)arg1 userDidPullToRefresh:(BOOL)arg2 {
    if ([SCIUtils getBoolPref:@"reels_prevent_doom_scroll"] && arg2) {
        IGRefreshControl *_refreshControl = MSHookIvar<IGRefreshControl *>(self, "_refreshControl");
        [_refreshControl finishLoading];
        [self finishPullToRefreshLoading];

        return;
    }

    if ([SCIUtils getBoolPref:@"reels_confirm_refresh"] && arg2) {
        SCILog(@"General", @"[SCInsta] Reel refresh triggered");
        
        [SCIUtils showConfirmation:^(void) { %orig(arg1, arg2); }
                     cancelHandler:^(void) {
                         IGRefreshControl *_refreshControl = MSHookIvar<IGRefreshControl *>(self, "_refreshControl");
                         [_refreshControl finishLoading];
                         [self finishPullToRefreshLoading];
                     }
                             title:@"Confirm Reels Refresh"
                           message:@"Are you sure you want to refresh the reels feed?"];
    } else {
        return %orig(arg1, arg2);
    }
}
%end

// * Disable volume/mute button triggering unmutes
%hook IGAudioStatusAnnouncer
- (void)_muteSwitchStateChanged:(id)changed {
    if (![SCIUtils getBoolPref:@"reels_disable_auto_unmute"]) {
        %orig(changed);
    }
}
- (void)_didPressVolumeButton:(id)button {
    if (![SCIUtils getBoolPref:@"reels_disable_auto_unmute"]) {
        %orig(button);
    }
}
- (void)_didUnplugHeadphones:(id)headphones {
    if (![SCIUtils getBoolPref:@"reels_disable_auto_unmute"]) {
        %orig(headphones);
    }
}
%end

%end

extern "C" void SCIInstallReelsPlaybackHooksIfNeeded(void) {
    BOOL shouldInstall = ![[SCIUtils getStringPref:@"reels_tap_control"] isEqualToString:@"default"] ||
                         [SCIUtils getBoolPref:@"reels_show_scrubber"] ||
                         [SCIUtils getBoolPref:@"reels_prevent_doom_scroll"] ||
                         [SCIUtils getBoolPref:@"reels_confirm_refresh"] ||
                         [SCIUtils getBoolPref:@"reels_disable_auto_unmute"];
    if (!shouldInstall) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIReelsPlaybackHooks);
    });
}

#import "SCIStartupHooks.h"

#import "SCIStabilityGuard.h"
#import "../Utils.h"

FOUNDATION_EXPORT void SCIInstallLiquidGlassHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallProgressiveBlurHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallFeedActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallReelsActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallStoriesActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallMessagesActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallProfileActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallProfilePhotoZoomHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallBackgroundRefreshHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallSeenButtonHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallFollowConfirmHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallCreateGroupButtonControlHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallSharedLinkCleanupHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallShareLongPressCopyHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallHideMetaAIHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallAdBlockingEarlyHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallStoryAdBlockingHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallFeedFilteringHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallFeedFilteringFeedHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallNoSuggestedUsersHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallLikeConfirmHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallTweakFeedHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallTweakStoryHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallTweakReelsHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallTweakMessagesHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallTweakGeneralUIHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallTweakLaunchCriticalHooks(void);
FOUNDATION_EXPORT void SCIInstallOpenLinkFromClipboardHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallHideExploreGridHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallHideTrendingSearchesHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallDisableFollowButtonEDRHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallNavigationHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallSettingsShortcutsHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallDisableHapticsHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallCopyDescriptionHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallNoRecentSearchesHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallDetailedColorPickerHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallEnhancedMediaResolutionHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallHideMetricsHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallDisableFeedAutoplayHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallPostCommentConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallSwipeCloseCommentsHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallHideStoryTrayHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallHideThreadsHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallHideRepostButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallDisableHomeButtonRefreshHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallDisableStorySeenHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallStickerInteractConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallStoryPollVoteCountsHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallHideReelsHeaderHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallReelsPlaybackHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallDisableScrollingReelsHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallFollowIndicatorHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallProfileAnalyzerVisitTrackerHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallDisableDMStorySeenHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallDisableInstantsCreationHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallInstantsActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallInstantsAllowScreenshotHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallInstantsReactionConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallInstantsGalleryUploadHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallVisualMsgModifierHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallNoSuggestedChatsHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallChangeThemeConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallFollowRequestConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallDisableTypingStatusHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallShhConfirmHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallHideFriendsMapHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallKeepDeletedMessagesHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallCallConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallDMAudioMsgConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallDMInteractionConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallNotesCustomizationHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallDMRefreshConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SCIInstallCaptureHidingHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallProfileHeaderControlsHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallAudioPageDownloadHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIInstallDMAudioDownloadHooksIfNeeded(void);

// Master kill switch: when YES, suppress all feature hook installation, but
// keep the home long-press shortcut so users can still reach Settings to turn
// it back off. Toggling requires a restart (each installer is dispatch_once).
static BOOL SCIShouldSuppressFeatureHooks(void) {
    return [SCIUtils getBoolPref:@"tools_disable_all"] || SCIStabilityGuardIsSafeStartupMode();
}

// Hooks that must always install regardless of the kill switch so users keep
// access to SCInsta Settings (home tab long-press → settings).
static void SCIInstallEssentialAccessHooks(void) {
    SCIInstallNavigationHooksIfNeeded();
    SCIInstallSettingsShortcutsHooksIfNeeded();
}

void SCIInstallLaunchCriticalHooks(void) {
    if (SCIShouldSuppressFeatureHooks()) {
        SCIInstallEssentialAccessHooks();
        return;
    }
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"26.0")) {
        if ([SCIUtils getBoolPref:@"interface_progressive_blur"]) {
            SCIInstallProgressiveBlurHooksIfEnabled();
        }
        if ([SCIUtils sci_isLiquidGlassEffectivelyEnabled]) {
            SCIInstallLiquidGlassHooksIfEnabled();
        }
    }
    SCIInstallTweakLaunchCriticalHooks();
    SCIInstallAdBlockingEarlyHooksIfEnabled();
    SCIInstallStoryAdBlockingHooksIfEnabled();
    SCIInstallNavigationHooksIfNeeded();
    SCIInstallSettingsShortcutsHooksIfNeeded();
}

void SCIInstallFeedSurfaceHooksIfNeeded(void) {
    if (SCIShouldSuppressFeatureHooks()) {
        SCIInstallEssentialAccessHooks();
        return;
    }
    SCIInstallTweakFeedHooksIfNeeded();
    SCIInstallFeedFilteringFeedHooksIfEnabled();
    SCIInstallFeedActionButtonHooksIfEnabled();
    SCIInstallBackgroundRefreshHooksIfEnabled();
    SCIInstallLikeConfirmHooksIfNeeded();
    SCIInstallDisableFeedAutoplayHooksIfEnabled();
    SCIInstallPostCommentConfirmHooksIfEnabled();
    SCIInstallSwipeCloseCommentsHooksIfEnabled();
    SCIInstallHideStoryTrayHooksIfEnabled();
    SCIInstallHideThreadsHooksIfEnabled();
    SCIInstallHideRepostButtonHooksIfEnabled();
    SCIInstallDisableHomeButtonRefreshHooksIfEnabled();
    SCIInstallCopyDescriptionHooksIfEnabled();
    SCIInstallHideMetricsHooksIfEnabled();
}

void SCIInstallStorySurfaceHooksIfNeeded(void) {
    if (SCIShouldSuppressFeatureHooks()) {
        SCIInstallEssentialAccessHooks();
        return;
    }
    SCIInstallTweakStoryHooksIfNeeded();
    SCIInstallFeedFilteringHooksIfEnabled();
    SCIInstallStoriesActionButtonHooksIfEnabled();
    SCIInstallSeenButtonHooksIfNeeded();
    SCIInstallHideMetaAIHooksIfEnabled();
    SCIInstallLikeConfirmHooksIfNeeded();
    SCIInstallDisableStorySeenHooksIfNeeded();
    SCIInstallStickerInteractConfirmHooksIfEnabled();
    SCIInstallStoryPollVoteCountsHooksIfEnabled();
    SCIInstallDetailedColorPickerHooksIfEnabled();
}

void SCIInstallReelsSurfaceHooksIfNeeded(void) {
    if (SCIShouldSuppressFeatureHooks()) {
        SCIInstallEssentialAccessHooks();
        return;
    }
    SCIInstallTweakReelsHooksIfNeeded();
    SCIInstallReelsActionButtonHooksIfEnabled();
    SCIInstallFeedFilteringHooksIfEnabled();
    SCIInstallLikeConfirmHooksIfNeeded();
    SCIInstallReelsPlaybackHooksIfNeeded();
    SCIInstallHideReelsHeaderHooksIfEnabled();
    SCIInstallDisableScrollingReelsHooksIfEnabled();
    SCIInstallHideRepostButtonHooksIfEnabled();
    SCIInstallHideMetricsHooksIfEnabled();
}

void SCIInstallMessagesSurfaceHooksIfNeeded(void) {
    if (SCIShouldSuppressFeatureHooks()) {
        SCIInstallEssentialAccessHooks();
        return;
    }
    SCIInstallTweakMessagesHooksIfNeeded();
    SCIInstallMessagesActionButtonHooksIfEnabled();
    SCIInstallSeenButtonHooksIfNeeded();
    SCIInstallCreateGroupButtonControlHooksIfEnabled();
    SCIInstallHideMetaAIHooksIfEnabled();
    SCIInstallDisableDMStorySeenHooksIfNeeded();
    SCIInstallDisableInstantsCreationHooksIfEnabled();
    SCIInstallInstantsActionButtonHooksIfEnabled();
    SCIInstallInstantsAllowScreenshotHooksIfEnabled();
    SCIInstallInstantsReactionConfirmHooksIfEnabled();
    SCIInstallInstantsGalleryUploadHooksIfEnabled();
    SCIInstallVisualMsgModifierHooksIfEnabled();
    SCIInstallNoSuggestedChatsHooksIfEnabled();
    SCIInstallChangeThemeConfirmHooksIfEnabled();
    SCIInstallFollowRequestConfirmHooksIfEnabled();
    SCIInstallDisableTypingStatusHooksIfEnabled();
    SCIInstallShhConfirmHooksIfNeeded();
    SCIInstallHideFriendsMapHooksIfEnabled();
    SCIInstallKeepDeletedMessagesHooksIfEnabled();
    SCIInstallCallConfirmHooksIfEnabled();
    SCIInstallDMAudioMsgConfirmHooksIfEnabled();
    SCIInstallDMInteractionConfirmHooksIfEnabled();
    SCIInstallNotesCustomizationHooksIfNeeded();
    SCIInstallDMRefreshConfirmHooksIfEnabled();
    SCIInstallDMAudioDownloadHooksIfNeeded();
    SCIInstallNoRecentSearchesHooksIfEnabled();
    SCIInstallDetailedColorPickerHooksIfEnabled();
}

void SCIInstallProfileSurfaceHooksIfNeeded(void) {
    if (SCIShouldSuppressFeatureHooks()) {
        SCIInstallEssentialAccessHooks();
        return;
    }
    SCIInstallProfileActionButtonHooksIfEnabled();
    SCIInstallProfilePhotoZoomHooksIfEnabled();
    SCIInstallFollowConfirmHooksIfNeeded();
    SCIInstallNoSuggestedUsersHooksIfEnabled();
    SCIInstallFollowIndicatorHooksIfEnabled();
    SCIInstallProfileHeaderControlsHooksIfNeeded();
    SCIInstallProfileAnalyzerVisitTrackerHooksIfEnabled();
    SCIInstallSettingsShortcutsHooksIfNeeded();
}

void SCIInstallGeneralUIHooksIfNeeded(void) {
    if (SCIShouldSuppressFeatureHooks()) {
        SCIInstallEssentialAccessHooks();
        return;
    }
    SCIInstallTweakGeneralUIHooksIfNeeded();
    SCIInstallSharedLinkCleanupHooksIfEnabled();
    SCIInstallShareLongPressCopyHooksIfNeeded();
    SCIInstallHideMetaAIHooksIfEnabled();
    SCIInstallNoSuggestedUsersHooksIfEnabled();
    SCIInstallOpenLinkFromClipboardHooksIfEnabled();
    SCIInstallHideExploreGridHooksIfEnabled();
    SCIInstallHideTrendingSearchesHooksIfEnabled();
    SCIInstallDisableFollowButtonEDRHooksIfEnabled();
    SCIInstallNavigationHooksIfNeeded();
    SCIInstallSettingsShortcutsHooksIfNeeded();
    SCIInstallDisableHapticsHooksIfEnabled();
    SCIInstallCopyDescriptionHooksIfEnabled();
    SCIInstallNoRecentSearchesHooksIfEnabled();
    SCIInstallEnhancedMediaResolutionHooksIfEnabled();
    SCIInstallAudioPageDownloadHooksIfNeeded();
    SCIInstallCaptureHidingHooksIfNeeded();
}

void SCIInstallEnabledFeatureHooks(void) {
    if (SCIShouldSuppressFeatureHooks()) {
        SCIInstallEssentialAccessHooks();
        return;
    }
    SCIInstallGeneralUIHooksIfNeeded();
    SCIInstallFeedSurfaceHooksIfNeeded();
    SCIInstallStorySurfaceHooksIfNeeded();
    SCIInstallReelsSurfaceHooksIfNeeded();
    SCIInstallMessagesSurfaceHooksIfNeeded();
    SCIInstallProfileSurfaceHooksIfNeeded();
}

#import "SPKStartupHooks.h"

#import "../Utils.h"
#import "SPKStabilityGuard.h"

FOUNDATION_EXPORT void SPKInstallLiquidGlassHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallProgressiveBlurHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallFeedActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallFollowingFeedHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallReelsActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallStoriesActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallMessagesActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallProfileActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallProfilePhotoZoomHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallBackgroundRefreshHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallSeenButtonHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallFollowConfirmHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallCreateGroupButtonControlHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallConfirmSendHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallSharedLinkCleanupHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallShareLongPressCopyHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallHideMetaAIHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallAccountSwitchHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallAdBlockingEarlyHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallStoryAdBlockingHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallFeedFilteringHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallFeedFilteringFeedHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallNoSuggestedUsersHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallLikeConfirmHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallTweakFeedHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallTweakStoryHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallTweakReelsHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallTweakMessagesHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallTweakGeneralUIHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallTweakLaunchCriticalHooks(void);
FOUNDATION_EXPORT void SPKInstallOpenLinkFromClipboardHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallHideExploreGridHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallHideTrendingSearchesHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallNavigationHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallSettingsShortcutsHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallDisableHapticsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallCopyDescriptionHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallNoRecentSearchesHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallSearchBarIconRemapHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallDetailedColorPickerHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallEnhancedMediaResolutionHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallHideMetricsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallDisableFeedAutoplayHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallPostCommentConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallSwipeCloseCommentsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallCommentActionsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallHideCommentGiftsButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallCommentComposerGalleryUploadHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallHideStoryTrayHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallHideThreadsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallHideRepostButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallDisableHomeButtonRefreshHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallDisableStorySeenHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallStickerInteractConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallStoryPollVoteCountsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallHideReelsHeaderHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallReelsPlaybackHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallDisableScrollingReelsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallFollowIndicatorHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallProfileAnalyzerVisitTrackerHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallDisableDMStorySeenHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallDisableInstantsCreationHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallInstantsActionButtonHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallInstantsAllowScreenshotHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallInstantsReactionConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallInstantsGalleryUploadHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallVisualMsgModifierHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallNoSuggestedChatsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallChangeThemeConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallFollowRequestConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallDisableTypingStatusHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallShhConfirmHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallHideFriendsMapHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallKeepDeletedMessagesHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallCallConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallDMAudioMsgConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallDMInteractionConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallDMRefreshConfirmHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallCaptureHidingHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallProfileHeaderControlsHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallAudioPageDownloadHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallDMAudioDownloadHooksIfNeeded(void);
FOUNDATION_EXPORT void SPKInstallNotesActionsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallHideDirectCallButtonsHooksIfEnabled(void);
FOUNDATION_EXPORT void SPKInstallFixDuplicateNotificationsHooksIfNeeded(void);

// Master kill switch: when YES, suppress all feature hook installation, but
// keep the home long-press shortcut so users can still reach Settings to turn
// it back off. Toggling requires a restart (each installer is dispatch_once).
static BOOL SPKShouldSuppressFeatureHooks(void) {
    return [SPKUtils getBoolPref:@"tools_disable_all"] || SPKStabilityGuardIsSafeStartupMode();
}

// Hooks that must always install regardless of the kill switch so users keep
// access to Sparkle Settings (home tab long-press → settings).
static void SPKInstallEssentialAccessHooks(void) {
    SPKInstallNavigationHooksIfNeeded();
    SPKInstallSettingsShortcutsHooksIfNeeded();
}

void SPKInstallLaunchCriticalHooks(void) {
    if (SPKShouldSuppressFeatureHooks()) {
        SPKInstallEssentialAccessHooks();
        return;
    }
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"26.0")) {
        if ([SPKUtils getBoolPref:@"interface_progressive_blur"]) {
            SPKInstallProgressiveBlurHooksIfEnabled();
        }
        if ([SPKUtils spk_isLiquidGlassEffectivelyEnabled]) {
            SPKInstallLiquidGlassHooksIfEnabled();
        }
    }
    SPKInstallTweakLaunchCriticalHooks();
    SPKInstallFollowingFeedHooksIfEnabled();
    SPKInstallAdBlockingEarlyHooksIfEnabled();
    SPKInstallStoryAdBlockingHooksIfEnabled();
    SPKInstallNavigationHooksIfNeeded();
    SPKInstallSettingsShortcutsHooksIfNeeded();
}

void SPKInstallFeedSurfaceHooksIfNeeded(void) {
    if (SPKShouldSuppressFeatureHooks()) {
        SPKInstallEssentialAccessHooks();
        return;
    }
    SPKInstallTweakFeedHooksIfNeeded();
    SPKInstallFeedFilteringFeedHooksIfEnabled();
    SPKInstallFeedActionButtonHooksIfEnabled();
    SPKInstallBackgroundRefreshHooksIfEnabled();
    SPKInstallLikeConfirmHooksIfNeeded();
    SPKInstallDisableFeedAutoplayHooksIfEnabled();
    SPKInstallPostCommentConfirmHooksIfEnabled();
    SPKInstallSwipeCloseCommentsHooksIfEnabled();
    SPKInstallCommentActionsHooksIfEnabled();
    SPKInstallHideCommentGiftsButtonHooksIfEnabled();
    SPKInstallCommentComposerGalleryUploadHooksIfEnabled();
    SPKInstallHideStoryTrayHooksIfEnabled();
    SPKInstallHideThreadsHooksIfEnabled();
    SPKInstallHideRepostButtonHooksIfEnabled();
    SPKInstallDisableHomeButtonRefreshHooksIfEnabled();
    SPKInstallCopyDescriptionHooksIfEnabled();
    SPKInstallHideMetricsHooksIfEnabled();
}

void SPKInstallStorySurfaceHooksIfNeeded(void) {
    if (SPKShouldSuppressFeatureHooks()) {
        SPKInstallEssentialAccessHooks();
        return;
    }
    SPKInstallTweakStoryHooksIfNeeded();
    SPKInstallFeedFilteringHooksIfEnabled();
    SPKInstallStoriesActionButtonHooksIfEnabled();
    SPKInstallSeenButtonHooksIfNeeded();
    SPKInstallHideMetaAIHooksIfEnabled();
    SPKInstallLikeConfirmHooksIfNeeded();
    SPKInstallDisableStorySeenHooksIfNeeded();
    SPKInstallStickerInteractConfirmHooksIfEnabled();
    SPKInstallStoryPollVoteCountsHooksIfEnabled();
    SPKInstallDetailedColorPickerHooksIfEnabled();
}

void SPKInstallReelsSurfaceHooksIfNeeded(void) {
    if (SPKShouldSuppressFeatureHooks()) {
        SPKInstallEssentialAccessHooks();
        return;
    }
    SPKInstallTweakReelsHooksIfNeeded();
    SPKInstallReelsActionButtonHooksIfEnabled();
    SPKInstallFeedFilteringHooksIfEnabled();
    SPKInstallLikeConfirmHooksIfNeeded();
    SPKInstallReelsPlaybackHooksIfNeeded();
    SPKInstallHideReelsHeaderHooksIfEnabled();
    SPKInstallDisableScrollingReelsHooksIfEnabled();
    SPKInstallHideRepostButtonHooksIfEnabled();
    SPKInstallHideMetricsHooksIfEnabled();
}

void SPKInstallMessagesSurfaceHooksIfNeeded(void) {
    if (SPKShouldSuppressFeatureHooks()) {
        SPKInstallEssentialAccessHooks();
        return;
    }
    SPKInstallTweakMessagesHooksIfNeeded();
    SPKInstallMessagesActionButtonHooksIfEnabled();
    SPKInstallSeenButtonHooksIfNeeded();
    SPKInstallCreateGroupButtonControlHooksIfEnabled();
    SPKInstallConfirmSendHooksIfEnabled();
    SPKInstallHideMetaAIHooksIfEnabled();
    SPKInstallDisableDMStorySeenHooksIfNeeded();
    SPKInstallDisableInstantsCreationHooksIfEnabled();
    SPKInstallInstantsActionButtonHooksIfEnabled();
    SPKInstallInstantsAllowScreenshotHooksIfEnabled();
    SPKInstallInstantsReactionConfirmHooksIfEnabled();
    SPKInstallInstantsGalleryUploadHooksIfEnabled();
    SPKInstallVisualMsgModifierHooksIfEnabled();
    SPKInstallNoSuggestedChatsHooksIfEnabled();
    SPKInstallChangeThemeConfirmHooksIfEnabled();
    SPKInstallFollowRequestConfirmHooksIfEnabled();
    SPKInstallDisableTypingStatusHooksIfEnabled();
    SPKInstallShhConfirmHooksIfNeeded();
    SPKInstallHideFriendsMapHooksIfEnabled();
    SPKInstallKeepDeletedMessagesHooksIfEnabled();
    SPKInstallCallConfirmHooksIfEnabled();
    SPKInstallDMAudioMsgConfirmHooksIfEnabled();
    SPKInstallDMInteractionConfirmHooksIfEnabled();
    SPKInstallDMRefreshConfirmHooksIfEnabled();
    SPKInstallDMAudioDownloadHooksIfNeeded();
    SPKInstallNotesActionsHooksIfEnabled();
    SPKInstallHideDirectCallButtonsHooksIfEnabled();
    SPKInstallNoRecentSearchesHooksIfEnabled();
    SPKInstallDetailedColorPickerHooksIfEnabled();
}

void SPKInstallProfileSurfaceHooksIfNeeded(void) {
    if (SPKShouldSuppressFeatureHooks()) {
        SPKInstallEssentialAccessHooks();
        return;
    }
    SPKInstallProfileActionButtonHooksIfEnabled();
    SPKInstallProfilePhotoZoomHooksIfEnabled();
    SPKInstallFollowConfirmHooksIfNeeded();
    SPKInstallNoSuggestedUsersHooksIfEnabled();
    SPKInstallFollowIndicatorHooksIfEnabled();
    SPKInstallProfileHeaderControlsHooksIfNeeded();
    SPKInstallProfileAnalyzerVisitTrackerHooksIfEnabled();
    SPKInstallSettingsShortcutsHooksIfNeeded();
}

void SPKInstallGeneralUIHooksIfNeeded(void) {
    if (SPKShouldSuppressFeatureHooks()) {
        SPKInstallEssentialAccessHooks();
        return;
    }
    SPKInstallAccountSwitchHooksIfNeeded();
    SPKInstallTweakGeneralUIHooksIfNeeded();
    SPKInstallSharedLinkCleanupHooksIfEnabled();
    SPKInstallShareLongPressCopyHooksIfNeeded();
    SPKInstallHideMetaAIHooksIfEnabled();
    SPKInstallNoSuggestedUsersHooksIfEnabled();
    SPKInstallOpenLinkFromClipboardHooksIfEnabled();
    SPKInstallHideExploreGridHooksIfEnabled();
    SPKInstallHideTrendingSearchesHooksIfEnabled();
    SPKInstallNavigationHooksIfNeeded();
    SPKInstallSettingsShortcutsHooksIfNeeded();
    SPKInstallDisableHapticsHooksIfEnabled();
    SPKInstallCopyDescriptionHooksIfEnabled();
    SPKInstallNoRecentSearchesHooksIfEnabled();
    SPKInstallSearchBarIconRemapHooksIfNeeded();
    SPKInstallEnhancedMediaResolutionHooksIfEnabled();
    SPKInstallAudioPageDownloadHooksIfNeeded();
    SPKInstallCaptureHidingHooksIfNeeded();
    SPKInstallFixDuplicateNotificationsHooksIfNeeded();
}

void SPKInstallEnabledFeatureHooks(void) {
    if (SPKShouldSuppressFeatureHooks()) {
        SPKInstallEssentialAccessHooks();
        return;
    }
    SPKInstallGeneralUIHooksIfNeeded();
    SPKInstallFeedSurfaceHooksIfNeeded();
    SPKInstallStorySurfaceHooksIfNeeded();
    SPKInstallReelsSurfaceHooksIfNeeded();
    SPKInstallMessagesSurfaceHooksIfNeeded();
    SPKInstallProfileSurfaceHooksIfNeeded();
}

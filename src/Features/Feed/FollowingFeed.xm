// Following feed mode, adapted from InstaSane by Edoardo (@n3d1117).
// https://github.com/n3d1117/InstaSane

#import <Foundation/Foundation.h>
#import <substrate.h>

#import "../../Utils.h"

static NSInteger const IGHomeFeedPickerMenuItemForYou = 0;
static NSInteger const IGHomeFeedPickerMenuItemFollowing = 5;

static BOOL SCIFollowingFeedEnabled(void) {
    return [[SCIUtils getStringPref:@"main_feed_mode"] isEqualToString:@"following"];
}

%group SCIFollowingFeedHooks

%hook IGHomeFeedPickerMenuController

- (id)initWithUserSession:(id)userSession
                menuItems:(NSArray *)menuItems
        homeFeedViewModel:(id)homeViewModel
          analyticsModule:(id)analyticsModule
     navigationController:(id)navigationController
isForYouContentLaneEnabled:(BOOL)forYouEnabled {
    NSMutableArray *items = menuItems.mutableCopy;
    [items removeObject:@(IGHomeFeedPickerMenuItemFollowing)];
    [items removeObject:@(IGHomeFeedPickerMenuItemForYou)];
    [items insertObject:@(IGHomeFeedPickerMenuItemFollowing) atIndex:0];
    return %orig(userSession, items, homeViewModel, analyticsModule, navigationController, YES);
}

- (void)_didSelectItem:(id)item {
    if (MSHookIvar<NSInteger>(item, "_feed_type") == IGHomeFeedPickerMenuItemFollowing) {
        return;
    }
    %orig;
}

%end

%hook _TtC14IGHomeMainFeed28IGHomeMainFeedViewController

- (void)viewWillAppear:(BOOL)animated {
    MSHookIvar<id>(self, "currentFeedMenuItem") = @(IGHomeFeedPickerMenuItemFollowing);
    %orig;
}

%end

%hook IGHomeFeedHeaderView

- (void)setTitle:(id)title animated:(BOOL)animated {
    if ([title isEqual:@"For you"]) {
        %orig(@"Following", animated);
        return;
    }
    %orig;
}

%end

%hook _TtC11IGDSAShared18IGDSAGatingManager

- (NSInteger)feedStickyContentLaneSelection {
    return 1;
}

%end

%hook IGMainFeedViewModel

- (id)initWithDeps:(id)deps
             posts:(id)posts
         nextMaxID:(id)nextMaxID
initialPaginationSource:(NSString *)paginationSource
contentCoordinator:(id)coordinator
dataSourceSupplementaryItemsProvider:(id)supplementaryProvider
disableAutomaticRefresh:(BOOL)disableRefresh
disableSerialization:(BOOL)disableSerialization
         sessionId:(id)sessionId
   analyticsModule:(id)analyticsModule
disableFlashFeedTLI:(BOOL)disableFlashFeedTLI
disableFlashFeedOnColdStart:(BOOL)disableColdStart
disableResponseDeferral:(BOOL)disableResponseDeferral
  hidesStoriesTray:(BOOL)hidesStoriesTray
   isSecondaryFeed:(BOOL)isSecondaryFeed
collectionViewBackgroundColorOverride:(id)backgroundColor
minWarmStartFetchInterval:(double)minWarmStart
peakMinWarmStartFetchInterval:(double)peakMinWarmStart
minimumWarmStartBackgroundedInterval:(double)backgroundedMinWarmStart
peakMinimumWarmStartBackgroundedInterval:(double)peakBackgroundedMinWarmStart
supplementalFeedHoistedMediaID:(id)hoistedMediaId
headerTitleOverride:(id)headerTitle
  isInFollowingTab:(BOOL)isInFollowingTab
useShimmerLoadingWhenNoStoriesTray:(BOOL)useShimmer
mainFeedDataFetcher:(id)dataFetcher {
    paginationSource = @"following";
    isInFollowingTab = YES;
    return %orig;
}

%end

%hook IGMainFeedNetworkSource

- (id)initWithPosts:(id)posts
          nextMaxID:(id)nextMaxID
initialPaginationSource:(NSString *)paginationSource
          fetchPath:(id)fetchPath
     responseParser:(id)responseParser
mainFeedNetworkSourceSessionDeps:(id)deps
     sessionTracker:(id)sessionTracker
    analyticsModule:(id)analyticsModule
      useNewUIGraph:(BOOL)useNewGraph {
    paginationSource = @"following";
    return %orig;
}

- (void)updatePaginationSource:(id)paginationSource nextMaxID:(id)nextMaxID {
    %orig(@"following", nextMaxID);
}

- (void)_updatePaginationSource:(id)paginationSource nextMaxID:(id)nextMaxID {
    %orig(@"following", nextMaxID);
}

%end

%hook _TtC24IGMainFeedDataFetcherKit30IGMainFeedRequestConfigFactory

- (id)generateHeadLoadRequestConfigWithReason:(NSInteger)reason
                                 trackingWith:(id)tracking
                           cancelOngoingFetch:(BOOL)cancel
                               hoistedMediaID:(id)hoistedMediaID
                        hoistedMediaShortcode:(id)shortcode
                                  deeplinkURL:(id)deeplinkURL
                             isNonFeedSurface:(BOOL)isNonFeedSurface
                             additionalParams:(id)params
                                prewarmConfig:(id)prewarmConfig
                              containerModule:(id)containerModule
                             paginationSource:(id)paginationSource
                          secondaryFeedFilter:(id)secondaryFeedFilter
                                  vpvdSeenIds:(id)seenIds {
    if ([paginationSource isEqual:@"following"]) {
        reason = 3;
    }
    return %orig;
}

%end

// Instagram 410.1.0 exposes a feed-only model without the newer shared Swift
// runtime name. Its Following tray still needs the original sizing workaround.
%hook IGStoryTrayCellViewModel

- (double)avatarSizeAdjustment {
    return 28.5;
}

%end

%end

extern "C" void SCIInstallFollowingFeedHooksIfEnabled(void) {
    if (!SCIFollowingFeedEnabled()) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIFollowingFeedHooks);
    });
}

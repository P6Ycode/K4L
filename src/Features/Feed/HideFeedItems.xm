#import "../../Utils.h"
#import "../../InstagramHeaders.h"

typedef NS_ENUM(NSInteger, SCIFeedFilterSurface) {
    SCIFeedFilterSurfaceFeed,
    SCIFeedFilterSurfaceReels,
    SCIFeedFilterSurfaceExplore,
    SCIFeedFilterSurfaceOther,
};

static BOOL SCIShouldHideAdsForSurface(SCIFeedFilterSurface surface) {
    switch (surface) {
        case SCIFeedFilterSurfaceFeed:
        case SCIFeedFilterSurfaceOther:
            return [SCIUtils getBoolPref:@"general_hide_ads_feed"];
        case SCIFeedFilterSurfaceReels:
            return [SCIUtils getBoolPref:@"general_hide_ads_reels"];
        case SCIFeedFilterSurfaceExplore:
            return [SCIUtils getBoolPref:@"general_hide_ads_explore"];
    }
    return NO;
}

static BOOL SCIShouldHideSuggestedAccountsForSurface(SCIFeedFilterSurface surface) {
    switch (surface) {
        case SCIFeedFilterSurfaceFeed:
            return [SCIUtils getBoolPref:@"general_hide_suggested_users_feed"];
        case SCIFeedFilterSurfaceReels:
            return [SCIUtils getBoolPref:@"general_hide_suggested_users_reels"];
        case SCIFeedFilterSurfaceExplore:
        case SCIFeedFilterSurfaceOther:
            return NO;
    }
    return NO;
}

static NSArray *removeItemsInList(NSArray *list, SCIFeedFilterSurface surface) {
    BOOL isFeed = surface == SCIFeedFilterSurfaceFeed;
    NSArray *originalObjs = list;
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        // Remove suggested posts
        if (isFeed && [SCIUtils getBoolPref:@"feed_hide_suggested_posts"]) {

            // Posts
            if (
                ([obj isKindOfClass:%c(IGMedia)] && [((IGMedia *)obj).explorePostInFeed isEqual:@YES])
                || ([obj isKindOfClass:%c(IGFeedGroupHeaderViewModel)] && [[obj title] isEqualToString:@"Suggested Posts"])
            ) {
                SCILog(@"General", @"[SCInsta] Removing suggested posts");

                continue;
            }

            // Suggested stories (carousel)
            if ([obj isKindOfClass:%c(IGInFeedStoriesTrayModel)]) {
                SCILog(@"General", @"[SCInsta] Hiding suggested stories carousel");

                continue;
            }

        }

        // Remove suggested reels (carousel)
        if (isFeed && [SCIUtils getBoolPref:@"feed_hide_suggested_reels"]) {
            if ([obj isKindOfClass:%c(IGFeedScrollableClipsModel)]) {
                SCILog(@"General", @"[SCInsta] Hiding suggested reels carousel");

                continue;
            }
        }
        
        // Remove suggested for you (accounts)
        if (SCIShouldHideSuggestedAccountsForSurface(surface)) {
            
            // Feed
            if (isFeed && [obj isKindOfClass:%c(IGHScrollAYMFModel)]) {
                SCILog(@"General", @"[SCInsta] Hiding accounts suggested for you (feed)");

                continue;
            }

            // Reels
            if ([obj isKindOfClass:%c(IGSuggestedUserInReelsModel)]) {
                SCILog(@"General", @"[SCInsta] Hiding accounts suggested for you (reels)");

                continue;
            }
        }

        // Remove suggested threads posts
        if ([SCIUtils getBoolPref:@"feed_hide_suggested_threads"]) {

            // Feed (carousel)
            if (isFeed) {
                if ([obj isKindOfClass:%c(IGBloksFeedUnitModel)] || [obj isKindOfClass:objc_getClass("IGThreadsInFeedModels.IGThreadsInFeedModel")]) {
                    SCILog(@"General", @"[SCInsta] Hiding suggested threads posts (carousel)");

                    continue;
                }
            }

            // Reels
            if ([obj isKindOfClass:%c(IGSundialNetegoItem)]) {
                SCILog(@"General", @"[SCInsta] Hiding suggested threads posts (reels)");

                continue;
            }

        }        

        // Remove story tray
        if (isFeed && [SCIUtils getBoolPref:@"feed_hide_stories_tray"]) {
            if ([obj isKindOfClass:%c(IGStoryDataController)]) {
                SCILog(@"General", @"[SCInsta] Hiding stories tray");

                continue;
            }
        }

        // Hide entire feed
        if (isFeed && [SCIUtils getBoolPref:@"feed_hide_entire_feed"]) {
            if ([obj isKindOfClass:%c(IGPostCreationManager)] || [obj isKindOfClass:%c(IGMedia)] || [obj isKindOfClass:%c(IGEndOfFeedDemarcatorModel)] || [obj isKindOfClass:%c(IGSpinnerLabelViewModel)]) {
                SCILog(@"General", @"[SCInsta] Hiding entire feed");

                continue;
            }
        }

        // Remove ads
        if (SCIShouldHideAdsForSurface(surface)) {
            if (
                ([obj isKindOfClass:%c(IGFeedItem)] && ([obj isSponsored] || [obj isSponsoredApp]))
                || ([obj isKindOfClass:%c(IGDiscoveryGridItem)] && [[obj model] isKindOfClass:%c(IGAdItem)])
                || [obj isKindOfClass:%c(IGAdItem)]
            ) {
                SCILog(@"General", @"[SCInsta] Removing ads");

                continue;
            }
        }

        [filteredObjs addObject:obj];
    }

    return [filteredObjs copy];
}

%group SCIFeedFilteringHooks

// Suggested posts/reels
%hook IGMainFeedListAdapterDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    NSArray *filteredObjs = removeItemsInList(%orig, SCIFeedFilterSurfaceFeed);

    // Remove loading spinner at end of feed (if 5 or less items in feed)
    NSUInteger arrayLength = [filteredObjs count];

    if (arrayLength <= 5) {
        filteredObjs = [filteredObjs filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
                return ![obj isKindOfClass:[%c(IGSpinnerLabelViewModel) class]];
            }]
        ];
    }

    return filteredObjs;
}
%end

%end

%group SCIFeedFilteringDeferredHooks

static NSArray *sciSundialFilterAndLimit(NSArray *list) {
    NSArray *filteredList = removeItemsInList(list, SCIFeedFilterSurfaceReels);

    if ([SCIUtils getBoolPref:@"reels_prevent_doom_scroll"]) {
        double reelCount = [SCIUtils getDoublePref:@"reels_doom_scroll_limit"];
        return [filteredList subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)reelCount, filteredList.count))];
    }

    return filteredList;
}

%hook IGSundialFeedDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    return sciSundialFilterAndLimit(%orig);
}
%end

// Demangled name: IGSundialFeed.IGSundialFeedDataSource
%hook _TtC13IGSundialFeed23IGSundialFeedDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    return sciSundialFilterAndLimit(%orig);
}
%end

%end

%group SCIAdBlockingEarlyHooks

%hook IGContextualFeedViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_feed"]) {
        return removeItemsInList(%orig, SCIFeedFilterSurfaceOther);
    }

    return %orig;
}
%end
%hook IGVideoFeedViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_feed"]) {
        return removeItemsInList(%orig, SCIFeedFilterSurfaceOther);
    }

    return %orig;
}
%end
%hook IGChainingFeedViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_feed"]) {
        return removeItemsInList(%orig, SCIFeedFilterSurfaceOther);
    }

    return %orig;
}
%end
%hook IGStoryAdPool
- (id)initWithUserSession:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_stories"]) {
        SCILog(@"General", @"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
%hook IGStoryAdsManager
- (id)initWithUserSession:(id)arg1 storyViewerLoggingContext:(id)arg2 storyFullscreenSectionLoggingContext:(id)arg3 viewController:(id)arg4 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_stories"]) {
        SCILog(@"General", @"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
%hook IGStoryAdsFetcher
- (id)initWithUserSession:(id)arg1 delegate:(id)arg2 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_stories"]) {
        SCILog(@"General", @"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
// IG 148.0
%hook IGStoryAdsResponseParser
- (id)parsedObjectFromResponse:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_stories"]) {
        SCILog(@"General", @"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
- (id)initWithReelStore:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_stories"]) {
        SCILog(@"General", @"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
%hook IGStoryAdsOptInTextView
- (id)initWithBrandedContentStyledString:(id)arg1 sponsoredPostLabel:(id)arg2 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_stories"]) {
        SCILog(@"General", @"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
%end
%hook IGSundialAdsResponseParser
- (id)parsedObjectFromResponse:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_reels"]) {
        SCILog(@"General", @"[SCInsta] Removing ads");

        return nil;
    }

    return %orig;
}
- (id)initWithMediaStore:(id)arg1 userStore:(id)arg2 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_reels"]) {
        SCILog(@"General", @"[SCInsta] Removing ads");
        
        return nil;
    }
    
    return %orig;
}
%end
// "Sponsored" posts on discover/search page
%hook IGExploreListKitDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_explore"]) {
        return removeItemsInList(%orig, SCIFeedFilterSurfaceExplore);
    }

    return %orig;
}
%end
// Demangled name: IGExploreViewControllerSwift.IGExploreListKitDataSource
%hook _TtC28IGExploreViewControllerSwift26IGExploreListKitDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_ads_explore"]) {
        return removeItemsInList(%orig, SCIFeedFilterSurfaceExplore);
    }

    return %orig;
}
%end

// Hide shopping carousel in reel comments
// Demangled name: IGCommentThreadCommerceCarouselPill.IGCommentThreadCommerceCarousel
%hook _TtC35IGCommentThreadCommerceCarouselPill31IGCommentThreadCommerceCarousel
- (id)initWithFrame:(CGRect)frame pillText:(id)text pillStyle:(NSInteger)style {
    if ([SCIUtils getBoolPref:@"feed_hide_comment_shopping"]) {
        return nil;
    }

    return %orig(frame, text, style);
}
%end

// Hide suggested search/shopping on reels

// Demangled name: IGShoppableEverythingCommon.IGRapEntrypointResolver
%hook _TtC27IGShoppableEverythingCommon23IGRapEntrypointResolver
- (id)initWithLauncherSet:(id)arg1 {
    if ([SCIUtils getBoolPref:@"general_hide_reels_shopping_cta"]) {
        return nil;
    }

    return %orig(arg1);
}
%end
// Demangled name: IGSundialOrganicCTAContainerView.IGSundialOrganicCTAContainerView
%hook _TtC32IGSundialOrganicCTAContainerView32IGSundialOrganicCTAContainerView
- (void)didMoveToWindow {
    %orig;

    if ([SCIUtils getBoolPref:@"general_hide_reels_shopping_cta"]) {
        [self removeFromSuperview];
    }
}
%end


%end

%group SCIFeedFilteringDeferredHooks

// Hide "suggested for you" text at end of feed
%hook IGEndOfFeedDemarcatorCellTopOfFeed
- (void)configureWithViewConfig:(id)arg1 {
    %orig;

    if ([SCIUtils getBoolPref:@"feed_hide_suggested_posts"]) {
        SCILog(@"General", @"[SCInsta] Hiding end of feed message");

        // Hide suggested for you text
        UILabel *_titleLabel = MSHookIvar<UILabel *>(self, "_titleLabel");

        if (_titleLabel != nil) {
            [_titleLabel setText:@""];
        }
    }

    return;
}
%end

%end

static BOOL SCIAnyFeedFilteringPrefEnabled(void) {
    for (NSString *key in @[
        @"general_hide_ads_feed",
        @"general_hide_ads_reels",
        @"general_hide_ads_explore",
        @"feed_hide_suggested_posts",
        @"feed_hide_suggested_reels",
        @"general_hide_suggested_users_feed",
        @"general_hide_suggested_users_reels",
        @"feed_hide_suggested_threads",
        @"feed_hide_stories_tray",
        @"feed_hide_entire_feed",
        @"reels_prevent_doom_scroll"
    ]) {
        if ([SCIUtils getBoolPref:key]) {
            return YES;
        }
    }

    return NO;
}

extern "C" void SCIInstallFeedFilteringFeedHooksIfEnabled(void) {
    if (!SCIAnyFeedFilteringPrefEnabled()) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIFeedFilteringHooks);
    });
}

extern "C" void SCIInstallFeedFilteringHooksIfEnabled(void) {
    if (!SCIAnyFeedFilteringPrefEnabled()) {
        return;
    }

    SCIInstallFeedFilteringFeedHooksIfEnabled();

    static dispatch_once_t deferredOnceToken;
    dispatch_once(&deferredOnceToken, ^{
        %init(SCIFeedFilteringDeferredHooks);
    });
}

extern "C" void SCIInstallAdBlockingEarlyHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"general_hide_ads_feed"] &&
        ![SCIUtils getBoolPref:@"general_hide_ads_stories"] &&
        ![SCIUtils getBoolPref:@"general_hide_ads_reels"] &&
        ![SCIUtils getBoolPref:@"general_hide_ads_explore"] &&
        ![SCIUtils getBoolPref:@"feed_hide_comment_shopping"] &&
        ![SCIUtils getBoolPref:@"general_hide_reels_shopping_cta"]) {
        return;
    }

    static dispatch_once_t earlyAdsOnceToken;
    dispatch_once(&earlyAdsOnceToken, ^{
        %init(SCIAdBlockingEarlyHooks);
    });
}

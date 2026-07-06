#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/ActionButton/ActionButtonLookupUtils.h"
#import "../../Utils.h"
#import "InstantsResolver.h"

// MARK: - Model Implementations

@implementation SPKInstantsResolvedSnap
- (NSURL *)url {
    return self.sparkleMediaURL;
}
- (NSURL *)imageURL {
    return self.sparklePhotoURL ?: self.sparkleMediaURL;
}
- (NSURL *)videoURL {
    return self.sparkleVideoURL;
}
- (NSDate *)takenAt {
    return self.importPostedDate;
}
- (id)media {
    return self.backingMedia;
}
@end

@implementation SPKInstantsResolverResult
@end

// MARK: - Service Cache Module

static NSArray *sCachedTimeOrderedSnaps = nil;
static NSArray *sCachedPeekPreviewSnaps = nil;

/// Live IGQuickSnapService instance, captured from the service hooks. Used at action
/// time to read the backing store's FULL snap list (see SPKInstantsStoreFullMediaList).
/// Held strongly: the service is a long-lived per-session object, and we must be able to
/// reach its store at action time even if IG isn't currently calling the getters.
static id sQuickSnapServiceInstance = nil;

/// Finds the live IGQuickSnapService from the current user session. Used both at hook
/// install time (to capture the service before its getters fire) and lazily at resolve
/// time if the hook-based capture missed it.
static id SPKInstantsLocateQuickSnapService(void) {
    @try {
        SEL sharedQSSel = NSSelectorFromString(@"sharedQuickSnapService");
        // Walk windows to find the user session (same pattern as SPKInstagramAPI)
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class])
                continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (![window respondsToSelector:@selector(userSession)])
                    continue;
                id session = [window valueForKey:@"userSession"];
                if (!session)
                    continue;
                if ([session respondsToSelector:sharedQSSel]) {
                    id service = ((id (*)(id, SEL))objc_msgSend)(session, sharedQSSel);
                    if (service)
                        return service;
                }
            }
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

/// Forward declarations — defined after the generic object-access helpers below.
static NSArray *SPKInstantsStoreSnapshot(void);
static NSArray *SPKInstantsUnionMediaLists(NSArray *primary, NSArray *secondary);
static NSString *SPKInstantsActiveSnapPKFromStackView(UIView *stackView);
static NSInteger SPKInstantsFindSnapIndexByPK(NSArray<SPKInstantsResolvedSnap *> *snaps, NSString *pk);
static id SPKInstantsBackingObjectFromView(UIView *view, NSInteger depth);
static NSInteger SPKInstantsVisualActiveIndex(UIView *stackView, NSArray *currentImages);
static NSString *SPKInstantsMediaPKForObject(id object, NSInteger depth);

/// Extracts a stable primary key string from a media object for deduplication.
/// Tries `pk`, `mediaPk`, and `graphQLID` selectors in order.
static NSString *SPKInstantsCacheMediaPK(id media) {
    if (!media)
        return nil;

    NSString *pk = SPKStringFromValue(SPKObjectForSelector(media, @"pk"));
    if (pk.length > 0)
        return pk;

    pk = SPKStringFromValue(SPKKVCObject(media, @"pk"));
    if (pk.length > 0)
        return pk;

    pk = SPKStringFromValue(SPKObjectForSelector(media, @"mediaPk"));
    if (pk.length > 0)
        return pk;

    pk = SPKStringFromValue(SPKKVCObject(media, @"mediaPk"));
    if (pk.length > 0)
        return pk;

    pk = SPKStringFromValue(SPKObjectForSelector(media, @"graphQLID"));
    if (pk.length > 0)
        return pk;

    pk = SPKStringFromValue(SPKKVCObject(media, @"graphQLID"));
    if (pk.length > 0)
        return pk;

    return nil;
}

/// Stores non-empty arrays from service hooks into the cache.
/// Only overwrites when the incoming array has items — the service reports only
/// *unseen* snaps, so its count drops to 0 as the user views them. We retain the
/// last non-empty snapshot for the duration of the viewer session (Requirement 2.3)
/// rather than letting a later empty callback wipe the cache.
/// Does not perform any resolution, URL extraction, or metadata parsing.
void SPKInstantsCacheServiceSnaps(id timeOrdered, id peekPreview, NSString *source) {
    BOOL hadMedia = (sCachedTimeOrderedSnaps.count > 0 || sCachedPeekPreviewSnaps.count > 0);
    NSArray *timeOrderedArr = SPKArrayFromCollection(timeOrdered);
    NSArray *peekPreviewArr = SPKArrayFromCollection(peekPreview);
    if (timeOrderedArr.count > 0) {
        sCachedTimeOrderedSnaps = timeOrderedArr;
        SPKLog(@"Instants", @"cache updated timeOrdered=%lu source=%@",
               (unsigned long)timeOrderedArr.count, source ?: @"unknown");
    }
    if (peekPreviewArr.count > 0) {
        sCachedPeekPreviewSnaps = peekPreviewArr;
        SPKLog(@"Instants", @"cache updated peekPreview=%lu source=%@",
               (unsigned long)peekPreviewArr.count, source ?: @"unknown");
    }

    // When the cache first gains media (after the header may already be on-screen with a
    // hidden/empty button), trigger a layout pass on any existing header view so
    // SPKInstantsPlaceButton re-runs and configures the button against the now-populated
    // cache. The notification alone isn't enough because SPKConfigureActionButton won't
    // store the context if the first configure returned empty.
    BOOL hasMedia = (sCachedTimeOrderedSnaps.count > 0 || sCachedPeekPreviewSnaps.count > 0);
    if (!hadMedia && hasMedia) {
        dispatch_async(dispatch_get_main_queue(), ^{
            Class headerClass = objc_getClass("_TtC45IGQuickSnapNavigationV3HeaderButtonController39IGQuickSnapNavigationV3HeaderButtonView");
            if (!headerClass)
                return;
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class])
                    continue;
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
                    NSUInteger idx = 0;
                    while (idx < queue.count) {
                        UIView *view = queue[idx++];
                        if ([view isKindOfClass:headerClass]) {
                            [view setNeedsLayout];
                            [view layoutIfNeeded];
                        }
                        for (UIView *sub in view.subviews)
                            [queue addObject:sub];
                    }
                }
            }
        });
    }
}

/// Returns the merged, deduplicated media list from both cache arrays.
/// Time-ordered snaps come first, then peek preview snaps that aren't already present.
/// Deduplication is by media PK.
NSArray *SPKInstantsMergedMediaList(void) {
    NSArray *timeOrdered = sCachedTimeOrderedSnaps;
    NSArray *peekPreview = sCachedPeekPreviewSnaps;

    if (!timeOrdered.count && !peekPreview.count)
        return @[];
    if (!peekPreview.count)
        return timeOrdered ?: @[];
    if (!timeOrdered.count)
        return peekPreview ?: @[];

    // Deduplicate: time-ordered items take priority, peek preview adds new items
    NSMutableOrderedSet *seenPKs = [NSMutableOrderedSet orderedSet];
    NSMutableArray *merged = [NSMutableArray arrayWithCapacity:timeOrdered.count + peekPreview.count];

    for (id media in timeOrdered) {
        NSString *pk = SPKInstantsCacheMediaPK(media);
        if (pk.length > 0) {
            if ([seenPKs containsObject:pk])
                continue;
            [seenPKs addObject:pk];
        }
        [merged addObject:media];
    }

    for (id media in peekPreview) {
        NSString *pk = SPKInstantsCacheMediaPK(media);
        if (pk.length > 0) {
            if ([seenPKs containsObject:pk])
                continue;
            [seenPKs addObject:pk];
        }
        [merged addObject:media];
    }

    return [merged copy];
}

#pragma mark - Media-to-Snap Conversion

/// Object value accessor that tries selector, KVC, Swift ivar (via SPKUtils), and ObjC ivar.
/// QuickSnap media objects are Swift fragment types whose data is reachable through
/// several access paths, so we try them all.
static id SPKInstantsObjectIvarValue(id target, NSString *key) {
    if (!target || key.length == 0)
        return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(target), key.UTF8String);
    if (!ivar && ![key hasPrefix:@"_"]) {
        NSString *underscored = [@"_" stringByAppendingString:key];
        ivar = class_getInstanceVariable(object_getClass(target), underscored.UTF8String);
    }
    if (!ivar)
        return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || (type[0] != '@' && type[0] != '#'))
        return nil;
    id value = nil;
    @try {
        value = object_getIvar(target, ivar);
    } @catch (__unused NSException *e) {
    }
    return value && ![value isKindOfClass:NSNull.class] ? value : nil;
}

static id SPKInstantsSwiftIvarValue(id target, NSString *key) {
    if (!target || key.length == 0)
        return nil;
    for (NSString *candidateKey in @[ key, [@"_" stringByAppendingString:key] ]) {
        id value = nil;
        @try {
            value = [SPKUtils getIvarForObj:target name:candidateKey.UTF8String];
        }
        @catch (__unused NSException *e) {
            value = nil;
        }
        if (value && ![value isKindOfClass:NSNull.class])
            return value;
    }
    return nil;
}

static id SPKInstantsObjectValue(id target, NSArray<NSString *> *keys) {
    if (!target)
        return nil;
    for (NSString *key in keys) {
        id value = SPKObjectForSelector(target, key);
        if (!value)
            value = SPKKVCObject(target, key);
        if (!value)
            value = SPKInstantsSwiftIvarValue(target, key);
        if (!value)
            value = SPKInstantsObjectIvarValue(target, key);
        if (value && ![value isKindOfClass:NSNull.class])
            return value;
    }
    return nil;
}

static double SPKInstantsDoubleValue(id target, NSArray<NSString *> *keys) {
    id value = SPKInstantsObjectValue(target, keys);
    if ([value respondsToSelector:@selector(doubleValue)])
        return [value doubleValue];
    return 0.0;
}

static BOOL SPKInstantsURLLooksVideo(NSURL *url) {
    NSString *extension = url.pathExtension.lowercaseString ?: @"";
    return [@[ @"mp4", @"mov", @"m4v", @"webm", @"hevc", @"m3u8" ] containsObject:extension];
}

/// Selects the best (highest-width) URL from a candidates/versions array.
static NSURL *SPKInstantsBestCandidateURL(id candidates) {
    NSArray *items = SPKArrayFromCollection(candidates);
    NSURL *bestURL = nil;
    NSInteger bestWidth = 0;
    for (id item in items) {
        NSURL *url = nil;
        NSInteger width = 0;
        if ([item isKindOfClass:NSDictionary.class]) {
            url = SPKURLFromValue(((NSDictionary *)item)[@"url"] ?: ((NSDictionary *)item)[@"urlString"]);
            width = [((NSDictionary *)item)[@"width"] integerValue];
        } else {
            url = SPKURLFromValue(SPKInstantsObjectValue(item, @[ @"url", @"urlString", @"uri" ]));
            id widthValue = SPKInstantsObjectValue(item, @[ @"width" ]);
            if ([widthValue respondsToSelector:@selector(integerValue)])
                width = [widthValue integerValue];
        }
        if (url && (!bestURL || width > bestWidth)) {
            bestURL = url;
            bestWidth = width;
        }
    }
    return bestURL;
}

static NSArray<NSString *> *SPKInstantsNestedKeys(void) {
    return @[ @"asIGQuickSnapMedia", @"asQuickSnapMedia", @"asMSHQuickSnapMedia",
              @"media", @"item", @"model", @"viewModel", @"legacyViewModel",
              @"quickSnapInfo", @"snap", @"instantSnap",
              @"asIGQuickSnapPhotoFragment", @"asQuickSnapPhotoFragment",
              @"asIGQuickSnapVideoFragment", @"asQuickSnapVideoFragment" ];
}

static NSURL *SPKInstantsVideoURLForObject(id object);
static NSURL *SPKInstantsPhotoURLForObject(id object);

/// Recursively determines whether an object represents a video Instant.
static BOOL SPKInstantsObjectLooksVideo(id object) {
    if (!object)
        return NO;

    NSString *mediaType = SPKStringFromValue(SPKInstantsObjectValue(object, @[ @"computedMediaType", @"mediaType", @"productType", @"type" ])).lowercaseString;
    if ([mediaType containsString:@"video"])
        return YES;
    if ([mediaType isEqualToString:@"2"])
        return YES;
    if (SPKInstantsDoubleValue(object, @[ @"videoDuration", @"duration" ]) > 0.0)
        return YES;
    if (SPKInstantsObjectValue(object, @[ @"videoVersions", @"video_versions", @"videoVersionsFragment" ]))
        return YES;

    id videoFragment = SPKInstantsObjectValue(object, @[ @"asIGQuickSnapVideoFragment", @"asQuickSnapVideoFragment" ]);
    if (videoFragment && videoFragment != object) {
        if (SPKInstantsVideoURLForObject(videoFragment))
            return YES;
        if (SPKInstantsDoubleValue(videoFragment, @[ @"videoDuration", @"duration" ]) > 0.0)
            return YES;
        if (SPKInstantsObjectValue(videoFragment, @[ @"videoVersions", @"video_versions", @"videoVersionsFragment" ]))
            return YES;
    }
    return NO;
}

/// Recursively extracts the best video URL from a media object, walking nested fragments.
static NSURL *SPKInstantsVideoURLForObject(id object) {
    if (!object)
        return nil;

    NSURL *directURL = SPKURLFromValue(object);
    if (SPKInstantsURLLooksVideo(directURL))
        return directURL;

    NSURL *url = SPKURLFromValue(SPKInstantsObjectValue(object, @[ @"sparkleVideoURL", @"videoURL", @"videoUrl", @"video_url", @"playableURL", @"playableUrl", @"playable_url", @"dashManifestURL", @"dashManifestUrl" ]));
    if (url)
        return url;

    id videoVersions = SPKInstantsObjectValue(object, @[ @"videoVersions", @"video_versions", @"videoVersionsFragment" ]);
    url = SPKInstantsBestCandidateURL(videoVersions);
    if (url)
        return url;

    id videoFragment = SPKInstantsObjectValue(object, @[ @"asIGQuickSnapVideoFragment", @"asQuickSnapVideoFragment" ]);
    if (videoFragment && videoFragment != object) {
        url = SPKInstantsVideoURLForObject(videoFragment);
        if (url)
            return url;
    }

    id nested = SPKInstantsObjectValue(object, SPKInstantsNestedKeys());
    if (nested && nested != object)
        return SPKInstantsVideoURLForObject(nested);

    return nil;
}

/// Recursively extracts the best photo URL from a media object, walking nested fragments.
static NSURL *SPKInstantsPhotoURLForObject(id object) {
    if (!object)
        return nil;

    NSURL *directURL = SPKURLFromValue(object);
    if (directURL && !SPKInstantsURLLooksVideo(directURL))
        return directURL;

    NSURL *url = SPKURLFromValue(SPKInstantsObjectValue(object, @[ @"sparklePhotoURL", @"displayUri", @"displayURI", @"mediaURLString", @"previewURLString", @"url", @"imageURL", @"imageUrl", @"thumbnailURL", @"squareCrop", @"fullSizeImageURLString" ]));
    if (url && !SPKInstantsURLLooksVideo(url))
        return url;

    id imageVersions = SPKInstantsObjectValue(object, @[ @"imageVersions2", @"image_versions2", @"imageVersions", @"imageVersionsFragment" ]);
    id candidates = SPKInstantsObjectValue(imageVersions, @[ @"candidates" ]);
    url = SPKInstantsBestCandidateURL(candidates ?: imageVersions);
    if (url)
        return url;

    // Try original_* variants (some models store original images separately)
    id originalImages = SPKInstantsObjectValue(object, @[ @"originalImages", @"original_images" ]);
    url = SPKInstantsBestCandidateURL(originalImages);
    if (url)
        return url;

    id mediaFragment = SPKInstantsObjectValue(object, @[ @"asIGQuickSnapMedia", @"asMSHQuickSnapMedia" ]);
    if (mediaFragment && mediaFragment != object) {
        url = SPKInstantsPhotoURLForObject(mediaFragment);
        if (url)
            return url;
    }

    // Try photo fragment (some Swift models have asIGQuickSnapPhotoFragment)
    id photoFragment = SPKInstantsObjectValue(object, @[ @"asIGQuickSnapPhotoFragment", @"asQuickSnapPhotoFragment" ]);
    if (photoFragment && photoFragment != object) {
        url = SPKInstantsPhotoURLForObject(photoFragment);
        if (url)
            return url;
    }

    id nested = SPKInstantsObjectValue(object, SPKInstantsNestedKeys());
    if (nested && nested != object)
        return SPKInstantsPhotoURLForObject(nested);

    return nil;
}

/// Recursively extracts the media PK string, walking nested fragments.
static NSString *SPKInstantsMediaPKForObject(id object, NSInteger depth) {
    if (!object || depth > 3)
        return nil;
    for (NSString *key in @[ @"graphQLID", @"mediaId", @"mediaID", @"pk", @"mediaPk", @"id" ]) {
        NSString *value = SPKStringFromValue(SPKInstantsObjectValue(object, @[ key ]));
        if (value.length > 0)
            return value;
    }
    id nested = SPKInstantsObjectValue(object, SPKInstantsNestedKeys());
    if (nested && nested != object)
        return SPKInstantsMediaPKForObject(nested, depth + 1);
    return nil;
}

/// Recursively extracts the posted date, walking nested fragments.
static NSDate *SPKInstantsPostedDateForObject(id object, NSInteger depth) {
    if (!object || depth > 3)
        return nil;
    for (NSString *key in @[ @"takenAt", @"taken_at", @"takenAtDate", @"device_timestamp", @"deviceTimestamp", @"created_at", @"createdAt", @"upload_time", @"uploadTime", @"published_time", @"publishedTime" ]) {
        id value = SPKInstantsObjectValue(object, @[ key ]);
        if (!value)
            continue;
        if ([value isKindOfClass:NSDate.class])
            return value;
        if ([value respondsToSelector:@selector(doubleValue)]) {
            double raw = [value doubleValue];
            if (raw > 1e15)
                raw /= 1000000.0;
            else if (raw > 1e12)
                raw /= 1000.0;
            if (raw > 0.0)
                return [NSDate dateWithTimeIntervalSince1970:raw];
        }
    }
    id nested = SPKInstantsObjectValue(object, SPKInstantsNestedKeys());
    if (nested && nested != object)
        return SPKInstantsPostedDateForObject(nested, depth + 1);
    return nil;
}

/// Converts an IGMedia (or compatible QuickSnap fragment) object into a fully populated
/// SPKInstantsResolvedSnap. Returns nil if no usable media URL can be extracted.
static SPKInstantsResolvedSnap *SPKInstantsResolvedSnapFromMedia(id media) {
    if (!media)
        return nil;

    NSString *username = SPKUsernameFromMediaObject(media);
    NSString *pk = SPKInstantsMediaPKForObject(media, 0);
    NSDate *postedDate = SPKInstantsPostedDateForObject(media, 0);

    NSURL *videoURL = SPKInstantsVideoURLForObject(media);
    NSURL *photoURL = SPKInstantsPhotoURLForObject(media);
    BOOL looksVideo = SPKInstantsObjectLooksVideo(media);
    BOOL isVideo = looksVideo && videoURL != nil;

    NSURL *mediaURL = isVideo ? videoURL : (photoURL ?: videoURL);

    if (!mediaURL) {
        // Enhanced diagnostic: dump class name and a few key ivars to understand the structure
        NSString *className = NSStringFromClass([media class]);
        // Try to enumerate ivars that might contain URL data
        NSMutableArray *ivarNames = [NSMutableArray array];
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(object_getClass(media), &ivarCount);
        for (unsigned int i = 0; ivars && i < ivarCount && i < 20; i++) {
            const char *name = ivar_getName(ivars[i]);
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (name && type) {
                NSString *ivarName = [NSString stringWithUTF8String:name];
                // Only log object-type ivars that might contain URLs/versions
                if (type[0] == '@' &&
                    ([ivarName containsString:@"image"] || [ivarName containsString:@"Image"] ||
                     [ivarName containsString:@"video"] || [ivarName containsString:@"Video"] ||
                     [ivarName containsString:@"url"] || [ivarName containsString:@"URL"] ||
                     [ivarName containsString:@"version"] || [ivarName containsString:@"Version"] ||
                     [ivarName containsString:@"media"] || [ivarName containsString:@"Media"] ||
                     [ivarName containsString:@"fragment"] || [ivarName containsString:@"Fragment"])) {
                    id ivarValue = nil;
                    @try {
                        ivarValue = object_getIvar(media, ivars[i]);
                    } @catch (__unused NSException *e) {
                    }
                    [ivarNames addObject:[NSString stringWithFormat:@"%@(%@)=%@",
                                                                    ivarName, [NSString stringWithUTF8String:type],
                                                                    ivarValue ? NSStringFromClass([ivarValue class]) : @"nil"]];
                }
            }
        }
        if (ivars)
            free(ivars);

        SPKLog(@"Instants", @"resolvedSnapFromMedia: no usable URL for media pk=%@ username=%@ class=%@ ivars=[%@]",
               pk ?: @"(nil)", username ?: @"(nil)", className,
               [ivarNames componentsJoinedByString:@", "]);
        return nil;
    }

    SPKInstantsResolvedSnap *snap = [[SPKInstantsResolvedSnap alloc] init];
    snap.sourceUsername = username;
    snap.sourceMediaPK = pk;
    snap.importPostedDate = postedDate;
    snap.sparkleIsVideo = isVideo;
    snap.sparkleMediaURL = mediaURL;
    snap.sparklePhotoURL = photoURL;
    snap.sparkleVideoURL = isVideo ? videoURL : nil;
    snap.sourceMediaURLString = mediaURL.absoluteString;
    snap.backingMedia = media;
    snap.resolverPath = @"service";

    return snap;
}

#pragma mark - Active Index Detection (Hook-Based Tracker)

/// Tracked active index — updated by hooking handleTap on the AnimatingSnapStackView.
/// This avoids reading the Swift `state` ivar (which crashes/returns nil after tap-through).
/// Reset to 0 when the consumption VC disappears.
static NSInteger sTrackedActiveIndex = 0;
/// The total count of snaps in the display list at the time tracking started.
/// Used to clamp the tracked index and detect stale values.
static NSUInteger sTrackedDisplayCount = 0;
/// Whether the hook-based tracker has been initialized this consumption session.
static BOOL sTrackedIndexValid = NO;

/// Called from the handleTap hook. Advances the tracked index.
static void SPKInstantsAdvanceTrackedIndex(void) {
    if (!sTrackedIndexValid)
        return;
    NSInteger nextIndex = sTrackedActiveIndex + 1;
    // Clamp: if we go past the end, stay at the last valid index.
    // The viewer wraps/stops on its own; we just track.
    if (sTrackedDisplayCount > 0 && nextIndex >= (NSInteger)sTrackedDisplayCount) {
        // The viewer will either wrap to 0 or dismiss. Keep at last for now.
        sTrackedActiveIndex = nextIndex; // Let it go slightly over; will be clamped at resolve time
    } else {
        sTrackedActiveIndex = nextIndex;
    }
    SPKLog(@"Instants", @"tracked index advanced to %ld (displayCount=%lu)",
           (long)sTrackedActiveIndex, (unsigned long)sTrackedDisplayCount);
}

/// Initializes tracking from the stack view's current state. Called lazily on first resolve.
/// Reads the currentImages array directly from the stack view (not from state — the view
/// has its own copy of this ivar that's safe to access via ObjC runtime).
static void SPKInstantsInitTracking(UIView *stackView) {
    if (sTrackedIndexValid)
        return;
    if (!stackView)
        return;

    // The AnimatingSnapStackView has a 'currentImages' ivar directly on it (not just on state).
    // This is a Swift Array bridged to NSArray of SingleSnapView instances.
    NSArray *currentImages = nil;
    @try {
        currentImages = SPKArrayFromCollection([stackView valueForKey:@"currentImages"]);
    } @catch (__unused NSException *e) {
    }
    if (!currentImages.count) {
        // Try the ivar directly (it's listed in the header as a direct ivar on the view)
        currentImages = SPKArrayFromCollection(SPKInstantsObjectIvarValue(stackView, @"currentImages"));
    }
    // Last resort: reconstruct from subviews
    if (!currentImages.count) {
        Class singleSnapClass = NSClassFromString(@"_TtC40IGQuickSnapImmersiveViewerSingleSnapView40IGQuickSnapImmersiveViewerSingleSnapView");
        if (!singleSnapClass)
            singleSnapClass = NSClassFromString(@"IGQuickSnapImmersiveViewerSingleSnapView");
        if (singleSnapClass) {
            NSMutableArray *snapViews = [NSMutableArray array];
            for (UIView *sub in stackView.subviews) {
                if ([sub isKindOfClass:singleSnapClass])
                    [snapViews addObject:sub];
            }
            if (snapViews.count > 0)
                currentImages = [snapViews copy];
        }
    }

    sTrackedDisplayCount = currentImages.count;

    // Try to read the initial index from state (may work on first open before tap-through).
    // If it fails, determine active by visual inspection of the subviews.
    NSInteger initialIndex = 0;
    id state = nil;
    @try {
        state = [stackView valueForKey:@"state"];
    } @catch (__unused NSException *e) {
    }
    if (state && [state isKindOfClass:NSObject.class]) {
        @try {
            id val = [state valueForKey:@"currentlyDisplayingQuickSnapIndex"];
            if ([val respondsToSelector:@selector(integerValue)]) {
                initialIndex = [val integerValue];
            }
        } @catch (__unused NSException *e) {
        }
    }

    // Validate: if index is 0 or state was nil, try the visual approach
    if (initialIndex == 0 || !state) {
        NSInteger visualIndex = SPKInstantsVisualActiveIndex(stackView, currentImages);
        if (visualIndex >= 0) {
            initialIndex = visualIndex;
        }
    }

    sTrackedActiveIndex = initialIndex;
    sTrackedIndexValid = YES;
    SPKLog(@"Instants", @"tracking initialized: index=%ld displayCount=%lu",
           (long)sTrackedActiveIndex, (unsigned long)sTrackedDisplayCount);
}

/// Resets tracking state (called when consumption VC disappears).
static void SPKInstantsResetTracking(void) {
    sTrackedActiveIndex = 0;
    sTrackedDisplayCount = 0;
    sTrackedIndexValid = NO;
}

/// Updates the display count for the tracker. Called from the main resolve function
/// once we know the actual display list size, so handleTap clamping works correctly.
static void SPKInstantsUpdateTrackingCount(NSUInteger count) {
    if (count > 0 && sTrackedDisplayCount != count) {
        sTrackedDisplayCount = count;
    }
}

/// Determines the active snap index by visual inspection of the stack view's subviews.
/// The active (topmost displayed) SingleSnapView is typically:
///   - The frontmost visible subview (last in subviews array) that matches SingleSnapView class
///   - NOT hidden, alpha > 0, and has a non-transformed (identity) state OR is the highest z-position
/// Returns -1 if not determinable.
static NSInteger SPKInstantsVisualActiveIndex(UIView *stackView, NSArray *currentImages) {
    if (!stackView || !currentImages.count)
        return -1;

    Class singleSnapClass = NSClassFromString(@"_TtC40IGQuickSnapImmersiveViewerSingleSnapView40IGQuickSnapImmersiveViewerSingleSnapView");
    if (!singleSnapClass)
        singleSnapClass = NSClassFromString(@"IGQuickSnapImmersiveViewerSingleSnapView");

    // Walk subviews in REVERSE order (frontmost = last). The first visible SingleSnapView
    // that isn't being animated away (transform ~ identity, full alpha) is the active one.
    NSArray<UIView *> *subviews = stackView.subviews;
    UIView *activeView = nil;

    SPKLog(@"Instants", @"visual: stackView has %lu subviews, currentImages has %lu items",
           (unsigned long)subviews.count, (unsigned long)currentImages.count);

    for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
        UIView *sub = subviews[i];
        if (sub.hidden || sub.alpha < 0.3)
            continue;
        if (sub.bounds.size.width < 20 || sub.bounds.size.height < 20)
            continue;

        BOOL isSnapView = NO;
        if (singleSnapClass && [sub isKindOfClass:singleSnapClass]) {
            isSnapView = YES;
        } else {
            // Fallback: check class name string
            NSString *cn = NSStringFromClass(sub.class);
            if ([cn containsString:@"SingleSnapView"])
                isSnapView = YES;
        }
        if (!isSnapView)
            continue;

        // Check if this view is in a "normal" display state (not being swept away).
        // An animating-away view typically has a non-identity transform (scaled down / rotated).
        CGAffineTransform t = sub.transform;
        BOOL isIdentityish = (fabs(t.a - 1.0) < 0.15 && fabs(t.d - 1.0) < 0.15 &&
                              fabs(t.b) < 0.15 && fabs(t.c) < 0.15);

        SPKLog(@"Instants", @"visual: subview[%ld] alpha=%.2f transform=[%.2f,%.2f,%.2f,%.2f] identity=%d class=%@",
               (long)i, sub.alpha, t.a, t.b, t.c, t.d, isIdentityish,
               NSStringFromClass(sub.class));

        if (isIdentityish) {
            activeView = sub;
            break;
        }
    }

    if (!activeView) {
        // All views might be mid-animation; pick the last visible one
        for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
            UIView *sub = subviews[i];
            if (sub.hidden || sub.alpha < 0.1)
                continue;
            BOOL isSnapView = NO;
            if (singleSnapClass && [sub isKindOfClass:singleSnapClass])
                isSnapView = YES;
            else if ([NSStringFromClass(sub.class) containsString:@"SingleSnapView"])
                isSnapView = YES;
            if (isSnapView) {
                activeView = sub;
                break;
            }
        }
    }

    if (!activeView) {
        SPKLog(@"Instants", @"visual: no active view found");
        return -1;
    }

    // Find this view's index in currentImages by pointer equality
    for (NSUInteger i = 0; i < currentImages.count; i++) {
        if (currentImages[i] == activeView) {
            SPKLog(@"Instants", @"visual: matched activeView at index %lu (pointer)", (unsigned long)i);
            return (NSInteger)i;
        }
    }

    SPKLog(@"Instants", @"visual: activeView %@ not found in currentImages by pointer, trying PK match",
           activeView);

    // If not found by pointer, try matching by identity (view might be recreated but
    // backing the same media). Match by extracting PK from both.
    NSString *activePK = nil;
    id backingMedia = SPKInstantsBackingObjectFromView(activeView, 0);
    if (backingMedia)
        activePK = SPKInstantsMediaPKForObject(backingMedia, 0);
    if (activePK.length > 0) {
        for (NSUInteger i = 0; i < currentImages.count; i++) {
            id item = currentImages[i];
            if (![item isKindOfClass:UIView.class])
                continue;
            id itemMedia = SPKInstantsBackingObjectFromView((UIView *)item, 0);
            if (itemMedia) {
                NSString *itemPK = SPKInstantsMediaPKForObject(itemMedia, 0);
                if ([activePK isEqualToString:itemPK])
                    return (NSInteger)i;
            }
        }
    }

    // Last resort: if currentImages was reconstructed from subviews in the same order,
    // the active view's position in subviews relative to other SingleSnapViews IS its index.
    // Find which SingleSnapView index this is among all SingleSnapViews in subviews.
    NSUInteger snapViewIndex = 0;
    for (UIView *sub in subviews) {
        BOOL isSnapView = NO;
        if (singleSnapClass && [sub isKindOfClass:singleSnapClass])
            isSnapView = YES;
        else if ([NSStringFromClass(sub.class) containsString:@"SingleSnapView"])
            isSnapView = YES;
        if (!isSnapView)
            continue;
        if (sub == activeView) {
            SPKLog(@"Instants", @"visual: matched activeView at subview snap index %lu", (unsigned long)snapViewIndex);
            return (NSInteger)snapViewIndex < (NSInteger)currentImages.count ? (NSInteger)snapViewIndex : -1;
        }
        snapViewIndex++;
    }

    SPKLog(@"Instants", @"visual: could not determine index");
    return -1;
}

/// Returns the best-known active index for the stack view.
/// Uses visual detection as primary (most reliable after tap-through), with the
/// hook-tracked index as fallback when visual detection can't determine the answer.
static NSInteger SPKInstantsActiveIndex(UIView *stackView) {
    // Initialize tracking if needed
    SPKInstantsInitTracking(stackView);

    // Primary: visual detection (always works if views are on screen)
    NSArray *currentImages = nil;
    @try {
        currentImages = SPKArrayFromCollection([stackView valueForKey:@"currentImages"]);
    } @catch (__unused NSException *e) {
    }
    if (!currentImages.count) {
        currentImages = SPKArrayFromCollection(SPKInstantsObjectIvarValue(stackView, @"currentImages"));
    }
    if (!currentImages.count) {
        // Reconstruct from subviews
        Class singleSnapClass = NSClassFromString(@"_TtC40IGQuickSnapImmersiveViewerSingleSnapView40IGQuickSnapImmersiveViewerSingleSnapView");
        if (!singleSnapClass)
            singleSnapClass = NSClassFromString(@"IGQuickSnapImmersiveViewerSingleSnapView");
        if (singleSnapClass) {
            NSMutableArray *snapViews = [NSMutableArray array];
            for (UIView *sub in stackView.subviews) {
                if ([sub isKindOfClass:singleSnapClass])
                    [snapViews addObject:sub];
            }
            if (snapViews.count > 0)
                currentImages = [snapViews copy];
        }
    }

    NSInteger visual = SPKInstantsVisualActiveIndex(stackView, currentImages);
    if (visual >= 0)
        return visual;

    // Fallback: hook-tracked index (if valid and in range)
    if (sTrackedIndexValid && sTrackedDisplayCount > 0) {
        NSInteger clamped = sTrackedActiveIndex;
        if (clamped >= (NSInteger)sTrackedDisplayCount)
            clamped = (NSInteger)sTrackedDisplayCount - 1;
        if (clamped < 0)
            clamped = 0;
        return clamped;
    }

    return 0;
}

/// Find the key window for a given view, falling back to the first key window.
static UIWindow *SPKInstantsWindowForHeader(UIView *header) {
    if (header.window)
        return header.window;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class])
            continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow)
                return window;
        }
    }
    return nil;
}

/// BFS walk from window to find the AnimatingSnapStackView.
static UIView *SPKInstantsSnapStackViewForHeader(UIView *header) {
    UIWindow *window = SPKInstantsWindowForHeader(header);
    if (!window)
        return nil;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    NSUInteger idx = 0;
    while (idx < queue.count) {
        UIView *view = queue[idx++];
        NSString *className = NSStringFromClass(view.class);
        if ([className containsString:@"IGQuickSnapImmersiveViewerAnimatingSnapStackView"] &&
            ![className containsString:@"PanHandler"] &&
            ![className containsString:@"State"]) {
            return view;
        }
        for (UIView *sub in view.subviews) {
            [queue addObject:sub];
        }
    }
    return nil;
}

/// Returns the current active index using the hook-based tracker.
/// Falls back to visual detection if tracking hasn't been initialized.
static NSInteger SPKInstantsRawActiveIndexFromStackView(UIView *stackView) {
    if (!stackView)
        return 0;
    return SPKInstantsActiveIndex(stackView);
}

#pragma mark - View-Based Fallback (for active/seen snaps not in service cache)

/// Walks a view tree to find an IGImageView/UIImageView that has loaded content.
static UIImageView *SPKInstantsImageViewInSnap(UIView *snap) {
    if (!snap)
        return nil;
    Class igImageViewClass = NSClassFromString(@"IGImageView");
    __block UIImageView *result = nil;
    __block UIImageView *fallback = nil;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:snap];
    NSUInteger idx = 0;
    while (idx < queue.count) {
        UIView *view = queue[idx++];
        if (view.hidden || view.alpha < 0.05) {
            for (UIView *s in view.subviews)
                [queue addObject:s];
            continue;
        }
        if (view.bounds.size.width < 8.0 || view.bounds.size.height < 8.0) {
            for (UIView *s in view.subviews)
                [queue addObject:s];
            continue;
        }
        BOOL isImageView = [view isKindOfClass:UIImageView.class] ||
                           (igImageViewClass && [view isKindOfClass:igImageViewClass]);
        if (!isImageView) {
            for (UIView *s in view.subviews)
                [queue addObject:s];
            continue;
        }

        UIImageView *imageView = (UIImageView *)view;
        if (imageView.image) {
            result = imageView;
            break;
        }

        // Check imageSpecifier.url (IGImageView stores loaded URLs this way)
        id spec = nil;
        @try {
            spec = [imageView valueForKey:@"imageSpecifier"];
        } @catch (__unused NSException *e) {
        }
        NSURL *specURL = SPKURLFromValue(SPKObjectForSelector(spec, @"url") ?: SPKKVCObject(spec, @"url"));
        if (specURL) {
            result = imageView;
            break;
        }
        if (!fallback)
            fallback = imageView;
        for (UIView *s in view.subviews)
            [queue addObject:s];
    }
    return result ?: fallback;
}

/// Extracts a photo URL from an IGImageView via its imageSpecifier.
static NSURL *SPKInstantsURLForImageView(UIImageView *imageView) {
    if (!imageView)
        return nil;
    id spec = nil;
    @try {
        spec = [imageView valueForKey:@"imageSpecifier"];
    } @catch (__unused NSException *e) {
    }
    NSURL *url = SPKURLFromValue(SPKObjectForSelector(spec, @"url") ?: SPKKVCObject(spec, @"url"));
    if (url)
        return url;
    return SPKURLFromValue(SPKObjectForSelector(imageView, @"url") ?: SPKKVCObject(imageView, @"url"));
}

/// Finds a video player view inside a snap view.
static UIView *SPKInstantsVideoViewInSnap(UIView *snap) {
    if (!snap)
        return nil;
    id direct = SPKInstantsObjectValue(snap, @[ @"videoView", @"_videoView" ]);
    if ([direct isKindOfClass:UIView.class])
        return (UIView *)direct;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:snap];
    NSUInteger idx = 0;
    while (idx < queue.count) {
        UIView *view = queue[idx++];
        if (view.hidden || view.alpha < 0.05) {
            for (UIView *s in view.subviews)
                [queue addObject:s];
            continue;
        }
        NSString *className = NSStringFromClass(view.class);
        if ([className containsString:@"IGAssetPlayerView"] || [className containsString:@"Video"])
            return view;
        for (UIView *s in view.subviews)
            [queue addObject:s];
    }
    return nil;
}

/// Extracts a video URL from an AVPlayer-like hierarchy.
static NSURL *SPKInstantsVideoURLFromPlayerLike(id playerLike, NSInteger depth) {
    if (!playerLike || depth > 4)
        return nil;
    NSURL *url = SPKURLFromValue(playerLike);
    if (url)
        return url;

    id currentItem = SPKObjectForSelector(playerLike, @"currentItem") ?: SPKKVCObject(playerLike, @"currentItem");
    if (currentItem && currentItem != playerLike) {
        id asset = SPKObjectForSelector(currentItem, @"asset") ?: SPKKVCObject(currentItem, @"asset");
        if ([asset isKindOfClass:[AVURLAsset class]])
            return ((AVURLAsset *)asset).URL;
        NSURL *assetURL = SPKURLFromValue(SPKObjectForSelector(asset, @"URL") ?: SPKKVCObject(asset, @"URL"));
        if (assetURL)
            return assetURL;
    }

    id asset = SPKObjectForSelector(playerLike, @"asset") ?: SPKKVCObject(playerLike, @"asset");
    if ([asset isKindOfClass:[AVURLAsset class]])
        return ((AVURLAsset *)asset).URL;
    NSURL *assetURL = SPKURLFromValue(SPKObjectForSelector(asset, @"URL") ?: SPKKVCObject(asset, @"URL"));
    if (assetURL)
        return assetURL;

    for (NSString *key in @[ @"player", @"avPlayer", @"queuePlayer", @"currentPlayer", @"playerController", @"playbackController", @"videoPlayer" ]) {
        id nested = SPKInstantsObjectValue(playerLike, @[ key ]);
        if (!nested || nested == playerLike)
            continue;
        url = SPKInstantsVideoURLFromPlayerLike(nested, depth + 1);
        if (url)
            return url;
    }
    return nil;
}

/// Extracts a video URL from a snap's playback hierarchy.
static NSURL *SPKInstantsVideoURLFromSnapPlayback(UIView *snap) {
    UIView *videoView = SPKInstantsVideoViewInSnap(snap);
    if (!videoView)
        return nil;
    NSURL *url = SPKInstantsVideoURLFromPlayerLike(videoView, 0);
    if (url)
        return url;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:videoView];
    NSUInteger idx = 0;
    while (idx < queue.count) {
        UIView *view = queue[idx++];
        url = SPKInstantsVideoURLFromPlayerLike(view, 0);
        if (url)
            return url;
        for (UIView *s in view.subviews)
            [queue addObject:s];
    }
    return nil;
}

/// Extracts a backing model object from a snap view (the model carries PK/username/URLs).
static id SPKInstantsBackingObjectFromView(UIView *view, NSInteger depth) {
    if (!view || depth > 3)
        return nil;
    for (NSString *key in @[ @"media", @"item", @"model", @"viewModel", @"legacyViewModel", @"quickSnapInfo", @"snap", @"instantSnap" ]) {
        id value = SPKObjectForSelector(view, key);
        if (!value)
            value = SPKKVCObject(view, key);
        if (value)
            return value;
    }
    if (depth < 2) {
        for (UIView *subview in view.subviews) {
            id result = SPKInstantsBackingObjectFromView(subview, depth + 1);
            if (result)
                return result;
        }
    }
    return nil;
}

/// Writes a UIImage to a temp file and returns a file:// URL.
static NSURL *SPKInstantsTempURLForImage(UIImage *image) {
    if (!image)
        return nil;
    NSData *data = UIImageJPEGRepresentation(image, 1.0);
    if (!data)
        return nil;
    NSString *name = [NSString stringWithFormat:@"sparkle-instant-%@.jpg", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if (![data writeToURL:url options:NSDataWritingAtomic error:nil])
        return nil;
    return url;
}

/// Resolves a snap from a live snap view (UIView from the stack's currentImages).
/// This is the fallback path for snaps that have been removed from the service cache.
static SPKInstantsResolvedSnap *SPKInstantsResolvedSnapFromView(UIView *snap) {
    if (!snap)
        return nil;
    UIImageView *imageView = SPKInstantsImageViewInSnap(snap);
    id backingMedia = SPKInstantsBackingObjectFromView(snap, 0);
    if (!backingMedia)
        backingMedia = SPKInstantsBackingObjectFromView(imageView, 0);

    // Try model-based URL extraction first (handles most cases)
    NSURL *videoURL = SPKInstantsVideoURLForObject(backingMedia);
    NSURL *photoURL = SPKInstantsPhotoURLForObject(backingMedia);

    // Fallback: extract from live playback / imageSpecifier
    if (!videoURL)
        videoURL = SPKInstantsVideoURLFromSnapPlayback(snap);
    if (!photoURL)
        photoURL = SPKInstantsURLForImageView(imageView);
    if (!photoURL && imageView.image)
        photoURL = SPKInstantsTempURLForImage(imageView.image);

    BOOL looksVideo = NO;
    if (backingMedia)
        looksVideo = SPKInstantsObjectLooksVideo(backingMedia);
    if (!looksVideo)
        looksVideo = (SPKInstantsVideoViewInSnap(snap) != nil);
    BOOL isVideo = looksVideo && videoURL != nil;

    NSURL *mediaURL = isVideo ? videoURL : (photoURL ?: videoURL);
    if (!mediaURL)
        return nil;

    NSString *username = backingMedia ? SPKUsernameFromMediaObject(backingMedia) : nil;
    NSString *pk = backingMedia ? SPKInstantsMediaPKForObject(backingMedia, 0) : nil;
    NSDate *postedDate = backingMedia ? SPKInstantsPostedDateForObject(backingMedia, 0) : nil;

    SPKInstantsResolvedSnap *resolved = [[SPKInstantsResolvedSnap alloc] init];
    resolved.sourceUsername = username;
    resolved.sourceMediaPK = pk;
    resolved.importPostedDate = postedDate;
    resolved.sparkleIsVideo = isVideo;
    resolved.sparkleMediaURL = mediaURL;
    resolved.sparklePhotoURL = photoURL;
    resolved.sparkleVideoURL = isVideo ? videoURL : nil;
    resolved.sourceMediaURLString = mediaURL.absoluteString;
    resolved.backingMedia = backingMedia;
    resolved.resolverPath = @"view";
    return resolved;
}

/// Resolves snaps from the live stack view's currentImages array.
/// This is the fallback when the service cache is empty (all snaps have been "seen").
static NSArray<SPKInstantsResolvedSnap *> *SPKInstantsResolveFromStackView(UIView *header, NSInteger *activeIndexOut) {
    UIView *stackView = SPKInstantsSnapStackViewForHeader(header);
    if (!stackView)
        return nil;

    // Read currentImages directly from the stack view (it has its own copy, separate from state)
    NSArray *currentImages = nil;
    @try {
        currentImages = SPKArrayFromCollection([stackView valueForKey:@"currentImages"]);
    } @catch (__unused NSException *e) {
    }
    if (!currentImages.count) {
        currentImages = SPKArrayFromCollection(SPKInstantsObjectIvarValue(stackView, @"currentImages"));
    }
    if (currentImages.count == 0)
        return nil;

    // Use the hook-based tracker for active index
    NSInteger rawIndex = SPKInstantsActiveIndex(stackView);
    if (activeIndexOut)
        *activeIndexOut = rawIndex;

    // Try to get viewModel items from the state if still accessible (may work early in session)
    NSArray *modelItems = nil;
    id state = nil;
    @try {
        state = [stackView valueForKey:@"state"];
    } @catch (__unused NSException *e) {
    }
    if (state && [state isKindOfClass:NSObject.class]) {
        id viewModel = nil;
        @try {
            viewModel = [state valueForKey:@"viewModel"];
        } @catch (__unused NSException *e) {
        }
        if (!viewModel) {
            @try {
                viewModel = [state valueForKey:@"_viewModel"];
            } @catch (__unused NSException *e) {
            }
        }
        modelItems = SPKArrayFromCollection(viewModel);
        if (!modelItems.count) {
            modelItems = SPKArrayFromCollection(SPKInstantsObjectValue(viewModel,
                                                                       @[ @"items", @"medias", @"media", @"snaps", @"quickSnaps", @"timeOrderedQuicksnaps", @"viewModels", @"children" ]));
        }
    }

    // Try model items first (they carry proper URLs/metadata)
    if (modelItems.count > 0) {
        NSMutableArray<SPKInstantsResolvedSnap *> *snaps = [NSMutableArray arrayWithCapacity:modelItems.count];
        for (id item in modelItems) {
            SPKInstantsResolvedSnap *snap = SPKInstantsResolvedSnapFromMedia(item);
            if (snap) {
                snap.resolverPath = @"stack.model";
                [snaps addObject:snap];
            }
        }
        if (snaps.count > 0) {
            SPKLog(@"Instants", @"stack model fallback: %lu snaps from viewModel", (unsigned long)snaps.count);
            return snaps;
        }
    }

    // Fallback: resolve from the view layer (currentImages are UIViews)
    NSMutableArray<SPKInstantsResolvedSnap *> *snaps = [NSMutableArray arrayWithCapacity:currentImages.count];
    for (id image in currentImages) {
        SPKInstantsResolvedSnap *resolved = nil;
        if ([image isKindOfClass:UIView.class]) {
            resolved = SPKInstantsResolvedSnapFromView((UIView *)image);
        }
        if (!resolved) {
            // The item might itself be a media model object, not a view
            resolved = SPKInstantsResolvedSnapFromMedia(image);
            if (resolved)
                resolved.resolverPath = @"stack.image.model";
        }
        if (resolved)
            [snaps addObject:resolved];
    }

    if (snaps.count > 0) {
        SPKLog(@"Instants", @"stack view fallback: %lu snaps from currentImages", (unsigned long)snaps.count);
    }
    return snaps.count > 0 ? snaps : nil;
}

/// Returns the username of the currently-visible author from the consumption author text view.
static NSString *SPKInstantsCurrentAuthorUsername(UIView *header) {
    UIWindow *window = SPKInstantsWindowForHeader(header);
    if (!window)
        return nil;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    NSUInteger idx = 0;
    while (idx < queue.count) {
        UIView *view = queue[idx++];
        if (view.hidden || view.alpha < 0.05) {
            for (UIView *s in view.subviews)
                [queue addObject:s];
            continue;
        }
        NSString *className = NSStringFromClass(view.class);
        if ([className containsString:@"IGQuickSnapConsumptionAuthorTextView"]) {
            // Try currentUsername selector/KVC
            id currentUsername = SPKObjectForSelector(view, @"currentUsername") ?: SPKKVCObject(view, @"currentUsername");
            NSString *username = SPKStringFromValue(currentUsername);
            if (username.length > 0 && username.length <= 30)
                return username;
            // Try usernameLabel
            id label = SPKObjectForSelector(view, @"usernameLabel") ?: SPKKVCObject(view, @"usernameLabel");
            if (!label)
                label = [SPKUtils getIvarForObj:view name:"usernameLabel"];
            if ([label isKindOfClass:UILabel.class]) {
                username = ((UILabel *)label).text;
                if ([username hasPrefix:@"@"])
                    username = [username substringFromIndex:1];
                if (username.length > 0 && username.length <= 30)
                    return username;
            }
        }
        for (UIView *s in view.subviews)
            [queue addObject:s];
    }
    return nil;
}

#pragma mark - Store-Backed Full List

/// Snapshot of the store's time-ordered list, captured on first resolve during a
/// consumption session. The live store mutates (removes snaps as they're marked seen),
/// so we freeze it once to guarantee the topmost snap stays available throughout viewing.
static NSArray *sStoreSnapshot = nil;
/// Reset token — cleared when the viewer disappears so a fresh snapshot is taken next time.
static BOOL sStoreSnapshotTaken = NO;

/// Captures a snapshot of the store's full list if we haven't already this session.
/// Returns the snapshot (immutable) or nil if the store isn't reachable.
static NSArray *SPKInstantsStoreSnapshot(void) {
    if (sStoreSnapshotTaken && sStoreSnapshot)
        return sStoreSnapshot;

    id service = sQuickSnapServiceInstance;
    if (!service) {
        service = SPKInstantsLocateQuickSnapService();
        if (service)
            sQuickSnapServiceInstance = service;
    }
    if (!service) {
        SPKLog(@"Instants", @"store: no service instance (hooks not fired & session lookup failed)");
        return sStoreSnapshot; // may be nil
    }

    id store = [SPKUtils getIvarForObj:service name:"quickSnapStore"];
    if (!store)
        store = SPKInstantsSwiftIvarValue(service, @"quickSnapStore");
    if (!store) {
        SPKLog(@"Instants", @"store: quickSnapStore ivar nil on service=%@", NSStringFromClass([service class]));
        return sStoreSnapshot;
    }

    id timeOrdered = [SPKUtils getIvarForObj:store name:"timeOrderedQuicksnaps"];
    if (!timeOrdered)
        timeOrdered = SPKInstantsSwiftIvarValue(store, @"timeOrderedQuicksnaps");
    NSArray *full = SPKArrayFromCollection(timeOrdered);

    if (full.count > 0) {
        // Take the snapshot: copy the array so mutations to the store don't affect us.
        if (!sStoreSnapshotTaken) {
            sStoreSnapshot = [full copy];
            sStoreSnapshotTaken = YES;
            SPKLog(@"Instants", @"store snapshot taken count=%lu", (unsigned long)sStoreSnapshot.count);
        } else if (full.count > sStoreSnapshot.count) {
            // Store grew (new snaps arrived during viewing) — expand our snapshot
            sStoreSnapshot = [full copy];
            SPKLog(@"Instants", @"store snapshot expanded count=%lu", (unsigned long)sStoreSnapshot.count);
        }
    }

    return sStoreSnapshot;
}

/// Resets the snapshot so the next consumption session takes a fresh one.
void SPKInstantsResetStoreSnapshot(void) {
    sStoreSnapshot = nil;
    sStoreSnapshotTaken = NO;
}

/// Returns `primary` plus any items of `secondary` whose media PK isn't already present.
/// Order: primary first (store's full time-ordered list), then new peek-preview items.
static NSArray *SPKInstantsUnionMediaLists(NSArray *primary, NSArray *secondary) {
    if (!primary.count)
        return secondary ?: @[];
    if (!secondary.count)
        return primary;

    NSMutableOrderedSet *seenPKs = [NSMutableOrderedSet orderedSet];
    NSMutableArray *merged = [NSMutableArray arrayWithCapacity:primary.count + secondary.count];
    for (id media in primary) {
        NSString *pk = SPKInstantsCacheMediaPK(media);
        if (pk.length > 0)
            [seenPKs addObject:pk];
        [merged addObject:media];
    }
    for (id media in secondary) {
        NSString *pk = SPKInstantsCacheMediaPK(media);
        if (pk.length > 0 && [seenPKs containsObject:pk])
            continue;
        if (pk.length > 0)
            [seenPKs addObject:pk];
        [merged addObject:media];
    }
    return [merged copy];
}

/// Determines the active snap's PK by reading the stack view's currently-displayed view
/// and extracting its backing model PK. Uses the hook-based tracker for the active index.
static NSString *SPKInstantsActiveSnapPKFromStackView(UIView *stackView) {
    if (!stackView)
        return nil;

    NSInteger displayIndex = SPKInstantsActiveIndex(stackView);

    // Read currentImages from the stack view directly
    NSArray *currentImages = nil;
    @try {
        currentImages = SPKArrayFromCollection([stackView valueForKey:@"currentImages"]);
    } @catch (__unused NSException *e) {
    }
    if (!currentImages.count) {
        currentImages = SPKArrayFromCollection(SPKInstantsObjectIvarValue(stackView, @"currentImages"));
    }

    if (displayIndex < 0 || displayIndex >= (NSInteger)currentImages.count) {
        // Try visual fallback
        NSInteger visualIdx = SPKInstantsVisualActiveIndex(stackView, currentImages);
        if (visualIdx >= 0)
            displayIndex = visualIdx;
    }

    if (displayIndex < 0 || displayIndex >= (NSInteger)currentImages.count)
        return nil;
    id activeView = currentImages[(NSUInteger)displayIndex];

    // Extract the backing media PK from the active view
    if ([activeView isKindOfClass:UIView.class]) {
        id backingMedia = SPKInstantsBackingObjectFromView((UIView *)activeView, 0);
        if (backingMedia) {
            NSString *pk = SPKInstantsMediaPKForObject(backingMedia, 0);
            if (pk.length > 0)
                return pk;
        }
    }

    // Fallback: try the state's viewModel items array at the same index (may work early)
    id state = nil;
    @try {
        state = [stackView valueForKey:@"state"];
    } @catch (__unused NSException *e) {
    }
    if (state && [state isKindOfClass:NSObject.class]) {
        id viewModel = nil;
        @try {
            viewModel = [state valueForKey:@"viewModel"];
        } @catch (__unused NSException *e) {
        }
        if (!viewModel) {
            @try {
                viewModel = [state valueForKey:@"_viewModel"];
            } @catch (__unused NSException *e) {
            }
        }
        NSArray *modelItems = SPKArrayFromCollection(viewModel);
        if (!modelItems.count) {
            modelItems = SPKArrayFromCollection(SPKInstantsObjectValue(viewModel,
                                                                       @[ @"items", @"medias", @"media", @"snaps", @"quickSnaps", @"timeOrderedQuicksnaps", @"viewModels", @"children" ]));
        }
        if (displayIndex < (NSInteger)modelItems.count) {
            NSString *pk = SPKInstantsMediaPKForObject(modelItems[(NSUInteger)displayIndex], 0);
            if (pk.length > 0)
                return pk;
        }
    }

    return nil;
}

/// Finds the index of a snap with the given PK in the resolved snaps array.
/// Returns -1 if not found.
static NSInteger SPKInstantsFindSnapIndexByPK(NSArray<SPKInstantsResolvedSnap *> *snaps, NSString *pk) {
    if (!pk.length || !snaps.count)
        return -1;
    for (NSUInteger i = 0; i < snaps.count; i++) {
        if ([snaps[i].sourceMediaPK isEqualToString:pk])
            return (NSInteger)i;
    }
    return -1;
}

#pragma mark - Main Resolution Entry Point

/// Primary resolution entry point. Called at action execution time only.
/// Builds the full resolved snap list from the service cache, determines the active index,
/// and returns a complete SPKInstantsResolverResult.
/// When the service cache is empty (all snaps "seen"), falls back to the live stack view.
SPKInstantsResolverResult *SPKInstantsResolveForHeader(UIView *header, NSString *reason) {
    // Architecture:
    //   - The BULK list (Download All) comes from the full store snapshot — every snap
    //     available this session, not just the ~4 currently held in the view stack.
    //   - The ACTIVE snap (single-tap download) is resolved directly from the topmost
    //     visible SingleSnapView, which is always correct regardless of the store list.
    //   - We try to map the active snap into the bulk list by PK so the active index is
    //     accurate; if that fails we still return the active snap via `activeSnap`.
    UIView *stackView = SPKInstantsSnapStackViewForHeader(header);

    // --- A. Build the display list (bounded view window) for active-snap resolution ---
    id state = nil;
    if (stackView) {
        @try {
            state = [stackView valueForKey:@"state"];
        } @catch (__unused NSException *e) {
        }
        if (!state || ![state isKindOfClass:NSObject.class]) {
            @try {
                state = [stackView valueForKey:@"_state"];
            } @catch (__unused NSException *e) {
            }
        }
        if (state && ![state isKindOfClass:NSObject.class])
            state = nil;
    }

    NSArray *currentImages = nil;
    NSArray *modelItems = nil;

    if (stackView) {
        @try {
            currentImages = SPKArrayFromCollection([stackView valueForKey:@"currentImages"]);
        } @catch (__unused NSException *e) {
        }
        if (!currentImages.count) {
            currentImages = SPKArrayFromCollection(SPKInstantsObjectIvarValue(stackView, @"currentImages"));
        }
        if (!currentImages.count) {
            Class singleSnapClass = NSClassFromString(@"_TtC40IGQuickSnapImmersiveViewerSingleSnapView40IGQuickSnapImmersiveViewerSingleSnapView");
            if (!singleSnapClass)
                singleSnapClass = NSClassFromString(@"IGQuickSnapImmersiveViewerSingleSnapView");
            if (singleSnapClass) {
                NSMutableArray *snapViews = [NSMutableArray array];
                for (UIView *sub in stackView.subviews) {
                    if ([sub isKindOfClass:singleSnapClass])
                        [snapViews addObject:sub];
                }
                if (snapViews.count > 0) {
                    currentImages = [snapViews copy];
                    SPKLog(@"Instants", @"currentImages reconstructed from subviews: %lu", (unsigned long)currentImages.count);
                }
            }
        }
    }

    if (state) {
        id viewModel = nil;
        @try {
            viewModel = [state valueForKey:@"viewModel"];
        } @catch (__unused NSException *e) {
        }
        if (!viewModel) {
            @try {
                viewModel = [state valueForKey:@"_viewModel"];
            } @catch (__unused NSException *e) {
            }
        }
        modelItems = SPKArrayFromCollection(viewModel);
        if (!modelItems.count) {
            modelItems = SPKArrayFromCollection(SPKInstantsObjectValue(viewModel,
                                                                       @[ @"items", @"medias", @"media", @"snaps", @"quickSnaps", @"timeOrderedQuicksnaps", @"viewModels", @"children" ]));
        }
    }

    // Determine which display-list slot is active (topmost visible view).
    if (stackView && !sTrackedIndexValid)
        SPKInstantsInitTracking(stackView);
    NSInteger displayIndex = stackView ? SPKInstantsActiveIndex(stackView) : 0;

    // Resolve the ACTIVE snap directly from the active view (always correct).
    SPKInstantsResolvedSnap *activeSnap = nil;
    NSString *activePK = nil;
    if (displayIndex >= 0 && displayIndex < (NSInteger)currentImages.count) {
        id activeView = currentImages[(NSUInteger)displayIndex];
        if ([activeView isKindOfClass:UIView.class]) {
            activeSnap = SPKInstantsResolvedSnapFromView((UIView *)activeView);
            if (activeSnap)
                activeSnap.resolverPath = @"active.view";
            activePK = activeSnap.sourceMediaPK;
        }
        // Fall back to the model item at the same slot
        if (!activeSnap && displayIndex < (NSInteger)modelItems.count) {
            activeSnap = SPKInstantsResolvedSnapFromMedia(modelItems[(NSUInteger)displayIndex]);
            if (activeSnap) {
                activeSnap.resolverPath = @"active.model";
                activePK = activeSnap.sourceMediaPK;
            }
        }
    }
    // Fill active snap username from the visible author text view if missing.
    if (activeSnap && !activeSnap.sourceUsername.length) {
        NSString *visibleAuthor = SPKInstantsCurrentAuthorUsername(header);
        if (visibleAuthor.length > 0) {
            activeSnap.sourceUsername = visibleAuthor;
            activeSnap.authorResolverPath = @"authorTextView";
        }
    }

    // --- B. Build the BULK list from the FULL store snapshot (+ service cache) ---
    NSArray *storeMedia = SPKInstantsStoreSnapshot();
    NSArray *cacheMedia = SPKInstantsMergedMediaList();
    NSArray *fullMedia = storeMedia.count > 0
                             ? SPKInstantsUnionMediaLists(storeMedia, cacheMedia)
                             : cacheMedia;

    NSMutableArray<SPKInstantsResolvedSnap *> *snaps = [NSMutableArray arrayWithCapacity:fullMedia.count];
    for (id media in fullMedia) {
        SPKInstantsResolvedSnap *snap = SPKInstantsResolvedSnapFromMedia(media);
        if (snap) {
            snap.resolverPath = @"store";
            [snaps addObject:snap];
        }
    }

    // --- C. Map active snap into the bulk list and finalize ---
    if (snaps.count > 0) {
        NSInteger activeIndex = -1;

        // The active VIEW frequently exposes no PK on the first interaction (its backing
        // media isn't wired up yet, and the resolved URL is a temp/derived one that won't
        // match the store's CDN URL). The model object at the same display slot does carry
        // a PK, so use it to map the active snap into the store list reliably.
        NSString *activeModelPK = nil;
        if (displayIndex >= 0 && displayIndex < (NSInteger)modelItems.count) {
            activeModelPK = SPKInstantsMediaPKForObject(modelItems[(NSUInteger)displayIndex], 0);
        }

        // Try PK match first (most reliable) — view PK, then model PK.
        if (activePK.length > 0) {
            activeIndex = SPKInstantsFindSnapIndexByPK(snaps, activePK);
        }
        if (activeIndex < 0 && activeModelPK.length > 0) {
            activeIndex = SPKInstantsFindSnapIndexByPK(snaps, activeModelPK);
        }

        // PK match failed (the active view often exposes no PK). Match by media URL:
        // the active view's image/video URL should equal one of the store snaps' URLs.
        if (activeIndex < 0 && activeSnap) {
            NSString *activeURL = activeSnap.sparkleMediaURL.absoluteString;
            NSString *activePhoto = activeSnap.sparklePhotoURL.absoluteString;
            NSString *activeVideo = activeSnap.sparkleVideoURL.absoluteString;
            for (NSUInteger i = 0; i < snaps.count; i++) {
                SPKInstantsResolvedSnap *s = snaps[i];
                NSString *sURL = s.sparkleMediaURL.absoluteString;
                NSString *sPhoto = s.sparklePhotoURL.absoluteString;
                NSString *sVideo = s.sparkleVideoURL.absoluteString;
                if ((activeURL && ([activeURL isEqualToString:sURL] || [activeURL isEqualToString:sPhoto] || [activeURL isEqualToString:sVideo])) ||
                    (activePhoto && sPhoto && [activePhoto isEqualToString:sPhoto]) ||
                    (activeVideo && sVideo && [activeVideo isEqualToString:sVideo])) {
                    activeIndex = (NSInteger)i;
                    break;
                }
            }
        }

        // Still no match (active snap genuinely not in the store list, e.g. already pruned,
        // or unkeyable). Prepend it so single-tap and the open index stay correct. This is a
        // last resort: when the model-PK match above succeeds — the common first-interaction
        // case — we never reach here, so the topmost snap is no longer duplicated.
        if (activeIndex < 0 && activeSnap && activeSnap.sparkleMediaURL) {
            [snaps insertObject:activeSnap atIndex:0];
            activeIndex = 0;
        }

        if (activeIndex < 0)
            activeIndex = 0;
        if (activeIndex >= (NSInteger)snaps.count)
            activeIndex = (NSInteger)snaps.count - 1;

        // Ensure activeSnap is set (use the matched store entry if direct resolution failed)
        if (!activeSnap && activeIndex < (NSInteger)snaps.count) {
            activeSnap = snaps[(NSUInteger)activeIndex];
        }

        SPKInstantsResolverResult *result = [[SPKInstantsResolverResult alloc] init];
        result.snaps = [snaps copy];
        result.activeIndex = activeIndex;
        result.activeSnap = activeSnap;
        result.path = @"store+active";

        SPKLog(@"Instants", @"resolve reason=%@ path=store+active count=%lu activeIndex=%ld activePK=%@ displayIdx=%ld",
               reason ?: @"unknown", (unsigned long)snaps.count, (long)activeIndex,
               activePK ?: @"(nil)", (long)displayIndex);
        for (NSUInteger i = 0; i < snaps.count; i++) {
            SPKInstantsResolvedSnap *s = snaps[i];
            SPKLog(@"Instants", @"  [%lu]%@ %@ user=%@ pk=%@ url=%@",
                   (unsigned long)i, (NSInteger)i == activeIndex ? @"*" : @" ",
                   s.sparkleIsVideo ? @"video" : @"photo",
                   s.sourceUsername ?: @"(nil)", s.sourceMediaPK ?: @"(nil)",
                   s.sparkleMediaURL ? @"YES" : @"NO");
        }
        return result;
    }

    // --- D. Store empty — fall back to the display list alone ---
    NSUInteger displayCount = modelItems.count > 0 ? modelItems.count : currentImages.count;
    if (displayCount > 0) {
        NSMutableArray<SPKInstantsResolvedSnap *> *displaySnaps = [NSMutableArray arrayWithCapacity:displayCount];
        for (NSUInteger i = 0; i < displayCount; i++) {
            SPKInstantsResolvedSnap *resolved = nil;
            if (i < modelItems.count) {
                resolved = SPKInstantsResolvedSnapFromMedia(modelItems[i]);
                if (resolved)
                    resolved.resolverPath = @"display.model";
            }
            if (!resolved && i < currentImages.count) {
                id imageItem = currentImages[i];
                if ([imageItem isKindOfClass:UIView.class]) {
                    resolved = SPKInstantsResolvedSnapFromView((UIView *)imageItem);
                }
                if (!resolved) {
                    resolved = SPKInstantsResolvedSnapFromMedia(imageItem);
                    if (resolved)
                        resolved.resolverPath = @"display.image.model";
                }
            }
            if (resolved)
                [displaySnaps addObject:resolved];
        }
        if (displaySnaps.count > 0) {
            NSInteger activeIndex = displayIndex;
            if (activeIndex >= (NSInteger)displaySnaps.count)
                activeIndex = (NSInteger)displaySnaps.count - 1;
            if (activeIndex < 0)
                activeIndex = 0;
            SPKInstantsResolverResult *result = [[SPKInstantsResolverResult alloc] init];
            result.snaps = [displaySnaps copy];
            result.activeIndex = activeIndex;
            result.activeSnap = activeSnap ?: displaySnaps[(NSUInteger)activeIndex];
            result.path = @"display-only";
            SPKLog(@"Instants", @"resolve reason=%@ path=display-only count=%lu activeIndex=%ld",
                   reason ?: @"unknown", (unsigned long)displaySnaps.count, (long)activeIndex);
            return result;
        }
    }

    // --- E. All paths failed ---
    SPKLog(@"Instants", @"resolve reason=%@ path=NONE count=0", reason ?: @"unknown");
    return nil;
}

#pragma mark - Hook Installation

typedef void (*SPKInstantsServiceUpdateIMP)(id, SEL, id, id, BOOL);
static SPKInstantsServiceUpdateIMP orig_instantsServiceListenerUpdate = NULL;
static SPKInstantsServiceUpdateIMP orig_instantsBadgeManagerServiceUpdate = NULL;

typedef id (*SPKInstantsServiceSnapsIMP)(id, SEL);
static SPKInstantsServiceSnapsIMP orig_instantsServiceAvailableTimeOrderedSnaps = NULL;
static SPKInstantsServiceSnapsIMP orig_instantsServiceSidePeekPreviewMedias = NULL;

static void replaced_instantsServiceListenerUpdate(id self, SEL _cmd, id timeOrdered, id peekPreview, BOOL didReceive) {
    if (orig_instantsServiceListenerUpdate)
        orig_instantsServiceListenerUpdate(self, _cmd, timeOrdered, peekPreview, didReceive);
    SPKInstantsCacheServiceSnaps(timeOrdered, peekPreview, @"listener");
}

static void replaced_instantsBadgeManagerServiceUpdate(id self, SEL _cmd, id timeOrdered, id peekPreview, BOOL didReceive) {
    if (orig_instantsBadgeManagerServiceUpdate)
        orig_instantsBadgeManagerServiceUpdate(self, _cmd, timeOrdered, peekPreview, didReceive);
    SPKInstantsCacheServiceSnaps(timeOrdered, peekPreview, @"badgeManager");
}

static id replaced_instantsServiceAvailableTimeOrderedSnaps(id self, SEL _cmd) {
    sQuickSnapServiceInstance = self;
    id result = orig_instantsServiceAvailableTimeOrderedSnaps ? orig_instantsServiceAvailableTimeOrderedSnaps(self, _cmd) : nil;
    SPKInstantsCacheServiceSnaps(result, nil, @"service.timeOrdered");
    return result;
}

static id replaced_instantsServiceSidePeekPreviewMedias(id self, SEL _cmd) {
    sQuickSnapServiceInstance = self;
    id result = orig_instantsServiceSidePeekPreviewMedias ? orig_instantsServiceSidePeekPreviewMedias(self, _cmd) : nil;
    SPKInstantsCacheServiceSnaps(nil, result, @"service.peekPreview");
    return result;
}

static void SPKInstantsHookInstanceMethod(const char *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!cls || !method) {
        SPKLog(@"Instants", @"Missing hook target %s %@", className, NSStringFromSelector(selector));
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

// Consumption VC viewDidDisappear: hook — resets the snapshot when the viewer closes.
typedef void (*SPKInstantsVCDisappearIMP)(id, SEL, BOOL);
static SPKInstantsVCDisappearIMP orig_consumptionVCViewDidDisappear = NULL;

// handleTap hook on AnimatingSnapStackView — tracks the active index as user taps through.
typedef void (*SPKInstantsHandleTapIMP)(id, SEL);
static SPKInstantsHandleTapIMP orig_stackViewHandleTap = NULL;

static void replaced_stackViewHandleTap(id self, SEL _cmd) {
    // Initialize tracking from this stack view if not yet done
    if (!sTrackedIndexValid && [self isKindOfClass:UIView.class]) {
        SPKInstantsInitTracking((UIView *)self);
    }
    // Call original (this advances the snap in the viewer)
    if (orig_stackViewHandleTap)
        orig_stackViewHandleTap(self, _cmd);
    // After the tap, the index has advanced
    SPKInstantsAdvanceTrackedIndex();
}

static void replaced_consumptionVCViewDidDisappear(id self, SEL _cmd, BOOL animated) {
    if (orig_consumptionVCViewDidDisappear)
        orig_consumptionVCViewDidDisappear(self, _cmd, animated);
    SPKInstantsResetStoreSnapshot();
    SPKInstantsResetTracking();
    sCachedTimeOrderedSnaps = nil;
    sCachedPeekPreviewSnaps = nil;
    SPKLog(@"Instants", @"consumption VC disappeared — snapshot, tracking & cache reset");
}

void SPKInstallInstantsResolverHooks(void) {
    static BOOL sInstalled = NO;
    if (sInstalled)
        return;
    sInstalled = YES;

    Class listenerClass = objc_getClass("_TtC30IGQuickSnapServiceListenerImpl30IGQuickSnapServiceListenerImpl");
    Class badgeClass = objc_getClass("IGBadgeManager");
    Class serviceClass = objc_getClass("_TtC18IGQuickSnapService18IGQuickSnapService");

    if (!listenerClass && !badgeClass && !serviceClass) {
        SPKLog(@"Instants", @"Instants hooks skipped: no QuickSnap classes found (IG 410 compat)");
        return;
    }

    SPKLog(@"Instants", @"Installing Instants resolver hooks (listener=%@, badge=%@, service=%@)",
           listenerClass ? @"YES" : @"NO",
           badgeClass ? @"YES" : @"NO",
           serviceClass ? @"YES" : @"NO");

    SPKInstantsHookInstanceMethod("_TtC30IGQuickSnapServiceListenerImpl30IGQuickSnapServiceListenerImpl",
                                  @selector(quickSnapServiceDidUpdateSnapsWithTimeOrderedQuicksnaps:peekPreviewSnaps:didReceiveNewSnaps:),
                                  (IMP)replaced_instantsServiceListenerUpdate,
                                  (IMP *)&orig_instantsServiceListenerUpdate);
    SPKInstantsHookInstanceMethod("IGBadgeManager",
                                  @selector(quickSnapServiceDidUpdateSnapsWithTimeOrderedQuicksnaps:peekPreviewSnaps:didReceiveNewSnaps:),
                                  (IMP)replaced_instantsBadgeManagerServiceUpdate,
                                  (IMP *)&orig_instantsBadgeManagerServiceUpdate);
    SPKInstantsHookInstanceMethod("_TtC18IGQuickSnapService18IGQuickSnapService",
                                  @selector(availableTimeOrderedSnaps),
                                  (IMP)replaced_instantsServiceAvailableTimeOrderedSnaps,
                                  (IMP *)&orig_instantsServiceAvailableTimeOrderedSnaps);
    SPKInstantsHookInstanceMethod("_TtC18IGQuickSnapService18IGQuickSnapService",
                                  @selector(sidePeekPreviewMedias),
                                  (IMP)replaced_instantsServiceSidePeekPreviewMedias,
                                  (IMP *)&orig_instantsServiceSidePeekPreviewMedias);

    // Eagerly capture the service instance so the store read works even if IG never
    // calls availableTimeOrderedSnaps again during this consumption session.
    if (!sQuickSnapServiceInstance) {
        id service = SPKInstantsLocateQuickSnapService();
        if (service) {
            sQuickSnapServiceInstance = service;
            SPKLog(@"Instants", @"captured service at hook-install time via session lookup");
        }
    }

    // Hook the consumption VC's viewDidDisappear: to reset the store snapshot when
    // the user leaves the viewer, so a fresh snapshot is taken next time.
    SPKInstantsHookInstanceMethod("_TtC26IGQuickSnapConsumptionCore36IGQuickSnapConsumptionViewController",
                                  @selector(viewDidDisappear:),
                                  (IMP)replaced_consumptionVCViewDidDisappear,
                                  (IMP *)&orig_consumptionVCViewDidDisappear);

    // Hook handleTap on the AnimatingSnapStackView to track the active index.
    // This fires each time the user taps to advance to the next snap.
    Class stackViewClass = objc_getClass("_TtC39IGQuickSnapImmersiveViewerSnapStackView48IGQuickSnapImmersiveViewerAnimatingSnapStackView");
    if (stackViewClass) {
        // Check if handleTap exists on this class
        Method handleTapMethod = class_getInstanceMethod(stackViewClass, @selector(handleTap));
        if (handleTapMethod) {
            SPKInstantsHookInstanceMethod("_TtC39IGQuickSnapImmersiveViewerSnapStackView48IGQuickSnapImmersiveViewerAnimatingSnapStackView",
                                          @selector(handleTap),
                                          (IMP)replaced_stackViewHandleTap,
                                          (IMP *)&orig_stackViewHandleTap);
            SPKLog(@"Instants", @"handleTap hook installed on AnimatingSnapStackView");
        } else {
            SPKLog(@"Instants", @"WARNING: handleTap method NOT found on AnimatingSnapStackView — trying didPress");
            // Fallback: try hooking didPressWithGestureRecognizer: instead (declared in header)
            Method didPressMethod = class_getInstanceMethod(stackViewClass, @selector(didPressWithGestureRecognizer:));
            if (didPressMethod) {
                SPKLog(@"Instants", @"Found didPressWithGestureRecognizer: — not hooking (would need different signature)");
            }
        }
    } else {
        SPKLog(@"Instants", @"WARNING: AnimatingSnapStackView class not found for handleTap hook");
    }

    SPKLog(@"Instants", @"Instants resolver hooks installed");
}

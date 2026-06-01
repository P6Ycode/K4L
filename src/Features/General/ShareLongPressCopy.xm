#import <objc/runtime.h>

#import "../../Shared/ActionButton/ActionButtonLookupUtils.h"
#import "../../Shared/Stories/SCIStoryContext.h"
#import "../../Utils.h"

static const void *kSCIShareCopyLongPressAssocKey = &kSCIShareCopyLongPressAssocKey;
static NSHashTable<UIGestureRecognizer *> *SCIShareCopyLongPressRecognizers(void) {
    static NSHashTable<UIGestureRecognizer *> *recognizers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        recognizers = [NSHashTable weakObjectsHashTable];
    });
    return recognizers;
}

static inline BOOL SCIShareLongPressCopyEnabled(void) {
    return [SCIUtils getBoolPref:@"general_hold_send_copy_link"];
}

static NSString *SCIShareDebugViewName(UIView *view) {
    return view ? [NSString stringWithFormat:@"%@<%p>", NSStringFromClass(view.class), view] : @"nil";
}

static NSString *SCIShareStringValue(id value) {
    NSString *string = SCIStringFromValue(value);
    return string.length > 0 ? string : nil;
}

static NSString *SCIShareStringForSelectorOrIvar(id object, NSString *name) {
    NSString *value = SCIShareStringValue(SCIObjectForSelector(object, name));
    if (value.length > 0) return value;

    value = SCIShareStringValue(SCIKVCObject(object, name));
    if (value.length > 0) return value;

    NSString *ivarName = [NSString stringWithFormat:@"_%@", name];
    return SCIShareStringValue([SCIUtils getIvarForObj:object name:ivarName.UTF8String]);
}

static NSString *SCIShareURLPathForObject(id object) {
    NSString *className = NSStringFromClass([object class]).lowercaseString ?: @"";
    if ([className containsString:@"reel"] || [className containsString:@"clips"] || [className containsString:@"sundial"]) {
        return @"reel";
    }

    for (NSString *selectorName in @[@"productType", @"mediaType", @"mediaSource", @"inventorySource"]) {
        NSString *value = SCIShareStringForSelectorOrIvar(object, selectorName).lowercaseString;
        if ([value containsString:@"reel"] || [value containsString:@"clips"]) {
            return @"reel";
        }
    }
    return @"p";
}

static NSURL *SCIInstagramPostURLForCode(NSString *code, id object) {
    if (code.length == 0) return nil;
    NSString *path = SCIShareURLPathForObject(object);
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/%@/", path, code]];
}

static BOOL SCIShareObjectCanExposeMediaPK(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0) return NO;
    NSString *className = NSStringFromClass([object class]).lowercaseString ?: @"";
    if ([className containsString:@"user"] || [className containsString:@"session"] || [className containsString:@"account"]) return NO;
    if ([selectorName isEqualToString:@"currentMediaPK"]) return YES;
    if ([className containsString:@"media"] || [className containsString:@"feed"] || [className containsString:@"ufi"] ||
        [className containsString:@"reel"] || [className containsString:@"sundial"] || [className containsString:@"clips"] ||
        [className containsString:@"post"]) {
        return YES;
    }
    return NO;
}

static NSString *SCIInstagramShortcodeForMediaPK(NSString *mediaPK) {
    return [SCIUtils instagramShortcodeForMediaPK:mediaPK];
}

static NSURL *SCIInstagramPostURLForMediaPK(NSString *mediaPK, id object, NSString *selectorName) {
    if (!SCIShareObjectCanExposeMediaPK(object, selectorName)) return nil;
    NSString *code = SCIInstagramShortcodeForMediaPK(mediaPK);
    NSURL *url = SCIInstagramPostURLForCode(code, object);
    if (url) {
        SCILog(@"General", @"[SCInsta ShareCopy] Using media PK fallback class=%@ selector=%@ mediaPK=%@ code=%@ url=%@",
               NSStringFromClass([object class]), selectorName, mediaPK, code, url.absoluteString);
    }
    return url;
}

static NSString *SCIShareMediaIDFromObject(id object) {
    for (NSString *selectorName in @[@"pk", @"id", @"mediaID", @"mediaId", @"mediaIdentifier"]) {
        NSString *identifier = SCIShareStringForSelectorOrIvar(object, selectorName);
        if (identifier.length > 0) {
            NSArray<NSString *> *parts = [identifier componentsSeparatedByString:@"_"];
            NSString *mediaID = parts.firstObject ?: identifier;
            return mediaID.length > 0 ? mediaID : identifier;
        }
    }
    return nil;
}

static NSURL *SCIInstagramStoryURLForMedia(id media) {
    NSString *username = SCIUsernameFromMediaObject(media);
    NSString *identifier = SCIShareMediaIDFromObject(media);
    if (username.length == 0 || identifier.length == 0) return nil;

    NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSString *encodedIdentifier = [identifier stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    if (encodedUsername.length == 0 || encodedIdentifier.length == 0) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/stories/%@/%@/", encodedUsername, encodedIdentifier]];
}

static BOOL SCIShareURLIsStoryURL(NSURL *url) {
    NSString *path = url.path.lowercaseString ?: @"";
    return [path containsString:@"/stories/"];
}

static BOOL SCIShareURLIsPostOrReelURL(NSURL *url) {
    NSString *path = url.path.lowercaseString ?: @"";
    return [path containsString:@"/p/"] || [path containsString:@"/reel/"] || [path containsString:@"/reels/"];
}

static BOOL SCIShareObjectLooksStoryLike(id object) {
    if (!object) return NO;
    NSString *className = NSStringFromClass([object class]).lowercaseString ?: @"";
    if ([className containsString:@"story"]) return YES;

    for (NSString *selectorName in @[@"productType", @"mediaType", @"mediaSource", @"inventorySource", @"mediaSubtype"]) {
        NSString *lower = SCIShareStringForSelectorOrIvar(object, selectorName).lowercaseString;
        if ([lower containsString:@"story"]) return YES;
    }
    return NO;
}

static BOOL SCIShareViewGraphLooksStoryLike(UIView *view) {
    for (UIView *walker = view; walker; walker = walker.superview) {
        if (SCIShareObjectLooksStoryLike(walker)) return YES;

        id delegate = SCIObjectForSelector(walker, @"delegate");
        if (SCIShareObjectLooksStoryLike(delegate)) return YES;

        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(walker.class, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            id value = nil;
            @try { value = object_getIvar(walker, ivars[i]); } @catch (__unused NSException *exception) {}
            if (SCIShareObjectLooksStoryLike(value)) {
                if (ivars) free(ivars);
                return YES;
            }
        }
        if (ivars) free(ivars);
    }

    UIViewController *controller = [SCIUtils nearestViewControllerForView:view];
    return SCIShareObjectLooksStoryLike(controller);
}

static NSURL *SCIShareCanonicalPostOrReelURLFromObjectAtDepth(id object, NSInteger depth) {
    if (!object || depth > 3) return nil;

    for (NSString *selectorName in @[@"permalink", @"permaLink", @"shareURL", @"shareUrl", @"canonicalURL", @"canonicalUrl", @"permalinkURL", @"instagramURL", @"instagramUrl", @"webURL", @"webUrl", @"url"]) {
        NSURL *url = SCIURLFromValue(SCIObjectForSelector(object, selectorName));
        if (!url) url = SCIURLFromValue(SCIKVCObject(object, selectorName));
        if (SCIShareURLIsPostOrReelURL(url)) return url;
    }

    for (NSString *selectorName in @[@"code", @"shortCode", @"shortcode", @"mediaCode", @"mediaShortcode", @"shortCodeToken"]) {
        if (SCIShareObjectLooksStoryLike(object)) break;
        NSString *code = SCIShareStringForSelectorOrIvar(object, selectorName);
        NSURL *url = SCIInstagramPostURLForCode(code, object);
        if (url) return url;
    }

    for (NSString *selectorName in @[@"currentMediaPK", @"mediaPK", @"mediaPk", @"mediaID", @"mediaId", @"mediaIdentifier", @"pk"]) {
        if (SCIShareObjectLooksStoryLike(object)) break;
        NSString *mediaPK = SCIShareStringForSelectorOrIvar(object, selectorName);
        NSURL *url = SCIInstagramPostURLForMediaPK(mediaPK, object, selectorName);
        if (url) return url;
    }

    for (NSString *selectorName in @[@"media", @"post", @"story", @"storyItem", @"storyMedia", @"mediaItem", @"reelMediaItem", @"item", @"currentStoryItem", @"visualMessage", @"model"]) {
        id nested = SCIObjectForSelector(object, selectorName);
        if (!nested) nested = SCIKVCObject(object, selectorName);
        NSURL *url = SCIShareCanonicalPostOrReelURLFromObjectAtDepth(nested, depth + 1);
        if (url) return url;
    }

    return nil;
}

static NSURL *SCIShareURLFromObjectAtDepth(id object, NSInteger depth) {
    if (!object || depth > 3) return nil;

    for (NSString *selectorName in @[@"permalink", @"permaLink", @"shareURL", @"shareUrl", @"canonicalURL", @"canonicalUrl", @"permalinkURL", @"instagramURL", @"instagramUrl", @"webURL", @"webUrl", @"url"]) {
        NSURL *url = SCIURLFromValue(SCIObjectForSelector(object, selectorName));
        if (url) return url;
        url = SCIURLFromValue(SCIKVCObject(object, selectorName));
        if (url) return url;
    }

    for (NSString *selectorName in @[@"code", @"shortCode", @"shortcode", @"mediaCode", @"mediaShortcode", @"shortCodeToken"]) {
        if (SCIShareObjectLooksStoryLike(object)) break;
        NSString *code = SCIShareStringForSelectorOrIvar(object, selectorName);
        NSURL *url = SCIInstagramPostURLForCode(code, object);
        if (url) return url;
    }

    for (NSString *selectorName in @[@"currentMediaPK", @"mediaPK", @"mediaPk", @"mediaID", @"mediaId", @"mediaIdentifier", @"pk"]) {
        if (SCIShareObjectLooksStoryLike(object)) break;
        NSString *mediaPK = SCIShareStringForSelectorOrIvar(object, selectorName);
        NSURL *url = SCIInstagramPostURLForMediaPK(mediaPK, object, selectorName);
        if (url) return url;
    }

    for (NSString *selectorName in @[@"media", @"post", @"story", @"storyItem", @"storyMedia", @"mediaItem", @"reelMediaItem", @"item", @"currentStoryItem", @"visualMessage", @"model"]) {
        id nested = SCIObjectForSelector(object, selectorName);
        if (!nested) nested = SCIKVCObject(object, selectorName);
        NSURL *url = SCIShareURLFromObjectAtDepth(nested, depth + 1);
        if (url) return url;
    }

    return nil;
}

static id SCIShareStorySectionControllerFromOverlay(UIView *overlayView) {
    NSArray<NSString *> *delegateSelectors = @[@"mediaOverlayDelegate", @"retryDelegate", @"tappableOverlayDelegate", @"buttonDelegate"];
    Class sectionControllerClass = NSClassFromString(@"IGStoryFullscreenSectionController");
    for (NSString *selectorName in delegateSelectors) {
        id delegate = SCIObjectForSelector(overlayView, selectorName);
        if (!delegate) delegate = SCIKVCObject(overlayView, selectorName);
        if (!delegate) continue;
        if (!sectionControllerClass || [delegate isKindOfClass:sectionControllerClass]) return delegate;
    }
    return nil;
}

static id SCIShareStoryMediaFromAnyObject(id object) {
    if (!object) return nil;
    for (NSString *selectorName in @[@"media", @"mediaItem", @"storyItem", @"item", @"model"]) {
        id candidate = SCIObjectForSelector(object, selectorName);
        if (!candidate) candidate = SCIKVCObject(object, selectorName);
        if (candidate && candidate != object) return candidate;
    }
    return object;
}

static id SCIShareStoryMediaFromOverlay(UIView *overlayView) {
    if (!overlayView) return nil;

    id sectionController = SCIShareStorySectionControllerFromOverlay(overlayView);
    UIViewController *viewerController = [SCIUtils nearestViewControllerForView:overlayView];
    if (!sectionController) {
        sectionController = SCIObjectForSelector(viewerController, @"currentSectionController");
        if (!sectionController) sectionController = SCIKVCObject(viewerController, @"currentSectionController");
        if (!sectionController) sectionController = [SCIUtils getIvarForObj:viewerController name:"_currentSectionController"];
    }

    for (id object in @[sectionController ?: (id)NSNull.null, viewerController ?: (id)NSNull.null]) {
        if (object == (id)NSNull.null) continue;
        for (NSString *selectorName in @[@"currentStoryItem", @"currentItem", @"item"]) {
            id media = SCIObjectForSelector(object, selectorName);
            if (!media) media = SCIKVCObject(object, selectorName);
            media = SCIShareStoryMediaFromAnyObject(media);
            if (media) return media;
        }
    }
    return nil;
}

static NSURL *SCIShareStoryURLFromOverlay(UIView *overlayView) {
    SCIStoryContext *context = SCIStoryContextFromOverlay(overlayView);
    id media = SCIShareStoryMediaFromOverlay(overlayView);
    NSURL *canonicalURL = SCIShareCanonicalPostOrReelURLFromObjectAtDepth(context.media ?: media, 0);
    if (canonicalURL) return canonicalURL;
    NSURL *sharedURL = SCIStoryURLForContext(context);
    if (sharedURL) return sharedURL;
    NSURL *url = SCIInstagramStoryURLForMedia(media);
    if (url) return url;
    return SCIShareURLFromObjectAtDepth(media, 0);
}

static UIView *SCIShareStoryOverlayAncestorForView(UIView *view) {
    for (UIView *walker = view; walker; walker = walker.superview) {
        if ([NSStringFromClass(walker.class) containsString:@"IGStoryFullscreenOverlayView"]) return walker;
    }
    return nil;
}

static UIView *SCIShareStoryOverlayForView(UIView *view) {
    UIView *overlay = SCIShareStoryOverlayAncestorForView(view);
    if (overlay) return overlay;

    UIView *activeOverlay = SCIStoryActiveOverlay();
    if (!activeOverlay || !activeOverlay.window || activeOverlay.window != view.window) return nil;
    if (!SCIShareViewGraphLooksStoryLike(view)) return nil;

    SCILog(@"General", @"[SCInsta ShareCopy] Using active story overlay for detached story control view=%@ overlay=%@", SCIShareDebugViewName(view), SCIShareDebugViewName(activeOverlay));
    return activeOverlay;
}

static NSURL *SCIShareURLFromViewHierarchy(UIView *view, BOOL canonicalOnly) {
    UIView *walker = view;
    for (NSInteger depth = 0; walker && depth < 24; depth++, walker = walker.superview) {
        NSURL *url = canonicalOnly ? SCIShareCanonicalPostOrReelURLFromObjectAtDepth(walker, 0) : SCIShareURLFromObjectAtDepth(walker, 0);
        if (url) return url;

        id delegate = SCIObjectForSelector(walker, @"delegate");
        url = canonicalOnly ? SCIShareCanonicalPostOrReelURLFromObjectAtDepth(delegate, 0) : SCIShareURLFromObjectAtDepth(delegate, 0);
        if (url) return url;

        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(walker.class, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            id value = nil;
            @try { value = object_getIvar(walker, ivars[i]); } @catch (__unused NSException *exception) {}
            url = canonicalOnly ? SCIShareCanonicalPostOrReelURLFromObjectAtDepth(value, 0) : SCIShareURLFromObjectAtDepth(value, 0);
            if (url) {
                if (ivars) free(ivars);
                return url;
            }
        }
        if (ivars) free(ivars);
    }

    UIViewController *controller = [SCIUtils nearestViewControllerForView:view];
    return canonicalOnly ? SCIShareCanonicalPostOrReelURLFromObjectAtDepth(controller, 0) : SCIShareURLFromObjectAtDepth(controller, 0);
}

static NSURL *SCIShareURLFromView(UIView *view) {
    UIView *storyOverlay = SCIShareStoryOverlayForView(view);
    SCILog(@"General", @"[SCInsta ShareCopy] Resolving link for view=%@ storyOverlay=%@", SCIShareDebugViewName(view), SCIShareDebugViewName(storyOverlay));

    if (storyOverlay) {
        NSURL *storyURL = SCIShareStoryURLFromOverlay(storyOverlay);
        if (storyURL) {
            SCILog(@"General", @"[SCInsta ShareCopy] Using story-overlay URL: %@", storyURL.absoluteString);
            return storyURL;
        }
        SCILog(@"General", @"[SCInsta ShareCopy] Story overlay present but no story URL resolved");
    }

    NSURL *canonicalURL = SCIShareURLFromViewHierarchy(view, YES);
    if (canonicalURL) {
        SCILog(@"General", @"[SCInsta ShareCopy] Using canonical post/reel URL: %@", canonicalURL.absoluteString);
        return canonicalURL;
    }

    NSURL *url = SCIShareURLFromViewHierarchy(view, NO);
    if (url && storyOverlay == nil && SCIShareURLIsStoryURL(url)) {
        SCILog(@"General", @"[SCInsta ShareCopy] Rejected story URL outside story overlay: %@", url.absoluteString);
        return nil;
    }
    if (url) {
        SCILog(@"General", @"[SCInsta ShareCopy] Using generic hierarchy URL: %@", url.absoluteString);
    } else {
        SCILog(@"General", @"[SCInsta ShareCopy] No URL resolved for view=%@", SCIShareDebugViewName(view));
    }
    return url;
}

static NSString *SCICopiedShareLinkTitleForURL(NSURL *url) {
    NSString *path = url.path.lowercaseString ?: @"";
    if ([path containsString:@"/stories/"]) return @"Copied story link";
    if ([path containsString:@"/reel/"] || [path containsString:@"/reels/"]) return @"Copied reel link";
    if ([path containsString:@"/p/"]) return @"Copied post link";
    return @"Copied link";
}

static void SCICopyShareURLForView(UIView *view) {
    if (!SCIShareLongPressCopyEnabled()) return;
    NSURL *url = SCIShareURLFromView(view);
    if ([SCIUtils getBoolPref:@"general_strip_share_link_tracking"]) {
        NSURL *sanitized = [SCIUtils sanitizedInstagramShareURL:url];
        if (sanitized && ![sanitized.absoluteString isEqualToString:url.absoluteString]) {
            SCILog(@"General", @"[SCInsta ShareCopy] Sanitized URL from %@ to %@", url.absoluteString, sanitized.absoluteString);
        }
        url = sanitized ?: url;
    }
    if (url.absoluteString.length == 0) {
        SCILog(@"General", @"[SCInsta ShareCopy] Copy failed: no link found for view=%@", SCIShareDebugViewName(view));
        SCINotify(kSCINotificationShareLongPressCopyLink, @"No link found", nil, @"error_filled", SCINotificationToneError);
        return;
    }
    UIPasteboard.generalPasteboard.string = url.absoluteString;
    SCILog(@"General", @"[SCInsta ShareCopy] Copied URL title=\"%@\" url=%@", SCICopiedShareLinkTitleForURL(url), url.absoluteString);
    SCINotify(kSCINotificationShareLongPressCopyLink, SCICopiedShareLinkTitleForURL(url), nil, @"copy_filled", SCINotificationToneSuccess);
}

static void SCIUpdateShareLongPressRecognizerStates(void) {
    BOOL enabled = SCIShareLongPressCopyEnabled();
    for (UIGestureRecognizer *gesture in SCIShareCopyLongPressRecognizers()) {
        gesture.enabled = enabled;
    }
}

static BOOL SCIShareViewLooksLikeSendControl(UIView *view) {
    NSString *label = (view.accessibilityLabel ?: view.accessibilityIdentifier ?: @"").lowercaseString;
    if ([label containsString:@"send"] || [label containsString:@"share"] || [label containsString:@"paper"] || [label containsString:@"airplane"] || [label containsString:@"direct"]) {
        return YES;
    }
    return NO;
}

static NSArray<UIView *> *SCIShareCandidateSubviews(UIView *root, NSInteger maxDepth) {
    if (!root || maxDepth < 0) return @[];
    NSMutableArray<UIView *> *matches = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *queue = [NSMutableArray arrayWithObject:@{@"view": root, @"depth": @0}];
    while (queue.count > 0) {
        NSDictionary *entry = queue.firstObject;
        [queue removeObjectAtIndex:0];
        UIView *view = entry[@"view"];
        NSInteger depth = [entry[@"depth"] integerValue];
        if (view != root && SCIShareViewLooksLikeSendControl(view)) {
            [matches addObject:view];
        }
        if (depth >= maxDepth) continue;
        for (UIView *subview in view.subviews) {
            [queue addObject:@{@"view": subview, @"depth": @(depth + 1)}];
        }
    }
    return matches;
}

static UIView *SCIShareViewForSelectorOrIvar(id container, NSString *name) {
    id candidate = SCIObjectForSelector(container, name);
    if (![candidate isKindOfClass:[UIView class]]) {
        NSString *ivarName = [NSString stringWithFormat:@"_%@", name];
        candidate = [SCIUtils getIvarForObj:container name:ivarName.UTF8String];
    }
    return [candidate isKindOfClass:[UIView class]] ? (UIView *)candidate : nil;
}

static void SCIInstallShareLongPressOnView(UIView *view) {
    if (!view) return;
    UIGestureRecognizer *existingRecognizer = objc_getAssociatedObject(view, kSCIShareCopyLongPressAssocKey);
    if (existingRecognizer) {
        existingRecognizer.enabled = SCIShareLongPressCopyEnabled();
        [SCIShareCopyLongPressRecognizers() addObject:existingRecognizer];
        return;
    }
    view.userInteractionEnabled = YES;
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:view action:@selector(sci_copyShareLinkLongPressed:)];
    gesture.minimumPressDuration = 0.22;
    gesture.cancelsTouchesInView = YES;
    gesture.delaysTouchesBegan = YES;
    gesture.delaysTouchesEnded = YES;
    gesture.enabled = SCIShareLongPressCopyEnabled();
    for (UIGestureRecognizer *existing in view.gestureRecognizers.copy) {
        if ([existing isKindOfClass:UILongPressGestureRecognizer.class] && existing != gesture) {
            [existing requireGestureRecognizerToFail:gesture];
        }
    }
    [view addGestureRecognizer:gesture];
    objc_setAssociatedObject(view, kSCIShareCopyLongPressAssocKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [SCIShareCopyLongPressRecognizers() addObject:gesture];
}

static void SCIInstallShareLongPressOnNativeRecognizerHosts(UIView *view, UIView *container) {
    for (UIView *walker = view.superview; walker && walker != container.superview; walker = walker.superview) {
        BOOL hasNativeLongPress = NO;
        for (UIGestureRecognizer *gesture in walker.gestureRecognizers) {
            if ([gesture isKindOfClass:UILongPressGestureRecognizer.class] &&
                !objc_getAssociatedObject(gesture, kSCIShareCopyLongPressAssocKey)) {
                hasNativeLongPress = YES;
                break;
            }
        }
        if (hasNativeLongPress) {
            SCIInstallShareLongPressOnView(walker);
        }
        if (walker == container) break;
    }
}

static void SCIInstallShareLongPressInContainer(UIView *container, NSArray<NSString *> *preferredNames, BOOL includeNativeHosts) {
    if (!container) return;
    for (NSString *name in preferredNames) {
        UIView *view = SCIShareViewForSelectorOrIvar(container, name);
        if (view) {
            SCIInstallShareLongPressOnView(view);
            if (includeNativeHosts) SCIInstallShareLongPressOnNativeRecognizerHosts(view, container);
        }
    }
    for (UIView *candidate in SCIShareCandidateSubviews(container, 4)) {
        SCIInstallShareLongPressOnView(candidate);
        if (includeNativeHosts) SCIInstallShareLongPressOnNativeRecognizerHosts(candidate, container);
    }
}

%group SCIShareLongPressCopyHooks

%hook UIView
%new - (void)sci_copyShareLinkLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    SCICopyShareURLForView((UIView *)self);
}
%end

%hook IGUFIButtonBarView
- (void)layoutSubviews {
    %orig;
    SCIInstallShareLongPressInContainer((UIView *)self, @[@"sendButton", @"shareButton", @"reshareButton"], YES);
}
%end

%hook IGUFIInteractionCountsView
- (void)layoutSubviews {
    %orig;
    SCIInstallShareLongPressInContainer((UIView *)self, @[@"sendButton", @"shareButton", @"reshareButton"], YES);
}
%end

%hook IGSundialViewerVerticalUFI
- (void)layoutSubviews {
    %orig;
    SCIInstallShareLongPressInContainer((UIView *)self, @[@"sendButton", @"shareButton", @"reshareButton"], YES);
}
%end

%hook IGStoryFullscreenOverlayView
- (void)layoutSubviews {
    %orig;
    SCIStorySetActiveOverlay((UIView *)self);
    SCIInstallShareLongPressInContainer((UIView *)self, @[@"sendButton", @"shareButton", @"reshareButton"], NO);
}
%end

%hook IGDirectVisualMessageViewerController
- (void)viewDidLayoutSubviews {
    %orig;
    SCIInstallShareLongPressInContainer(((UIViewController *)self).view, @[@"sendButton", @"shareButton"], NO);
}
%end

%end

extern "C" void SCIInstallShareLongPressCopyHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIShareLongPressCopyHooks);
        [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification *notification) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SCIUpdateShareLongPressRecognizerStates();
            });
        }];
    });
}

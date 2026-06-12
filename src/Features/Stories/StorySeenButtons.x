#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../InstagramHeaders.h"
#import "../../AssetUtils.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "../../Shared/Messages/SCIDirectSeenContext.h"
#import "../../Shared/Stories/SCIStoryButtonPlacement.h"
#import "../../Shared/Stories/SCIStoryContext.h"
#import "../../Shared/UI/SCIChrome.h"
#ifdef __cplusplus
extern "C" {
#endif
void SCIApplyButtonStyle(UIButton *button, NSInteger source);
#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
extern "C" {
#endif
void SCIUpdateStoryMentionsButton(UIView *overlayView, CGFloat x, CGFloat y, CGFloat size);
void SCIRemoveStoryMentionsButton(UIView *overlayView);
#ifdef __cplusplus
}
#endif

static NSString * const kSCISeenMessagesBarIconResource = @"eye";
static NSInteger const kSCIActionButtonSourceDirect = 4;
static NSInteger const kSCIStorySeenButtonTag = 926001;
static NSInteger const kSCIStoryMentionsButtonTag = 926002;
static NSInteger const kSCIStoriesActionButtonTag = 921343;
static const void *kSCIStoryOverlayObservedFooterAssocKey = &kSCIStoryOverlayObservedFooterAssocKey;
static const void *kSCIStoryOverlayHasObserverAssocKey = &kSCIStoryOverlayHasObserverAssocKey;
static void *kSCIStoryOverlayAlphaObserverContext = &kSCIStoryOverlayAlphaObserverContext;
static __weak UIView *SCIActiveStoryOverlayView = nil;

static id SCIKVCObject(id target, NSString *key);
static id SCIObjectForSelector(id target, NSString *selectorName);
static id SCIFirstObjectForSelectors(id target, NSArray<NSString *> *selectors);
void SCIMarkStoryAsSeenForViewWithAdvancePref(UIView *view, NSString *advancePrefKey);

static inline BOOL SCIManualStorySeenEnabled(void) {
    return [SCIUtils getBoolPref:@"stories_manual_seen"];
}
static inline BOOL SCIStorySeenHooksNeeded(void) {
    return [SCIUtils getBoolPref:@"stories_manual_seen"] ||
           SCIStoryManualSeenUserList(NO).count > 0 ||
           [SCIUtils getBoolPref:@"stories_mentions_btn"] ||
           [SCIUtils getBoolPref:@"stories_mark_seen_on_reply"] ||
           [SCIUtils getBoolPref:@"stories_advance_on_reply_seen"];
}
static id SCIKVCObject(id target, NSString *key) {
    if (!target || key.length == 0) return nil;

    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SCIObjectForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;

    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static id SCIFirstObjectForSelectors(id target, NSArray<NSString *> *selectors) {
    if (!target || selectors.count == 0) return nil;
    for (NSString *selectorName in selectors) {
        id value = SCIObjectForSelector(target, selectorName);
        if (value) return value;
    }
    return nil;
}

static void SCIPlayButtonTappedHaptic(void) {
    UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
    [feedback selectionChanged];
}
static BOOL SCIOverlayIsDirectVisualOverlay(UIView *overlayView) {
    UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:overlayView];
    Class directViewerClass = NSClassFromString(@"IGDirectVisualMessageViewerController");
    return (directViewerClass && [nearestVC isKindOfClass:directViewerClass]);
}
static UIButton *SCIStorySeenButtonWithTag(UIView *container, NSInteger tag) {
    UIView *existing = [container viewWithTag:tag];
    if ([existing isKindOfClass:SCIChromeButton.class]) {
        return (UIButton *)existing;
    }
    [existing removeFromSuperview];

    SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:@"" pointSize:24.0 diameter:44.0];
    button.tag = tag;
    button.adjustsImageWhenHighlighted = YES;
    button.showsMenuAsPrimaryAction = NO;
    button.clipsToBounds = NO;
    [container addSubview:button];
    return button;
}

static void SCISetSeenButtonImage(UIButton *button, UIImage *image, NSString *logMessage) {
    UIImage *templatedImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if ([button isKindOfClass:SCIChromeButton.class]) {
        SCIChromeButton *chromeButton = (SCIChromeButton *)button;
        chromeButton.iconView.image = templatedImage;
        chromeButton.iconTint = UIColor.whiteColor;
        [button setImage:nil forState:UIControlStateNormal];
    } else {
        [button setImage:templatedImage forState:UIControlStateNormal];
    }

    SCILog(@"Capture", @"%@ tag=%ld button=%@<%p> subviews=%@ imageView=%@<%p> imageSuperview=%@<%p>",
           logMessage,
           (long)button.tag,
           NSStringFromClass(button.class),
           button,
           button.subviews,
           NSStringFromClass(button.imageView.class),
           button.imageView,
           NSStringFromClass(button.imageView.superview.class),
           button.imageView.superview);
}

static void SCIApplyStorySeenButtonStyle(UIButton *button) {
    if (!button) return;
    SCIApplyButtonStyle(button, kSCIActionButtonSourceDirect);
}

static UIView *SCIStoryFooterContainerFromOverlay(UIView *overlayView) {
    if (!overlayView) return nil;

    UIView *footerContainer = [SCIUtils getIvarForObj:overlayView name:"_footerContainerView"];
    if (![footerContainer isKindOfClass:[UIView class]]) {
        id selectorFooter = SCIObjectForSelector(overlayView, @"footerContainerView");
        footerContainer = [selectorFooter isKindOfClass:[UIView class]] ? (UIView *)selectorFooter : nil;
    }
    return footerContainer;
}

static void SCIUpdateStoryButtonsAlpha(UIView *overlayView, CGFloat alpha) {
    if (!overlayView) return;

    UIButton *actionButton = (UIButton *)[overlayView viewWithTag:kSCIStoriesActionButtonTag];
    if ([actionButton isKindOfClass:[UIButton class]]) {
        actionButton.alpha = alpha;
    }

    UIButton *seenButton = (UIButton *)[overlayView viewWithTag:kSCIStorySeenButtonTag];
    if ([seenButton isKindOfClass:[UIButton class]]) {
        seenButton.alpha = alpha;
    }

    UIButton *mentionsButton = (UIButton *)[overlayView viewWithTag:kSCIStoryMentionsButtonTag];
    if ([mentionsButton isKindOfClass:[UIButton class]]) {
        mentionsButton.alpha = alpha;
    }
}

static void SCIRemoveStoryOverlayAlphaObserverIfNeeded(UIView *overlayView) {
    UIView *observedFooter = objc_getAssociatedObject(overlayView, kSCIStoryOverlayObservedFooterAssocKey);
    BOOL hasObserver = [objc_getAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey) boolValue];
    if (observedFooter && hasObserver) {
        [observedFooter removeObserver:overlayView forKeyPath:@"alpha" context:kSCIStoryOverlayAlphaObserverContext];
    }

    objc_setAssociatedObject(overlayView, kSCIStoryOverlayObservedFooterAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void SCIEnsureStoryOverlayAlphaObserver(UIView *overlayView) {
    if (!overlayView) return;

    UIView *footerContainer = SCIStoryFooterContainerFromOverlay(overlayView);
    UIView *observedFooter = objc_getAssociatedObject(overlayView, kSCIStoryOverlayObservedFooterAssocKey);
    BOOL hasObserver = [objc_getAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey) boolValue];
    if (observedFooter && observedFooter != footerContainer && hasObserver) {
        [observedFooter removeObserver:overlayView forKeyPath:@"alpha" context:kSCIStoryOverlayAlphaObserverContext];
        objc_setAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hasObserver = NO;
    }

    if (observedFooter != footerContainer) {
        objc_setAssociatedObject(overlayView, kSCIStoryOverlayObservedFooterAssocKey, footerContainer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (footerContainer && !hasObserver) {
        [footerContainer addObserver:overlayView
                          forKeyPath:@"alpha"
                             options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                             context:kSCIStoryOverlayAlphaObserverContext];
        objc_setAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static CGRect SCIStorySeenBaseFrame(UIView *overlayView) {
    return SCIStoryFloatingButtonFrame(overlayView, 38.0);
}

static id SCIStorySectionControllerFromOverlayView(UIView *overlayView) {
    if (!overlayView) return nil;

    NSArray<NSString *> *delegateSelectors = @[@"mediaOverlayDelegate", @"retryDelegate", @"tappableOverlayDelegate", @"buttonDelegate"];
    Class sectionControllerClass = NSClassFromString(@"IGStoryFullscreenSectionController");

    for (NSString *selectorName in delegateSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![overlayView respondsToSelector:selector]) continue;

        id delegate = ((id (*)(id, SEL))objc_msgSend)(overlayView, selector);
        if (!delegate) continue;

        if (!sectionControllerClass || [delegate isKindOfClass:sectionControllerClass]) {
            return delegate;
        }
    }

    return nil;
}

static NSString *SCIStringFromValue(id value) {
    if (!value || value == (id)kCFNull) return nil;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *string = (NSString *)value;
        return string.length > 0 ? string : nil;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *string = [value stringValue];
        return string.length > 0 ? string : nil;
    }
    return [[value description] length] > 0 ? [value description] : nil;
}

static id SCIStoryMediaFromAnyObject(id object) {
    if (!object) return nil;
    id candidate = SCIFirstObjectForSelectors(object, @[@"media", @"mediaItem", @"storyItem", @"item", @"model"]);
    return candidate ?: object;
}

static BOOL SCIResolveStoryContextFromOverlay(UIView *overlayView, id *outMarkTarget, id *outSectionController, id *outMedia) {
    SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
    if (sharedContext) {
        if (outMarkTarget) *outMarkTarget = sharedContext.markSeenTarget;
        if (outSectionController) *outSectionController = sharedContext.sectionController;
        if (outMedia) *outMedia = sharedContext.media;
        return (sharedContext.media != nil);
    }

    if (!overlayView) return NO;

    SEL markSelector = NSSelectorFromString(@"fullscreenSectionController:didMarkItemAsSeen:");
    UIViewController *viewerController = [SCIUtils nearestViewControllerForView:overlayView];

    id sectionController = SCIStorySectionControllerFromOverlayView(overlayView);
    id markTarget = nil;
    id sectionDelegate = SCIObjectForSelector(sectionController, @"delegate");
    if (sectionDelegate && [sectionDelegate respondsToSelector:markSelector]) {
        markTarget = sectionDelegate;
    } else if (viewerController && [viewerController respondsToSelector:markSelector]) {
        markTarget = viewerController;
    } else {
        id overlayAncestor = SCIObjectForSelector(overlayView, @"_viewControllerForAncestor");
        if (overlayAncestor && [overlayAncestor respondsToSelector:markSelector]) {
            markTarget = overlayAncestor;
        }
    }

    if (!sectionController && markTarget) {
        sectionController = SCIFirstObjectForSelectors(markTarget, @[@"currentSectionController"]);
        if (!sectionController) {
            sectionController = [SCIUtils getIvarForObj:markTarget name:"_currentSectionController"];
        }
    }

    id media = SCIFirstObjectForSelectors(sectionController, @[@"currentStoryItem", @"currentItem", @"item"]);
    if (!media) media = SCIFirstObjectForSelectors(markTarget, @[@"currentStoryItem", @"currentItem", @"item"]);
    if (!media && viewerController) media = SCIFirstObjectForSelectors(viewerController, @[@"currentStoryItem", @"currentItem", @"item"]);
    media = SCIStoryMediaFromAnyObject(media);

    if (outMarkTarget) *outMarkTarget = markTarget;
    if (outSectionController) *outSectionController = sectionController;
    if (outMedia) *outMedia = media;

    return (media != nil);
}

static void SCIAdvanceStoryAfterManualSeenIfNeeded(UIView *overlayView, NSString *advancePrefKey) {
    SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
    if (sharedContext) {
        SCIStoryAdvanceContextIfNeeded(sharedContext, advancePrefKey);
        return;
    }

    if (advancePrefKey.length == 0 || ![SCIUtils getBoolPref:advancePrefKey]) return;

    id sectionController = SCIStorySectionControllerFromOverlayView(overlayView);
    if (!sectionController) return;

    SCIForceStoryAutoAdvance = YES;
    BOOL advanced = NO;
    SEL advanceSelector = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
    if ([sectionController respondsToSelector:advanceSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(sectionController, advanceSelector, 1);
        advanced = YES;
    }

    if (!advanced) {
        advanceSelector = NSSelectorFromString(@"storyPlayerMediaViewDidPlayToEnd:");
        if ([sectionController respondsToSelector:advanceSelector]) {
            id mediaView = [SCIUtils getIvarForObj:sectionController name:"_mediaView"];
            if (!mediaView) mediaView = [SCIUtils getIvarForObj:overlayView name:"_mediaView"];
            ((void (*)(id, SEL, id))objc_msgSend)(sectionController, advanceSelector, mediaView);
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        SCIForceStoryAutoAdvance = NO;
    });
}

// Forward declaration — implemented in StoryMentions.x
extern void SCIPresentStoryMentionsSheet(UIView *overlayView);

static void SCIMarkCurrentStoryAsSeenFromOverlayWithAdvancePref(UIView *overlayView, NSString *advancePrefKey) {
    if (!overlayView) return;

    SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
    if (sharedContext) {
        if (!sharedContext.markSeenTarget || !sharedContext.sectionController || !sharedContext.media) {
            SCINotify(kSCINotificationStoryMarkSeen, @"Unable to mark story as seen", nil, @"error_filled", SCINotificationToneError);
            return;
        }
        if (!SCIStoryMarkContextAsSeen(sharedContext)) {
            SCINotify(kSCINotificationStoryMarkSeen, @"Unable to mark story as seen", nil, @"error_filled", SCINotificationToneError);
            return;
        }
        SCIStoryAdvanceContextIfNeeded(sharedContext, advancePrefKey);
        SCINotify(kSCINotificationStoryMarkSeen, @"Marked story as seen", nil, @"circle_check_filled", SCINotificationToneSuccess);
        return;
    }

    id markTarget = nil;
    id sectionController = nil;
    id media = nil;
    BOOL resolved = SCIResolveStoryContextFromOverlay(overlayView, &markTarget, &sectionController, &media);
    if (!markTarget || !sectionController || !media) {
        SCINotify(kSCINotificationStoryMarkSeen, @"Unable to mark story as seen", nil, @"error_filled", SCINotificationToneError);
        return;
    }

    SEL markSelector = NSSelectorFromString(@"fullscreenSectionController:didMarkItemAsSeen:");
    SCIForcedStorySeenMediaPK = [SCIStoryMediaIdentifier(media) copy];
    SCIForceMarkStoryAsSeen = YES;
    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)(markTarget, markSelector, sectionController, media);
    } @finally {
        SCIForceMarkStoryAsSeen = NO;
        SCIForcedStorySeenMediaPK = nil;
    }

    if (resolved) {
        SCIAdvanceStoryAfterManualSeenIfNeeded(overlayView, advancePrefKey);
    }

    SCINotify(kSCINotificationStoryMarkSeen, @"Marked story as seen", nil, @"circle_check_filled", SCINotificationToneSuccess);
}

static void SCIMarkCurrentStoryAsSeenFromOverlay(UIView *overlayView) {
    SCIMarkCurrentStoryAsSeenFromOverlayWithAdvancePref(overlayView, @"stories_advance_on_manual_seen");
}

void SCIMarkStoryAsSeenForView(UIView *view) {
    SCIMarkStoryAsSeenForViewWithAdvancePref(view, nil);
}

void SCIMarkStoryAsSeenForViewWithAdvancePref(UIView *view, NSString *advancePrefKey) {
    UIView *walker = view;
    for (NSInteger depth = 0; walker && depth < 24; depth++, walker = walker.superview) {
        if ([walker isKindOfClass:%c(IGStoryFullscreenOverlayView)]) {
            SCIMarkCurrentStoryAsSeenFromOverlayWithAdvancePref(walker, advancePrefKey);
            return;
        }
    }
}

UIView *SCIActiveStoryOverlayForInteractions(void) {
    return SCIStoryActiveOverlay() ?: SCIActiveStoryOverlayView;
}

%group SCIStorySeenButtonHooks

%hook IGStoryFullscreenOverlayView
- (void)layoutSubviews {
    %orig;

    UIView *overlayView = (UIView *)self;
    SCIActiveStoryOverlayView = overlayView;
    SCIStorySetActiveOverlay(overlayView);
    SCIEnsureStoryOverlayAlphaObserver(overlayView);

    UIButton *seenButton = (UIButton *)[(UIView *)self viewWithTag:kSCIStorySeenButtonTag];
    if (SCIOverlayIsDirectVisualOverlay((UIView *)self)) {
        [seenButton removeFromSuperview];
        SCIRemoveStoryMentionsButton(overlayView);
        UIView *footerContainer = SCIStoryFooterContainerFromOverlay(overlayView);
        if (footerContainer) {
            SCIUpdateStoryButtonsAlpha(overlayView, footerContainer.alpha);
        }
        return;
    }

    SCIStoryContext *storyContext = SCIStoryContextFromOverlay(overlayView);
    BOOL showSeenButton = SCIStoryManualSeenAppliesToContext(storyContext);
    if (!showSeenButton && SCIManualStorySeenEnabled() && SCIStoryManualSeenListContainsUser(SCIStoryUserPKFromMediaObject(storyContext.media), YES)) {
        static NSMutableSet<NSString *> *autoSeenMarked;
        static dispatch_once_t autoSeenOnceToken;
        dispatch_once(&autoSeenOnceToken, ^{
            autoSeenMarked = [NSMutableSet set];
        });
        NSString *mediaIdentifier = SCIStoryMediaIdentifierForContext(storyContext);
        if (mediaIdentifier.length > 0 && ![autoSeenMarked containsObject:mediaIdentifier]) {
            [autoSeenMarked addObject:mediaIdentifier];
            SCIStoryMarkContextAsSeen(storyContext);
        }
    }
    if (!showSeenButton) {
        [seenButton removeFromSuperview];
        UIView *footerContainer = SCIStoryFooterContainerFromOverlay(overlayView);
        if (footerContainer) {
            SCIUpdateStoryButtonsAlpha(overlayView, footerContainer.alpha);
        }
    }

    if (showSeenButton && !seenButton) {
        seenButton = SCIStorySeenButtonWithTag((UIView *)self, kSCIStorySeenButtonTag);
        [seenButton addTarget:self action:@selector(sci_storySeenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sci_storySeenButtonLongPressed:)];
        longPress.minimumPressDuration = 0.5;
        [seenButton addGestureRecognizer:longPress];

        UIImage *seenImage = [SCIAssetUtils instagramIconNamed:kSCISeenMessagesBarIconResource pointSize:24.0];
        SCISetSeenButtonImage(seenButton, seenImage, @"Story seen custom icon assigned");
    }
    if (showSeenButton) {
        SCIApplyStorySeenButtonStyle(seenButton);
    }

    UIButton *storyActionButton = (UIButton *)[overlayView viewWithTag:kSCIStoriesActionButtonTag];
    BOOL actionVisible = [storyActionButton isKindOfClass:[UIButton class]]
        && !storyActionButton.hidden
        && storyActionButton.superview == overlayView
        && CGRectGetWidth(storyActionButton.frame) > 0.0
        && CGRectGetHeight(storyActionButton.frame) > 0.0;
    CGRect baseFrame = SCIStorySeenBaseFrame(overlayView);
    CGFloat size = CGRectGetWidth(baseFrame);
    if (actionVisible) {
        size = CGRectGetWidth(storyActionButton.frame);
    }
    if (size <= 0.0) size = 38.0;

    CGFloat spacingReduction = 2.0;
    CGFloat y = actionVisible ? CGRectGetMinY(storyActionButton.frame) : CGRectGetMinY(baseFrame);
    CGFloat nextX = actionVisible
        ? (CGRectGetMinX(storyActionButton.frame) - size + spacingReduction)
        : CGRectGetMinX(baseFrame);

    if (showSeenButton && seenButton) {
        seenButton.frame = CGRectMake(nextX, y, size, size);
        [overlayView bringSubviewToFront:seenButton];
        nextX -= (size - spacingReduction);
    } else if (seenButton) {
        [seenButton removeFromSuperview];
        seenButton = nil;
    }

    SCIUpdateStoryMentionsButton(overlayView, nextX, y, size);

    UIView *footerContainer = SCIStoryFooterContainerFromOverlay(overlayView);
    if (footerContainer) {
        SCIUpdateStoryButtonsAlpha(overlayView, footerContainer.alpha);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context == kSCIStoryOverlayAlphaObserverContext && [keyPath isEqualToString:@"alpha"]) {
        CGFloat alpha = 1.0;
        id newAlphaValue = change[NSKeyValueChangeNewKey];
        if ([newAlphaValue respondsToSelector:@selector(floatValue)]) {
            alpha = [newAlphaValue floatValue];
        } else if ([object isKindOfClass:[UIView class]]) {
            alpha = ((UIView *)object).alpha;
        }
        SCIUpdateStoryButtonsAlpha((UIView *)self, alpha);
        return;
    }

    %orig(keyPath, object, change, context);
}

- (void)dealloc {
    SCIRemoveStoryOverlayAlphaObserverIfNeeded((UIView *)self);
    if (SCIStoryActiveOverlay() == (UIView *)self) {
        SCIStorySetActiveOverlay(nil);
    }
    if (SCIActiveStoryOverlayView == (UIView *)self) {
        SCIActiveStoryOverlayView = nil;
    }
    %orig;
}

%new - (void)sci_storySeenButtonTapped:(UIButton *)sender {
    (void)sender;
    SCIPlayButtonTappedHaptic();
    SCIMarkCurrentStoryAsSeenFromOverlay((UIView *)self);
}

%new - (void)sci_storySeenButtonLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    SCIPlayButtonTappedHaptic();
    SCIStoryContext *context = SCIStoryContextFromOverlay((UIView *)self);
    NSString *title = SCIStoryCurrentUserRuleConfirmationTitle(context);
    NSString *message = SCIStoryCurrentUserRuleConfirmationMessage(context);
    if (title.length == 0 || message.length == 0) {
        SCINotify(kSCINotificationStorySeenUserRule, @"Story user not found", nil, @"error_filled", SCINotificationToneError);
        return;
    }
    [SCIUtils showConfirmation:^{
        NSString *notificationTitle = nil;
        NSString *notificationSubtitle = nil;
        if (!SCIStoryToggleCurrentUserRule(context, &notificationTitle, &notificationSubtitle)) {
            SCINotify(kSCINotificationStorySeenUserRule, @"Story user not found", nil, @"error_filled", SCINotificationToneError);
            return;
        }
        SCINotify(kSCINotificationStorySeenUserRule, notificationTitle, notificationSubtitle, @"circle_check_filled", SCINotificationToneSuccess);
        [(UIView *)self setNeedsLayout];
    } title:title message:message];
}


%end

void SCIInstallStorySeenButtonHooksIfNeeded(void) {
    if (!SCIStorySeenHooksNeeded()) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIStorySeenButtonHooks);
    });
}

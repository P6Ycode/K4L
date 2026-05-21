#import "../../Utils.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

extern void SCIMarkStoryAsSeenForViewWithAdvancePref(UIView *view, NSString *advancePrefKey);
extern UIView *SCIActiveStoryOverlayForInteractions(void);

static inline BOOL SCIStoryLegacyInteractionPrefEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"story_mark_seen_on_interaction"] != nil &&
        [SCIUtils getBoolPref:@"story_mark_seen_on_interaction"];
}

static inline BOOL SCIStoryMarkSeenOnLikeEnabled(void) {
    return [SCIUtils getBoolPref:@"story_mark_seen_on_like"] || SCIStoryLegacyInteractionPrefEnabled();
}

static inline BOOL SCIStoryMarkSeenOnReplyEnabled(void) {
    return [SCIUtils getBoolPref:@"story_mark_seen_on_reply"] || SCIStoryLegacyInteractionPrefEnabled();
}

static inline BOOL SCIStoryInteractionHooksNeeded(void) {
    return [SCIUtils getBoolPref:@"like_confirm_stories"] ||
        SCIStoryMarkSeenOnLikeEnabled() ||
        SCIStoryMarkSeenOnReplyEnabled() ||
        [SCIUtils getBoolPref:@"advance_story_when_like_marked_seen"] ||
        [SCIUtils getBoolPref:@"advance_story_when_reply_marked_seen"];
}

static inline id SCIObjectForSelectorIfAvailable(id target, NSString *selectorName) {
    if (!target || !selectorName.length) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static BOOL SCIBoolValueForSelector(id target, NSString *selectorName, BOOL *resolved) {
    if (resolved) *resolved = NO;
    if (!target || !selectorName.length) return NO;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return NO;

    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    const char *returnType = signature.methodReturnType;
    if (!returnType || !returnType[0]) return NO;

    if (returnType[0] == '@') {
        id value = ((id (*)(id, SEL))objc_msgSend)(target, selector);
        if (!value) return NO;
        if ([value respondsToSelector:@selector(boolValue)]) {
            if (resolved) *resolved = YES;
            return ((BOOL (*)(id, SEL))objc_msgSend)(value, @selector(boolValue));
        }
        if ([value respondsToSelector:@selector(doubleValue)]) {
            if (resolved) *resolved = YES;
            return ((double (*)(id, SEL))objc_msgSend)(value, @selector(doubleValue)) != 0.0;
        }
        if ([value respondsToSelector:@selector(integerValue)]) {
            if (resolved) *resolved = YES;
            return ((NSInteger (*)(id, SEL))objc_msgSend)(value, @selector(integerValue)) != 0;
        }
        return NO;
    }

    NSNumber *number = [SCIUtils numericValueForObj:target selectorName:selectorName];
    if (!number) return NO;
    if (resolved) *resolved = YES;
    return [number boolValue];
}

static BOOL SCILikeStateFromControl(id control, BOOL *resolved) {
    if (resolved) *resolved = NO;
    if (!control) return NO;
    if ([control isKindOfClass:[UIControl class]]) {
        if (resolved) *resolved = YES;
        return ((UIControl *)control).selected;
    }
    return NO;
}

static BOOL SCILikeStateFromModel(id model, BOOL *resolved) {
    if (resolved) *resolved = NO;
    if (!model) return NO;

    for (NSString *selectorName in @[
        @"hasLiked",
        @"isLiked",
        @"isLikedByCurrentUser",
        @"viewerHasLiked",
        @"isLikedByViewer",
        @"liked"
    ]) {
        BOOL found = NO;
        BOOL liked = SCIBoolValueForSelector(model, selectorName, &found);
        if (found) {
            if (resolved) *resolved = YES;
            return liked;
        }
    }
    return NO;
}

static void SCIPresentLikeToggleConfirmation(BOOL isUnlike,
                                             NSString *likeTitle,
                                             NSString *likeMessage,
                                             NSString *unlikeTitle,
                                             NSString *unlikeMessage,
                                             void (^handler)(void)) {
    [SCIUtils showConfirmation:handler
                         title:(isUnlike ? unlikeTitle : likeTitle)
                       message:(isUnlike ? unlikeMessage : likeMessage)];
}

static id SCILikeButtonFromContext(id context) {
    if (!context) return nil;
    id button = SCIObjectForSelectorIfAvailable(context, @"likeButton");
    if (button) return button;

    id ufiView = [SCIUtils getIvarForObj:context name:"_ufiButtonBarView"];
    if (!ufiView) ufiView = SCIObjectForSelectorIfAvailable(context, @"ufiButtonBarView");
    if (!ufiView) return nil;

    return SCIObjectForSelectorIfAvailable(ufiView, @"likeButton");
}

static id SCIMediaFromContext(id context) {
    if (!context) return nil;
    id media = [SCIUtils getIvarForObj:context name:"_media"];
    if (media) return media;

    media = SCIObjectForSelectorIfAvailable(context, @"media");
    if (media) return media;

    id viewModel = [SCIUtils getIvarForObj:context name:"_cellViewModel_DO_NOT_USE"];
    if (!viewModel) viewModel = SCIObjectForSelectorIfAvailable(context, @"cellViewModel");
    if (!viewModel) return nil;

    return SCIObjectForSelectorIfAvailable(viewModel, @"media");
}

static id SCICommentFromContext(id context) {
    if (!context) return nil;
    id comment = [SCIUtils getIvarForObj:context name:"_commentModel"];
    if (comment) return comment;

    comment = [SCIUtils getIvarForObj:context name:"_comment"];
    if (comment) return comment;

    comment = SCIObjectForSelectorIfAvailable(context, @"commentModel");
    if (comment) return comment;

    return SCIObjectForSelectorIfAvailable(context, @"comment");
}

static BOOL SCIFeedLikeIsUnlike(id button, id context) {
    BOOL resolved = NO;
    BOOL liked = SCILikeStateFromControl(button, &resolved);
    if (!resolved) {
        id likeButton = SCILikeButtonFromContext(context);
        liked = SCILikeStateFromControl(likeButton, &resolved);
    }
    if (!resolved) {
        id media = SCIMediaFromContext(context);
        liked = SCILikeStateFromModel(media, &resolved);
    }
    return resolved && liked;
}

static BOOL SCICommentLikeIsUnlike(id button, id context) {
    BOOL resolved = NO;
    BOOL liked = SCILikeStateFromControl(button, &resolved);
    if (!resolved) {
        id likeButton = SCILikeButtonFromContext(context);
        liked = SCILikeStateFromControl(likeButton, &resolved);
    }
    if (!resolved) {
        id comment = SCICommentFromContext(context);
        liked = SCILikeStateFromModel(comment, &resolved);
    }
    return resolved && liked;
}

static void SCIStoryMarkSeenForInteractionView(UIView *view, NSString *advancePrefKey) {
    if (!view) return;
    SCIMarkStoryAsSeenForViewWithAdvancePref(view, advancePrefKey);
}

static void SCIStoryReplySideEffects(void) {
    if (!SCIStoryMarkSeenOnReplyEnabled()) return;
    UIView *overlay = SCIActiveStoryOverlayForInteractions();
    if (!overlay) return;
    SCIStoryMarkSeenForInteractionView(overlay, @"advance_story_when_reply_marked_seen");
}

///////////////////////////////////////////////////////////

// Confirmation handlers

static BOOL SCIBypassFeedPostLikeConfirm = NO;

#define SCI_RUN_WITH_FEED_POST_LIKE_CONFIRM_BYPASS(orig) \
    do {                                                 \
        SCIBypassFeedPostLikeConfirm = YES;              \
        @try {                                           \
            orig;                                        \
        } @finally {                                     \
            SCIBypassFeedPostLikeConfirm = NO;           \
        }                                                \
    } while (0)

#define SCICONFIRMLIKE(prefKey, logText, titleText, messageText, orig) \
    if ([SCIUtils getBoolPref:prefKey]) {                              \
        SCILog(@"General", @"[SCInsta] %@", logText);                               \
        [SCIUtils showConfirmation:^(void) { orig; }                   \
                                 title:titleText                       \
                               message:messageText];                   \
    }                                                                  \
    else {                                                             \
        return orig;                                                   \
    }                                                                  \

#define CONFIRMFEEDPOSTLIKE(context, button, orig) \
    if (SCIBypassFeedPostLikeConfirm) { \
        return orig; \
    } \
    if ([SCIUtils getBoolPref:@"like_confirm_feed_post_likes"]) { \
        BOOL isUnlike = SCIFeedLikeIsUnlike((button), (context)); \
        SCILog(@"General", @"[SCInsta] Confirm feed post %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SCIPresentLikeToggleConfirmation( \
            isUnlike, \
            @"Confirm Post Like", \
            @"Are you sure you want to like this post?", \
            @"Confirm Post Unlike", \
            @"Are you sure you want to unlike this post?", \
            ^{ SCI_RUN_WITH_FEED_POST_LIKE_CONFIRM_BYPASS(orig); } \
        ); \
    } \
    else { \
        return orig; \
    }

#define CONFIRMFEEDDOUBLETAPLIKE(context, orig) \
    if ([SCIUtils getBoolPref:@"like_confirm_feed_double_tap_likes"]) { \
        BOOL isUnlike = SCIFeedLikeIsUnlike(nil, (context)); \
        SCILog(@"General", @"[SCInsta] Confirm feed double-tap %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SCIPresentLikeToggleConfirmation( \
            isUnlike, \
            @"Confirm Post Like", \
            @"Are you sure you want to like this post?", \
            @"Confirm Post Unlike", \
            @"Are you sure you want to unlike this post?", \
            ^{ SCI_RUN_WITH_FEED_POST_LIKE_CONFIRM_BYPASS(orig); } \
        ); \
    } \
    else { \
        SCI_RUN_WITH_FEED_POST_LIKE_CONFIRM_BYPASS(orig); \
    }

#define CONFIRMCOMMENTLIKE(context, button, orig) \
    if ([SCIUtils getBoolPref:@"like_confirm_comment_likes"]) { \
        BOOL isUnlike = SCICommentLikeIsUnlike((button), (context)); \
        SCILog(@"General", @"[SCInsta] Confirm comment %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SCIPresentLikeToggleConfirmation( \
            isUnlike, \
            @"Confirm Comment Like", \
            @"Are you sure you want to like this comment?", \
            @"Confirm Comment Unlike", \
            @"Are you sure you want to unlike this comment?", \
            ^{ orig; } \
        ); \
    } else { \
        return orig; \
    }

#define CONFIRMREELSLIKE(context, button, orig) \
    if ([SCIUtils getBoolPref:@"like_confirm_reels"]) { \
        BOOL isUnlike = SCIFeedLikeIsUnlike((button), (context)); \
        SCILog(@"General", @"[SCInsta] Confirm reels %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SCIPresentLikeToggleConfirmation( \
            isUnlike, \
            @"Confirm Reel Like", \
            @"Are you sure you want to like this reel?", \
            @"Confirm Reel Unlike", \
            @"Are you sure you want to unlike this reel?", \
            ^{ orig; } \
        ); \
    } else { \
        return orig; \
    }

#define CONFIRMREELSDOUBLETAPLIKE(context, orig) \
    if ([SCIUtils getBoolPref:@"like_confirm_reels_double_tap"]) { \
        BOOL isUnlike = SCIFeedLikeIsUnlike(nil, (context)); \
        SCILog(@"General", @"[SCInsta] Confirm reels double-tap %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SCIPresentLikeToggleConfirmation( \
            isUnlike, \
            @"Confirm Reel Like", \
            @"Are you sure you want to like this reel?", \
            @"Confirm Reel Unlike", \
            @"Are you sure you want to unlike this reel?", \
            ^{ orig; } \
        ); \
    } else { \
        return orig; \
    }

///////////////////////////////////////////////////////////

// Liking posts
%group SCILikeConfirmHooks

%hook IGUFIButtonBarView
- (void)_onLikeButtonPressed {
    CONFIRMFEEDPOSTLIKE(self, nil, %orig);
}
- (void)_onLikeButtonPressed:(id)arg1 {
    CONFIRMFEEDPOSTLIKE(self, arg1, %orig);
}
%end
%hook IGFeedItemUFICell
- (void)UFIButtonBarDidTapOnLike:(id)arg1 {
    CONFIRMFEEDPOSTLIKE(self, arg1, %orig);
}
%end
%hook IGFeedItemUFICellConfigurableDelegateImpl
- (void)feedItemUFICellDidTapLikeButton:(id)arg1 {
    CONFIRMFEEDPOSTLIKE(self, arg1, %orig);
}
- (void)_performSingleTapLikeToggle {
    CONFIRMFEEDPOSTLIKE(self, nil, %orig);
}
%end
%hook IGFeedPhotoView
- (void)_onDoubleTap {
    CONFIRMFEEDDOUBLETAPLIKE(self, %orig);
}
- (void)_onDoubleTap:(id)arg1 {
    CONFIRMFEEDDOUBLETAPLIKE(self, %orig);
}
%end
%hook IGVideoPlayerOverlayContainerView
- (void)_handleDoubleTapGesture:(id)arg1 {
    CONFIRMFEEDDOUBLETAPLIKE(self, %orig);
}
%end

// Liking reels
%hook IGSundialViewerVideoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(self, arg1, %orig);
}
- (void)controlsOverlayControllerDidLongPressLikeButton:(id)arg1 gestureRecognizer:(id)arg2 {
    CONFIRMREELSLIKE(self, arg1, %orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
%end
%hook IGSundialViewerPhotoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(self, arg1, %orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
- (void)swift_photoCell:(id)arg1 didObserveDoubleTapWithLocationInfo:(id)arg2 gestureRecognizer:(id)arg3 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
%end
%hook IGSundialViewerCarouselCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(self, arg1, %orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
- (void)carouselCell:(id)arg1 didObserveDoubleTapWithLocationInfo:(id)arg2 gestureRecognizer:(id)arg3 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
%end

// Liking comments
%hook IGCommentCellController
- (void)commentCell:(id)arg1 didTapLikeButton:(id)arg2 {
    CONFIRMCOMMENTLIKE(arg1, arg2, %orig);
}
- (void)commentCell:(id)arg1 didTapLikedByButtonForUser:(id)arg2 {
    CONFIRMCOMMENTLIKE(nil, nil, %orig);
}
- (void)commentCellDidLongPressOnLikeButton:(id)arg1 {
    CONFIRMCOMMENTLIKE(nil, arg1, %orig);
}
- (void)commentCellDidEndLongPressOnLikeButton:(id)arg1 {
    CONFIRMCOMMENTLIKE(nil, arg1, %orig);
}
- (void)commentCellDidDoubleTap:(id)arg1 {
    CONFIRMCOMMENTLIKE(arg1, nil, %orig);
}
%end
%hook IGFeedItemPreviewCommentCell
- (void)_didTapLikeButton {
    CONFIRMCOMMENTLIKE(self, nil, %orig);
}
%end

// Liking stories (newer Instagram builds)
static void (*orig_sciStoryLikeTap)(id, SEL, id);
static void new_sciStoryLikeTap(id self, SEL _cmd, id button) {
    if (![SCIUtils getBoolPref:@"like_confirm_stories"]) {
        orig_sciStoryLikeTap(self, _cmd, button);
        if (SCIStoryMarkSeenOnLikeEnabled() && [button isKindOfClass:[UIView class]]) {
            SCIStoryMarkSeenForInteractionView((UIView *)button, @"advance_story_when_like_marked_seen");
        }
        return;
    }

    BOOL isSelected = [button isKindOfClass:[UIButton class]] ? [(UIButton *)button isSelected] : NO;
    BOOL isUnlike = !isSelected;

    UIButton *btn = [button isKindOfClass:[UIButton class]] ? (UIButton *)button : nil;
    SEL setLikedSel = NSSelectorFromString(@"setIsLiked:animated:");

    [SCIUtils showConfirmation:^{
        if (btn) {
            [btn setSelected:isSelected];
            if ([btn respondsToSelector:setLikedSel]) {
                ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(btn, setLikedSel, isSelected, YES);
            }
        }
        orig_sciStoryLikeTap(self, _cmd, button);
        if (!isUnlike && SCIStoryMarkSeenOnLikeEnabled() && [button isKindOfClass:[UIView class]]) {
            SCIStoryMarkSeenForInteractionView((UIView *)button, @"advance_story_when_like_marked_seen");
        }
    } title:(isUnlike ? @"Confirm Story Unlike" : @"Confirm Story Like")
      message:(isUnlike ? @"Are you sure you want to unlike this story?" : @"Are you sure you want to like this story?")];

    if (btn) {
        [UIView performWithoutAnimation:^{
            [btn setSelected:!isSelected];
            if ([btn respondsToSelector:setLikedSel]) {
                ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(btn, setLikedSel, !isSelected, NO);
            }
        }];
    }
}

static void SCIInstallStoryLikeConfirmHookIfNeeded(void) {
    if (!SCIStoryInteractionHooksNeeded()) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"_TtC22IGStoryLikesController38IGStoryLikesInteractionControllingImpl");
        if (!cls) cls = NSClassFromString(@"IGStoryLikesInteractionControllingImpl");
        if (!cls) return;

        SEL sel = NSSelectorFromString(@"handleStoryLikeTapWith:");
        if (!class_getInstanceMethod(cls, sel)) {
            sel = NSSelectorFromString(@"handleStoryLikeTapWithButton:");
        }
        if (!class_getInstanceMethod(cls, sel)) return;

        MSHookMessageEx(cls, sel, (IMP)new_sciStoryLikeTap, (IMP *)&orig_sciStoryLikeTap);
    });
}

%hook IGDirectComposer
- (void)_didTapSend {
    %orig;
    SCIStoryReplySideEffects();
}

- (void)_didTapSend:(id)arg {
    %orig;
    SCIStoryReplySideEffects();
}

- (void)_send {
    %orig;
    SCIStoryReplySideEffects();
}

- (void)_didTapEmojiQuickReactionButton:(id)button {
    if (SCIActiveStoryOverlayForInteractions()) {
        %orig;
        SCIStoryReplySideEffects();
        return;
    }
    %orig;
}

- (void)_didTapEmojiReactionButton:(id)button {
    if (SCIActiveStoryOverlayForInteractions()) {
        %orig;
        SCIStoryReplySideEffects();
        return;
    }
    %orig;
}
%end

static void (*orig_storyFooterEmojiQuick)(id, SEL, id, id);
static void SCIHookedStoryFooterEmojiQuick(id self, SEL _cmd, id inputView, id button) {
    if (orig_storyFooterEmojiQuick) orig_storyFooterEmojiQuick(self, _cmd, inputView, button);
    SCIStoryReplySideEffects();
}

static void (*orig_storyFooterEmojiReaction)(id, SEL, id, id);
static void SCIHookedStoryFooterEmojiReaction(id self, SEL _cmd, id inputView, id button) {
    if (orig_storyFooterEmojiReaction) orig_storyFooterEmojiReaction(self, _cmd, inputView, button);
    SCIStoryReplySideEffects();
}

static void (*orig_storyQuickReaction)(id, SEL, id, id, id);
static void SCIHookedStoryQuickReaction(id self, SEL _cmd, id view, id sourceButton, id emoji) {
    if (orig_storyQuickReaction) orig_storyQuickReaction(self, _cmd, view, sourceButton, emoji);
    SCIStoryReplySideEffects();
}

static void (*orig_storyPrivateEmojiQuick)(id, SEL, id);
static void SCIHookedStoryPrivateEmojiQuick(id self, SEL _cmd, id button) {
    if (orig_storyPrivateEmojiQuick) orig_storyPrivateEmojiQuick(self, _cmd, button);
    SCIStoryReplySideEffects();
}

static void (*orig_directReshareQuickReaction)(id, SEL, id);
static void SCIHookedDirectReshareQuickReaction(id self, SEL _cmd, id arg) {
    if (orig_directReshareQuickReaction) orig_directReshareQuickReaction(self, _cmd, arg);
    SCIStoryReplySideEffects();
}

static Class SCIStoryReplyFooterClass(void) {
    for (NSString *className in @[
        @"IGStoryDefaultFooter.IGStoryFullscreenDefaultFooterView",
        @"IGStoryFullscreenDefaultFooterView"
    ]) {
        Class cls = NSClassFromString(className);
        if (cls) return cls;
    }
    return Nil;
}

static void SCIInstallStoryReplyHooksIfNeeded(void) {
    if (!SCIStoryInteractionHooksNeeded()) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class footerClass = SCIStoryReplyFooterClass();
        SEL quickSelector = NSSelectorFromString(@"inputView:didTapEmojiQuickReactionButton:");
        if (footerClass && class_getInstanceMethod(footerClass, quickSelector)) {
            MSHookMessageEx(footerClass, quickSelector, (IMP)SCIHookedStoryFooterEmojiQuick, (IMP *)&orig_storyFooterEmojiQuick);
        }

        SEL reactionSelector = NSSelectorFromString(@"inputView:didTapEmojiReactionButton:");
        if (footerClass && class_getInstanceMethod(footerClass, reactionSelector)) {
            MSHookMessageEx(footerClass, reactionSelector, (IMP)SCIHookedStoryFooterEmojiReaction, (IMP *)&orig_storyFooterEmojiReaction);
        }

        Class quickReactionClass = NSClassFromString(@"IGStoryQuickReactions.IGStoryQuickReactionsController");
        SEL quickReactionSelector = NSSelectorFromString(@"quickReactionsView:sourceEmojiButton:didTapEmoji:");
        if (quickReactionClass && class_getInstanceMethod(quickReactionClass, quickReactionSelector)) {
            MSHookMessageEx(quickReactionClass, quickReactionSelector, (IMP)SCIHookedStoryQuickReaction, (IMP *)&orig_storyQuickReaction);
        }

        SEL privateQuickSelector = NSSelectorFromString(@"_didTapEmojiQuickReactionButton:");
        if (footerClass && class_getInstanceMethod(footerClass, privateQuickSelector)) {
            MSHookMessageEx(footerClass, privateQuickSelector, (IMP)SCIHookedStoryPrivateEmojiQuick, (IMP *)&orig_storyPrivateEmojiQuick);
        }

        Class quickReactionDelegateClass = NSClassFromString(@"_TtC29IGStoryQuickReactionsDelegate33IGStoryQuickReactionsDelegateImpl");
        if (!quickReactionDelegateClass) quickReactionDelegateClass = NSClassFromString(@"IGStoryQuickReactionsDelegateImpl");
        SEL directReshareSelector = NSSelectorFromString(@"directReshareMediaReplyFooterViewDidTapQuickReactionEmoji:");
        if (quickReactionDelegateClass && class_getInstanceMethod(quickReactionDelegateClass, directReshareSelector)) {
            MSHookMessageEx(quickReactionDelegateClass, directReshareSelector, (IMP)SCIHookedDirectReshareQuickReaction, (IMP *)&orig_directReshareQuickReaction);
        }
    });
}

// DM like button (seems to be hidden)
%hook IGDirectThreadViewController
- (void)_didTapLikeButton {
    %orig;
}
- (void)_didTapLikeButton:(id)arg1 {
    %orig;
}
%end

%end

static void (*orig_sciReelsLikeHandlerTap)(id, SEL, id, id, BOOL) = NULL;
static void sciReelsLikeHandlerTap(id self, SEL _cmd, id context, id likeButton, BOOL willAnimate) {
    if (![SCIUtils getBoolPref:@"like_confirm_reels"]) {
        if (orig_sciReelsLikeHandlerTap) orig_sciReelsLikeHandlerTap(self, _cmd, context, likeButton, willAnimate);
        return;
    }

    __strong id strongContext = context;
    __strong id strongButton = likeButton;
    BOOL isUnlike = SCIFeedLikeIsUnlike(strongButton, strongContext);
    SCILog(@"General", @"[SCInsta] Confirm reels %@ triggered", isUnlike ? @"unlike" : @"like");
    SCIPresentLikeToggleConfirmation(
        isUnlike,
        @"Confirm Reel Like",
        @"Are you sure you want to like this reel?",
        @"Confirm Reel Unlike",
        @"Are you sure you want to unlike this reel?",
        ^{
            if (orig_sciReelsLikeHandlerTap) orig_sciReelsLikeHandlerTap(self, _cmd, strongContext, strongButton, willAnimate);
        }
    );
}

static void (*orig_sciReelsLikeHandlerTapCompletion)(id, SEL, id, id, BOOL, id) = NULL;
static void sciReelsLikeHandlerTapCompletion(id self, SEL _cmd, id context, id likeButton, BOOL willAnimate, id completion) {
    if (![SCIUtils getBoolPref:@"like_confirm_reels"]) {
        if (orig_sciReelsLikeHandlerTapCompletion) orig_sciReelsLikeHandlerTapCompletion(self, _cmd, context, likeButton, willAnimate, completion);
        return;
    }

    __strong id strongContext = context;
    __strong id strongButton = likeButton;
    id strongCompletion = completion ? [completion copy] : nil;
    BOOL isUnlike = SCIFeedLikeIsUnlike(strongButton, strongContext);
    SCILog(@"General", @"[SCInsta] Confirm reels %@ triggered", isUnlike ? @"unlike" : @"like");
    SCIPresentLikeToggleConfirmation(
        isUnlike,
        @"Confirm Reel Like",
        @"Are you sure you want to like this reel?",
        @"Confirm Reel Unlike",
        @"Are you sure you want to unlike this reel?",
        ^{
            if (orig_sciReelsLikeHandlerTapCompletion) orig_sciReelsLikeHandlerTapCompletion(self, _cmd, strongContext, strongButton, willAnimate, strongCompletion);
        }
    );
}

static void SCIInstallReelsSwiftLikeConfirmHookIfNeeded(void) {
    if (![SCIUtils getBoolPref:@"like_confirm_reels"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"_TtC30IGSundialOverlayActionHandlers38IGSundialViewerLikeButtonActionHandler");
        if (!cls) cls = NSClassFromString(@"IGSundialViewerLikeButtonActionHandler");
        Class meta = cls ? object_getClass(cls) : Nil;
        if (!meta) return;

        SEL tapSel = NSSelectorFromString(@"handleTapWithActionContext:likeButton:willPlayRingsCustomLikeAnimation:");
        if (class_getClassMethod(cls, tapSel)) {
            MSHookMessageEx(meta, tapSel, (IMP)sciReelsLikeHandlerTap, (IMP *)&orig_sciReelsLikeHandlerTap);
        }

        SEL tapCompletionSel = NSSelectorFromString(@"handleTapWithActionContext:likeButton:willPlayRingsCustomLikeAnimation:completion:");
        if (class_getClassMethod(cls, tapCompletionSel)) {
            MSHookMessageEx(meta, tapCompletionSel, (IMP)sciReelsLikeHandlerTapCompletion, (IMP *)&orig_sciReelsLikeHandlerTapCompletion);
        }
    });
}

void SCIInstallLikeConfirmHooksIfNeeded(void) {
    if (![SCIUtils getBoolPref:@"like_confirm_feed_post_likes"] &&
        ![SCIUtils getBoolPref:@"like_confirm_feed_double_tap_likes"] &&
        ![SCIUtils getBoolPref:@"like_confirm_comment_likes"] &&
        ![SCIUtils getBoolPref:@"like_confirm_reels"] &&
        ![SCIUtils getBoolPref:@"like_confirm_reels_double_tap"] &&
        !SCIStoryInteractionHooksNeeded()) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCILikeConfirmHooks);
    });

    SCIInstallStoryLikeConfirmHookIfNeeded();
    SCIInstallStoryReplyHooksIfNeeded();
    SCIInstallReelsSwiftLikeConfirmHookIfNeeded();
}

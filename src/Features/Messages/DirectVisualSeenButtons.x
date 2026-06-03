#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../InstagramHeaders.h"
#import "../../AssetUtils.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "../../Shared/Messages/SCIDirectSeenContext.h"
#import "../../Shared/Stories/SCIStoryContext.h"
#import "../../Shared/UI/SCIChrome.h"
#ifdef __cplusplus
extern "C" {
#endif
void SCIApplyButtonStyle(UIButton *button, NSInteger source);
#ifdef __cplusplus
}
#endif

static NSString * const kSCISeenMessagesBarIconResource = @"eye";
static NSInteger const kSCIActionButtonSourceDirect = 4;
static NSInteger const kSCIDirectActionButtonTag = 921344;
static NSInteger const kSCIDirectSeenButtonTag = 921345;
static const void *kSCIDirectSeenBottomConstraintAssocKey = &kSCIDirectSeenBottomConstraintAssocKey;
static const void *kSCIDirectSeenTrailingOverlayConstraintAssocKey = &kSCIDirectSeenTrailingOverlayConstraintAssocKey;
static const void *kSCIDirectSeenTrailingActionConstraintAssocKey = &kSCIDirectSeenTrailingActionConstraintAssocKey;
static const void *kSCIDirectSeenCenterYActionConstraintAssocKey = &kSCIDirectSeenCenterYActionConstraintAssocKey;
static const void *kSCIDirectSeenWidthConstraintAssocKey = &kSCIDirectSeenWidthConstraintAssocKey;
static const void *kSCIDirectSeenHeightConstraintAssocKey = &kSCIDirectSeenHeightConstraintAssocKey;
static const void *kSCIDirectSeenAnchoredActionButtonAssocKey = &kSCIDirectSeenAnchoredActionButtonAssocKey;
static const void *kSCIDirectVisualObservedInputViewAssocKey = &kSCIDirectVisualObservedInputViewAssocKey;
static const void *kSCIDirectVisualHasInputObserverAssocKey = &kSCIDirectVisualHasInputObserverAssocKey;
static void *kSCIDirectVisualInputAlphaObserverContext = &kSCIDirectVisualInputAlphaObserverContext;

static id SCIKVCObject(id target, NSString *key);

static inline BOOL SCIDirectManualSeenRulesEnabled(void) {
    return [SCIUtils getBoolPref:@"msgs_manual_seen"] || SCIDirectManualSeenThreadCount(NO) > 0;
}

static inline BOOL SCIDirectSeenHooksNeeded(void) {
    return SCIDirectManualSeenRulesEnabled() ||
           [SCIUtils getBoolPref:@"msgs_manual_visual_seen"] ||
           [SCIUtils getBoolPref:@"msgs_advance_visual_on_seen"];
}
static NSArray *SCIArrayFromCollection(id collection) {
    if (!collection ||
        [collection isKindOfClass:[NSDictionary class]] ||
        [collection isKindOfClass:[NSString class]] ||
        [collection isKindOfClass:[NSURL class]]) {
        return nil;
    }

    if ([collection isKindOfClass:[NSArray class]]) {
        return collection;
    }

    if ([collection isKindOfClass:[NSOrderedSet class]]) {
        return [(NSOrderedSet *)collection array];
    }

    if ([collection isKindOfClass:[NSSet class]]) {
        return [(NSSet *)collection allObjects];
    }

    if ([collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id item in collection) {
            [array addObject:item];
        }
        return array;
    }

    return nil;
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

static UIView *SCIDirectOverlayViewFromController(UIViewController *controller) {
    if (!controller) return nil;

    id viewerContainer = [SCIUtils getIvarForObj:controller name:"_viewerContainerView"];
    if (!viewerContainer) viewerContainer = SCIKVCObject(controller, @"viewerContainerView");

    SEL overlaySelector = NSSelectorFromString(@"overlayView");
    if (![viewerContainer respondsToSelector:overlaySelector]) return nil;
    id overlay = ((id (*)(id, SEL))objc_msgSend)(viewerContainer, overlaySelector);
    return [overlay isKindOfClass:[UIView class]] ? (UIView *)overlay : nil;
}

static id SCIDirectCurrentMessageFromController(UIViewController *controller) {
    if (!controller) return nil;

    id dataSource = [SCIUtils getIvarForObj:controller name:"_dataSource"];
    if (!dataSource) dataSource = SCIKVCObject(controller, @"dataSource");

    id message = [SCIUtils getIvarForObj:dataSource name:"_currentMessage"];
    if (!message) message = SCIKVCObject(dataSource, @"currentMessage");
    return message;
}

static NSInteger SCIDirectCurrentIndexFromController(UIViewController *controller) {
    if (!controller) return 0;

    id dataSource = [SCIUtils getIvarForObj:controller name:"_dataSource"];
    if (!dataSource) dataSource = SCIKVCObject(controller, @"dataSource");

    for (NSString *selectorName in @[@"currentItemIndex", @"currentIndex", @"itemIndex"]) {
        NSNumber *index = [SCIUtils numericValueForObj:dataSource selectorName:selectorName];
        if (index && index.integerValue >= 0) return index.integerValue;
    }

    for (NSString *key in @[@"currentItemIndex", @"currentIndex", @"itemIndex"]) {
        id value = SCIKVCObject(dataSource, key);
        if ([value respondsToSelector:@selector(integerValue)] && [value integerValue] >= 0) {
            return [value integerValue];
        }
    }

    return 0;
}

static CGFloat SCIHeightFromFrameLikeObject(id object) {
    if (!object) return 0.0;

    if ([object isKindOfClass:[UIView class]]) {
        return ((UIView *)object).frame.size.height;
    }

    @try {
        id frameValue = [object valueForKey:@"frame"];
        if ([frameValue isKindOfClass:[NSValue class]]) {
            return ((NSValue *)frameValue).CGRectValue.size.height;
        }
    } @catch (__unused NSException *exception) {
    }

    return 0.0;
}

static CGFloat SCIDirectBottomOffset(UIViewController *controller) {
    if (!controller) return 12.0;

    id inputView = [SCIUtils getIvarForObj:controller name:"_inputView"];
    CGFloat offset = controller.view.safeAreaInsets.bottom + 12.0;
    if (inputView) {
        offset += SCIHeightFromFrameLikeObject(inputView);
    }

    return offset;
}

static UIView *SCIDirectInputViewFromController(UIViewController *controller) {
    if (!controller) return nil;

    id inputView = [SCIUtils getIvarForObj:controller name:"_inputView"];
    if (![inputView isKindOfClass:[UIView class]]) {
        inputView = SCIKVCObject(controller, @"inputView");
    }
    return [inputView isKindOfClass:[UIView class]] ? (UIView *)inputView : nil;
}

static void SCIUpdateDirectVisualButtonsAlpha(UIViewController *controller, CGFloat alpha) {
    if (!controller) return;
    UIView *overlay = SCIDirectOverlayViewFromController(controller);
    if (!overlay) return;

    UIButton *actionButton = (UIButton *)[overlay viewWithTag:kSCIDirectActionButtonTag];
    if ([actionButton isKindOfClass:[UIButton class]]) {
        actionButton.alpha = alpha;
    }

    UIButton *seenButton = (UIButton *)[overlay viewWithTag:kSCIDirectSeenButtonTag];
    if ([seenButton isKindOfClass:[UIButton class]]) {
        seenButton.alpha = alpha;
    }
}

static void SCIRemoveDirectVisualInputAlphaObserverIfNeeded(UIViewController *controller) {
    UIView *observedInputView = objc_getAssociatedObject(controller, kSCIDirectVisualObservedInputViewAssocKey);
    BOOL hasObserver = [objc_getAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey) boolValue];
    if (observedInputView && hasObserver) {
        [observedInputView removeObserver:controller forKeyPath:@"alpha" context:kSCIDirectVisualInputAlphaObserverContext];
    }

    objc_setAssociatedObject(controller, kSCIDirectVisualObservedInputViewAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void SCIEnsureDirectVisualInputAlphaObserver(UIViewController *controller) {
    if (!controller) return;

    UIView *inputView = SCIDirectInputViewFromController(controller);
    UIView *observedInputView = objc_getAssociatedObject(controller, kSCIDirectVisualObservedInputViewAssocKey);
    BOOL hasObserver = [objc_getAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey) boolValue];
    if (observedInputView && observedInputView != inputView && hasObserver) {
        [observedInputView removeObserver:controller forKeyPath:@"alpha" context:kSCIDirectVisualInputAlphaObserverContext];
        objc_setAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hasObserver = NO;
    }

    if (observedInputView != inputView) {
        objc_setAssociatedObject(controller, kSCIDirectVisualObservedInputViewAssocKey, inputView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (inputView && !hasObserver) {
        [inputView addObserver:controller
                    forKeyPath:@"alpha"
                       options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                       context:kSCIDirectVisualInputAlphaObserverContext];
        objc_setAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static inline BOOL SCIShouldShowDirectVisualSeenButton(void) {
    return [SCIUtils getBoolPref:@"msgs_manual_seen"] || [SCIUtils getBoolPref:@"msgs_manual_visual_seen"];
}

static BOOL SCIDirectInvokeNoArgSelector(id object, SEL selector) {
    if (!object || !selector || ![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL))objc_msgSend)(object, selector);
    return YES;
}

static BOOL SCIDirectInvokeObjectArgSelector(id object, SEL selector, id argument) {
    if (!object || !selector || ![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
    return YES;
}

static BOOL SCIDirectInvokeIntegerArgSelector(id object, SEL selector, NSInteger argument) {
    if (!object || !selector || ![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(object, selector, argument);
    return YES;
}

static BOOL SCIDirectInvokeDismissShowNextSelector(id object) {
    SEL selector = NSSelectorFromString(@"dismissWithShowNext:completion:");
    if (!object || ![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, BOOL, id))objc_msgSend)(object, selector, YES, nil);
    return YES;
}

static NSArray *SCIDirectVisualAdvanceTargets(UIViewController *controller) {
    if (!controller) return @[];

    NSMutableArray *targets = [NSMutableArray array];
    NSArray<NSString *> *keys = @[
        @"_presentationManager",
        @"presentationManager",
        @"_viewerPresentationManager",
        @"viewerPresentationManager",
        @"_viewerContainerView",
        @"viewerContainerView",
        @"_viewerContainer",
        @"viewerContainer",
        @"_dataSource",
        @"dataSource",
        @"_delegate",
        @"delegate",
        @"_viewModel",
        @"viewModel"
    ];

    for (NSString *key in keys) {
        id target = [key hasPrefix:@"_"] ? [SCIUtils getIvarForObj:controller name:key.UTF8String] : SCIKVCObject(controller, key);
        if (target && ![targets containsObject:target]) {
            [targets addObject:target];
        }
    }

    if (![targets containsObject:controller]) {
        [targets addObject:controller];
    }

    return targets;
}

static BOOL SCIDirectAdvanceVisualViewer(UIViewController *controller) {
    if (!controller) return NO;

    SEL overlayTapSelector = NSSelectorFromString(@"fullscreenOverlay:didTapInRegion:");
    if ([controller respondsToSelector:overlayTapSelector]) {
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(controller, overlayTapSelector, nil, 3);
        return YES;
    }

    NSArray *targets = SCIDirectVisualAdvanceTargets(controller);

    for (id target in targets) {
        if (SCIDirectInvokeDismissShowNextSelector(target)) return YES;
    }

    NSArray<NSString *> *integerSelectors = @[
        @"advanceToNextItemWithNavigationAction:",
        @"advanceToNextItemWithNavigationType:",
        @"advanceToNextItemForNavigationAction:",
        @"moveToNextItemWithNavigationAction:",
        @"navigateToNextItemWithNavigationAction:"
    ];
    for (id target in targets) {
        for (NSString *selectorName in integerSelectors) {
            if (SCIDirectInvokeIntegerArgSelector(target, NSSelectorFromString(selectorName), 1)) return YES;
        }
    }

    NSArray<NSString *> *noArgSelectors = @[
        @"_advanceToNextItem",
        @"advanceToNextItem",
        @"moveToNextItem",
        @"navigateToNextItem",
        @"displayNextItem",
        @"showNextItem",
        @"goToNextItem"
    ];
    for (id target in targets) {
        for (NSString *selectorName in noArgSelectors) {
            if (SCIDirectInvokeNoArgSelector(target, NSSelectorFromString(selectorName))) return YES;
        }
    }

    overlayTapSelector = NSSelectorFromString(@"expandOverlay:didTapInRegion:");
    if ([controller respondsToSelector:overlayTapSelector]) {
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(controller, overlayTapSelector, nil, 3);
        return YES;
    }

    return SCIDirectInvokeObjectArgSelector(controller, NSSelectorFromString(@"_didTapHeaderViewDismissButton:"), nil);
}

static void SCIMarkDirectVisualMessageAsSeen(UIViewController *controller) {
    if (!controller) return;

    id message = SCIDirectCurrentMessageFromController(controller);
    if (!message) {
        SCINotify(kSCINotificationDirectVisualMarkSeen, @"Message not found", nil, @"error_filled", SCINotificationToneError);
        return;
    }

    id responders = [SCIUtils getIvarForObj:controller name:"_eventResponders"];
    if (!responders) responders = SCIKVCObject(controller, @"eventResponders");

    SEL beginPlaybackSelector = NSSelectorFromString(@"visualMessageViewerController:didBeginPlaybackForVisualMessage:atIndex:");
    Class eventHandlerClass = NSClassFromString(@"IGDirectVisualMessageViewerEventHandler");
    NSArray *responderCollection = SCIArrayFromCollection(responders);
    NSMutableArray *orderedResponders = [NSMutableArray array];
    for (id responder in responderCollection ?: (responders ? @[responders] : @[])) {
        if (eventHandlerClass && [responder isKindOfClass:eventHandlerClass]) {
            [orderedResponders addObject:responder];
        }
    }
    for (id responder in responderCollection ?: (responders ? @[responders] : @[])) {
        if (![orderedResponders containsObject:responder]) {
            [orderedResponders addObject:responder];
        }
    }

    BOOL dispatched = NO;

    SCIPendingDirectVisualMessageToMarkSeen = message;
    @try {
        for (id responder in orderedResponders) {
            if ([responder respondsToSelector:beginPlaybackSelector]) {
                dispatched = YES;
                ((void (*)(id, SEL, id, id, NSInteger))objc_msgSend)(responder, beginPlaybackSelector, controller, message, 0);
            }
        }
    } @finally {
        SCIPendingDirectVisualMessageToMarkSeen = nil;
    }
    if (!dispatched) {
        SCINotify(kSCINotificationDirectVisualMarkSeen, @"Unable to mark as seen", nil, @"error_filled", SCINotificationToneError);
        return;
    }

    if ([SCIUtils getBoolPref:@"msgs_advance_visual_on_seen"]) {
        __weak UIViewController *weakController = controller;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIDirectAdvanceVisualViewer(weakController);
        });
    }

    SCINotify(kSCINotificationDirectVisualMarkSeen, @"Marked as seen", nil, @"circle_check_filled", SCINotificationToneSuccess);
}

static void SCIInstallDirectSeenButton(UIViewController *controller) {
    UIView *overlay = SCIDirectOverlayViewFromController(controller);
    if (!overlay) return;

    UIButton *seenButton = (UIButton *)[overlay viewWithTag:kSCIDirectSeenButtonTag];
    if (!SCIShouldShowDirectVisualSeenButton()) {
        [seenButton removeFromSuperview];
        return;
    }

    if (![seenButton isKindOfClass:SCIChromeButton.class]) {
        [seenButton removeFromSuperview];
        seenButton = SCIStorySeenButtonWithTag(overlay, kSCIDirectSeenButtonTag);
        seenButton.tag = kSCIDirectSeenButtonTag;
        seenButton.adjustsImageWhenHighlighted = YES;
        UIImage *seenImage = [SCIAssetUtils instagramIconNamed:kSCISeenMessagesBarIconResource pointSize:24.0];
        SCISetSeenButtonImage(seenButton, seenImage, @"Direct seen custom icon assigned");
        [seenButton addTarget:controller action:@selector(sci_didTapDirectSeenButton:) forControlEvents:UIControlEventTouchUpInside];
    }

    seenButton.translatesAutoresizingMaskIntoConstraints = NO;
    SCIApplyStorySeenButtonStyle(seenButton);

    CGFloat size = 44.0;
    CGFloat bottomOffset = SCIDirectBottomOffset(controller);
    UIButton *actionButton = (UIButton *)[overlay viewWithTag:kSCIDirectActionButtonTag];
    BOOL actionVisible = [actionButton isKindOfClass:[UIButton class]]
        && !actionButton.hidden
        && actionButton.superview == overlay
        && CGRectGetWidth(actionButton.bounds) > 0.0
        && CGRectGetHeight(actionButton.bounds) > 0.0;

    NSLayoutConstraint *bottomConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenBottomConstraintAssocKey);
    NSLayoutConstraint *trailingOverlayConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenTrailingOverlayConstraintAssocKey);
    NSLayoutConstraint *trailingActionConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenTrailingActionConstraintAssocKey);
    NSLayoutConstraint *centerYActionConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenCenterYActionConstraintAssocKey);
    NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenWidthConstraintAssocKey);
    NSLayoutConstraint *heightConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenHeightConstraintAssocKey);
    UIButton *anchoredActionButton = objc_getAssociatedObject(seenButton, kSCIDirectSeenAnchoredActionButtonAssocKey);

    if (!bottomConstraint || !trailingOverlayConstraint || !widthConstraint || !heightConstraint) {
        bottomConstraint = [seenButton.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor constant:-bottomOffset];
        trailingOverlayConstraint = [seenButton.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-10.0];
        widthConstraint = [seenButton.widthAnchor constraintEqualToConstant:size];
        heightConstraint = [seenButton.heightAnchor constraintEqualToConstant:size];

        [NSLayoutConstraint activateConstraints:@[
            bottomConstraint,
            trailingOverlayConstraint,
            widthConstraint,
            heightConstraint
        ]];

        objc_setAssociatedObject(seenButton, kSCIDirectSeenBottomConstraintAssocKey, bottomConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(seenButton, kSCIDirectSeenTrailingOverlayConstraintAssocKey, trailingOverlayConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(seenButton, kSCIDirectSeenWidthConstraintAssocKey, widthConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(seenButton, kSCIDirectSeenHeightConstraintAssocKey, heightConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (actionVisible && (!trailingActionConstraint || anchoredActionButton != actionButton)) {
        if (trailingActionConstraint) {
            trailingActionConstraint.active = NO;
        }
        trailingActionConstraint = [seenButton.trailingAnchor constraintEqualToAnchor:actionButton.leadingAnchor constant:-5.0];
        objc_setAssociatedObject(seenButton, kSCIDirectSeenTrailingActionConstraintAssocKey, trailingActionConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(seenButton, kSCIDirectSeenAnchoredActionButtonAssocKey, actionButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (actionVisible && (!centerYActionConstraint || anchoredActionButton != actionButton)) {
        if (centerYActionConstraint) {
            centerYActionConstraint.active = NO;
        }
        centerYActionConstraint = [seenButton.centerYAnchor constraintEqualToAnchor:actionButton.centerYAnchor];
        objc_setAssociatedObject(seenButton, kSCIDirectSeenCenterYActionConstraintAssocKey, centerYActionConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    bottomConstraint.constant = -bottomOffset;
    trailingOverlayConstraint.constant = -10.0;
    widthConstraint.constant = size;
    heightConstraint.constant = size;

    if (actionVisible && trailingActionConstraint) {
        bottomConstraint.active = NO;
        trailingOverlayConstraint.active = NO;
        trailingActionConstraint.active = YES;
        if (centerYActionConstraint) centerYActionConstraint.active = YES;
    } else {
        if (centerYActionConstraint) centerYActionConstraint.active = NO;
        if (trailingActionConstraint) trailingActionConstraint.active = NO;
        trailingOverlayConstraint.active = YES;
        bottomConstraint.active = YES;
    }

    [overlay bringSubviewToFront:seenButton];
}

%group SCIDirectVisualSeenButtonHooks

%hook IGDirectVisualMessageViewerController
- (void)viewDidLayoutSubviews {
    %orig;
    if (!SCIDirectSeenHooksNeeded()) return;
    UIView *inputView = SCIDirectInputViewFromController((UIViewController *)self);
    SCIEnsureDirectVisualInputAlphaObserver((UIViewController *)self);
    SCIInstallDirectSeenButton((UIViewController *)self);
    SCIUpdateDirectVisualButtonsAlpha((UIViewController *)self, inputView ? inputView.alpha : 1.0);
    __weak UIViewController *weakController = (UIViewController *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *strongController = weakController;
        if (!strongController) return;
        UIView *strongInputView = SCIDirectInputViewFromController(strongController);
        SCIInstallDirectSeenButton(strongController);
        SCIUpdateDirectVisualButtonsAlpha(strongController, strongInputView ? strongInputView.alpha : 1.0);
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (!SCIDirectSeenHooksNeeded()) {
        %orig(keyPath, object, change, context);
        return;
    }
    if (context == kSCIDirectVisualInputAlphaObserverContext && [keyPath isEqualToString:@"alpha"]) {
        CGFloat alpha = 1.0;
        id newAlphaValue = change[NSKeyValueChangeNewKey];
        if ([newAlphaValue respondsToSelector:@selector(floatValue)]) {
            alpha = [newAlphaValue floatValue];
        } else if ([object isKindOfClass:[UIView class]]) {
            alpha = ((UIView *)object).alpha;
        }
        SCIUpdateDirectVisualButtonsAlpha((UIViewController *)self, alpha);
        return;
    }

    %orig(keyPath, object, change, context);
}

- (void)dealloc {
    SCIRemoveDirectVisualInputAlphaObserverIfNeeded((UIViewController *)self);
    %orig;
}

%new - (void)sci_didTapDirectSeenButton:(UIButton *)sender {
    (void)sender;
    SCIPlayButtonTappedHaptic();
    SCIMarkDirectVisualMessageAsSeen((UIViewController *)self);
}
%end

%end

void SCIInstallDirectVisualSeenButtonHooksIfNeeded(void) {
    if (!SCIDirectSeenHooksNeeded()) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIDirectVisualSeenButtonHooks);
    });
}

#import "../../Utils.h"

#import <objc/message.h>
#import <objc/runtime.h>

static char kSCISwipeCloseCommentsInstalledKey;
static char kSCISwipeCloseCommentsTargetKey;

static NSString * const kSCISwipeCloseCommentsDirectionKey = @"general_comments_swipe_close_direction";
static NSString * const kSCISwipeCloseCommentsDirectionLeft = @"left";
static NSString * const kSCISwipeCloseCommentsDirectionRight = @"right";
static NSString * const kSCISwipeCloseCommentsDirectionBoth = @"both";

typedef NS_OPTIONS(NSUInteger, SCISwipeCloseCommentsDirection) {
    SCISwipeCloseCommentsDirectionLeft = 1 << 0,
    SCISwipeCloseCommentsDirectionRight = 1 << 1,
};

static CGFloat const kSCICommentsSwipeMinimumHorizontalDistance = 8.0;
static CGFloat const kSCICommentsSwipeCommitProgress = 0.3;
static CGFloat const kSCICommentsSwipeVelocityCommitMinimumDistance = 70.0;
static CGFloat const kSCICommentsSwipeCommitVelocity = 800.0;

static SCISwipeCloseCommentsDirection SCISwipeCloseCommentsDirectionFromPref(void) {
    NSString *value = [SCIUtils getStringPref:kSCISwipeCloseCommentsDirectionKey];
    if ([value isEqualToString:kSCISwipeCloseCommentsDirectionLeft]) {
        return SCISwipeCloseCommentsDirectionLeft;
    }
    if ([value isEqualToString:kSCISwipeCloseCommentsDirectionRight]) {
        return SCISwipeCloseCommentsDirectionRight;
    }
    if ([value isEqualToString:kSCISwipeCloseCommentsDirectionBoth]) {
        return SCISwipeCloseCommentsDirectionLeft | SCISwipeCloseCommentsDirectionRight;
    }
    return SCISwipeCloseCommentsDirectionLeft | SCISwipeCloseCommentsDirectionRight;
}

static NSString *SCICommentsSwipeDescribe(id object) {
    if (!object) return @"nil";
    return [NSString stringWithFormat:@"%@<%p>", NSStringFromClass([object class]), object];
}

static NSString *SCICommentsSwipeStateName(UIGestureRecognizerState state) {
    switch (state) {
        case UIGestureRecognizerStatePossible: return @"possible";
        case UIGestureRecognizerStateBegan: return @"began";
        case UIGestureRecognizerStateChanged: return @"changed";
        case UIGestureRecognizerStateEnded: return @"ended";
        case UIGestureRecognizerStateCancelled: return @"cancelled";
        case UIGestureRecognizerStateFailed: return @"failed";
        default: return [NSString stringWithFormat:@"unknown(%ld)", (long)state];
    }
}

static CGFloat SCICommentsSwipeSignedHorizontalProgress(CGFloat translationX, SCISwipeCloseCommentsDirection direction) {
    if ((direction & SCISwipeCloseCommentsDirectionLeft) && translationX < 0.0) {
        return -translationX;
    }
    if ((direction & SCISwipeCloseCommentsDirectionRight) && translationX > 0.0) {
        return translationX;
    }
    return 0.0;
}

static CGFloat SCICommentsSwipeSignedHorizontalVelocity(CGFloat velocityX, SCISwipeCloseCommentsDirection direction) {
    if ((direction & SCISwipeCloseCommentsDirectionLeft) && velocityX < 0.0) {
        return -velocityX;
    }
    if ((direction & SCISwipeCloseCommentsDirectionRight) && velocityX > 0.0) {
        return velocityX;
    }
    return 0.0;
}

static NSNumber *SCICommentsSwipeNumberFromSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        double (*sendDouble)(id, SEL) = (double (*)(id, SEL))objc_msgSend;
        return @(sendDouble(object, selector));
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSNumber *SCICommentsSwipeUnsignedNumberFromSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        unsigned long long (*sendUnsigned)(id, SEL) = (unsigned long long (*)(id, SEL))objc_msgSend;
        return @(sendUnsigned(object, selector));
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSNumber *SCICommentsSwipeBoolNumberFromSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        BOOL (*sendBool)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
        return @(sendBool(object, selector));
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL SCICommentsSwipeStringLooksCommentRelated(NSString *value) {
    return [value rangeOfString:@"comment" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL SCICommentsSwipeStringLooksShareRelated(NSString *value) {
    if (value.length == 0) return NO;
    NSArray<NSString *> *patterns = @[
        @"share",
        @"IGExternalShare",
        @"ShareSheet",
        @"Copy link",
        @"WhatsApp",
        @"Add to story"
    ];
    for (NSString *pattern in patterns) {
        if ([value rangeOfString:pattern options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static BOOL SCICommentsSwipeViewTreeLooksShareRelated(UIView *view, NSUInteger depth, NSUInteger *visitedCount, NSString **reason) {
    if (!view || depth > 8 || *visitedCount > 180) {
        return NO;
    }
    *visitedCount += 1;

    NSString *className = NSStringFromClass([view class]);
    if (SCICommentsSwipeStringLooksShareRelated(className)) {
        if (reason) *reason = [NSString stringWithFormat:@"view class %@", className];
        return YES;
    }

    NSString *identifier = view.accessibilityIdentifier;
    if (SCICommentsSwipeStringLooksShareRelated(identifier)) {
        if (reason) *reason = [NSString stringWithFormat:@"view accessibilityIdentifier %@", identifier];
        return YES;
    }

    NSString *label = view.accessibilityLabel;
    if (SCICommentsSwipeStringLooksShareRelated(label)) {
        if (reason) *reason = [NSString stringWithFormat:@"view accessibilityLabel %@", label];
        return YES;
    }

    UIResponder *responder = view.nextResponder;
    if (responder && SCICommentsSwipeStringLooksShareRelated(NSStringFromClass([responder class]))) {
        if (reason) *reason = [NSString stringWithFormat:@"nextResponder %@", NSStringFromClass([responder class])];
        return YES;
    }

    for (UIView *subview in view.subviews) {
        if (SCICommentsSwipeViewTreeLooksShareRelated(subview, depth + 1, visitedCount, reason)) {
            return YES;
        }
    }

    return NO;
}

static BOOL SCICommentsSwipeControllerTreeLooksShareRelated(UIViewController *controller, NSUInteger depth, NSString **reason) {
    if (!controller || depth > 5) {
        return NO;
    }

    NSString *className = NSStringFromClass([controller class]);
    if (SCICommentsSwipeStringLooksShareRelated(className)) {
        if (reason) *reason = [NSString stringWithFormat:@"controller class %@", className];
        return YES;
    }

    NSString *title = controller.title;
    if (SCICommentsSwipeStringLooksShareRelated(title)) {
        if (reason) *reason = [NSString stringWithFormat:@"controller title %@", title];
        return YES;
    }

    for (UIViewController *child in controller.childViewControllers) {
        if (SCICommentsSwipeControllerTreeLooksShareRelated(child, depth + 1, reason)) {
            return YES;
        }
    }

    UIViewController *presented = controller.presentedViewController;
    if (presented && presented != controller) {
        if (SCICommentsSwipeControllerTreeLooksShareRelated(presented, depth + 1, reason)) {
            return YES;
        }
    }

    return NO;
}

static BOOL SCICommentsSwipeViewTreeLooksCommentRelated(UIView *view, NSUInteger depth, NSUInteger *visitedCount, NSString **reason) {
    if (!view || depth > 8 || *visitedCount > 180) {
        return NO;
    }
    *visitedCount += 1;

    NSString *className = NSStringFromClass([view class]);
    if (SCICommentsSwipeStringLooksCommentRelated(className)) {
        if (reason) *reason = [NSString stringWithFormat:@"view class %@", className];
        return YES;
    }

    NSString *identifier = view.accessibilityIdentifier;
    if (SCICommentsSwipeStringLooksCommentRelated(identifier)) {
        if (reason) *reason = [NSString stringWithFormat:@"view accessibilityIdentifier %@", identifier];
        return YES;
    }

    NSString *label = view.accessibilityLabel;
    if (SCICommentsSwipeStringLooksCommentRelated(label)) {
        if (reason) *reason = [NSString stringWithFormat:@"view accessibilityLabel %@", label];
        return YES;
    }

    UIResponder *responder = view.nextResponder;
    if (responder && SCICommentsSwipeStringLooksCommentRelated(NSStringFromClass([responder class]))) {
        if (reason) *reason = [NSString stringWithFormat:@"nextResponder %@", NSStringFromClass([responder class])];
        return YES;
    }

    for (UIView *subview in view.subviews) {
        if (SCICommentsSwipeViewTreeLooksCommentRelated(subview, depth + 1, visitedCount, reason)) {
            return YES;
        }
    }

    return NO;
}

static BOOL SCICommentsSwipeControllerTreeLooksCommentRelated(UIViewController *controller, NSUInteger depth, NSString **reason) {
    if (!controller || depth > 5) {
        return NO;
    }

    NSString *className = NSStringFromClass([controller class]);
    if (SCICommentsSwipeStringLooksCommentRelated(className)) {
        if (reason) *reason = [NSString stringWithFormat:@"controller class %@", className];
        return YES;
    }

    NSString *title = controller.title;
    if (SCICommentsSwipeStringLooksCommentRelated(title)) {
        if (reason) *reason = [NSString stringWithFormat:@"controller title %@", title];
        return YES;
    }

    for (UIViewController *child in controller.childViewControllers) {
        if (SCICommentsSwipeControllerTreeLooksCommentRelated(child, depth + 1, reason)) {
            return YES;
        }
    }

    UIViewController *presented = controller.presentedViewController;
    if (presented && presented != controller) {
        if (SCICommentsSwipeControllerTreeLooksCommentRelated(presented, depth + 1, reason)) {
            return YES;
        }
    }

    return NO;
}

static UIView *SCICommentsSwipeContentView(UIViewController *controller) {
    UIView *root = controller.view;
    if ([root.accessibilityIdentifier isEqualToString:@"ig-partial-modal-sheet-view-controller-content"]) {
        return root;
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root ?: [UIView new]];
    NSUInteger index = 0;
    while (index < queue.count && index < 160) {
        UIView *view = queue[index++];
        if ([view.accessibilityIdentifier isEqualToString:@"ig-partial-modal-sheet-view-controller-content"]) {
            return view;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return root;
}

static UIView *SCICommentsSwipeSheetContainerView(UIViewController *controller, UIView *contentView) {
    if (!controller) return contentView;

    UIView *root = controller.view;
    CGRect rootWindowFrame = root ? [root convertRect:root.bounds toView:nil] : CGRectZero;
    CGFloat screenHeight = CGRectGetHeight([UIScreen mainScreen].bounds);
    if (screenHeight < 1.0) screenHeight = CGRectGetHeight(rootWindowFrame);

    UIView *bestView = nil;
    UIView *view = contentView;
    while (view && view != root) {
        CGRect windowFrame = [view convertRect:view.bounds toView:nil];
        BOOL hasUsefulSize = CGRectGetHeight(windowFrame) > 80.0 && CGRectGetWidth(windowFrame) > 80.0;
        BOOL notFullScreenWrapper = CGRectGetMinY(windowFrame) > 8.0 || CGRectGetHeight(windowFrame) < screenHeight * 0.94;
        if (hasUsefulSize && notFullScreenWrapper) {
            bestView = view;
            break;
        }
        view = view.superview;
    }

    if (bestView) {
        return bestView;
    }

    view = contentView;
    while (view.superview && view.superview != root) {
        view = view.superview;
    }
    return contentView ?: view ?: root;
}

static CGFloat SCICommentsSwipeDismissDistanceForView(UIViewController *controller, UIView *sheetView) {
    CGRect rootFrame = [controller.view convertRect:controller.view.bounds toView:nil];
    CGRect sheetFrame = [sheetView convertRect:sheetView.bounds toView:nil];
    CGFloat screenHeight = CGRectGetHeight(rootFrame);
    if (screenHeight < 1.0) {
        screenHeight = CGRectGetHeight([UIScreen mainScreen].bounds);
    }

    CGFloat distanceToMoveTopBelowScreen = screenHeight - CGRectGetMinY(sheetFrame) + 36.0;
    return MAX(distanceToMoveTopBelowScreen, 180.0);
}

@interface SCISwipeCloseCommentsTarget : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic) SCISwipeCloseCommentsDirection direction;
@property (nonatomic) BOOL hasLoggedSheetState;
@property (nonatomic, weak) UIView *activeSheetView;
@property (nonatomic) CGAffineTransform originalTransform;
@property (nonatomic) CGFloat activeDismissDistance;
@end

@implementation SCISwipeCloseCommentsTarget

- (void)logSheetStateIfNeededForController:(UIViewController *)controller contentView:(UIView *)contentView {
    if (self.hasLoggedSheetState) {
        return;
    }
    self.hasLoggedSheetState = YES;

    SCILog(@"General", @"[SCInsta CommentsSwipe] Sheet state controller=%@ content=%@ target=%@ sheetOffset=%@ disablePanToClose=%@ disableVerticalPan=%@ shouldSuppressDismiss=%@",
           SCICommentsSwipeDescribe(controller),
           SCICommentsSwipeDescribe(contentView),
           SCICommentsSwipeUnsignedNumberFromSelector(controller, @selector(targetSheetState)) ?: @"n/a",
           SCICommentsSwipeNumberFromSelector(controller, @selector(sheetOffset)) ?: @"n/a",
           SCICommentsSwipeBoolNumberFromSelector(controller, @selector(disablePanToClose)) ?: @"n/a",
           SCICommentsSwipeBoolNumberFromSelector(controller, @selector(disableVerticalPan)) ?: @"n/a",
           SCICommentsSwipeBoolNumberFromSelector(controller, @selector(shouldSuppressDismiss)) ?: @"n/a");
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *contentView = gesture.view;
    UIViewController *controller = self.controller ?: [SCIUtils viewControllerForView:contentView];
    CGPoint translation = [gesture translationInView:contentView];
    CGPoint velocity = [gesture velocityInView:contentView];

    CGFloat verticalTranslation = SCICommentsSwipeSignedHorizontalProgress(translation.x, self.direction);
    CGFloat verticalVelocity = SCICommentsSwipeSignedHorizontalVelocity(velocity.x, self.direction);

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.hasLoggedSheetState = NO;
        [self logSheetStateIfNeededForController:controller contentView:contentView];
        self.activeSheetView = SCICommentsSwipeSheetContainerView(controller, contentView);
        self.originalTransform = self.activeSheetView.transform;
        self.activeDismissDistance = SCICommentsSwipeDismissDistanceForView(controller, self.activeSheetView);
        CGRect sheetWindowFrame = [self.activeSheetView convertRect:self.activeSheetView.bounds toView:nil];
        CGRect contentWindowFrame = [contentView convertRect:contentView.bounds toView:nil];
        CGRect rootWindowFrame = [controller.view convertRect:controller.view.bounds toView:nil];
        SCILog(@"General", @"[SCInsta CommentsSwipe] Interactive begin sheet=%@ sheetFrame=%@ contentFrame=%@ rootFrame=%@ dismissDistance=%.1f originalTransform=%@",
               SCICommentsSwipeDescribe(self.activeSheetView),
               NSStringFromCGRect(sheetWindowFrame),
               NSStringFromCGRect(contentWindowFrame),
               NSStringFromCGRect(rootWindowFrame),
               self.activeDismissDistance,
               NSStringFromCGAffineTransform(self.originalTransform));
    }

    UIView *sheetView = self.activeSheetView ?: SCICommentsSwipeSheetContainerView(controller, contentView);
    CGFloat clampedTranslation = MAX(0.0, MIN(verticalTranslation, self.activeDismissDistance));
    CGFloat progress = self.activeDismissDistance > 1.0 ? clampedTranslation / self.activeDismissDistance : 0.0;

    BOOL shouldLog = gesture.state == UIGestureRecognizerStateBegan ||
                     gesture.state == UIGestureRecognizerStateEnded ||
                     gesture.state == UIGestureRecognizerStateCancelled ||
                     gesture.state == UIGestureRecognizerStateFailed;
    if (shouldLog) {
        SCILog(@"General", @"[SCInsta CommentsSwipe] Interactive pan state=%@ rawX=%.1f rawVX=%.1f mappedY=%.1f mappedVY=%.1f progress=%.2f controller=%@ sheet=%@",
               SCICommentsSwipeStateName(gesture.state),
               translation.x,
               velocity.x,
               clampedTranslation,
               verticalVelocity,
               progress,
               SCICommentsSwipeDescribe(controller),
               SCICommentsSwipeDescribe(sheetView));
    }

    BOOL finished = gesture.state == UIGestureRecognizerStateEnded ||
                    gesture.state == UIGestureRecognizerStateCancelled ||
                    gesture.state == UIGestureRecognizerStateFailed;
    if (!finished) {
        sheetView.transform = CGAffineTransformTranslate(self.originalTransform, 0.0, clampedTranslation);
        return;
    }

    BOOL distanceCommitted = progress >= kSCICommentsSwipeCommitProgress;
    BOOL velocityCommitted = clampedTranslation >= kSCICommentsSwipeVelocityCommitMinimumDistance && verticalVelocity >= kSCICommentsSwipeCommitVelocity;
    BOOL committed = gesture.state == UIGestureRecognizerStateEnded && (distanceCommitted || velocityCommitted);
    if (!committed) {
        [UIView animateWithDuration:0.24 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
            sheetView.transform = self.originalTransform;
        } completion:nil];
        SCILog(@"General", @"[SCInsta CommentsSwipe] Interactive cancel progress=%.2f translationY=%.1f velocityY=%.1f distanceCommitted=%d velocityCommitted=%d",
               progress,
               clampedTranslation,
               verticalVelocity,
               distanceCommitted,
               velocityCommitted);
        return;
    }

    SCILog(@"General", @"[SCInsta CommentsSwipe] Interactive commit progress=%.2f translationY=%.1f velocityY=%.1f distanceCommitted=%d velocityCommitted=%d usingNativeDismiss=1",
           progress,
           clampedTranslation,
           verticalVelocity,
           distanceCommitted,
           velocityCommitted);

    sheetView.userInteractionEnabled = NO;
    [controller dismissViewControllerAnimated:YES completion:^{
        sheetView.userInteractionEnabled = YES;
        sheetView.transform = self.originalTransform;
    }];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    (void)gestureRecognizer;
    UIView *view = touch.view;
    while (view) {
        if ([view isKindOfClass:[UIControl class]]) {
            return NO;
        }
        view = view.superview;
    }
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (![gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return YES;
    }

    UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
    CGPoint translation = [pan translationInView:pan.view];
    CGPoint velocity = [pan velocityInView:pan.view];
    CGFloat allowedProgress = SCICommentsSwipeSignedHorizontalProgress(translation.x, self.direction);
    CGFloat allowedVelocity = SCICommentsSwipeSignedHorizontalVelocity(velocity.x, self.direction);
    BOOL horizontalEnough = fabs(velocity.x) > fabs(velocity.y) * 1.15 || fabs(translation.x) > fabs(translation.y) * 1.15;
    BOOL shouldBegin = horizontalEnough && (allowedProgress >= kSCICommentsSwipeMinimumHorizontalDistance || allowedVelocity > 160.0);

    SCILog(@"General", @"[SCInsta CommentsSwipe] Pan shouldBegin=%d translation=(%.1f, %.1f) velocity=(%.1f, %.1f) allowedProgress=%.1f allowedVelocity=%.1f direction=%lu",
           shouldBegin,
           translation.x,
           translation.y,
           velocity.x,
           velocity.y,
           allowedProgress,
           allowedVelocity,
           (unsigned long)self.direction);
    return shouldBegin;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return YES;
}

@end

static void SCIInstallSwipeCloseCommentsGesture(UIViewController *controller) {
    if (![SCIUtils getBoolPref:@"general_comments_swipe_close"]) {
        return;
    }

    UIView *contentView = SCICommentsSwipeContentView(controller);
    if (!contentView) {
        SCIWarnLog(@"General", @"[SCInsta CommentsSwipe] Skipping %@: content view not found", SCICommentsSwipeDescribe(controller));
        return;
    }

    if ([objc_getAssociatedObject(contentView, &kSCISwipeCloseCommentsInstalledKey) boolValue]) {
        return;
    }

    NSString *excludedReason = nil;
    NSUInteger excludedVisitedCount = 0;
    if (SCICommentsSwipeControllerTreeLooksShareRelated(controller, 0, &excludedReason) ||
        SCICommentsSwipeViewTreeLooksShareRelated(contentView, 0, &excludedVisitedCount, &excludedReason)) {
        SCILog(@"General", @"[SCInsta CommentsSwipe] Skipping %@ content=%@: share-sheet surface detected reason=%@ visited=%lu",
               SCICommentsSwipeDescribe(controller),
               SCICommentsSwipeDescribe(contentView),
               excludedReason ?: @"unknown",
               (unsigned long)excludedVisitedCount);
        return;
    }

    NSString *reason = nil;
    if (!SCICommentsSwipeControllerTreeLooksCommentRelated(controller, 0, &reason)) {
        NSUInteger visitedCount = 0;
        if (!SCICommentsSwipeViewTreeLooksCommentRelated(contentView, 0, &visitedCount, &reason)) {
            SCILog(@"General", @"[SCInsta CommentsSwipe] Skipping %@ content=%@: no comment-related controller/view found, visited=%lu",
                   SCICommentsSwipeDescribe(controller),
                   SCICommentsSwipeDescribe(contentView),
                   (unsigned long)visitedCount);
            return;
        }
    }

    SCISwipeCloseCommentsTarget *target = [[SCISwipeCloseCommentsTarget alloc] init];
    target.controller = controller;
    target.direction = SCISwipeCloseCommentsDirectionFromPref();

    if (target.direction == 0) {
        SCIWarnLog(@"General", @"[SCInsta CommentsSwipe] Skipping %@: no swipe directions enabled", SCICommentsSwipeDescribe(controller));
        return;
    }

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:target action:@selector(handlePan:)];
    pan.delegate = target;
    pan.cancelsTouchesInView = NO;
    [contentView addGestureRecognizer:pan];

    objc_setAssociatedObject(contentView, &kSCISwipeCloseCommentsTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(contentView, &kSCISwipeCloseCommentsInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    SCILog(@"General", @"[SCInsta CommentsSwipe] Installed horizontal pan recognizer on content=%@ controller=%@ directionPref=%@ directionMask=%lu reason=%@ existingGestures=%lu",
           SCICommentsSwipeDescribe(contentView),
           SCICommentsSwipeDescribe(controller),
           [SCIUtils getStringPref:kSCISwipeCloseCommentsDirectionKey] ?: @"both",
           (unsigned long)target.direction,
           reason ?: @"unknown",
           (unsigned long)contentView.gestureRecognizers.count);
}

%group SCISwipeCloseCommentsHooks

%hook IGDSDefaultPartialModalSheetViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIInstallSwipeCloseCommentsGesture((UIViewController *)self);

    __weak UIViewController *weakController = (UIViewController *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *controller = weakController;
        if (controller) {
            SCIInstallSwipeCloseCommentsGesture(controller);
        }
    });
}

%end

%end

extern "C" void SCIInstallSwipeCloseCommentsHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"general_comments_swipe_close"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCILog(@"General", @"[SCInsta CommentsSwipe] Installing hooks");
        %init(SCISwipeCloseCommentsHooks);
    });
}

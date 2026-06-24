#import "../../Utils.h"
#import "../../InstagramHeaders.h"

#import <objc/message.h>

static NSString * const kSCIHideCommentGiftsButtonPref = @"general_comments_hide_gifts_button";

static inline BOOL SCIHideCommentGiftsButtonEnabled(void) {
    return [SCIUtils getBoolPref:kSCIHideCommentGiftsButtonPref];
}

static BOOL SCIViewMatchesCommentGiftButton(UIView *view) {
    if (![view isKindOfClass:[UIControl class]]) return NO;

    NSString *label = view.accessibilityLabel;
    if (![label isEqualToString:@"Gifts button"]) return NO;

    NSString *className = NSStringFromClass([view class]);
    return [className containsString:@"IGBouncyIconButton"] ||
           [className containsString:@"IGBouncyButton"] ||
           [view isKindOfClass:[UIControl class]];
}

static UIView *SCICommentGiftButtonInView(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return nil;
    if (SCIViewMatchesCommentGiftButton(view)) return view;

    for (UIView *subview in view.subviews) {
        UIView *candidate = SCICommentGiftButtonInView(subview, depth + 1);
        if (candidate) return candidate;
    }

    return nil;
}

static UIView *SCICommentGiftButtonFromCandidate(id candidate) {
    if (![candidate isKindOfClass:[UIView class]]) return nil;

    UIView *view = (UIView *)candidate;
    if (SCIViewMatchesCommentGiftButton(view)) return view;

    UIView *nested = SCICommentGiftButtonInView(view, 0);
    return nested ?: view;
}

static UIView *SCICommentComposerGiftButton(UIView *composerView) {
    for (NSString *ivarName in @[@"_lazyGiftButton", @"_giftButton"]) {
        UIView *candidate = SCICommentGiftButtonFromCandidate([SCIUtils getIvarForObj:composerView name:ivarName.UTF8String]);
        if (candidate) return candidate;
    }

    return SCICommentGiftButtonInView(composerView, 0);
}

static void SCISetCommentComposerGiftButtonEnabled(id composerView, BOOL enabled) {
    SEL selector = @selector(setGiftButtonEnabled:);
    if ([composerView respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(composerView, selector, enabled);
    }
}

static void SCIHideCommentComposerGiftButton(UIView *composerView) {
    if (!SCIHideCommentGiftsButtonEnabled()) return;

    SCISetCommentComposerGiftButtonEnabled(composerView, NO);

    UIView *giftButton = SCICommentComposerGiftButton(composerView);
    if (!giftButton) return;

    CGRect giftFrame = [giftButton.superview convertRect:giftButton.frame toView:composerView];
    giftButton.hidden = YES;
    giftButton.userInteractionEnabled = NO;
    giftButton.alpha = 0.0;

    UIView *textView = [SCIUtils getIvarForObj:composerView name:"_growingTextView"];
    UIView *backgroundView = [SCIUtils getIvarForObj:composerView name:"_roundedBackgroundImageView"];
    if (![textView isKindOfClass:[UIView class]]) return;

    CGRect textFrame = [textView.superview convertRect:textView.frame toView:composerView];
    CGFloat trailingTarget = CGRectGetMaxX(giftFrame);
    if (trailingTarget <= CGRectGetMaxX(textFrame) + 1.0) return;
    if (CGRectGetMinX(giftFrame) < CGRectGetMaxX(textFrame) - 2.0) return;

    CGRect expandedTextFrame = textFrame;
    expandedTextFrame.size.width = trailingTarget - CGRectGetMinX(textFrame);
    textView.frame = [composerView convertRect:expandedTextFrame toView:textView.superview];

    if ([backgroundView isKindOfClass:[UIView class]]) {
        CGRect backgroundFrame = [backgroundView.superview convertRect:backgroundView.frame toView:composerView];
        if (CGRectGetMaxX(backgroundFrame) <= trailingTarget + 1.0 &&
            CGRectGetMinX(backgroundFrame) <= CGRectGetMinX(textFrame) + 2.0) {
            backgroundFrame.size.width = trailingTarget - CGRectGetMinX(backgroundFrame);
            backgroundView.frame = [composerView convertRect:backgroundFrame toView:backgroundView.superview];
        }
    }
}

%group SCIHideCommentGiftsButtonHooks

%hook IGCommentComposerView

- (void)setGiftButtonEnabled:(BOOL)enabled {
    %orig(SCIHideCommentGiftsButtonEnabled() ? NO : enabled);
}

- (BOOL)giftButtonEnabled {
    if (SCIHideCommentGiftsButtonEnabled()) return NO;
    return %orig;
}

- (void)layoutSubviews {
    if (SCIHideCommentGiftsButtonEnabled()) {
        SCISetCommentComposerGiftButtonEnabled(self, NO);
    }

    %orig;

    SCIHideCommentComposerGiftButton((UIView *)self);
}

- (CGSize)sizeThatFits:(CGSize)size {
    if (SCIHideCommentGiftsButtonEnabled()) {
        SCISetCommentComposerGiftButtonEnabled(self, NO);
    }

    return %orig(size);
}

%end

%end

extern "C" void SCIInstallHideCommentGiftsButtonHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIHideCommentGiftsButtonHooks);
    });
}

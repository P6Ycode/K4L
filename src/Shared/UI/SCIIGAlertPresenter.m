#import "SCIIGAlertPresenter.h"
#include <CoreGraphics/CGGeometry.h>
#include <UIKit/UIKit.h>
#import "../../InstagramHeaders.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import "../../Utils.h"

static const void *kSCIIGAlertInputViewKey = &kSCIIGAlertInputViewKey;
static const void *kSCIIGAlertInputFieldKey = &kSCIIGAlertInputFieldKey;
static const void *kSCIIGAlertInputHasMessageKey = &kSCIIGAlertInputHasMessageKey;
static const void *kSCIIGAlertNativeActionStyleKey = &kSCIIGAlertNativeActionStyleKey;
static const void *kSCIIGAlertNativeActionStylesKey = &kSCIIGAlertNativeActionStylesKey;
static const CGFloat kSCIIGAlertInputHeight = 44.0;
static const CGFloat kSCIIGAlertInputVerticalPadding = 14.0;
static const CGFloat kSCIIGAlertInputBottomPadding = 12.0;
static const CGFloat kSCIIGAlertInputHorizontalInset = 24.0;

static CGSize (*sSCIIGAlertOriginalSizeThatFits)(id, SEL, CGSize);
static void (*sSCIIGAlertOriginalLayoutSubviews)(id, SEL);
static BOOL sSCIIGAlertHooksInstalled;

@implementation SCIIGAlertAction

+ (instancetype)actionWithTitle:(NSString *)title
                          style:(SCIIGAlertActionStyle)style
                        handler:(SCIIGAlertActionHandler)handler {
    SCIIGAlertAction *action = [[self alloc] init];
    action->_title = [title copy];
    action->_style = style;
    action->_handler = [handler copy];
    return action;
}

@end

static UIViewController *SCIIGResolvedPresenter(UIViewController *presenter) {
    return presenter ?: topMostController();
}

static id SCIIGGetIvarObject(id object, const char *name) {
    if (!object || !name) return nil;
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (!ivar) return nil;
    return object_getIvar(object, ivar);
}

static void SCIIGCallActionHandler(SCIIGAlertAction *action) {
    if (action.handler) {
        action.handler();
    }
}

static UIAlertActionStyle SCIUIKitActionStyle(SCIIGAlertActionStyle style) {
    switch (style) {
        case SCIIGAlertActionStyleCancel:
            return UIAlertActionStyleCancel;
        case SCIIGAlertActionStyleDestructive:
            return UIAlertActionStyleDestructive;
        case SCIIGAlertActionStyleDefault:
        default:
            return UIAlertActionStyleDefault;
    }
}

static long long SCIIGNativeAlertActionStyle(SCIIGAlertActionStyle style) {
    switch (style) {
        case SCIIGAlertActionStyleCancel:
            return 2;
        case SCIIGAlertActionStyleDestructive:
            return 1;
        case SCIIGAlertActionStyleDefault:
        default:
            return 0;
    }
}

static long long SCIIGNativeActionSheetStyle(SCIIGAlertActionStyle style) {
    return (long long)style;
}

static BOOL SCIIGActionsContainDestructiveAction(NSArray<SCIIGAlertAction *> *actions) {
    for (SCIIGAlertAction *action in actions) {
        if (action.style == SCIIGAlertActionStyleDestructive) {
            return YES;
        }
    }
    return NO;
}

static long long SCIIGNativeAlertActionStyleForAction(SCIIGAlertAction *action, BOOL containsDestructiveAction) {
    if (containsDestructiveAction && action.style == SCIIGAlertActionStyleCancel) {
        return SCIIGNativeAlertActionStyle(SCIIGAlertActionStyleDefault);
    }
    return SCIIGNativeAlertActionStyle(action.style);
}

static NSString *SCIIGDescriptionTextForInputAlert(NSString *message) {
    return message.length > 0 ? message : nil;
}

static void SCIIGPresentUIKitAlert(UIViewController *presenter,
                                   NSString *title,
                                   NSString *message,
                                   NSArray<SCIIGAlertAction *> *actions,
                                   UIAlertControllerStyle style) {
    UIViewController *resolvedPresenter = SCIIGResolvedPresenter(presenter);
    if (!resolvedPresenter) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:style];
    for (SCIIGAlertAction *action in actions) {
        [alert addAction:[UIAlertAction actionWithTitle:action.title
                                                  style:SCIUIKitActionStyle(action.style)
                                                handler:^(__unused UIAlertAction *uiAction) {
            SCIIGCallActionHandler(action);
        }]];
    }

    if (style == UIAlertControllerStyleActionSheet && alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = resolvedPresenter.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(resolvedPresenter.view.bounds),
                                                                    CGRectGetMidY(resolvedPresenter.view.bounds),
                                                                    1.0,
                                                                    1.0);
    }
    [resolvedPresenter presentViewController:alert animated:YES completion:nil];
}

static void SCIIGPresentUIKitTextInputAlert(UIViewController *presenter,
                                            NSString *title,
                                            NSString *message,
                                            NSString *placeholder,
                                            NSString *initialText,
                                            BOOL autocapitalized,
                                            NSString *confirmTitle,
                                            NSString *cancelTitle,
                                            SCIIGAlertActionStyle confirmStyle,
                                            SCIIGAlertTextHandler confirmBlock,
                                            SCIIGAlertActionHandler cancelBlock) {
    UIViewController *resolvedPresenter = SCIIGResolvedPresenter(presenter);
    if (!resolvedPresenter) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = placeholder;
        field.text = initialText;
        field.autocapitalizationType = autocapitalized ? UITextAutocapitalizationTypeWords : UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:cancelTitle
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        if (cancelBlock) cancelBlock();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:confirmTitle
                                              style:SCIUIKitActionStyle(confirmStyle)
                                            handler:^(__unused UIAlertAction *action) {
        if (confirmBlock) confirmBlock(alert.textFields.firstObject.text);
    }]];
    [resolvedPresenter presentViewController:alert animated:YES completion:nil];
}

static UIView *SCIIGCreateInputView(NSString *placeholder, NSString *initialText, BOOL autocapitalized, UITextField **textFieldOut) {
    Class formFieldContainerClass = NSClassFromString(@"IGDSFormField");
    UIView *inputView = nil;
    UITextField *textField = nil;

    if (formFieldContainerClass && [formFieldContainerClass instancesRespondToSelector:@selector(initWithFrame:)]) {
        inputView = [[formFieldContainerClass alloc] initWithFrame:CGRectMake(0.0, 0.0, 260.0, kSCIIGAlertInputHeight)];
        if ([inputView respondsToSelector:@selector(formField)]) {
            textField = ((id (*)(id, SEL))objc_msgSend)(inputView, @selector(formField));
        }
    }

    if (!textField) {
        Class formFieldClass = NSClassFromString(@"IGFormField");
        if (formFieldClass && [formFieldClass instancesRespondToSelector:@selector(initWithFrame:)]) {
            textField = [[formFieldClass alloc] initWithFrame:CGRectMake(0.0, 0.0, 260.0, kSCIIGAlertInputHeight)];
            inputView = textField;
        }
    }

    if (!textField) {
        textField = [[UITextField alloc] initWithFrame:CGRectMake(0.0, 0.0, 260.0, kSCIIGAlertInputHeight)];
        inputView = textField;
    }

    if (inputView != textField && !textField.superview) {
        textField.frame = CGRectInset(inputView.bounds, 12.0, 0.0);
        textField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [inputView addSubview:textField];
    }
    UIColor *placeholderColor = [UIColor secondaryLabelColor];
    UIColor *fieldBackground = [UIColor colorWithWhite:0.5 alpha:0.1];

    inputView.backgroundColor = fieldBackground;
    inputView.layer.cornerRadius = 16.0;
    inputView.frame = CGRectMake(0.0, 0.0, 260.0, kSCIIGAlertInputHeight);
    inputView.clipsToBounds = NO;

    textField.backgroundColor = UIColor.clearColor;
    textField.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    textField.textColor = UIColor.labelColor;
    textField.tintColor = [UIColor systemBlueColor];
    textField.attributedPlaceholder = placeholder.length > 0
        ? [[NSAttributedString alloc] initWithString:placeholder attributes:@{ NSForegroundColorAttributeName: placeholderColor }]
        : nil;
    textField.text = initialText;
    textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    textField.autocapitalizationType = autocapitalized ? UITextAutocapitalizationTypeWords : UITextAutocapitalizationTypeNone;
    textField.returnKeyType = UIReturnKeyDone;
    textField.borderStyle = UITextBorderStyleNone;
    textField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 12.0, 1.0)];
    textField.leftViewMode = UITextFieldViewModeAlways;

    if (textFieldOut) {
        *textFieldOut = textField;
    }
    return inputView;
}

static CGRect SCIIGFrameInView(UIView *source, UIView *target) {
    if (!source || !target) return CGRectNull;
    return [source.superview convertRect:source.frame toView:target];
}

static CGFloat SCIIGMeasuredBottomForLabelInView(UIView *labelView, UIView *target) {
    if (!labelView || !target) return CGFLOAT_MIN;
    if (labelView.hidden) return CGFLOAT_MIN;
    if (labelView.alpha <= 0.01) return CGFLOAT_MIN;

    // Check if UILabel is empty
    if ([labelView isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)labelView;
        if (label.text.length == 0 && label.attributedText.length == 0) {
            return CGFLOAT_MIN;
        }
    } else if ([labelView respondsToSelector:@selector(text)]) {
        @try {
            NSString *text = [labelView valueForKey:@"text"];
            if ([text isKindOfClass:[NSString class]] && text.length == 0) {
                return CGFLOAT_MIN;
            }
        } @catch (__unused NSException *e) {}
    }

    CGRect frame = SCIIGFrameInView(labelView, target);
    if (CGRectIsNull(frame)) return CGFLOAT_MIN;
    if (frame.size.height <= 0.0) return CGFLOAT_MIN;

    CGFloat measuredHeight = CGRectGetHeight(frame);
    if ([labelView respondsToSelector:@selector(sizeThatFits:)]) {
        CGSize measured = [labelView sizeThatFits:CGSizeMake(CGRectGetWidth(frame), CGFLOAT_MAX)];
        if (measured.height > 0.0) {
            measuredHeight = MAX(measuredHeight, ceil(measured.height));
        }
    }

    return CGRectGetMinY(frame) + measuredHeight;
}

static CGFloat SCIIGMinimumButtonY(NSArray<UIView *> *buttons, UIView *coordinateView) {
    if (!coordinateView || ![buttons isKindOfClass:[NSArray class]] || buttons.count == 0) return CGFLOAT_MAX;

    CGFloat minY = CGFLOAT_MAX;
    for (UIView *button in buttons) {
        CGRect buttonFrame = SCIIGFrameInView(button, coordinateView);
        if (!CGRectIsNull(buttonFrame)) {
            minY = MIN(minY, CGRectGetMinY(buttonFrame));
        }
    }
    return minY;
}

static UIView *SCIIGDirectChildAncestor(UIView *view, UIView *root) {
    if (!view || !root) return nil;
    UIView *current = view;
    while (current && current.superview != root) {
        current = current.superview;
    }
    return (current && current.superview == root) ? current : nil;
}

static void SCIIGShiftButtonRegionToStartAtY(UIView *root, UIView *coordinateView, NSArray<UIView *> *buttons, CGFloat minimumY) {
    if (!root || !coordinateView || ![buttons isKindOfClass:[NSArray class]] || buttons.count == 0) return;

    UIView *inputView = objc_getAssociatedObject(coordinateView, kSCIIGAlertInputViewKey);
    if (!inputView) {
        inputView = objc_getAssociatedObject(root, kSCIIGAlertInputViewKey);
    }

    CGFloat minButtonY = SCIIGMinimumButtonY(buttons, coordinateView);
    if (minButtonY == CGFLOAT_MAX) return;

    CGFloat delta = ceil(minimumY - minButtonY);
    if (delta <= 0.0) return;

    // Collect unique direct-child ancestors of each button within root.
    NSMutableSet<NSValue *> *shifted = [NSMutableSet set];
    for (UIView *button in buttons) {
        UIView *ancestor = SCIIGDirectChildAncestor(button, root);
        if (!ancestor || ancestor == inputView) continue;
        NSValue *key = [NSValue valueWithNonretainedObject:ancestor];
        if ([shifted containsObject:key]) continue;
        [shifted addObject:key];

        CGRect frame = ancestor.frame;
        frame.origin.y += delta;
        ancestor.frame = frame;
    }

    // Also shift any other direct subviews of root that sit in the button region.
    for (UIView *subview in root.subviews) {
        if (subview == inputView) continue;
        NSValue *key = [NSValue valueWithNonretainedObject:subview];
        if ([shifted containsObject:key]) continue;

        CGRect subviewFrame = SCIIGFrameInView(subview, coordinateView);
        if (CGRectIsNull(subviewFrame)) continue;
        if (CGRectGetMinY(subviewFrame) < minButtonY - 10.0) continue;

        [shifted addObject:key];
        CGRect frame = subview.frame;
        frame.origin.y += delta;
        subview.frame = frame;
    }

    // Grow root if shifted content exceeds its bounds.
    CGFloat maxBottom = 0.0;
    for (NSValue *val in shifted) {
        UIView *v = [val nonretainedObjectValue];
        CGFloat bottom = CGRectGetMaxY(v.frame);
        if (bottom > maxBottom) maxBottom = bottom;
    }
    if (maxBottom > CGRectGetHeight(root.bounds)) {
        CGRect rootFrame = root.frame;
        rootFrame.size.height = maxBottom;
        root.frame = rootFrame;
    }
}

static UIColor *SCIIGColorFromClassSelector(NSString *className, SEL selector) {
    Class colorClass = NSClassFromString(className);
    if (!colorClass || ![colorClass respondsToSelector:selector]) return nil;

    id color = ((id (*)(id, SEL))objc_msgSend)(colorClass, selector);
    return [color isKindOfClass:[UIColor class]] ? color : nil;
}

static UIColor *SCIIGDangerActionColor(void) {
    UIColor *color = SCIIGColorFromClassSelector(@"HMDSColor", @selector(dangerText));
    if (color) return color;

    color = SCIIGColorFromClassSelector(@"HMDSColor", @selector(danger));
    if (color) return color;

    color = SCIIGColorFromClassSelector(@"TWDSColor", @selector(negative));
    if (color) return color;

    return [UIColor colorWithDynamicProvider:^UIColor *(__unused UITraitCollection *traits) {
        return [UIColor colorWithRed:1.0 green:0.396 blue:0.490 alpha:1.0];
    }];
}

static NSNumber *SCIIGNativeStyleForButton(id alertView, UIView *button, NSUInteger index) {
    NSMapTable *buttonToActionMap = SCIIGGetIvarObject(alertView, "_buttonToActionMap");
    id nativeAction = nil;
    if ([buttonToActionMap respondsToSelector:@selector(objectForKey:)]) {
        nativeAction = [buttonToActionMap objectForKey:button];
    }

    NSNumber *mappedStyle = nativeAction ? objc_getAssociatedObject(nativeAction, kSCIIGAlertNativeActionStyleKey) : nil;
    if (mappedStyle) return mappedStyle;

    NSArray<NSNumber *> *styles = objc_getAssociatedObject(alertView, kSCIIGAlertNativeActionStylesKey);
    return index < styles.count ? styles[index] : nil;
}

static NSArray<UIView *> *SCIIGFindAlertButtons(id alertView) {
    if (!alertView) return @[];
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];

    // 1. Try _buttons ivar
    id ivarButtons = SCIIGGetIvarObject(alertView, "_buttons");
    if ([ivarButtons isKindOfClass:[NSArray class]]) {
        for (id btn in ivarButtons) {
            if ([btn isKindOfClass:[UIView class]]) {
                [buttons addObject:btn];
            }
        }
        if (buttons.count > 0) return buttons.copy;
    }

    // 2. Try keyEnumerator on _buttonToActionMap
    id buttonToActionMap = SCIIGGetIvarObject(alertView, "_buttonToActionMap");
    if ([buttonToActionMap respondsToSelector:@selector(keyEnumerator)]) {
        for (id key in [buttonToActionMap keyEnumerator]) {
            if ([key isKindOfClass:[UIView class]]) {
                [buttons addObject:key];
            }
        }
        if (buttons.count > 0) return buttons.copy;
    }

    // 3. Recursive subview search
    if ([alertView isKindOfClass:[UIView class]]) {
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:alertView];
        while (queue.count > 0) {
            UIView *current = queue.firstObject;
            [queue removeObjectAtIndex:0];

            NSString *className = NSStringFromClass([current class]);
            if ([current isKindOfClass:[UIButton class]] ||
                [className rangeOfString:@"Button" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [className rangeOfString:@"ActionView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [buttons addObject:current];
            } else {
                [queue addObjectsFromArray:current.subviews];
            }
        }
    }

    return buttons.copy;
}

static void SCIIGStyleAlertButtons(id alertView) {
    NSArray<UIView *> *buttons = SCIIGFindAlertButtons(alertView);
    if (buttons.count == 0) return;

    UIColor *dangerColor = SCIIGDangerActionColor();
    [buttons enumerateObjectsUsingBlock:^(UIView *button, NSUInteger index, __unused BOOL *stop) {
        NSNumber *styleNumber = SCIIGNativeStyleForButton(alertView, button, index);
        if (styleNumber.integerValue != SCIIGAlertActionStyleDestructive) return;

        button.tintColor = dangerColor;
        if ([button respondsToSelector:@selector(setTitleColor:forState:)]) {
            ((void (*)(id, SEL, id, UIControlState))objc_msgSend)(button, @selector(setTitleColor:forState:), dangerColor, UIControlStateNormal);
        }
    }];
}

static CGSize SCIIGAlertHookSizeThatFits(id self, SEL _cmd, CGSize size) {
    CGSize fittingSize = sSCIIGAlertOriginalSizeThatFits ? sSCIIGAlertOriginalSizeThatFits(self, _cmd, size) : CGSizeZero;
    UIView *inputView = objc_getAssociatedObject(self, kSCIIGAlertInputViewKey);
    if (!inputView) {
        return fittingSize;
    }

    CGFloat extraHeight = kSCIIGAlertInputVerticalPadding + kSCIIGAlertInputHeight + kSCIIGAlertInputBottomPadding;
    fittingSize.height += extraHeight;
    return fittingSize;
}

static void SCIIGAlertHookLayoutSubviews(id self, SEL _cmd) {
    if (sSCIIGAlertOriginalLayoutSubviews) {
        sSCIIGAlertOriginalLayoutSubviews(self, _cmd);
    }

    UIView *alertView = (UIView *)self;
    SCIIGStyleAlertButtons(self);

    UIView *inputView = objc_getAssociatedObject(self, kSCIIGAlertInputViewKey);
    if (!inputView) return;

    UIView *scrollView = SCIIGGetIvarObject(self, "_scrollView");
    UIView *container = scrollView ?: alertView;
    if (inputView.superview != container) {
        [inputView removeFromSuperview];
        [container addSubview:inputView];
    }

    UIView *descriptionLabel = SCIIGGetIvarObject(self, "_descriptionLabel");
    UIView *titleLabel = SCIIGGetIvarObject(self, "_titleLabel");
    CGFloat width = MIN(CGRectGetWidth(container.bounds) - (kSCIIGAlertInputHorizontalInset * 2.0), 280.0);
    width = MAX(width, 160.0);

    CGFloat labelBottom = CGFLOAT_MIN;
    CGFloat descBottom = SCIIGMeasuredBottomForLabelInView(descriptionLabel, container);
    CGFloat titleBottom = SCIIGMeasuredBottomForLabelInView(titleLabel, container);

    if (descBottom != CGFLOAT_MIN && titleBottom != CGFLOAT_MIN) {
        labelBottom = MAX(descBottom, titleBottom);
    } else if (descBottom != CGFLOAT_MIN) {
        labelBottom = descBottom;
    } else {
        labelBottom = titleBottom;
    }

    CGFloat y = labelBottom != CGFLOAT_MIN
        ? labelBottom + kSCIIGAlertInputVerticalPadding
        : kSCIIGAlertInputVerticalPadding;
    y = MAX(y, kSCIIGAlertInputVerticalPadding);

    CGFloat x = floor((CGRectGetWidth(container.bounds) - width) / 2.0);
    inputView.frame = CGRectMake(x, y, width, kSCIIGAlertInputHeight);

    NSArray<UIView *> *buttons = SCIIGFindAlertButtons(self);
    CGFloat minimumButtonY = CGRectGetMaxY(inputView.frame) + kSCIIGAlertInputBottomPadding;
    if (scrollView && [buttons isKindOfClass:[NSArray class]]) {
        // Separate buttons into those inside vs outside the scrollView.
        NSMutableArray<UIView *> *buttonsInScroll = [NSMutableArray array];
        NSMutableArray<UIView *> *buttonsOutsideScroll = [NSMutableArray array];
        for (UIView *button in buttons) {
            BOOL insideScroll = NO;
            UIView *walk = button.superview;
            while (walk) {
                if (walk == scrollView) { insideScroll = YES; break; }
                if (walk == alertView) break;
                walk = walk.superview;
            }
            if (insideScroll) {
                [buttonsInScroll addObject:button];
            } else {
                [buttonsOutsideScroll addObject:button];
            }
        }

        // Shift buttons inside the scrollView using scrollView-local coordinates.
        if (buttonsInScroll.count > 0) {
            SCIIGShiftButtonRegionToStartAtY(scrollView, scrollView, buttonsInScroll, minimumButtonY);
            // Grow scrollView content if needed.
            if ([scrollView isKindOfClass:[UIScrollView class]]) {
                CGFloat maxBottom = 0.0;
                for (UIView *sub in scrollView.subviews) {
                    CGFloat bottom = CGRectGetMaxY(sub.frame);
                    if (bottom > maxBottom) maxBottom = bottom;
                }
                ((UIScrollView *)scrollView).contentSize = CGSizeMake(CGRectGetWidth(scrollView.bounds), maxBottom);
            }
        }

        // Shift buttons outside the scrollView using alertView coordinates.
        if (buttonsOutsideScroll.count > 0) {
            CGRect inputFrameInAlert = SCIIGFrameInView(inputView, alertView);
            CGFloat minimumButtonYInAlert = CGRectIsNull(inputFrameInAlert)
                ? minimumButtonY
                : CGRectGetMaxY(inputFrameInAlert) + kSCIIGAlertInputBottomPadding;
            SCIIGShiftButtonRegionToStartAtY(alertView, alertView, buttonsOutsideScroll, minimumButtonYInAlert);
        }
    } else {
        SCIIGShiftButtonRegionToStartAtY(container, container, buttons, minimumButtonY);
    }

    // Trim the alert to tightly fit the actual content after repositioning.
    if (buttons.count > 0) {
        CGFloat maxButtonBottom = 0.0;
        for (UIView *button in buttons) {
            CGRect buttonFrameInAlert = SCIIGFrameInView(button, alertView);
            if (!CGRectIsNull(buttonFrameInAlert)) {
                CGFloat bottom = CGRectGetMaxY(buttonFrameInAlert);
                if (bottom > maxButtonBottom) maxButtonBottom = bottom;
            }
        }
        if (maxButtonBottom > 0.0) {
            CGFloat desiredHeight = maxButtonBottom;
            CGFloat currentHeight = CGRectGetHeight(alertView.frame);
            if (currentHeight > desiredHeight + 1.0) {
                CGRect frame = alertView.frame;
                CGFloat shrink = currentHeight - desiredHeight;
                frame.size.height = desiredHeight;
                frame.origin.y += shrink / 2.0;
                alertView.frame = frame;

                // Also resize the immediate container if it wraps the alert tightly.
                UIView *wrapper = alertView.superview;
                if (wrapper && fabs(CGRectGetHeight(wrapper.bounds) - currentHeight) < 2.0) {
                    CGRect wrapperFrame = wrapper.frame;
                    wrapperFrame.size.height = desiredHeight;
                    wrapperFrame.origin.y += shrink / 2.0;
                    wrapper.frame = wrapperFrame;
                }
            }
        }
    }
}

static void SCIIGSwizzleInstanceMethod(Class cls, SEL origSel, IMP newImp, IMP *outOrigImp) {
    if (!cls || !origSel || !newImp) return;
    Method origMethod = class_getInstanceMethod(cls, origSel);
    if (!origMethod) return;

    const char *types = method_getTypeEncoding(origMethod);
    IMP origImp = method_getImplementation(origMethod);

    if (class_addMethod(cls, origSel, newImp, types)) {
        if (outOrigImp) *outOrigImp = origImp;
    } else {
        IMP prevImp = method_setImplementation(origMethod, newImp);
        if (outOrigImp) *outOrigImp = prevImp;
    }
}

static void SCIIGInstallAlertHooksIfNeeded(Class alertClass) {
    if (sSCIIGAlertHooksInstalled || !alertClass) return;

    SCIIGSwizzleInstanceMethod(alertClass, @selector(sizeThatFits:), (IMP)SCIIGAlertHookSizeThatFits, (IMP *)&sSCIIGAlertOriginalSizeThatFits);
    SCIIGSwizzleInstanceMethod(alertClass, @selector(layoutSubviews), (IMP)SCIIGAlertHookLayoutSubviews, (IMP *)&sSCIIGAlertOriginalLayoutSubviews);

    sSCIIGAlertHooksInstalled = YES;
}

@implementation SCIIGAlertPresenter

+ (BOOL)presentAlertFromViewController:(UIViewController *)presenter
                                 title:(NSString *)title
                               message:(NSString *)message
                               actions:(NSArray<SCIIGAlertAction *> *)actions {
    Class actionClass = NSClassFromString(@"IGCustomAlertAction");
    Class alertClass = NSClassFromString(@"IGDSAlertDialogView");
    Class styleClass = NSClassFromString(@"IGDSAlertDialogStyle");
    SEL actionSelector = @selector(actionWithTitle:style:handler:);
    SEL alertSelector = NSSelectorFromString(@"initWithStyle:titleText:descriptionText:actions:showHorizontalButtons:");

    if (!actionClass || !alertClass || ![actionClass respondsToSelector:actionSelector] || ![alertClass instancesRespondToSelector:alertSelector]) {
        SCIIGPresentUIKitAlert(presenter, title, message, actions, UIAlertControllerStyleAlert);
        return NO;
    }

    SCIIGInstallAlertHooksIfNeeded(alertClass);

    BOOL containsDestructiveAction = SCIIGActionsContainDestructiveAction(actions);
    NSMutableArray *nativeActions = [NSMutableArray arrayWithCapacity:actions.count];
    NSMutableArray<NSNumber *> *nativeActionStyles = [NSMutableArray arrayWithCapacity:actions.count];
    for (SCIIGAlertAction *action in actions) {
        id nativeAction = ((id (*)(id, SEL, id, long long, id))objc_msgSend)(actionClass,
                                                                            actionSelector,
                                                                            action.title,
                                                                            SCIIGNativeAlertActionStyleForAction(action, containsDestructiveAction),
                                                                            ^{
            SCIIGCallActionHandler(action);
        });
        if (!nativeAction) {
            SCIIGPresentUIKitAlert(presenter, title, message, actions, UIAlertControllerStyleAlert);
            return NO;
        }
        objc_setAssociatedObject(nativeAction, kSCIIGAlertNativeActionStyleKey, @(action.style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [nativeActions addObject:nativeAction];
        [nativeActionStyles addObject:@(action.style)];
    }

    id style = styleClass ? [[styleClass alloc] init] : nil;
    id alertView = ((id (*)(id, SEL, id, id, id, id, BOOL))objc_msgSend)([alertClass alloc],
                                                                        alertSelector,
                                                                        style,
                                                                        title,
                                                                        message,
                                                                        nativeActions,
                                                                        actions.count <= 2);
    if (![alertView respondsToSelector:@selector(show)]) {
        SCIIGPresentUIKitAlert(presenter, title, message, actions, UIAlertControllerStyleAlert);
        return NO;
    }

    objc_setAssociatedObject(alertView, kSCIIGAlertNativeActionStylesKey, nativeActionStyles, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL))objc_msgSend)(alertView, @selector(show));
    return YES;
}

+ (BOOL)presentActionSheetFromViewController:(UIViewController *)presenter
                                       title:(NSString *)title
                                     message:(NSString *)message
                                     actions:(NSArray<SCIIGAlertAction *> *)actions {
    Class actionClass = NSClassFromString(@"IGActionSheetControllerAction");
    Class sheetClass = NSClassFromString(@"IGActionSheetController");
    SEL actionSelector = NSSelectorFromString(@"initWithTitle:subtitle:style:handler:accessibilityIdentifier:accessibilityLabel:");
    SEL sheetSelector = @selector(initWithActions:);

    if (!actionClass || !sheetClass || ![actionClass instancesRespondToSelector:actionSelector] || ![sheetClass instancesRespondToSelector:sheetSelector]) {
        SCIIGPresentUIKitAlert(presenter, title, message, actions, UIAlertControllerStyleActionSheet);
        return NO;
    }

    NSMutableArray *nativeActions = [NSMutableArray arrayWithCapacity:actions.count];
    for (SCIIGAlertAction *action in actions) {
        // The native IGActionSheetController already provides its own Cancel button,
        // so skip cancel-style actions to avoid duplicates.
        if (action.style == SCIIGAlertActionStyleCancel) continue;

        id nativeAction = ((id (*)(id, SEL, id, id, long long, id, id, id))objc_msgSend)([actionClass alloc],
                                                                                        actionSelector,
                                                                                        action.title,
                                                                                        nil,
                                                                                        SCIIGNativeActionSheetStyle(action.style),
                                                                                        ^{
            SCIIGCallActionHandler(action);
        },
                                                                                        nil,
                                                                                        action.title);
        if (!nativeAction) {
            SCIIGPresentUIKitAlert(presenter, title, message, actions, UIAlertControllerStyleActionSheet);
            return NO;
        }
        [nativeActions addObject:nativeAction];
    }

    id sheet = nil;
    SEL titledSheetSelector = NSSelectorFromString(@"initWithHeader:primaryText:secondaryText:actions:layoutSpec:impressionTag:");
    if ((title.length > 0 || message.length > 0) && [sheetClass instancesRespondToSelector:titledSheetSelector]) {
        NSAttributedString *primaryText = title.length > 0 ? [[NSAttributedString alloc] initWithString:title] : nil;
        NSAttributedString *secondaryText = message.length > 0 ? [[NSAttributedString alloc] initWithString:message] : nil;
        sheet = ((id (*)(id, SEL, id, id, id, id, id, id))objc_msgSend)([sheetClass alloc],
                                                                        titledSheetSelector,
                                                                        nil,
                                                                        primaryText,
                                                                        secondaryText,
                                                                        nativeActions,
                                                                        nil,
                                                                        nil);
    } else {
        sheet = ((id (*)(id, SEL, id))objc_msgSend)([sheetClass alloc], sheetSelector, nativeActions);
    }
    if (![sheet respondsToSelector:@selector(show)]) {
        SCIIGPresentUIKitAlert(presenter, title, message, actions, UIAlertControllerStyleActionSheet);
        return NO;
    }

    ((void (*)(id, SEL))objc_msgSend)(sheet, @selector(show));

    // Tint the native cancel button with the danger/cancel color.
    UIView *cancelButton = SCIIGGetIvarObject(sheet, "_cancelButton");
    if ([cancelButton isKindOfClass:[UIButton class]]) {
        UIColor *cancelColor = SCIIGDangerActionColor();
        [(UIButton *)cancelButton setTitleColor:cancelColor forState:UIControlStateNormal];
        cancelButton.tintColor = cancelColor;
    }
    return YES;
}

+ (BOOL)presentTextInputAlertFromViewController:(UIViewController *)presenter
                                          title:(NSString *)title
                                        message:(NSString *)message
                                    placeholder:(NSString *)placeholder
                                    initialText:(NSString *)initialText
                               autocapitalized:(BOOL)autocapitalized
                                  confirmTitle:(NSString *)confirmTitle
                                   cancelTitle:(NSString *)cancelTitle
                                  confirmStyle:(SCIIGAlertActionStyle)confirmStyle
                                  confirmBlock:(SCIIGAlertTextHandler)confirmBlock
                                   cancelBlock:(SCIIGAlertActionHandler)cancelBlock {
    __block UITextField *textField = nil;
    UIView *inputView = SCIIGCreateInputView(placeholder, initialText, autocapitalized, &textField);

    Class actionClass = NSClassFromString(@"IGCustomAlertAction");
    Class alertClass = NSClassFromString(@"IGDSAlertDialogView");
    Class styleClass = NSClassFromString(@"IGDSAlertDialogStyle");
    SEL actionSelector = @selector(actionWithTitle:style:handler:);
    SEL alertSelector = NSSelectorFromString(@"initWithStyle:titleText:descriptionText:actions:showHorizontalButtons:");

    if (!inputView || !textField || !actionClass || !alertClass || ![actionClass respondsToSelector:actionSelector] || ![alertClass instancesRespondToSelector:alertSelector]) {
        SCIIGPresentUIKitTextInputAlert(presenter, title, message, placeholder, initialText, autocapitalized, confirmTitle, cancelTitle, confirmStyle, confirmBlock, cancelBlock);
        return NO;
    }

    SCIIGInstallAlertHooksIfNeeded(alertClass);

    id cancelAction = ((id (*)(id, SEL, id, long long, id))objc_msgSend)(actionClass,
                                                                         actionSelector,
                                                                         cancelTitle,
                                                                         SCIIGNativeAlertActionStyle(SCIIGAlertActionStyleCancel),
                                                                         ^{
        if (cancelBlock) cancelBlock();
    });
    id confirmAction = ((id (*)(id, SEL, id, long long, id))objc_msgSend)(actionClass,
                                                                          actionSelector,
                                                                          confirmTitle,
                                                                          SCIIGNativeAlertActionStyle(confirmStyle),
                                                                          ^{
        if (confirmBlock) confirmBlock(textField.text);
    });
    if (!cancelAction || !confirmAction) {
        SCIIGPresentUIKitTextInputAlert(presenter, title, message, placeholder, initialText, autocapitalized, confirmTitle, cancelTitle, confirmStyle, confirmBlock, cancelBlock);
        return NO;
    }
    objc_setAssociatedObject(cancelAction, kSCIIGAlertNativeActionStyleKey, @(SCIIGAlertActionStyleCancel), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(confirmAction, kSCIIGAlertNativeActionStyleKey, @(confirmStyle), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id style = styleClass ? [[styleClass alloc] init] : nil;
    NSString *descriptionText = SCIIGDescriptionTextForInputAlert(message);
    id alertView = ((id (*)(id, SEL, id, id, id, id, BOOL))objc_msgSend)([alertClass alloc],
                                                                        alertSelector,
                                                                        style,
                                                                        title,
                                                                        descriptionText,
                                                                        @[cancelAction, confirmAction],
                                                                        YES);
    if (![alertView respondsToSelector:@selector(show)]) {
        SCIIGPresentUIKitTextInputAlert(presenter, title, message, placeholder, initialText, autocapitalized, confirmTitle, cancelTitle, confirmStyle, confirmBlock, cancelBlock);
        return NO;
    }

    objc_setAssociatedObject(alertView, kSCIIGAlertInputViewKey, inputView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(alertView, kSCIIGAlertInputFieldKey, textField, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(alertView, kSCIIGAlertInputHasMessageKey, @(message.length > 0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(alertView, kSCIIGAlertNativeActionStylesKey, @[@(SCIIGAlertActionStyleCancel), @(confirmStyle)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL))objc_msgSend)(alertView, @selector(show));
    dispatch_async(dispatch_get_main_queue(), ^{
        [textField becomeFirstResponder];
    });
    return YES;
}

@end

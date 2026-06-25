#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#import "../../Utils.h"
#import "../../Shared/UI/SCIChrome.h"
#import "CaptureHiding.h"


static const void *kSCICaptureFieldKey  = &kSCICaptureFieldKey;
static const void *kSCICaptureCanvasKey = &kSCICaptureCanvasKey;

const NSInteger kSCICaptureFollowIndicatorTag = 926003;

static NSSet<NSNumber *> *SCICaptureHiddenTags(void) {
    static NSSet<NSNumber *> *tags;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tags = [NSSet setWithArray:@[
            @921341, @921342, @921343, @921344, @921345,
            @926001, @926002,
            @(kSCICaptureFollowIndicatorTag)
        ]];
    });
    return tags;
}

static UIView *SCIFindCanvasView(UIView *root, int depth) {
    if (!root || depth > 4) return nil;
    for (UIView *sub in root.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"CanvasView"] ||
            [cls containsString:@"TextLayoutCanvas"]) {
            return sub;
        }
        UIView *found = SCIFindCanvasView(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

static NSString *SCICaptureSubviewSummary(UIView *view) {
    if (!view) return @"(nil)";

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UIView *subview in view.subviews) {
        [parts addObject:[NSString stringWithFormat:@"%@<%p> tag=%ld hidden=%@ alpha=%.2f",
            NSStringFromClass(subview.class),
            subview,
            (long)subview.tag,
            subview.hidden ? @"YES" : @"NO",
            subview.alpha]];
    }
    return parts.count ? [parts componentsJoinedByString:@", "] : @"(none)";
}

static void SCIEnsureSecureCanvas(UIView *button) {
    if (!button || !button.window) return;
    if ([button isKindOfClass:NSClassFromString(@"SCIChromeButton")]) return;
    if (![SCIUtils getBoolPref:@"interface_hide_ui_on_capture"]) return;

    // Check if secure field already exists
    UITextField *field = objc_getAssociatedObject(button, kSCICaptureFieldKey);
    if (field) return;

    SCILog(@"Capture", @"Creating secure canvas for tag=%ld class=%@",
           (long)button.tag, NSStringFromClass([button class]));

    // 1. Create secure text field
    field = [UITextField new];
    field.secureTextEntry = YES;
    field.userInteractionEnabled = NO;
    field.backgroundColor = [UIColor clearColor];
    field.borderStyle = UITextBorderStyleNone;
    field.textColor = [UIColor clearColor];
    field.tintColor = [UIColor clearColor];
    field.translatesAutoresizingMaskIntoConstraints = NO;

    // Associate it BEFORE adding as subview so the addSubview: hook recognizes it
    objc_setAssociatedObject(button, kSCICaptureFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 2. Snapshot existing children (if any were added before didMoveToWindow)
    NSMutableArray<UIView *> *existing = [NSMutableArray array];
    for (UIView *child in button.subviews) {
        if (child != field) {
            [existing addObject:child];
        }
    }

    // 3. Add secure field to button
    [button addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
        [field.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
        [field.topAnchor constraintEqualToAnchor:button.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:button.bottomAnchor]
    ]];
    [field setNeedsLayout];
    [field layoutIfNeeded];

    // 4. Locate CanvasView
    UIView *canvas = SCIFindCanvasView(field, 0);
    if (!canvas) {
        SCIWarnLog(@"Capture", @"CanvasView not found for tag=%ld", (long)button.tag);
        [field removeFromSuperview];
        objc_setAssociatedObject(button, kSCICaptureFieldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    // 5. Configure Canvas
    canvas.userInteractionEnabled = YES;
    canvas.clipsToBounds = NO;
    canvas.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [canvas.leadingAnchor constraintEqualToAnchor:field.leadingAnchor],
        [canvas.trailingAnchor constraintEqualToAnchor:field.trailingAnchor],
        [canvas.topAnchor constraintEqualToAnchor:field.topAnchor],
        [canvas.bottomAnchor constraintEqualToAnchor:field.bottomAnchor]
    ]];

    objc_setAssociatedObject(button, kSCICaptureCanvasKey, canvas, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 6. Migrate pre-existing subviews to canvas
    for (UIView *child in existing) {
        [child removeFromSuperview];
        [canvas addSubview:child];
    }

    SCILog(@"Capture", @"Secure canvas successfully applied to tag=%ld (%lu pre-existing children moved)",
           (long)button.tag, (unsigned long)existing.count);
    SCILog(@"Capture", @"button=%@<%p> subviews=%@",
           NSStringFromClass(button.class), button, SCICaptureSubviewSummary(button));
    if ([button isKindOfClass:UIButton.class]) {
        UIButton *uiButton = (UIButton *)button;
        SCILog(@"Capture", @"imageView=%@<%p> imageSuperview=%@<%p>",
               NSStringFromClass(uiButton.imageView.class),
               uiButton.imageView,
               NSStringFromClass(uiButton.imageView.superview.class),
               uiButton.imageView.superview);
    }
    SCILog(@"Capture", @"canvas=%@<%p> canvasSubviews=%@",
           NSStringFromClass(canvas.class), canvas, SCICaptureSubviewSummary(canvas));
}

%group SCICaptureHidingHooks

%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (self.window &&
        ![self isKindOfClass:NSClassFromString(@"SCIChromeButton")] &&
        [SCICaptureHiddenTags() containsObject:@(self.tag)]) {
        SCIEnsureSecureCanvas(self);
    }
}

- (void)addSubview:(UIView *)view {
    if (![self isKindOfClass:NSClassFromString(@"SCIChromeButton")] &&
        [SCICaptureHiddenTags() containsObject:@(self.tag)]) {
        // If this is the secure field itself, let it pass
        UITextField *secureField = objc_getAssociatedObject(self, kSCICaptureFieldKey);
        if (view == secureField) {
            %orig;
            return;
        }

        // Ensure canvas is instantiated
        SCIEnsureSecureCanvas(self);

        UIView *canvas = objc_getAssociatedObject(self, kSCICaptureCanvasKey);
        if (canvas) {
            // Intercept and redirect the subview into the secure canvas
            [canvas addSubview:view];
            SCILog(@"Capture", @"Redirected subview class=%@ tag=%ld into secure canvas",
                   NSStringFromClass([view class]), (long)self.tag);
        } else {
            // Fallback
            %orig;
        }
    } else {
        %orig;
    }
}

%end

%end

extern "C" void SCIInstallCaptureHidingHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCILog(@"Capture", @"Installing capture hiding hooks...");
        %init(SCICaptureHidingHooks);
    });
}

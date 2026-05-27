#import <objc/runtime.h>

#import "../../Utils.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"

static NSInteger const kSCIDirectActionButtonTag = 921344;
static const void *kSCIDirectActionBottomConstraintAssocKey = &kSCIDirectActionBottomConstraintAssocKey;
static const void *kSCIDirectActionTrailingConstraintAssocKey = &kSCIDirectActionTrailingConstraintAssocKey;
static const void *kSCIDirectActionWidthConstraintAssocKey = &kSCIDirectActionWidthConstraintAssocKey;
static const void *kSCIDirectActionHeightConstraintAssocKey = &kSCIDirectActionHeightConstraintAssocKey;

static UIView *SCIDirectOverlayView(UIViewController *controller) {
	if (!controller) return nil;
	id viewerContainer = [SCIUtils getIvarForObj:controller name:"_viewerContainerView"];
	if (!viewerContainer) viewerContainer = SCIKVCObject(controller, @"viewerContainerView");
	id overlay = SCIObjectForSelector(viewerContainer, @"overlayView");
	return [overlay isKindOfClass:[UIView class]] ? (UIView *)overlay : nil;
}

static CGFloat SCIHeightFromFrameLikeObject(id object) {
	if (!object) return 0.0;
	if ([object isKindOfClass:[UIView class]]) return ((UIView *)object).frame.size.height;

	@try {
		id frameValue = [object valueForKey:@"frame"];
		if ([frameValue isKindOfClass:[NSValue class]]) return ((NSValue *)frameValue).CGRectValue.size.height;
	} @catch (__unused NSException *exception) {
	}

	return 0.0;
}

static CGFloat SCIDirectBottomOffset(UIViewController *controller) {
	id inputView = [SCIUtils getIvarForObj:controller name:"_inputView"];
	CGFloat offset = controller.view.safeAreaInsets.bottom + 12.0;
	if (inputView) offset += SCIHeightFromFrameLikeObject(inputView);
	return offset;
}

static SCIActionButtonContext *SCIMessagesActionContext(UIViewController *controller) {
	SCIActionButtonContext *context = [[SCIActionButtonContext alloc] init];
	context.source = SCIActionButtonSourceDirect;
	context.controller = controller;
	context.settingsTitle = SCIActionButtonTopicTitleForSource(SCIActionButtonSourceDirect);
	context.supportedActions = SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceDirect);
	context.mediaResolver = ^id (SCIActionButtonContext *resolvedContext) {
		return SCIDirectResolvedMediaFromController(resolvedContext.controller);
	};
	context.currentIndexResolver = ^NSInteger (SCIActionButtonContext *resolvedContext) {
		return SCIDirectCurrentIndexFromController(resolvedContext.controller);
	};
	return context;
}

static BOOL SCIDirectConstraintMatches(NSLayoutConstraint *constraint, CGFloat constant) {
	return constraint && constraint.active && ABS(constraint.constant - constant) < 0.5;
}

static BOOL SCIDirectActionButtonLayoutIsCurrent(UIButton *button, CGFloat bottomOffset) {
	if (![button isKindOfClass:[UIButton class]] || button.hidden || !button.superview) return NO;

	NSLayoutConstraint *bottomConstraint = objc_getAssociatedObject(button, kSCIDirectActionBottomConstraintAssocKey);
	NSLayoutConstraint *trailingConstraint = objc_getAssociatedObject(button, kSCIDirectActionTrailingConstraintAssocKey);
	NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(button, kSCIDirectActionWidthConstraintAssocKey);
	NSLayoutConstraint *heightConstraint = objc_getAssociatedObject(button, kSCIDirectActionHeightConstraintAssocKey);

	return SCIDirectConstraintMatches(trailingConstraint, -10.0) &&
	       SCIDirectConstraintMatches(bottomConstraint, -bottomOffset) &&
	       SCIDirectConstraintMatches(widthConstraint, 44.0) &&
	       SCIDirectConstraintMatches(heightConstraint, 44.0);
}

static void SCIInstallDirectActionButton(UIViewController *controller) {
	UIView *overlay = SCIDirectOverlayView(controller);
	if (!overlay) return;

	UIButton *button = (UIButton *)[overlay viewWithTag:kSCIDirectActionButtonTag];
	if (![SCIUtils getBoolPref:@"msgs_action_btn"]) {
		[button removeFromSuperview];
		return;
	}

	CGFloat bottomOffset = SCIDirectBottomOffset(controller);
	if (SCIDirectActionButtonLayoutIsCurrent(button, bottomOffset)) return;

	button = SCIActionButtonWithTag(overlay, kSCIDirectActionButtonTag);
	SCIConfigureActionButton(button, SCIMessagesActionContext(controller));
	if (button.hidden) return;

	CGFloat size = 44.0;
	button.translatesAutoresizingMaskIntoConstraints = NO;

	NSLayoutConstraint *bottomConstraint = objc_getAssociatedObject(button, kSCIDirectActionBottomConstraintAssocKey);
	NSLayoutConstraint *trailingConstraint = objc_getAssociatedObject(button, kSCIDirectActionTrailingConstraintAssocKey);
	NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(button, kSCIDirectActionWidthConstraintAssocKey);
	NSLayoutConstraint *heightConstraint = objc_getAssociatedObject(button, kSCIDirectActionHeightConstraintAssocKey);

	if (!bottomConstraint || !trailingConstraint || !widthConstraint || !heightConstraint) {
		trailingConstraint = [button.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-10.0];
		bottomConstraint = [button.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor constant:-bottomOffset];
		widthConstraint = [button.widthAnchor constraintEqualToConstant:size];
		heightConstraint = [button.heightAnchor constraintEqualToConstant:size];
		[NSLayoutConstraint activateConstraints:@[trailingConstraint, bottomConstraint, widthConstraint, heightConstraint]];

		objc_setAssociatedObject(button, kSCIDirectActionBottomConstraintAssocKey, bottomConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(button, kSCIDirectActionTrailingConstraintAssocKey, trailingConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(button, kSCIDirectActionWidthConstraintAssocKey, widthConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(button, kSCIDirectActionHeightConstraintAssocKey, heightConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	trailingConstraint.constant = -10.0;
	bottomConstraint.constant = -bottomOffset;
	widthConstraint.constant = size;
	heightConstraint.constant = size;

	SCIApplyButtonStyle(button, SCIActionButtonSourceDirect);
	[overlay bringSubviewToFront:button];
}

%group SCIMessagesActionButtonHooks

%hook IGDirectVisualMessageViewerController
- (void)viewDidLayoutSubviews {
	%orig;

	SCIInstallDirectActionButton((UIViewController *)self);
	__weak UIViewController *weakController = (UIViewController *)self;
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *strongController = weakController;
		if (!strongController) return;
		SCIInstallDirectActionButton(strongController);
	});
}
%end

%end

extern "C" void SCIInstallMessagesActionButtonHooksIfEnabled(void) {
	if (![SCIUtils getBoolPref:@"msgs_action_btn"]) return;

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
	%init(SCIMessagesActionButtonHooks);
	});
}

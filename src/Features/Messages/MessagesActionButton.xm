#import <objc/runtime.h>

#import "../../Utils.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"

static NSInteger const kSCIDirectActionButtonTag = 921344;
static const void *kSCIDirectActionBottomConstraintAssocKey = &kSCIDirectActionBottomConstraintAssocKey;
static const void *kSCIDirectActionTrailingConstraintAssocKey = &kSCIDirectActionTrailingConstraintAssocKey;
static const void *kSCIDirectActionWidthConstraintAssocKey = &kSCIDirectActionWidthConstraintAssocKey;
static const void *kSCIDirectActionHeightConstraintAssocKey = &kSCIDirectActionHeightConstraintAssocKey;
static const void *kSCIDirectActionButtonMediaKey = &kSCIDirectActionButtonMediaKey;

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

static NSArray *SCIDirectVisualMessageItemsFromController(UIViewController *controller) {
	if (!controller) return nil;
	id dataSource = [SCIUtils getIvarForObj:controller name:"_dataSource"];
	if (!dataSource) dataSource = SCIKVCObject(controller, @"dataSource");
	if (!dataSource) return nil;

	for (NSString *key in @[@"visualMessages", @"messages", @"items", @"visualMessageItems", @"viewerItems"]) {
		id value = SCIObjectForSelector(dataSource, key) ?: SCIKVCObject(dataSource, key);
		if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSOrderedSet class]] || [value isKindOfClass:[NSSet class]]) {
			NSArray *arr = SCIArrayFromCollection(value);
			if (arr.count > 0) return arr;
		}
	}

	for (Class cls = [dataSource class]; cls && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
		unsigned int ivarCount = 0;
		Ivar *ivars = class_copyIvarList(cls, &ivarCount);
		for (unsigned int i = 0; i < ivarCount; i++) {
			const char *typeEncoding = ivar_getTypeEncoding(ivars[i]);
			if (typeEncoding && typeEncoding[0] == '@') {
				const char *name = ivar_getName(ivars[i]);
				id value = [SCIUtils getIvarForObj:dataSource name:name];
				if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSOrderedSet class]] || [value isKindOfClass:[NSSet class]]) {
					NSArray *arr = SCIArrayFromCollection(value);
					if (arr.count > 1) {
						free(ivars);
						return arr;
					}
				}
			}
		}
		free(ivars);
	}

	return nil;
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
	context.bulkMediaResolver = ^id (SCIActionButtonContext *resolvedContext) {
		return SCIDirectVisualMessageItemsFromController(resolvedContext.controller) ?: SCIDirectResolvedMediaFromController(resolvedContext.controller);
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

	// Layer 1 fix: detect media change to force reconfiguration even when layout is unchanged
	id currentMedia = SCIDirectResolvedMediaFromController(controller);
	id lastMedia = button ? objc_getAssociatedObject(button, kSCIDirectActionButtonMediaKey) : nil;
	BOOL mediaChanged = (lastMedia != currentMedia);

	if (SCIDirectActionButtonLayoutIsCurrent(button, bottomOffset) && !mediaChanged) return;

	button = SCIActionButtonWithTag(overlay, kSCIDirectActionButtonTag);
	SCIConfigureActionButton(button, SCIMessagesActionContext(controller));

	// Store the resolved media pointer for change detection on next call
	objc_setAssociatedObject(button, kSCIDirectActionButtonMediaKey, currentMedia, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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

// Reinstall now and once more on the next runloop, so the action button picks up
// the new item after `_currentVisualMessageIndex` has settled.
static void SCIDirectReinstallActionButtonSoon(UIViewController *controller) {
	if (!controller) return;
	SCIInstallDirectActionButton(controller);
	__weak UIViewController *weakController = controller;
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *strongController = weakController;
		if (strongController) SCIInstallDirectActionButton(strongController);
	});
}

%group SCIMessagesActionButtonHooks

%hook IGDirectVisualMessageViewerController
- (void)viewDidLayoutSubviews {
	%orig;
	SCIDirectReinstallActionButtonSoon((UIViewController *)self);
}

// Swiping between visual messages doesn't relayout the controller's view, so the
// layout hook above won't fire. The controller is the story-player media delegate,
// so these callbacks fire on every item change — reconfigure for the new item.
- (void)storyPlayerMediaViewDidLoad:(id)load loadSource:(id)source networkRequestSummary:(id)summary {
	%orig;
	SCIDirectReinstallActionButtonSoon((UIViewController *)self);
}

- (void)storyPlayerMediaViewDidBeginPlayback:(id)playback {
	%orig;
	SCIDirectReinstallActionButtonSoon((UIViewController *)self);
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

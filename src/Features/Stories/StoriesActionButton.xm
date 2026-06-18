#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../../Shared/Stories/SCIStoryButtonPlacement.h"
#import "../../Shared/Stories/SCIStoryContext.h"

static NSInteger const kSCIStoriesActionButtonTag = 921343;

static id SCIStorySectionControllerFromOverlay(UIView *overlayView) {
	SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
	if (sharedContext.sectionController) return sharedContext.sectionController;
	NSArray<NSString *> *delegateSelectors = @[@"mediaOverlayDelegate", @"retryDelegate", @"tappableOverlayDelegate", @"buttonDelegate"];
	Class sectionControllerClass = NSClassFromString(@"IGStoryFullscreenSectionController");

	for (NSString *selectorName in delegateSelectors) {
		id delegate = SCIObjectForSelector(overlayView, selectorName);
		if (!delegate) continue;
		if (!sectionControllerClass || [delegate isKindOfClass:sectionControllerClass]) return delegate;
	}

	return nil;
}

static id SCIStoryMediaFromOverlay(UIView *overlayView) {
	SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
	if (sharedContext.media) return sharedContext.media;
	id sectionController = SCIStorySectionControllerFromOverlay(overlayView);
	id media = SCIObjectForSelector(sectionController, @"currentStoryItem");
	if (media) return media;

	UIViewController *ancestorController = [SCIUtils viewControllerForAncestralView:overlayView];
	media = SCIObjectForSelector(ancestorController, @"currentStoryItem");
	return media;
}

static UIViewController *SCIStoryControllerFromOverlay(UIView *overlayView) {
	SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
	if (sharedContext.viewerController) return sharedContext.viewerController;
	if (!overlayView) return nil;

	id ancestorController = SCIObjectForSelector(overlayView, @"_viewControllerForAncestor");
	if ([ancestorController isKindOfClass:[UIViewController class]]) {
		return (UIViewController *)ancestorController;
	}

	return [SCIUtils nearestViewControllerForView:overlayView];
}

static NSArray *SCIStoryItemsFromCandidate(id candidate) {
    if (!candidate) return nil;

    for (NSString *selectorName in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
        id value = SCIObjectForSelector(candidate, selectorName);
        if (!value) value = SCIKVCObject(candidate, selectorName);
        NSArray *items = SCIArrayFromCollection(value);
        if (items.count > 1) return items;
    }

    SEL cachedSelector = NSSelectorFromString(@"allItemsForTrayUsingCachedValue:");
    if ([candidate respondsToSelector:cachedSelector]) {
        @try {
            id value = ((id (*)(id, SEL, BOOL))objc_msgSend)(candidate, cachedSelector, YES);
            NSArray *items = SCIArrayFromCollection(value);
            if (items.count > 1) return items;
        } @catch (__unused NSException *exception) {
        }
    }

    // Dynamic ivar fallback scanning
    for (Class cls = [candidate class]; cls && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char *typeEncoding = ivar_getTypeEncoding(ivars[i]);
            if (typeEncoding && typeEncoding[0] == '@') {
                const char *name = ivar_getName(ivars[i]);
                id value = [SCIUtils getIvarForObj:candidate name:name];
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

static id SCIStoryMediaObjectFromCandidate(id candidate) {
    if (!candidate) return nil;
    for (NSString *selectorName in @[@"media", @"storyItem", @"item", @"mediaItem", @"currentStoryItem"]) {
        id value = SCIObjectForSelector(candidate, selectorName);
        if (!value) value = SCIKVCObject(candidate, selectorName);
        if (value && value != candidate) return value;
    }
    return candidate;
}

static id SCIStoryBulkMediaFromOverlay(UIView *overlayView) {
    SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
    if (sharedContext.allMedia.count > 1) return sharedContext.allMedia;
    id current = SCIStoryMediaFromOverlay(overlayView);
    id sectionController = SCIStorySectionControllerFromOverlay(overlayView);
    UIViewController *controller = SCIStoryControllerFromOverlay(overlayView);
    id currentViewModel = SCIObjectForSelector(controller, @"currentViewModel") ?: SCIKVCObject(controller, @"currentViewModel");

    NSString *currentUserPK = SCIStoryUserPKFromMediaObject(current);

    for (id candidate in @[sectionController ?: (id)NSNull.null, currentViewModel ?: (id)NSNull.null, controller ?: (id)NSNull.null]) {
        if (!candidate || candidate == (id)NSNull.null) continue;
        NSArray *items = SCIStoryItemsFromCandidate(candidate);
        if (items.count <= 1) continue;

        NSMutableArray *resolvedMedia = [NSMutableArray array];
        for (id item in items) {
            id media = SCIStoryMediaObjectFromCandidate(item);
            if (media) {
                if (currentUserPK) {
                    NSString *itemUserPK = SCIStoryUserPKFromMediaObject(media);
                    if ([itemUserPK isEqualToString:currentUserPK]) {
                        [resolvedMedia addObject:media];
                    }
                } else {
                    [resolvedMedia addObject:media];
                }
            }
        }
        if (resolvedMedia.count > 1) {
            return [resolvedMedia copy];
        }
    }

    return current;
}

static SCIActionButtonContext *SCIStoriesActionContext(UIView *overlayView) {
	SCIActionButtonContext *context = [[SCIActionButtonContext alloc] init];
	context.source = SCIActionButtonSourceStories;
	context.view = overlayView;
	context.controller = SCIStoryControllerFromOverlay(overlayView);
	context.settingsTitle = SCIActionButtonTopicTitleForSource(SCIActionButtonSourceStories);
	context.supportedActions = SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceStories);
	context.mediaResolver = ^id (SCIActionButtonContext *resolvedContext) {
		return SCIStoryMediaFromOverlay(resolvedContext.view);
	};
	context.bulkMediaResolver = ^id (SCIActionButtonContext *resolvedContext) {
        return SCIStoryBulkMediaFromOverlay(resolvedContext.view);
    };
	context.currentIndexResolver = ^NSInteger (SCIActionButtonContext *resolvedContext) {
		SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(resolvedContext.view);
		return sharedContext ? sharedContext.currentIndex : 0;
	};
	return context;
}

static BOOL SCIStoriesActionFrameMatches(UIButton *button, CGRect frame) {
	if (![button isKindOfClass:[UIButton class]] || button.hidden || !button.superview) return NO;
	return ABS(CGRectGetMinX(button.frame) - CGRectGetMinX(frame)) < 0.5 &&
	       ABS(CGRectGetMinY(button.frame) - CGRectGetMinY(frame)) < 0.5 &&
	       ABS(CGRectGetWidth(button.frame) - CGRectGetWidth(frame)) < 0.5 &&
	       ABS(CGRectGetHeight(button.frame) - CGRectGetHeight(frame)) < 0.5;
}

static const void *kSCIStoriesActionButtonMediaKey = &kSCIStoriesActionButtonMediaKey;

static void SCIInstallStoriesActionButton(UIView *overlayView) {
	if (!overlayView) return;

	if (SCIIsDirectVisualViewerAncestor(overlayView)) {
		UIButton *existing = (UIButton *)[overlayView viewWithTag:kSCIStoriesActionButtonTag];
		[existing removeFromSuperview];
		return;
	}

	UIButton *button = (UIButton *)[overlayView viewWithTag:kSCIStoriesActionButtonTag];
	if (![SCIUtils getBoolPref:@"stories_action_btn"]) {
		[button removeFromSuperview];
		return;
	}

	CGFloat size = 44.0;
	CGRect expectedFrame = SCIStoryFloatingButtonFrame(overlayView, size);
	if (CGRectIsEmpty(expectedFrame)) {
		[button removeFromSuperview];
		return;
	}

	id currentMedia = SCIStoryMediaFromOverlay(overlayView);
	id lastMedia = button ? objc_getAssociatedObject(button, kSCIStoriesActionButtonMediaKey) : nil;

	if (SCIStoriesActionFrameMatches(button, expectedFrame) && lastMedia == currentMedia) return;

	button = SCIActionButtonWithTag(overlayView, kSCIStoriesActionButtonTag);
	button.translatesAutoresizingMaskIntoConstraints = YES;
	SCIConfigureActionButton(button, SCIStoriesActionContext(overlayView));
	objc_setAssociatedObject(button, kSCIStoriesActionButtonMediaKey, currentMedia, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if (button.hidden) return;

	button.frame = expectedFrame;
	SCIApplyButtonStyle(button, SCIActionButtonSourceStories);
}

%group SCIStoriesActionButtonHooks

%hook IGStoryFullscreenOverlayView
- (void)layoutSubviews {
	%orig;
	SCIStorySetActiveOverlay((UIView *)self);
	SCIInstallStoriesActionButton((UIView *)self);
}
%end

%end

extern "C" void SCIInstallStoriesActionButtonHooksIfEnabled(void) {
	if (![SCIUtils getBoolPref:@"stories_action_btn"]) return;

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
	%init(SCIStoriesActionButtonHooks);
	});
}

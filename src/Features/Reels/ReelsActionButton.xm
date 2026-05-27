#import <objc/message.h>
#import <objc/runtime.h>

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"

static NSInteger const kSCIReelsActionButtonTag = 921342;
static const void *kSCIReelsActionBottomConstraintAssocKey = &kSCIReelsActionBottomConstraintAssocKey;
static const void *kSCIReelsActionCenterXConstraintAssocKey = &kSCIReelsActionCenterXConstraintAssocKey;
static const void *kSCIReelsActionWidthConstraintAssocKey = &kSCIReelsActionWidthConstraintAssocKey;
static const void *kSCIReelsActionHeightConstraintAssocKey = &kSCIReelsActionHeightConstraintAssocKey;
static CGFloat const kSCIReelsActionButtonSize = 44.0;
static CGFloat const kSCIReelsActionButtonBottomOffset = -5.0;

static UIView *SCIReelsFindSuperviewOfClass(UIView *view, NSString *className) {
	Class cls = NSClassFromString(className);
	if (!cls) return nil;
	UIView *current = view.superview;
	for (NSInteger depth = 0; current && depth < 20; depth++) {
		if ([current isKindOfClass:cls]) return current;
		current = current.superview;
	}
	return nil;
}

static id SCIReelsFindMediaIvar(UIView *view) {
	Class mediaClass = NSClassFromString(@"IGMedia");
	if (!view || !mediaClass) return nil;

	unsigned int count = 0;
	Ivar *ivars = class_copyIvarList([view class], &count);
	id found = nil;
	for (unsigned int i = 0; i < count; i++) {
		const char *type = ivar_getTypeEncoding(ivars[i]);
		if (!type || type[0] != '@') continue;
		@try {
			id value = object_getIvar(view, ivars[i]);
			if (value && [value isKindOfClass:mediaClass]) {
				found = value;
				break;
			}
		} @catch (__unused NSException *exception) {
		}
	}
	if (ivars) free(ivars);
	return found;
}

static NSArray *SCIReelsCarouselChildren(id parentMedia) {
	if (!parentMedia) return nil;
	NSArray *children = SCIArrayFromCollection(SCIObjectForSelector(parentMedia, @"carouselMedia"));
	if (children.count == 0) children = SCIArrayFromCollection(SCIObjectForSelector(parentMedia, @"carouselChildren"));
	if (children.count == 0) children = SCIArrayFromCollection(SCIObjectForSelector(parentMedia, @"children"));
	if (children.count == 0) children = SCIArrayFromCollection(SCIKVCObject(parentMedia, @"carousel_media"));
	return children;
}

static NSInteger SCIReelsCarouselCurrentIndex(UIView *carouselCell, id parentMedia) {
	if (!carouselCell || !parentMedia) return -1;

	NSArray *children = SCIReelsCarouselChildren(parentMedia);
	if (children.count == 0) return -1;
	if (children.count == 1) return 0;

	NSInteger currentIdx = 0;
	Ivar idxIvar = class_getInstanceVariable([carouselCell class], "_currentIndex");
	if (idxIvar) {
		ptrdiff_t offset = ivar_getOffset(idxIvar);
		currentIdx = *(NSInteger *)((char *)(__bridge void *)carouselCell + offset);
	}

	if (!idxIvar || currentIdx == 0) {
		Ivar fracIvar = class_getInstanceVariable([carouselCell class], "_currentFractionalIndex");
		if (fracIvar) {
			ptrdiff_t offset = ivar_getOffset(fracIvar);
			double fractionalIndex = *(double *)((char *)(__bridge void *)carouselCell + offset);
			NSInteger roundedIdx = (NSInteger)round(fractionalIndex);
			if (roundedIdx > 0) currentIdx = roundedIdx;
		}
	}

	Ivar collectionViewIvar = class_getInstanceVariable([carouselCell class], "_collectionView");
	if (collectionViewIvar) {
		UICollectionView *cv = object_getIvar(carouselCell, collectionViewIvar);
		if (cv) {
			CGFloat pageWidth = cv.bounds.size.width;
			if (pageWidth > 0) {
				NSInteger cvIdx = (NSInteger)round(cv.contentOffset.x / pageWidth);
				if (cvIdx > currentIdx) currentIdx = cvIdx;
			}
		}
	}

	if (currentIdx < 0) return 0;
	if ((NSUInteger)currentIdx >= children.count) return (NSInteger)children.count - 1;
	return currentIdx;
}

static id SCIReelsCurrentCarouselChildMedia(UIView *carouselCell, id parentMedia) {
	if (!carouselCell || !parentMedia) return parentMedia;

	NSArray *children = SCIReelsCarouselChildren(parentMedia);
	NSInteger currentIdx = SCIReelsCarouselCurrentIndex(carouselCell, parentMedia);
	if (currentIdx < 0) return parentMedia;
	return (children.count > 0 && (NSUInteger)currentIdx < children.count) ? children[currentIdx] : parentMedia;
}

static UIView *SCIReelsCarouselCellFromView(UIView *view) {
	UIView *carouselCell = SCIReelsFindSuperviewOfClass(view, @"IGSundialViewerCarouselCell");
	if (carouselCell) return carouselCell;

	Class carouselClass = NSClassFromString(@"IGSundialViewerCarouselCell");
	if (!carouselClass) return nil;

	NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:view ?: (id)NSNull.null];
	NSMutableSet<UIView *> *visited = [NSMutableSet set];
	while (queue.count > 0) {
		UIView *candidate = queue.firstObject;
		[queue removeObjectAtIndex:0];
		if (candidate == (id)NSNull.null || !candidate || [visited containsObject:candidate]) continue;
		[visited addObject:candidate];

		if ([candidate isKindOfClass:carouselClass]) return candidate;

		for (UIView *subview in candidate.subviews) [queue addObject:subview];
		UIView *superview = candidate.superview;
		if (superview && ![visited containsObject:superview]) [queue addObject:superview];
	}
	return nil;
}

static id SCIReelsMediaProvider(UIView *sourceView) {
	UIView *videoCell = SCIReelsFindSuperviewOfClass(sourceView, @"IGSundialViewerVideoCell");
	if (videoCell) {
		id media = SCIReelsFindMediaIvar(videoCell);
		if (media) return media;
	}

	UIView *photoCell = SCIReelsFindSuperviewOfClass(sourceView, @"IGSundialViewerPhotoCell");
	if (photoCell) {
		id media = SCIReelsFindMediaIvar(photoCell);
		if (media) return media;
	}

	UIView *carouselCell = SCIReelsCarouselCellFromView(sourceView);
	if (carouselCell) {
		id parentMedia = SCIReelsFindMediaIvar(carouselCell);
		if (parentMedia) return SCIReelsCurrentCarouselChildMedia(carouselCell, parentMedia);
	}

	id delegate = SCIObjectForSelector(sourceView, @"delegate");
	id media = SCIObjectForSelector(delegate, @"media");
	if (!media) media = SCIKVCObject(delegate, @"media");
	return media;
}

static id SCIReelsBulkMediaProvider(UIView *sourceView) {
	UIView *carouselCell = SCIReelsCarouselCellFromView(sourceView);
	if (carouselCell) {
		id parentMedia = SCIReelsFindMediaIvar(carouselCell);
		if (parentMedia && SCIReelsCarouselChildren(parentMedia).count > 1) {
			return parentMedia;
		}
	}
	return SCIReelsMediaProvider(sourceView);
}

static NSInteger SCIReelsCurrentIndexFromVerticalUFI(UIView *verticalUFIView) {
	if (!verticalUFIView) return -1;

	for (NSString *selectorName in @[@"pageIndicator", @"pagingControl"]) {
		id indicator = SCIObjectForSelector(verticalUFIView, selectorName);
		if ([indicator isKindOfClass:[UIPageControl class]]) return (NSInteger)((UIPageControl *)indicator).currentPage;
		NSNumber *currentPageNumber = [SCIUtils numericValueForObj:indicator selectorName:@"currentPage"];
		if (currentPageNumber) return currentPageNumber.integerValue;
	}

	NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:verticalUFIView];
	while (queue.count > 0) {
		UIView *candidate = queue.firstObject;
		[queue removeObjectAtIndex:0];
		if ([candidate isKindOfClass:[UIPageControl class]]) return (NSInteger)((UIPageControl *)candidate).currentPage;
		for (UIView *subview in candidate.subviews) [queue addObject:subview];
	}

	return -1;
}

static NSString *SCIReelsCaptionForContext(SCIActionButtonContext *context, id media, NSArray *entries, NSInteger currentIndex) {
	NSString *caption = SCICaptionFromMediaObject(media);
	if (caption.length > 0) return caption;
	NSInteger idx = MAX(0, MIN((NSInteger)entries.count - 1, currentIndex));
	if (entries.count > 0) {
		id entryMedia = [entries[idx] valueForKey:@"mediaObject"];
		caption = SCICaptionFromMediaObject(entryMedia);
	}
	return caption;
}

static BOOL SCIReelsTriggerRepost(SCIActionButtonContext *context) {
	if (!context.view) return NO;

	SEL noArgSelector = NSSelectorFromString(@"_didTapRepostButton");
	if ([context.view respondsToSelector:noArgSelector]) {
		((void (*)(id, SEL))objc_msgSend)(context.view, noArgSelector);
		return YES;
	}

	SEL oneArgSelector = @selector(_didTapRepostButton:);
	if ([context.view respondsToSelector:oneArgSelector]) {
		((void (*)(id, SEL, id))objc_msgSend)(context.view, oneArgSelector, nil);
		return YES;
	}

	return NO;
}

static SCIActionButtonContext *SCIReelsActionContext(UIView *verticalUFIView) {
	SCIActionButtonContext *context = [[SCIActionButtonContext alloc] init];
	context.source = SCIActionButtonSourceReels;
	context.view = verticalUFIView;
	context.settingsTitle = SCIActionButtonTopicTitleForSource(SCIActionButtonSourceReels);
	context.supportedActions = SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceReels);
	context.mediaResolver = ^id (SCIActionButtonContext *resolvedContext) {
		return SCIReelsMediaProvider(resolvedContext.view);
	};
	context.bulkMediaResolver = ^id (SCIActionButtonContext *resolvedContext) {
		return SCIReelsBulkMediaProvider(resolvedContext.view);
	};
	context.currentIndexResolver = ^NSInteger (SCIActionButtonContext *resolvedContext) {
		UIView *carouselCell = SCIReelsCarouselCellFromView(resolvedContext.view);
		if (carouselCell) {
			id parentMedia = SCIReelsFindMediaIvar(carouselCell);
			NSInteger carouselIndex = SCIReelsCarouselCurrentIndex(carouselCell, parentMedia);
			if (carouselIndex >= 0) return carouselIndex;
		}
		NSInteger ufiIndex = SCIReelsCurrentIndexFromVerticalUFI(resolvedContext.view);
		return ufiIndex >= 0 ? ufiIndex : 0;
	};
	context.captionResolver = ^NSString * (SCIActionButtonContext *resolvedContext, id media, NSArray *entries, NSInteger currentIndex) {
		return SCIReelsCaptionForContext(resolvedContext, media, entries, currentIndex);
	};
	context.repostHandler = ^BOOL (SCIActionButtonContext *resolvedContext) {
		return SCIReelsTriggerRepost(resolvedContext);
	};
	return context;
}

static BOOL SCIReelsConstraintMatches(NSLayoutConstraint *constraint, CGFloat constant) {
	return constraint && constraint.active && ABS(constraint.constant - constant) < 0.5;
}

static BOOL SCIReelsActionButtonLayoutIsCurrent(UIButton *button) {
	if (![button isKindOfClass:[UIButton class]] || button.hidden || !button.superview) return NO;

	NSLayoutConstraint *bottomConstraint = objc_getAssociatedObject(button, kSCIReelsActionBottomConstraintAssocKey);
	NSLayoutConstraint *centerXConstraint = objc_getAssociatedObject(button, kSCIReelsActionCenterXConstraintAssocKey);
	NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(button, kSCIReelsActionWidthConstraintAssocKey);
	NSLayoutConstraint *heightConstraint = objc_getAssociatedObject(button, kSCIReelsActionHeightConstraintAssocKey);

	return SCIReelsConstraintMatches(bottomConstraint, kSCIReelsActionButtonBottomOffset) &&
	       centerXConstraint && centerXConstraint.active &&
	       SCIReelsConstraintMatches(widthConstraint, kSCIReelsActionButtonSize) &&
	       SCIReelsConstraintMatches(heightConstraint, kSCIReelsActionButtonSize);
}

void SCIInstallReelsActionButton(UIView *verticalUFIView) {
	if (!verticalUFIView) return;

	UIButton *button = (UIButton *)[verticalUFIView viewWithTag:kSCIReelsActionButtonTag];
	if (![SCIUtils getBoolPref:@"reels_action_btn"]) {
		[button removeFromSuperview];
		return;
	}

	if (SCIReelsActionButtonLayoutIsCurrent(button)) {
		return;
	}

	button = SCIActionButtonWithTag(verticalUFIView, kSCIReelsActionButtonTag);
	SCIConfigureActionButton(button, SCIReelsActionContext(verticalUFIView));
	if (button.hidden) return;

	button.translatesAutoresizingMaskIntoConstraints = NO;

	NSLayoutConstraint *bottomConstraint = objc_getAssociatedObject(button, kSCIReelsActionBottomConstraintAssocKey);
	NSLayoutConstraint *centerXConstraint = objc_getAssociatedObject(button, kSCIReelsActionCenterXConstraintAssocKey);
	NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(button, kSCIReelsActionWidthConstraintAssocKey);
	NSLayoutConstraint *heightConstraint = objc_getAssociatedObject(button, kSCIReelsActionHeightConstraintAssocKey);

	if (!bottomConstraint || !centerXConstraint || !widthConstraint || !heightConstraint) {
		bottomConstraint = [button.bottomAnchor constraintEqualToAnchor:verticalUFIView.topAnchor constant:kSCIReelsActionButtonBottomOffset];
		centerXConstraint = [button.centerXAnchor constraintEqualToAnchor:verticalUFIView.centerXAnchor];
		widthConstraint = [button.widthAnchor constraintEqualToConstant:kSCIReelsActionButtonSize];
		heightConstraint = [button.heightAnchor constraintEqualToConstant:kSCIReelsActionButtonSize];
		[NSLayoutConstraint activateConstraints:@[bottomConstraint, centerXConstraint, widthConstraint, heightConstraint]];

		objc_setAssociatedObject(button, kSCIReelsActionBottomConstraintAssocKey, bottomConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(button, kSCIReelsActionCenterXConstraintAssocKey, centerXConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(button, kSCIReelsActionWidthConstraintAssocKey, widthConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(button, kSCIReelsActionHeightConstraintAssocKey, heightConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	bottomConstraint.constant = kSCIReelsActionButtonBottomOffset;
	widthConstraint.constant = kSCIReelsActionButtonSize;
	heightConstraint.constant = kSCIReelsActionButtonSize;

	verticalUFIView.clipsToBounds = NO;
	verticalUFIView.layer.masksToBounds = NO;
	[verticalUFIView bringSubviewToFront:button];
	SCIApplyButtonStyle(button, SCIActionButtonSourceReels);
}

%group SCIReelsActionButtonHooks

%hook IGSundialViewerVerticalUFI
- (void)layoutSubviews {
	%orig;
	SCIInstallReelsActionButton((UIView *)self);
}
%end

%end

extern "C" void SCIInstallReelsActionButtonHooksIfEnabled(void) {
	if (![SCIUtils getBoolPref:@"reels_action_btn"]) return;

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
	%init(SCIReelsActionButtonHooks);
	});
}

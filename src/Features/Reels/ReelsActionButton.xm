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
static const void *kSCIReelsActionButtonMediaKey = &kSCIReelsActionButtonMediaKey;
static const void *kSCIReelsActionButtonCarouselIndexKey = &kSCIReelsActionButtonCarouselIndexKey;
static CGFloat const kSCIReelsActionButtonSize = 44.0;
static CGFloat const kSCIReelsActionButtonBottomOffset = -5.0;

// MARK: - View hierarchy helpers

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

// MARK: - Deterministic resolution from IGUnifiedVideoCollectionView (Layer 2)

/// Walk up from `view` to find the paging collection view that holds all reel cells.
static UICollectionView *SCIReelsFindPagingCollectionView(UIView *view) {
	Class pagingClass = NSClassFromString(@"IGUnifiedVideoCollectionView");
	if (!pagingClass) return nil;
	UIView *current = view.superview;
	for (NSInteger depth = 0; current && depth < 30; depth++) {
		if ([current isKindOfClass:pagingClass]) return (UICollectionView *)current;
		current = current.superview;
	}
	return nil;
}

/// Given the paging collection view, find the currently visible reel cell
/// using contentOffset + cell height. Returns a UICollectionViewCell that is
/// an IGSundialViewerVideoCell, CarouselCell, or PhotoCell.
static UICollectionViewCell *SCIReelsCurrentCellFromPagingView(UICollectionView *pagingView) {
	if (!pagingView) return nil;

	CGFloat pageHeight = pagingView.bounds.size.height;
	if (pageHeight <= 0) return nil;

	// Center-point heuristic: find the cell whose center is closest to the
	// collection view's visible center.
	CGFloat centerY = pagingView.contentOffset.y + pageHeight / 2.0;

	NSArray<UICollectionViewCell *> *visibleCells = pagingView.visibleCells;
	UICollectionViewCell *bestCell = nil;
	CGFloat bestDistance = CGFLOAT_MAX;

	for (UICollectionViewCell *cell in visibleCells) {
		CGFloat cellCenterY = CGRectGetMidY(cell.frame);
		CGFloat distance = ABS(cellCenterY - centerY);
		if (distance < bestDistance) {
			bestDistance = distance;
			bestCell = cell;
		}
	}

	return bestCell;
}

/// Read the media ivar (_mediaPassthrough) from a known cell type.
/// Falls back to scanning all object-typed ivars for IGMedia.
static id SCIReelsMediaFromCell(UICollectionViewCell *cell) {
	if (!cell) return nil;

	// Fast path: read _mediaPassthrough directly (present on both VideoCell and CarouselCell)
	Ivar mediaPTIvar = class_getInstanceVariable([cell class], "_mediaPassthrough");
	if (mediaPTIvar) {
		const char *type = ivar_getTypeEncoding(mediaPTIvar);
		if (type && type[0] == '@') {
			@try {
				id media = object_getIvar(cell, mediaPTIvar);
				if (media) {
					return media;
				}
			} @catch (__unused NSException *exception) {}
		}
	}

	// Fallback: scan ivars for IGMedia
	Class mediaClass = NSClassFromString(@"IGMedia");
	if (!mediaClass) return nil;

	unsigned int count = 0;
	Ivar *ivars = class_copyIvarList([cell class], &count);
	id found = nil;
	for (unsigned int i = 0; i < count; i++) {
		const char *type = ivar_getTypeEncoding(ivars[i]);
		if (!type || type[0] != '@') continue;
		@try {
			id value = object_getIvar(cell, ivars[i]);
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

// MARK: - Carousel helpers

static NSArray *SCIReelsCarouselChildren(id parentMedia) {
	return SCIActionButtonCarouselChildren(parentMedia);
}

/// Read the carousel's current page index from a **specific** carousel cell.
/// Only reads ivars from the cell we deterministically found — never from a BFS result.
static NSInteger SCIReelsCarouselCurrentIndex(UICollectionViewCell *carouselCell, id parentMedia) {
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

static id SCIReelsCurrentCarouselChildMedia(UICollectionViewCell *carouselCell, id parentMedia) {
	if (!carouselCell || !parentMedia) return parentMedia;

	NSArray *children = SCIReelsCarouselChildren(parentMedia);
	NSInteger currentIdx = SCIReelsCarouselCurrentIndex(carouselCell, parentMedia);
	if (currentIdx < 0) return parentMedia;
	return (children.count > 0 && (NSUInteger)currentIdx < children.count) ? children[currentIdx] : parentMedia;
}

// MARK: - Media resolution (deterministic, with BFS fallback)

/// Walk UP the superview chain to find the cell that actually CONTAINS this UFI/button.
/// This is the cell the button belongs to — independent of which cell is currently
/// centered, so it doesn't drift with scroll timing.
static UICollectionViewCell *SCIReelsOwnEnclosingCell(UIView *view) {
	Class carouselClass = NSClassFromString(@"IGSundialViewerCarouselCell");
	Class videoCellClass = NSClassFromString(@"IGSundialViewerVideoCell");
	Class photoCellClass = NSClassFromString(@"IGSundialViewerPhotoCell");
	UIView *current = view;
	for (NSInteger depth = 0; current && depth < 25; depth++) {
		if ((carouselClass && [current isKindOfClass:carouselClass]) ||
		    (videoCellClass && [current isKindOfClass:videoCellClass]) ||
		    (photoCellClass && [current isKindOfClass:photoCellClass])) {
			return (UICollectionViewCell *)current;
		}
		current = current.superview;
	}
	return nil;
}

/// Primary resolution: the UFI's OWN enclosing cell (per-button correct, timing-independent).
/// Fallback: globally-centered cell via the paging collection view, then the delegate chain.
static id SCIReelsMediaProvider(UIView *sourceView) {
	// --- PRIMARY: resolve THIS UFI's own enclosing cell ---
	UICollectionViewCell *ownCell = SCIReelsOwnEnclosingCell(sourceView);
	if (ownCell) {
		id media = SCIReelsMediaFromCell(ownCell);
		if (media) {
			return media; // carousel parent returned as-is; currentIndexResolver picks the child
		}
	}

	// --- FALLBACK: globally-centered cell via IGUnifiedVideoCollectionView ---
	UICollectionView *pagingView = SCIReelsFindPagingCollectionView(sourceView);
	if (pagingView) {
		UICollectionViewCell *currentCell = SCIReelsCurrentCellFromPagingView(pagingView);
		if (currentCell) {
			id media = SCIReelsMediaFromCell(currentCell);
			if (media) {
				return media;
			}
		}
	}

	// Last resort: delegate chain
	id delegate = SCIObjectForSelector(sourceView, @"delegate");
	id media = SCIObjectForSelector(delegate, @"media");
	if (!media) media = SCIKVCObject(delegate, @"media");
	return media;
}

static id SCIReelsBulkMediaProvider(UIView *sourceView) {
	UICollectionViewCell *ownCell = SCIReelsOwnEnclosingCell(sourceView);
	if (ownCell) {
		id media = SCIReelsMediaFromCell(ownCell);
		Class carouselClass = NSClassFromString(@"IGSundialViewerCarouselCell");
		if (media && carouselClass && [ownCell isKindOfClass:carouselClass]) {
			NSArray *children = SCIReelsCarouselChildren(media);
			if (children.count > 1) return media;
		}
	}
	return SCIReelsMediaProvider(sourceView);
}

// MARK: - Current index resolution

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

static NSInteger SCIReelsCurrentIndexForContext(UIView *sourceView) {
	// PRIMARY: this UFI's own enclosing carousel cell.
	UICollectionViewCell *ownCell = SCIReelsOwnEnclosingCell(sourceView);
	if (ownCell) {
		id parentMedia = SCIReelsMediaFromCell(ownCell);
		Class carouselClass = NSClassFromString(@"IGSundialViewerCarouselCell");
		if (carouselClass && [ownCell isKindOfClass:carouselClass] && parentMedia) {
			NSInteger carouselIndex = SCIReelsCarouselCurrentIndex(ownCell, parentMedia);
			if (carouselIndex >= 0) return carouselIndex;
		}
	}

	// Fallback: UFI page indicator
	NSInteger ufiIndex = SCIReelsCurrentIndexFromVerticalUFI(sourceView);
	return ufiIndex >= 0 ? ufiIndex : 0;
}

// MARK: - Caption & repost

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

// MARK: - Action context

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
		return SCIReelsCurrentIndexForContext(resolvedContext.view);
	};
	context.captionResolver = ^NSString * (SCIActionButtonContext *resolvedContext, id media, NSArray *entries, NSInteger currentIndex) {
		return SCIReelsCaptionForContext(resolvedContext, media, entries, currentIndex);
	};
	context.repostHandler = ^BOOL (SCIActionButtonContext *resolvedContext) {
		return SCIReelsTriggerRepost(resolvedContext);
	};
	return context;
}

// MARK: - Layout check

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

// MARK: - Installer (with media-change gate — Layer 1)

void SCIInstallReelsActionButton(UIView *verticalUFIView) {
	if (!verticalUFIView) return;

	UIButton *button = (UIButton *)[verticalUFIView viewWithTag:kSCIReelsActionButtonTag];
	if (![SCIUtils getBoolPref:@"reels_action_btn"]) {
		[button removeFromSuperview];
		return;
	}

	// Resolve current media to detect whether we need to reconfigure
	id currentMedia = SCIReelsMediaProvider(verticalUFIView);
	NSInteger currentCarouselIdx = SCIReelsCurrentIndexForContext(verticalUFIView);
	id lastMedia = button ? objc_getAssociatedObject(button, kSCIReelsActionButtonMediaKey) : nil;
	NSNumber *lastCarouselIdx = button ? objc_getAssociatedObject(button, kSCIReelsActionButtonCarouselIndexKey) : nil;

	BOOL mediaChanged = (lastMedia != currentMedia) ||
	                     (lastCarouselIdx && lastCarouselIdx.integerValue != currentCarouselIdx);

	if (SCIReelsActionButtonLayoutIsCurrent(button) && !mediaChanged) {
		return;
	}

	button = SCIActionButtonWithTag(verticalUFIView, kSCIReelsActionButtonTag);
	SCIConfigureActionButton(button, SCIReelsActionContext(verticalUFIView));

	// Store the resolved media + carousel index for change detection on next call
	objc_setAssociatedObject(button, kSCIReelsActionButtonMediaKey, currentMedia, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(button, kSCIReelsActionButtonCarouselIndexKey, @(currentCarouselIdx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"

// ─── Constants & Types ──────────────────────────────────────────────

static const char kSPKCellSectionControllerAssocKey = 0;
static const char kSPKOverlayPollViewsAssocKey = 0;

// Register a poll sticker against its enclosing overlay so the overlay's
// layoutSubviews can re-apply vote badges to just that view, instead of
// walking the entire overlay subtree on every layout pass (the overwhelmingly
// common case is a story with no poll at all).
static void SPKRegisterPollViewWithOverlay(UIView *pollView) {
    Class overlayClass = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayClass)
        return;
    for (UIView *view = pollView.superview; view; view = view.superview) {
        if (![view isKindOfClass:overlayClass])
            continue;
        NSHashTable *pollViews = objc_getAssociatedObject(view, &kSPKOverlayPollViewsAssocKey);
        if (!pollViews) {
            pollViews = [NSHashTable weakObjectsHashTable];
            objc_setAssociatedObject(view, &kSPKOverlayPollViewsAssocKey, pollViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (![pollViews containsObject:pollView])
            [pollViews addObject:pollView];
        return;
    }
}

// ─── Customization ──────────────────────────────────────────────────
// Adjust these values to customize the badge position and size.
#define kSPKPollBadgePaddingHorizontal 12.0
#define kSPKPollBadgePaddingVertical 6.0
#define kSPKPollBadgeMarginRight -6.0
// Set to 0.0 to center vertically, or a positive/negative value to offset from the center
#define kSPKPollBadgeCenterYOffset -18.0

// ─── Utilities ──────────────────────────────────────────────────────

static id SPKCallMaybe(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0)
        return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector])
        return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SPKKVCMaybe(id object, NSString *key) {
    if (!object || key.length == 0)
        return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray *SPKArrayIvar(id object, const char *name) {
    if (!object || !name)
        return nil;
    for (Class cls = [object class]; cls && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (!ivar)
            continue;
        @try {
            id value = object_getIvar(object, ivar);
            return [value isKindOfClass:[NSArray class]] ? value : nil;
        } @catch (__unused NSException *exception) {
            return nil;
        }
    }
    return nil;
}

// ─── Label & String Handling ────────────────────────────────────────

static BOOL SPKStoryPollStickerIsEditing(UIView *view) {
    for (UIResponder *responder = view; responder; responder = responder.nextResponder) {
        NSString *className = NSStringFromClass([responder class]);
        if ([className containsString:@"StoryPostCaptureEditing"] ||
            [className containsString:@"StoryMediaCompositionEditing"] ||
            [className containsString:@"StoryStickerTray"]) {
            return YES;
        }
    }
    return NO;
}

// ─── Data Extraction ────────────────────────────────────────────────

static NSInteger SPKStoryPollTallyCount(id tally) {
    if ([tally respondsToSelector:@selector(integerValue)])
        return [tally integerValue];
    for (NSString *selectorName in @[ @"totalCount", @"count", @"countValue", @"voteCount", @"pollVotersCount" ]) {
        id value = SPKCallMaybe(tally, selectorName) ?: SPKKVCMaybe(tally, selectorName);
        if ([value respondsToSelector:@selector(integerValue)]) {
            return [value integerValue];
        }
    }
    return 0;
}

// Returns the IGAPIStoryPollTappableObject -> IGAPIPollSticker -> tallies
static id SPKStoryPollAuthoritativeSticker(id media, id viewModel) {
    NSArray *storyPolls = SPKCallMaybe(media, @"_private_storyPolls") ?: SPKKVCMaybe(media, @"_private_storyPolls");
    if (![storyPolls isKindOfClass:[NSArray class]] || storyPolls.count == 0) {
        storyPolls = SPKCallMaybe(media, @"storyPolls") ?: SPKKVCMaybe(media, @"storyPolls");
    }
    if (![storyPolls isKindOfClass:[NSArray class]] || storyPolls.count == 0)
        return nil;

    id viewPollValue = SPKCallMaybe(viewModel, @"pollId") ?: SPKKVCMaybe(viewModel, @"pollId");
    NSString *viewPollID = [viewPollValue description];

    for (id storyPoll in storyPolls) {
        id sticker = SPKCallMaybe(storyPoll, @"pollSticker") ?: SPKKVCMaybe(storyPoll, @"pollSticker");
        if (!sticker)
            continue;
        if (viewPollID.length == 0)
            return sticker;
        id stickerPollValue = SPKCallMaybe(sticker, @"pollId") ?: SPKKVCMaybe(sticker, @"pollId");
        NSString *stickerPollID = [stickerPollValue description];
        if ([stickerPollID isEqualToString:viewPollID])
            return sticker;
    }

    id first = storyPolls.firstObject;
    return SPKCallMaybe(first, @"pollSticker") ?: SPKKVCMaybe(first, @"pollSticker");
}

static id SPKFindMediaForPollView(UIView *pollView) {
    // Check if any parent cell has an associated section controller.
    UICollectionViewCell *parentCell = nil;
    UIView *current = pollView;
    while (current != nil) {
        if ([current isKindOfClass:[UICollectionViewCell class]]) {
            parentCell = (UICollectionViewCell *)current;
            break;
        }
        current = current.superview;
    }

    if (parentCell) {
        id sectionController = objc_getAssociatedObject(parentCell, &kSPKCellSectionControllerAssocKey);
        if (sectionController) {
            id media = SPKCallMaybe(sectionController, @"currentStoryItem") ?: SPKCallMaybe(sectionController, @"model");
            if (media)
                return media;
        }
    }

    // 2. Fallback: traverse responder chain
    for (UIResponder *responder = pollView; responder; responder = responder.nextResponder) {
        for (NSString *selectorName in @[ @"media", @"igMedia", @"storyMedia", @"storyItem", @"item", @"feedItem" ]) {
            id media = SPKCallMaybe(responder, selectorName) ?: SPKKVCMaybe(responder, selectorName);
            if (media && media != responder)
                return media;
        }
    }

    return nil;
}

static void SPKApplyStoryPollVoteCounts(UIView *pollView, NSArray<UIView *> *optionViews) {
    if (![SPKUtils getBoolPref:@"stories_poll_vote_counts"])
        return;
    if (!pollView.window || SPKStoryPollStickerIsEditing(pollView)) {
        for (UIView *subview in pollView.subviews) {
            if (subview.tag >= 998800 && subview.tag < 998900)
                subview.hidden = YES;
        }
        return;
    }

    id media = SPKFindMediaForPollView(pollView);
    if (!media)
        return;

    id viewModel = SPKCallMaybe(pollView, @"pollSticker") ?: SPKCallMaybe(pollView, @"igapiStickerModel") ?
                                                                                                          : SPKCallMaybe(pollView, @"exportModel");
    id model = SPKStoryPollAuthoritativeSticker(media, viewModel) ?: viewModel;

    NSArray *tallies = SPKCallMaybe(model, @"tallies") ?: SPKKVCMaybe(model, @"tallies");
    if (![tallies isKindOfClass:[NSArray class]] || tallies.count == 0) {
        for (UIView *subview in pollView.subviews) {
            if (subview.tag >= 998800 && subview.tag < 998900)
                subview.hidden = YES;
        }
        return;
    }

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;

    NSUInteger count = MIN(optionViews.count, tallies.count);
    for (NSUInteger index = 0; index < count; index++) {
        UIView *optionView = optionViews[index];

        NSInteger votes = SPKStoryPollTallyCount(tallies[index]);
        NSString *formattedVotes = [formatter stringFromNumber:@(votes)] ?: [NSString stringWithFormat:@"%td", votes];

        // Use a unique tag for each option view's badge
        NSInteger badgeTag = 998800 + index;
        UILabel *badge = [pollView viewWithTag:badgeTag];
        if (!badge) {
            badge = [[UILabel alloc] init];
            badge.tag = badgeTag;
            badge.font = [UIFont boldSystemFontOfSize:12];
            // Poll stickers always render on a light card, so pin the badge to the
            // dark-mode variant (dark pill + light text) regardless of the user's
            // system appearance — otherwise it's low-contrast in dark mode.
            UITraitCollection *darkTraits = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark];
            badge.textColor = [[SPKUtils SPKColor_InstagramPrimaryText] resolvedColorWithTraitCollection:darkTraits];
            badge.backgroundColor = [[SPKUtils SPKColor_InstagramTertiaryBackground] resolvedColorWithTraitCollection:darkTraits];
            badge.textAlignment = NSTextAlignmentCenter;
            badge.layer.masksToBounds = YES;
            [pollView addSubview:badge];
        }

        badge.hidden = NO;
        badge.text = formattedVotes;
        [badge sizeToFit];

        CGSize badgeSize = badge.frame.size;
        badgeSize.width += kSPKPollBadgePaddingHorizontal;
        badgeSize.height += kSPKPollBadgePaddingVertical;

        // Enforce perfect circle if the width is smaller than the height (e.g. for single digits)
        badgeSize.width = MAX(badgeSize.width, badgeSize.height);

        // Convert optionView bounds to pollView coordinate space so we aren't clipped by the optionView
        CGRect optionFrame = [optionView convertRect:optionView.bounds toView:pollView];

        CGFloat badgeX = CGRectGetMaxX(optionFrame) - badgeSize.width - kSPKPollBadgeMarginRight;
        CGFloat badgeY = CGRectGetMidY(optionFrame) - (badgeSize.height / 2.0) + kSPKPollBadgeCenterYOffset;

        badge.frame = CGRectMake(badgeX, badgeY, badgeSize.width, badgeSize.height);
        badge.layer.cornerRadius = badgeSize.height / 2.0;

        // Poll stickers are displayed with an upscaling transform, so a label
        // rasterized at the screen scale gets magnified by the parent and looks
        // blurry. Re-rasterize the text at the badge's true on-screen scale
        // (measured through the live transform chain) so it stays crisp.
        UIWindow *window = pollView.window;
        CGFloat onScreenScale = 1.0;
        if (window) {
            CGPoint origin = [pollView convertPoint:CGPointZero toView:window];
            CGPoint unit = [pollView convertPoint:CGPointMake(1.0, 0.0) toView:window];
            onScreenScale = hypot(unit.x - origin.x, unit.y - origin.y);
        }
        CGFloat targetContentsScale = UIScreen.mainScreen.scale * MAX(1.0, onScreenScale);
        if (fabs(badge.layer.contentsScale - targetContentsScale) > 0.01) {
            badge.layer.contentsScale = targetContentsScale;
            [badge setNeedsDisplay];
        }

        [pollView bringSubviewToFront:badge];
    }

    // Hide any phantom badges that were created from previous logic or if options count shrank
    for (UIView *subview in pollView.subviews) {
        if (subview.tag >= 998800 + count && subview.tag < 998900) {
            subview.hidden = YES;
        }
    }
}

// ─── Hooks ──────────────────────────────────────────────────────────

%group SPKStoryPollVoteCountsHooks

// Bind section controller to cell so child views can easily access the current story item.
%hook IGStoryFullscreenSectionController
- (id)cellForItemAtIndex:(NSInteger)index {
    UICollectionViewCell *cell = %orig;
    if (cell)
        objc_setAssociatedObject(cell, &kSPKCellSectionControllerAssocKey, self, OBJC_ASSOCIATION_ASSIGN);
    return cell;
}
%end

%hook IGStorySectionController
- (id)cellForItemAtIndex:(NSInteger)index {
    UICollectionViewCell *cell = %orig;
    if (cell)
        objc_setAssociatedObject(cell, &kSPKCellSectionControllerAssocKey, self, OBJC_ASSOCIATION_ASSIGN);
    return cell;
}
%end

// Modern poll sticker
%hook IGPollStickerV2View
- (void)layoutSubviews {
    %orig;
    NSArray *options = SPKArrayIvar(self, "_optionViews");
    if (options.count > 0) {
        SPKApplyStoryPollVoteCounts((UIView *)self, options);
        SPKRegisterPollViewWithOverlay((UIView *)self);
    }
}
%end

// Legacy poll sticker
%hook IGPollStickerView
- (void)layoutSubviews {
    %orig;
    NSArray *options = SPKArrayIvar(self, "_optionViews") ?: SPKArrayIvar(self, "_voteOptionViews") ?
                                                                                                    : SPKArrayIvar(self, "_options");
    if (options.count > 0) {
        SPKApplyStoryPollVoteCounts((UIView *)self, options);
        SPKRegisterPollViewWithOverlay((UIView *)self);
    }
}
%end

// Overlay view constantly lays out (e.g. progress bar), so re-applying here
// guarantees our text isn't overwritten by Instagram's asynchronous poll result
// fetches. We only touch poll stickers the sticker hooks above have registered,
// so a story with no poll (the common case) costs a single associated-object
// lookup rather than a full subtree walk on every layout pass.
%hook IGStoryFullscreenOverlayView
- (void)layoutSubviews {
    %orig;
    NSHashTable *pollViews = objc_getAssociatedObject(self, &kSPKOverlayPollViewsAssocKey);
    if (pollViews.count == 0)
        return;

    for (UIView *pollView in pollViews.allObjects) {
        if (!pollView.superview)
            continue;
        NSArray *options = SPKArrayIvar(pollView, "_optionViews") ?: SPKArrayIvar(pollView, "_voteOptionViews") ?
                                                                                                                : SPKArrayIvar(pollView, "_options");
        if (options.count > 0)
            SPKApplyStoryPollVoteCounts(pollView, options);
    }
}
%end

%end // group SPKStoryPollVoteCountsHooks

#pragma mark - Entry Point

extern "C" void SPKInstallStoryPollVoteCountsHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"stories_poll_vote_counts"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKStoryPollVoteCountsHooks);
    });
}

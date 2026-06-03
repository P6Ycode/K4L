#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../InstagramHeaders.h"
#import "../../AssetUtils.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "../../Shared/Messages/SCIDirectSeenContext.h"
#import "../../Shared/Stories/SCIStoryContext.h"
#import "../../Shared/UI/SCIChrome.h"

#ifdef __cplusplus
extern "C" {
#endif
void SCIApplyButtonStyle(UIButton *button, NSInteger source);
#ifdef __cplusplus
}
#endif

static NSString * const kSCIStoryMentionsBarIconResource = @"mention";
static NSInteger const kSCIActionButtonSourceDirect = 4;
static NSInteger const kSCIStoryMentionsButtonTag = 926002;

extern void SCIPresentStoryMentionsSheet(UIView *overlayView);

static id SCIKVCObject(id target, NSString *key);
static id SCIObjectForSelector(id target, NSString *selectorName);
static id SCIFirstObjectForSelectors(id target, NSArray<NSString *> *selectors);

static inline BOOL SCIStoryMentionsButtonEnabled(void) {
    return [SCIUtils getBoolPref:@"stories_mentions_btn"];
}
static NSArray *SCIArrayFromCollection(id collection) {
    if (!collection ||
        [collection isKindOfClass:[NSDictionary class]] ||
        [collection isKindOfClass:[NSString class]] ||
        [collection isKindOfClass:[NSURL class]]) {
        return nil;
    }

    if ([collection isKindOfClass:[NSArray class]]) {
        return collection;
    }

    if ([collection isKindOfClass:[NSOrderedSet class]]) {
        return [(NSOrderedSet *)collection array];
    }

    if ([collection isKindOfClass:[NSSet class]]) {
        return [(NSSet *)collection allObjects];
    }

    if ([collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id item in collection) {
            [array addObject:item];
        }
        return array;
    }

    return nil;
}

static id SCIKVCObject(id target, NSString *key) {
    if (!target || key.length == 0) return nil;

    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SCIObjectForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;

    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static id SCIFirstObjectForSelectors(id target, NSArray<NSString *> *selectors) {
    if (!target || selectors.count == 0) return nil;
    for (NSString *selectorName in selectors) {
        id value = SCIObjectForSelector(target, selectorName);
        if (value) return value;
    }
    return nil;
}

static void SCIPlayButtonTappedHaptic(void) {
    UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
    [feedback selectionChanged];
}
static UIButton *SCIStorySeenButtonWithTag(UIView *container, NSInteger tag) {
    UIView *existing = [container viewWithTag:tag];
    if ([existing isKindOfClass:SCIChromeButton.class]) {
        return (UIButton *)existing;
    }
    [existing removeFromSuperview];

    SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:@"" pointSize:24.0 diameter:44.0];
    button.tag = tag;
    button.adjustsImageWhenHighlighted = YES;
    button.showsMenuAsPrimaryAction = NO;
    button.clipsToBounds = NO;
    [container addSubview:button];
    return button;
}

static void SCISetSeenButtonImage(UIButton *button, UIImage *image, NSString *logMessage) {
    UIImage *templatedImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if ([button isKindOfClass:SCIChromeButton.class]) {
        SCIChromeButton *chromeButton = (SCIChromeButton *)button;
        chromeButton.iconView.image = templatedImage;
        chromeButton.iconTint = UIColor.whiteColor;
        [button setImage:nil forState:UIControlStateNormal];
    } else {
        [button setImage:templatedImage forState:UIControlStateNormal];
    }

    SCILog(@"Capture", @"%@ tag=%ld button=%@<%p> subviews=%@ imageView=%@<%p> imageSuperview=%@<%p>",
           logMessage,
           (long)button.tag,
           NSStringFromClass(button.class),
           button,
           button.subviews,
           NSStringFromClass(button.imageView.class),
           button.imageView,
           NSStringFromClass(button.imageView.superview.class),
           button.imageView.superview);
}

static id SCIStorySectionControllerFromOverlayView(UIView *overlayView) {
    if (!overlayView) return nil;

    NSArray<NSString *> *delegateSelectors = @[@"mediaOverlayDelegate", @"retryDelegate", @"tappableOverlayDelegate", @"buttonDelegate"];
    Class sectionControllerClass = NSClassFromString(@"IGStoryFullscreenSectionController");

    for (NSString *selectorName in delegateSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![overlayView respondsToSelector:selector]) continue;

        id delegate = ((id (*)(id, SEL))objc_msgSend)(overlayView, selector);
        if (!delegate) continue;

        if (!sectionControllerClass || [delegate isKindOfClass:sectionControllerClass]) {
            return delegate;
        }
    }

    return nil;
}

static NSString *SCIStringFromValue(id value) {
    if (!value || value == (id)kCFNull) return nil;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *string = (NSString *)value;
        return string.length > 0 ? string : nil;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *string = [value stringValue];
        return string.length > 0 ? string : nil;
    }
    return [[value description] length] > 0 ? [value description] : nil;
}

static id SCIStoryMediaFromAnyObject(id object) {
    if (!object) return nil;
    id candidate = SCIFirstObjectForSelectors(object, @[@"media", @"mediaItem", @"storyItem", @"item", @"model"]);
    return candidate ?: object;
}

static BOOL SCIResolveStoryContextFromOverlay(UIView *overlayView, id *outMarkTarget, id *outSectionController, id *outMedia) {
    SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
    if (sharedContext) {
        if (outMarkTarget) *outMarkTarget = sharedContext.markSeenTarget;
        if (outSectionController) *outSectionController = sharedContext.sectionController;
        if (outMedia) *outMedia = sharedContext.media;
        return (sharedContext.media != nil);
    }

    if (!overlayView) return NO;

    SEL markSelector = NSSelectorFromString(@"fullscreenSectionController:didMarkItemAsSeen:");
    UIViewController *viewerController = [SCIUtils nearestViewControllerForView:overlayView];

    id sectionController = SCIStorySectionControllerFromOverlayView(overlayView);
    id markTarget = nil;
    id sectionDelegate = SCIObjectForSelector(sectionController, @"delegate");
    if (sectionDelegate && [sectionDelegate respondsToSelector:markSelector]) {
        markTarget = sectionDelegate;
    } else if (viewerController && [viewerController respondsToSelector:markSelector]) {
        markTarget = viewerController;
    } else {
        id overlayAncestor = SCIObjectForSelector(overlayView, @"_viewControllerForAncestor");
        if (overlayAncestor && [overlayAncestor respondsToSelector:markSelector]) {
            markTarget = overlayAncestor;
        }
    }

    if (!sectionController && markTarget) {
        sectionController = SCIFirstObjectForSelectors(markTarget, @[@"currentSectionController"]);
        if (!sectionController) {
            sectionController = [SCIUtils getIvarForObj:markTarget name:"_currentSectionController"];
        }
    }

    id media = SCIFirstObjectForSelectors(sectionController, @[@"currentStoryItem", @"currentItem", @"item"]);
    if (!media) media = SCIFirstObjectForSelectors(markTarget, @[@"currentStoryItem", @"currentItem", @"item"]);
    if (!media && viewerController) media = SCIFirstObjectForSelectors(viewerController, @[@"currentStoryItem", @"currentItem", @"item"]);
    media = SCIStoryMediaFromAnyObject(media);

    if (outMarkTarget) *outMarkTarget = markTarget;
    if (outSectionController) *outSectionController = sectionController;
    if (outMedia) *outMedia = media;

    return (media != nil);
}

static NSArray<NSDictionary *> *SCIStoryMentionsForOverlay(UIView *overlayView) {
    id markTarget = nil;
    id sectionController = nil;
    id media = nil;
    if (!SCIResolveStoryContextFromOverlay(overlayView, &markTarget, &sectionController, &media)) {
        return @[];
    }

    id mentionsCollection = SCIObjectForSelector(media, @"reelMentions");
    NSArray *mentions = SCIArrayFromCollection(mentionsCollection);
    if (mentions.count == 0) return @[];

    NSMutableArray<NSDictionary *> *userInfos = [NSMutableArray array];
    for (id mention in mentions) {
        id user = SCIKVCObject(mention, @"user");
        if (!user) user = SCIObjectForSelector(mention, @"user");
        if (!user) continue;

        NSString *username = SCIStringFromValue(SCIKVCObject(user, @"username"));
        if (!username) username = SCIStringFromValue(SCIObjectForSelector(user, @"username"));
        NSString *fullName = SCIStringFromValue(SCIKVCObject(user, @"fullName"));
        if (!fullName) fullName = SCIStringFromValue(SCIKVCObject(user, @"full_name"));

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        if (username.length > 0) entry[@"username"] = username;
        if (fullName.length > 0) entry[@"fullName"] = fullName;
        if (entry.count > 0) [userInfos addObject:entry];
    }

    return userInfos;
}

static void SCIApplyStoryMentionsButtonStyle(UIButton *button) {
    if (!button) return;
    SCIApplyButtonStyle(button, kSCIActionButtonSourceDirect);
}

void SCIRemoveStoryMentionsButton(UIView *overlayView) {
    UIButton *mentionsButton = (UIButton *)[overlayView viewWithTag:kSCIStoryMentionsButtonTag];
    [mentionsButton removeFromSuperview];
}

void SCIUpdateStoryMentionsButton(UIView *overlayView, CGFloat x, CGFloat y, CGFloat size) {
    NSArray<NSDictionary *> *storyMentions = SCIStoryMentionsForOverlay(overlayView);
    BOOL showMentionsButton = SCIStoryMentionsButtonEnabled() && storyMentions.count > 0;
    UIButton *mentionsButton = (UIButton *)[overlayView viewWithTag:kSCIStoryMentionsButtonTag];

    if (showMentionsButton && !mentionsButton) {
        mentionsButton = SCIStorySeenButtonWithTag(overlayView, kSCIStoryMentionsButtonTag);
        [mentionsButton addTarget:overlayView action:@selector(sci_storyMentionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

        UIImage *mentionsImage = [SCIAssetUtils instagramIconNamed:kSCIStoryMentionsBarIconResource pointSize:24.0];
        SCISetSeenButtonImage(mentionsButton, mentionsImage, @"Story mentions custom icon assigned");
    } else if (!showMentionsButton && mentionsButton) {
        [mentionsButton removeFromSuperview];
        mentionsButton = nil;
    }

    if (!showMentionsButton || !mentionsButton) return;
    SCIApplyStoryMentionsButtonStyle(mentionsButton);
    mentionsButton.frame = CGRectMake(x, y, size, size);
    [overlayView bringSubviewToFront:mentionsButton];
}

%group SCIStoryMentionsButtonHooks

%hook IGStoryFullscreenOverlayView
%new - (void)sci_storyMentionsButtonTapped:(UIButton *)sender {
    (void)sender;
    SCIPlayButtonTappedHaptic();
    SCIPresentStoryMentionsSheet((UIView *)self);
}
%end

%end

void SCIInstallStoryMentionsButtonHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIStoryMentionsButtonHooks);
    });
}

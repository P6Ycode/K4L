#import <objc/message.h>
#import <objc/runtime.h>

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Shared/Gallery/SCIGalleryPickerViewController.h"
#import "../../Shared/Gallery/SCIGalleryFile.h"
#import "../../Shared/UI/SCINotificationCenter.h"

// Long-press the comment composer's photo entry button to attach an image from the
// in-app SCInsta Gallery (Vault). A normal tap still opens Instagram's own photo
// gallery; the long-press routes through our gallery picker sheet instead and feeds
// the chosen image into the composer via the same entry point IG uses internally
// (-setupImageBeforeCommentComposingBeginWithSelectedPhoto:, which takes a UIImage).

static NSString * const kSCICommentGalleryUploadPref = @"general_comments_gallery_upload";
static const void *kSCICommentGalleryGestureKey = &kSCICommentGalleryGestureKey;

static inline BOOL SCICommentGalleryUploadEnabled(void) {
    return [SCIUtils getBoolPref:kSCICommentGalleryUploadPref];
}

// _lazyPhotoEntryButton / _lazyPhotoCommentButton are IGLazyView wrappers (NOT UIViews).
// The real button view is created lazily and retrieved via -viewIfLoaded.
static UIView *SCICommentComposerLoadedView(id lazyView) {
    if (![lazyView respondsToSelector:@selector(viewIfLoaded)]) return nil;
    id view = ((id (*)(id, SEL))objc_msgSend)(lazyView, @selector(viewIfLoaded));
    return [view isKindOfClass:[UIView class]] ? (UIView *)view : nil;
}

static UIView *SCICommentComposerPhotoEntryButton(UIView *composerView) {
    for (NSString *ivar in @[@"_lazyPhotoEntryButton", @"_lazyPhotoCommentButton"]) {
        id lazyView = [SCIUtils getIvarForObj:composerView name:ivar.UTF8String];
        if (!lazyView) continue;
        UIView *button = SCICommentComposerLoadedView(lazyView);
        if (button && button.window) {
            return button;
        }
    }
    return nil;
}

// The composer view's delegate is the IGCommentComposerController, which exposes the
// public attach entry point used here. Walk up from the button to find the composer.
static UIView *SCICommentComposerViewForView(UIView *view) {
    UIView *candidate = view;
    while (candidate && ![candidate isKindOfClass:NSClassFromString(@"IGCommentComposerView")]) {
        candidate = candidate.superview;
    }
    return candidate;
}

static void SCICommentComposerAttachImage(UIView *composerView, UIImage *image) {
    if (!composerView || !image) return;
    id controller = nil;
    if ([composerView respondsToSelector:@selector(delegate)]) {
        controller = ((id (*)(id, SEL))objc_msgSend)(composerView, @selector(delegate));
    }
    SEL setup = @selector(setupImageBeforeCommentComposingBeginWithSelectedPhoto:);
    if (![controller respondsToSelector:setup]) {
        SCINotify(kSCINotificationDownloadGallery, @"Couldn't attach photo", nil, @"error", SCINotificationToneError);
        return;
    }
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, setup, image);
    } @catch (NSException *exception) {
        SCILog(@"Comments", @"[SCInsta] attach photo threw: %@", exception);
    }
}

static void SCICommentComposerPresentGalleryPicker(UIView *composerView) {
    if (!composerView) return;

    NSSet<NSNumber *> *imageTypes = [NSSet setWithObject:@(SCIGalleryMediaTypeImage)];
    if (![SCIGalleryPickerViewController hasSelectableFilesForAllowedMediaTypes:imageTypes]) {
        SCINotify(kSCINotificationDownloadGallery, @"No photos in Gallery", nil, @"media", SCINotificationToneError);
        return;
    }

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];

    __weak UIView *weakComposer = composerView;
    [SCIGalleryPickerViewController presentFromViewController:topMostController()
                                                       title:@"Choose Photo"
                                           allowedMediaTypes:imageTypes
                                     allowsMultipleSelection:NO
                                                  completion:^(NSArray<SCIGalleryFile *> *selectedFiles) {
        SCIGalleryFile *file = selectedFiles.firstObject;
        UIImage *image = file ? [UIImage imageWithContentsOfFile:file.filePath] : nil;
        if (image) SCICommentComposerAttachImage(weakComposer, image);
    }];
}

@interface SCICommentGalleryUploadTarget : NSObject
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation SCICommentGalleryUploadTarget
+ (instancetype)shared {
    static SCICommentGalleryUploadTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [[SCICommentGalleryUploadTarget alloc] init];
    });
    return target;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    if (!SCICommentGalleryUploadEnabled()) return;
    SCICommentComposerPresentGalleryPicker(SCICommentComposerViewForView(gesture.view));
}
@end

static void SCICommentComposerInstallLongPress(UIView *composerView) {
    if (!SCICommentGalleryUploadEnabled()) return;

    UIView *photoButton = SCICommentComposerPhotoEntryButton(composerView);
    if (!photoButton) return;
    if (objc_getAssociatedObject(photoButton, kSCICommentGalleryGestureKey)) return;

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[SCICommentGalleryUploadTarget shared]
                action:@selector(handleLongPress:)];
    [photoButton addGestureRecognizer:longPress];
    objc_setAssociatedObject(photoButton, kSCICommentGalleryGestureKey, longPress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%group SCICommentComposerGalleryUploadHooks

%hook IGCommentComposerView

- (void)layoutSubviews {
    %orig;
    SCICommentComposerInstallLongPress((UIView *)self);
}

%end

%end

extern "C" void SCIInstallCommentComposerGalleryUploadHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCICommentComposerGalleryUploadHooks);
    });
}

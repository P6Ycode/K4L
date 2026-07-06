#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../AssetUtils.h"
#import "../../Settings/Topics/SPKInstantsSettingsProvider.h"
#import "../../Shared/Gallery/SPKGalleryFile.h"
#import "../../Shared/Gallery/SPKGalleryPickerViewController.h"
#import "../../Shared/Instants/SPKInstantsFrameInjector.h"
#import "../../Shared/PhotoEdit/SPKPhotoEditorViewController.h"
#import "../../Shared/UI/SPKChrome.h"
#import "../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../Utils.h"

static NSString *const kSPKInstantsUploadFromGalleryPref = @"instants_upload_from_gallery";

static BOOL SPKInstantsUploadFromGalleryEnabled(void) {
    return [SPKUtils getBoolPref:kSPKInstantsUploadFromGalleryPref];
}

static UIImage *sSPKInstantsPendingImage = nil;
static CVPixelBufferRef sSPKInstantsCachedPixelBuffer = NULL;
static __weak UIImage *sSPKInstantsCachedImage = nil;
static int32_t sSPKInstantsCachedWidth = 0;
static int32_t sSPKInstantsCachedHeight = 0;
static OSType sSPKInstantsCachedFormat = 0;

// Confirm-capture freeze: the injector keeps the most recent live pixel buffer so
// freezeNow can snapshot it instantly. While frozen, that frame is replayed
// downstream so the preview (and the resulting capture) is the exact frame the
// user pressed the shutter on.
static CVPixelBufferRef sSPKInstantsLatestLivePixelBuffer = NULL;
static CVPixelBufferRef sSPKInstantsFrozenPixelBuffer = NULL;
static BOOL sSPKInstantsIsFrozen = NO;
static dispatch_queue_t SPKInstantsFreezeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.sparkle.sparkle.instants.freeze", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static const void *kSPKInstantsGalleryButtonKey = &kSPKInstantsGalleryButtonKey;
static const void *kSPKInstantsGalleryFrameKey = &kSPKInstantsGalleryFrameKey;
static const void *kSPKInstantsVideoInjectorKey = &kSPKInstantsVideoInjectorKey;
static NSInteger const kSPKInstantsGalleryButtonTag = 921401;
static __weak UIView *sSPKInstantsVisibleCreationView = nil;

static void SPKInstantsPinEdges(UIView *view, UIView *host) {
    if (!view || !host)
        return;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:host.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
    ]];
}

static void SPKInstantsClearFrameCache(void) {
    if (sSPKInstantsCachedPixelBuffer) {
        CVPixelBufferRelease(sSPKInstantsCachedPixelBuffer);
        sSPKInstantsCachedPixelBuffer = NULL;
    }
    sSPKInstantsCachedImage = nil;
    sSPKInstantsCachedWidth = 0;
    sSPKInstantsCachedHeight = 0;
    sSPKInstantsCachedFormat = 0;
}

static UIImage *SPKInstantsNormalizedImage(UIImage *image) {
    if (!image || image.imageOrientation == UIImageOrientationUp)
        return image;
    UIGraphicsBeginImageContextWithOptions(image.size, YES, image.scale);
    [image drawInRect:(CGRect){CGPointZero, image.size}];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalized ?: image;
}

static void SPKInstantsSetPendingImage(UIImage *image) {
    sSPKInstantsPendingImage = SPKInstantsNormalizedImage(image);
    SPKInstantsClearFrameCache();
    UIImage *capturedImage = sSPKInstantsPendingImage;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sSPKInstantsPendingImage == capturedImage) {
            sSPKInstantsPendingImage = nil;
            SPKInstantsClearFrameCache();
        }
    });
}

static UIViewController *SPKInstantsTopPresenter(void) {
    UIViewController *presenter = topMostController();
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    return presenter;
}

static UIWindow *SPKInstantsWindowForView(UIView *view) {
    if (view.window)
        return view.window;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class])
            continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow)
                return window;
        }
    }
    return nil;
}

static void SPKInstantsWalkViews(UIView *root, void (^visitor)(UIView *view, BOOL *stop)) {
    if (!root || !visitor)
        return;
    BOOL stop = NO;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count > 0 && !stop) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        visitor(view, &stop);
        if (stop)
            break;
        for (UIView *subview in view.subviews) {
            [queue addObject:subview];
        }
    }
}

static BOOL SPKInstantsViewIsVisible(UIView *view) {
    return view && view.window && !view.hidden && view.alpha >= 0.05 && view.bounds.size.width > 1.0 && view.bounds.size.height > 1.0;
}

static BOOL SPKInstantsHeaderHasVisibleCreationView(UIView *header) {
    if (SPKInstantsViewIsVisible(sSPKInstantsVisibleCreationView) &&
        SPKInstantsWindowForView(sSPKInstantsVisibleCreationView) == SPKInstantsWindowForView(header)) {
        return YES;
    }

    UIWindow *window = SPKInstantsWindowForView(header);
    if (!window)
        return NO;
    __block BOOL found = NO;
    SPKInstantsWalkViews(window, ^(UIView *view, BOOL *stop) {
        if (!SPKInstantsViewIsVisible(view))
            return;
        if ([NSStringFromClass(view.class) containsString:@"IGQuickSnapCreationView"]) {
            found = YES;
            *stop = YES;
        }
    });
    return found;
}

static BOOL SPKInstantsHeaderHasVisibleSnapView(UIView *header) {
    UIWindow *window = SPKInstantsWindowForView(header);
    if (!window)
        return NO;
    __block BOOL found = NO;
    SPKInstantsWalkViews(window, ^(UIView *view, BOOL *stop) {
        if (!SPKInstantsViewIsVisible(view))
            return;
        if ([NSStringFromClass(view.class) containsString:@"IGQuickSnapImmersiveViewerSingleSnapView"]) {
            found = YES;
            *stop = YES;
        }
    });
    return found;
}

static UIView *SPKInstantsHeaderOwnedView(UIView *header, NSString *key) {
    if (!header || key.length == 0)
        return nil;
    id view = nil;
    @try {
        view = [header valueForKey:key];
    } @catch (__unused NSException *exception) {
    }
    if (![view isKindOfClass:UIView.class]) {
        Ivar ivar = class_getInstanceVariable(header.class, key.UTF8String);
        if (ivar) {
            @try {
                view = object_getIvar(header, ivar);
            } @catch (__unused NSException *exception) {
            }
        }
    }
    return [view isKindOfClass:UIView.class] ? (UIView *)view : nil;
}

static UIView *SPKInstantsHeaderArchiveButton(UIView *header) {
    UIView *archiveButton = SPKInstantsHeaderOwnedView(header, @"archiveButton");
    if (archiveButton && archiveButton.superview == header && !archiveButton.hidden && archiveButton.alpha >= 0.01) {
        return archiveButton;
    }
    return nil;
}

static UIView *SPKInstantsHeaderInWindow(UIWindow *window) {
    if (!window)
        return nil;
    __block UIView *header = nil;
    SPKInstantsWalkViews(window, ^(UIView *view, BOOL *stop) {
        if (!SPKInstantsViewIsVisible(view))
            return;
        if ([NSStringFromClass(view.class) containsString:@"IGQuickSnapNavigationV3HeaderButtonView"]) {
            header = view;
            *stop = YES;
        }
    });
    return header;
}

static NSString *SPKInstantsControlText(UIView *view) {
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        return [button titleForState:UIControlStateNormal] ?: button.accessibilityLabel;
    }
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        return label.text ?: label.accessibilityLabel;
    }
    return view.accessibilityLabel;
}

static BOOL SPKInstantsCreationViewIsPostCapture(UIView *creationView) {
    if (!creationView)
        return NO;
    __block BOOL foundUndo = NO;
    SPKInstantsWalkViews(creationView, ^(UIView *view, BOOL *stop) {
        if (!SPKInstantsViewIsVisible(view))
            return;

        // Language-independent first: an "undo" tap action or undo glyph marks the
        // post-capture edit state. The "Undo" title match is a localized fallback.
        if ([view isKindOfClass:UIControl.class] &&
            [SPKUtils control:(UIControl *)view
                hasTapActionContaining:@"undo"]) {
            foundUndo = YES;
            *stop = YES;
            return;
        }
        if ([view isKindOfClass:UIButton.class]) {
            NSString *iconName = [SPKUtils igImageNameForImage:((UIButton *)view).currentImage];
            if ([iconName rangeOfString:@"undo" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                foundUndo = YES;
                *stop = YES;
                return;
            }
        }

        NSString *text = [SPKInstantsControlText(view) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([text caseInsensitiveCompare:@"Undo"] == NSOrderedSame) {
            foundUndo = YES;
            *stop = YES;
        }
    });
    return foundUndo;
}

static void SPKInstantsClearPendingImageForCreationView(UIView *creationView) {
    (void)creationView;
    sSPKInstantsPendingImage = nil;
    SPKInstantsClearFrameCache();
}

static void SPKInstantsPresentImageForPositioning(UIImage *image) {
    if (!image)
        return;
    [SPKPhotoEditorViewController presentWithSourceImage:SPKInstantsNormalizedImage(image)
                                           configuration:[SPKPhotoEditorConfiguration lockedSquareConfiguration]
                                                    from:SPKInstantsTopPresenter()
                                              completion:^(UIImage *croppedImage) {
                                                  SPKInstantsSetPendingImage(croppedImage);
                                              }];
}

static CVPixelBufferRef SPKInstantsRenderImageToPixelBuffer(UIImage *image,
                                                            int32_t width,
                                                            int32_t height,
                                                            OSType format) CF_RETURNS_RETAINED;
static CVPixelBufferRef SPKInstantsRenderImageToPixelBuffer(UIImage *image,
                                                            int32_t width,
                                                            int32_t height,
                                                            OSType format) {
    if (!image.CGImage || width <= 0 || height <= 0)
        return NULL;
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{},
        (NSString *)kCVPixelBufferMetalCompatibilityKey : @YES,
        (NSString *)kCVPixelBufferOpenGLESCompatibilityKey : @YES
    };

    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          width,
                                          height,
                                          format,
                                          (__bridge CFDictionaryRef)attributes,
                                          &pixelBuffer);
    if (status != kCVReturnSuccess || !pixelBuffer)
        return NULL;

    CGFloat visibleSide = MIN((CGFloat)width, (CGFloat)height);
    CGRect drawRect = CGRectMake(((CGFloat)width - visibleSide) / 2.0,
                                 ((CGFloat)height - visibleSide) / 2.0,
                                 visibleSide,
                                 visibleSide);
    BOOL rendered = NO;

    if (format == kCVPixelFormatType_32BGRA) {
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *base = CVPixelBufferGetBaseAddress(pixelBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(base,
                                                     width,
                                                     height,
                                                     8,
                                                     bytesPerRow,
                                                     colorSpace,
                                                     kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        if (context) {
            CGContextSetFillColorWithColor(context, UIColor.blackColor.CGColor);
            CGContextFillRect(context, CGRectMake(0.0, 0.0, width, height));
            CGContextDrawImage(context, drawRect, image.CGImage);
            CGContextRelease(context);
            rendered = YES;
        }
        CGColorSpaceRelease(colorSpace);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    } else if (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
               format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        size_t bgraBytesPerRow = ((width * 4 + 63) / 64) * 64;
        void *bgra = calloc(bgraBytesPerRow * height, 1);
        if (bgra) {
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(bgra,
                                                         width,
                                                         height,
                                                         8,
                                                         bgraBytesPerRow,
                                                         colorSpace,
                                                         kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
            if (context) {
                CGContextSetFillColorWithColor(context, UIColor.blackColor.CGColor);
                CGContextFillRect(context, CGRectMake(0.0, 0.0, width, height));
                CGContextDrawImage(context, drawRect, image.CGImage);
                CGContextRelease(context);

                if (CVPixelBufferLockBaseAddress(pixelBuffer, 0) == kCVReturnSuccess) {
                    void *yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
                    void *cbcrBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
                    if (yBase && cbcrBase) {
                        vImage_Buffer src = {bgra, (vImagePixelCount)height, (vImagePixelCount)width, bgraBytesPerRow};
                        vImage_Buffer yPlane = {
                            yBase,
                            CVPixelBufferGetHeightOfPlane(pixelBuffer, 0),
                            CVPixelBufferGetWidthOfPlane(pixelBuffer, 0),
                            CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)};
                        vImage_Buffer cbcrPlane = {
                            cbcrBase,
                            CVPixelBufferGetHeightOfPlane(pixelBuffer, 1),
                            CVPixelBufferGetWidthOfPlane(pixelBuffer, 1),
                            CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)};
                        BOOL fullRange = (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
                        vImage_YpCbCrPixelRange range = fullRange
                                                            ? (vImage_YpCbCrPixelRange){0, 128, 255, 255, 255, 1, 255, 0}
                                                            : (vImage_YpCbCrPixelRange){16, 128, 235, 240, 235, 16, 240, 16};
                        vImage_ARGBToYpCbCr conversion;
                        if (vImageConvert_ARGBToYpCbCr_GenerateConversion(kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4,
                                                                          &range,
                                                                          &conversion,
                                                                          kvImageARGB8888,
                                                                          kvImage420Yp8_CbCr8,
                                                                          kvImageNoFlags) == kvImageNoError) {
                            const uint8_t permuteMap[4] = {3, 2, 1, 0};
                            rendered = (vImageConvert_ARGB8888To420Yp8_CbCr8(&src,
                                                                             &yPlane,
                                                                             &cbcrPlane,
                                                                             &conversion,
                                                                             permuteMap,
                                                                             kvImageNoFlags) == kvImageNoError);
                        }
                    }
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
                }
            }
            CGColorSpaceRelease(colorSpace);
            free(bgra);
        }
    }

    if (!rendered) {
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }
    return pixelBuffer;
}

// Wrap an existing pixel buffer (a snapshotted live frame) into a fresh sample
// buffer that carries the template's timing/format, so it can be replayed
// downstream as if it were the current camera frame.
static CMSampleBufferRef SPKInstantsSampleBufferForPixelBuffer(CVPixelBufferRef pixelBuffer,
                                                               CMSampleBufferRef templateBuffer) CF_RETURNS_RETAINED;
static CMSampleBufferRef SPKInstantsSampleBufferForPixelBuffer(CVPixelBufferRef pixelBuffer,
                                                               CMSampleBufferRef templateBuffer) {
    if (!pixelBuffer || !templateBuffer)
        return NULL;

    CMVideoFormatDescriptionRef formatDescription = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,
                                                     pixelBuffer,
                                                     &formatDescription) != noErr ||
        !formatDescription) {
        return NULL;
    }

    CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeZero, kCMTimeInvalid};
    CMSampleBufferGetSampleTimingInfo(templateBuffer, 0, &timing);

    CMSampleBufferRef output = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                       pixelBuffer,
                                       true,
                                       NULL,
                                       NULL,
                                       formatDescription,
                                       &timing,
                                       &output);
    CFRelease(formatDescription);
    return output;
}

static CMSampleBufferRef SPKInstantsSampleBufferForImage(UIImage *image,
                                                         CMSampleBufferRef templateBuffer) CF_RETURNS_RETAINED;
static CMSampleBufferRef SPKInstantsSampleBufferForImage(UIImage *image,
                                                         CMSampleBufferRef templateBuffer) {
    if (!image.CGImage || !templateBuffer)
        return NULL;
    CMFormatDescriptionRef templateFormat = CMSampleBufferGetFormatDescription(templateBuffer);
    if (!templateFormat)
        return NULL;

    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(templateFormat);
    OSType format = CMFormatDescriptionGetMediaSubType(templateFormat);
    if (!sSPKInstantsCachedPixelBuffer ||
        sSPKInstantsCachedImage != image ||
        sSPKInstantsCachedWidth != dimensions.width ||
        sSPKInstantsCachedHeight != dimensions.height ||
        sSPKInstantsCachedFormat != format) {
        SPKInstantsClearFrameCache();
        sSPKInstantsCachedPixelBuffer = SPKInstantsRenderImageToPixelBuffer(image, dimensions.width, dimensions.height, format);
        sSPKInstantsCachedImage = image;
        sSPKInstantsCachedWidth = dimensions.width;
        sSPKInstantsCachedHeight = dimensions.height;
        sSPKInstantsCachedFormat = format;
    }
    if (!sSPKInstantsCachedPixelBuffer)
        return NULL;

    CMVideoFormatDescriptionRef formatDescription = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,
                                                     sSPKInstantsCachedPixelBuffer,
                                                     &formatDescription) != noErr ||
        !formatDescription) {
        return NULL;
    }

    CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeZero, kCMTimeInvalid};
    CMSampleBufferGetSampleTimingInfo(templateBuffer, 0, &timing);

    CMSampleBufferRef output = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                       sSPKInstantsCachedPixelBuffer,
                                       true,
                                       NULL,
                                       NULL,
                                       formatDescription,
                                       &timing,
                                       &output);
    CFRelease(formatDescription);
    return output;
}

@interface SPKInstantsVideoBufferInjector : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id realDelegate;
@end

@implementation SPKInstantsVideoBufferInjector
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.realDelegate respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
    return self.realDelegate;
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    id realDelegate = self.realDelegate;
    if (!realDelegate)
        return;

    // Keep the most recent live frame so a confirm-capture freeze can snapshot it
    // instantly. Cheap: just retain the current pixel buffer (no conversion).
    CVPixelBufferRef livePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (livePixelBuffer) {
        CVPixelBufferRetain(livePixelBuffer);
        dispatch_sync(SPKInstantsFreezeQueue(), ^{
            if (sSPKInstantsLatestLivePixelBuffer) {
                CVPixelBufferRelease(sSPKInstantsLatestLivePixelBuffer);
            }
            sSPKInstantsLatestLivePixelBuffer = livePixelBuffer;
        });
    }

    // Gallery/files upload: when the user has positioned and cropped an image to send,
    // this pending image MUST take priority over everything else — including the
    // confirm-capture frozen frame. The pending image is the user's intended content.
    UIImage *pendingImage = SPKInstantsUploadFromGalleryEnabled() ? sSPKInstantsPendingImage : nil;
    if (pendingImage) {
        CMSampleBufferRef replacement = SPKInstantsSampleBufferForImage(pendingImage, sampleBuffer);
        if (replacement) {
            [(id<AVCaptureVideoDataOutputSampleBufferDelegate>)realDelegate captureOutput:output
                                                                    didOutputSampleBuffer:replacement
                                                                           fromConnection:connection];
            CFRelease(replacement);
            return;
        }
    }

    // While frozen (confirm-capture), replay the snapshotted frame so the preview
    // and the eventual capture are the exact frame the user pressed the shutter on.
    __block CVPixelBufferRef frozen = NULL;
    if (sSPKInstantsIsFrozen) {
        dispatch_sync(SPKInstantsFreezeQueue(), ^{
            if (sSPKInstantsFrozenPixelBuffer) {
                frozen = CVPixelBufferRetain(sSPKInstantsFrozenPixelBuffer);
            }
        });
    }
    if (frozen) {
        CMSampleBufferRef replacement = SPKInstantsSampleBufferForPixelBuffer(frozen, sampleBuffer);
        CVPixelBufferRelease(frozen);
        if (replacement) {
            [(id<AVCaptureVideoDataOutputSampleBufferDelegate>)realDelegate captureOutput:output
                                                                    didOutputSampleBuffer:replacement
                                                                           fromConnection:connection];
            CFRelease(replacement);
            return;
        }
    }

    if ([realDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        [(id<AVCaptureVideoDataOutputSampleBufferDelegate>)realDelegate captureOutput:output
                                                                didOutputSampleBuffer:sampleBuffer
                                                                       fromConnection:connection];
    }
}
@end

@implementation SPKInstantsFrameInjector

+ (void)freezeNow {
    dispatch_sync(SPKInstantsFreezeQueue(), ^{
        if (!sSPKInstantsLatestLivePixelBuffer)
            return;
        if (sSPKInstantsFrozenPixelBuffer) {
            CVPixelBufferRelease(sSPKInstantsFrozenPixelBuffer);
        }
        sSPKInstantsFrozenPixelBuffer = CVPixelBufferRetain(sSPKInstantsLatestLivePixelBuffer);
        sSPKInstantsIsFrozen = YES;
    });
}

+ (void)clearFrozen {
    dispatch_sync(SPKInstantsFreezeQueue(), ^{
        sSPKInstantsIsFrozen = NO;
        if (sSPKInstantsFrozenPixelBuffer) {
            CVPixelBufferRelease(sSPKInstantsFrozenPixelBuffer);
            sSPKInstantsFrozenPixelBuffer = NULL;
        }
    });
}

@end

@interface SPKInstantsImagePickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@implementation SPKInstantsImagePickerDelegate
+ (instancetype)shared {
    static SPKInstantsImagePickerDelegate *delegate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegate = [[SPKInstantsImagePickerDelegate alloc] init];
    });
    return delegate;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES
                               completion:^{
                                   if (image)
                                       SPKInstantsPresentImageForPositioning(image);
                               }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
@end

@interface SPKInstantsDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@end

@implementation SPKInstantsDocumentPickerDelegate
+ (instancetype)shared {
    static SPKInstantsDocumentPickerDelegate *delegate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegate = [[SPKInstantsDocumentPickerDelegate alloc] init];
    });
    return delegate;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url)
        return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    if (scoped)
        [url stopAccessingSecurityScopedResource];
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       if (image)
                                           SPKInstantsPresentImageForPositioning(image);
                                   }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self documentPicker:controller didPickDocumentsAtURLs:(url ? @[ url ] : @[])];
}
@end

@interface SPKInstantsGalleryButtonTarget : NSObject
+ (instancetype)shared;
- (void)buttonTapped:(UIButton *)sender;
@end

static void SPKPresentInstantsSourcePicker(__unused UIView *sourceView) {
    UIViewController *presenter = SPKInstantsTopPresenter();
    NSMutableArray<SPKIGAlertAction *> *actions = [NSMutableArray array];

    [actions addObject:[SPKIGAlertAction actionWithTitle:@"Select from Photos"
                                                   style:SPKIGAlertActionStyleDefault
                                                 handler:^{
                                                     UIImagePickerController *picker = [[UIImagePickerController alloc] init];
                                                     picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                                                     picker.mediaTypes = @[ @"public.image" ];
                                                     picker.delegate = [SPKInstantsImagePickerDelegate shared];
                                                     picker.modalPresentationStyle = UIModalPresentationFullScreen;
                                                     [SPKInstantsTopPresenter() presentViewController:picker animated:YES completion:nil];
                                                 }]];

    if ([SPKGalleryPickerViewController hasSelectableFilesForAllowedMediaTypes:[NSSet setWithObject:@(SPKGalleryMediaTypeImage)]]) {
        [actions addObject:[SPKIGAlertAction actionWithTitle:@"Select from Gallery"
                                                       style:SPKIGAlertActionStyleDefault
                                                     handler:^{
                                                         [SPKGalleryPickerViewController presentFromViewController:SPKInstantsTopPresenter()
                                                                                                             title:@"Choose Photo"
                                                                                                 allowedMediaTypes:[NSSet setWithObject:@(SPKGalleryMediaTypeImage)]
                                                                                           allowsMultipleSelection:NO
                                                                                                        completion:^(NSArray<SPKGalleryFile *> *selectedFiles) {
                                                                                                            SPKGalleryFile *file = selectedFiles.firstObject;
                                                                                                            UIImage *image = file ? [UIImage imageWithContentsOfFile:file.filePath] : nil;
                                                                                                            if (image)
                                                                                                                SPKInstantsPresentImageForPositioning(image);
                                                                                                        }];
                                                     }]];
    }

    [actions addObject:[SPKIGAlertAction actionWithTitle:@"Select from Files"
                                                   style:SPKIGAlertActionStyleDefault
                                                 handler:^{
                                                     UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeImage ] asCopy:YES];
                                                     picker.allowsMultipleSelection = NO;
                                                     picker.delegate = [SPKInstantsDocumentPickerDelegate shared];
                                                     [SPKInstantsTopPresenter() presentViewController:picker animated:YES completion:nil];
                                                 }]];

    [actions addObject:[SPKIGAlertAction actionWithTitle:@"Instants Settings"
                                                   style:SPKIGAlertActionStyleDefault
                                                 handler:^{
                                                     [SPKUtils showSettingsForTopicTitle:@"Instants"];
                                                 }]];

    [actions addObject:[SPKIGAlertAction actionWithTitle:@"Cancel" style:SPKIGAlertActionStyleCancel handler:nil]];
    if (![SPKIGAlertPresenter presentActionSheetFromViewController:presenter
                                                             title:@"Upload Photo"
                                                           message:@"Choose a photo to position and crop, then send as an Instant."
                                                           actions:actions]) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
}

@implementation SPKInstantsGalleryButtonTarget
+ (instancetype)shared {
    static SPKInstantsGalleryButtonTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [[SPKInstantsGalleryButtonTarget alloc] init];
    });
    return target;
}

- (void)buttonTapped:(UIButton *)sender {
    SPKPresentInstantsSourcePicker(sender);
}
@end

static BOOL SPKInstantsGalleryFrameMatches(UIView *view, CGRect frame) {
    if (![view isKindOfClass:UIView.class] || view.hidden || !view.superview)
        return NO;
    return ABS(CGRectGetMinX(view.frame) - CGRectGetMinX(frame)) < 0.5 &&
           ABS(CGRectGetMinY(view.frame) - CGRectGetMinY(frame)) < 0.5 &&
           ABS(CGRectGetWidth(view.frame) - CGRectGetWidth(frame)) < 0.5 &&
           ABS(CGRectGetHeight(view.frame) - CGRectGetHeight(frame)) < 0.5;
}

static UIView *SPKInstantsGalleryFallbackRightAnchor(UIView *header, UIView *host) {
    CGFloat halfWidth = header.bounds.size.width / 2.0;
    UIView *anchor = nil;
    CGFloat minX = CGFLOAT_MAX;

    for (UIView *subview in header.subviews) {
        if (subview == host || subview.hidden || subview.alpha < 0.01)
            continue;
        if (subview.bounds.size.width < 4.0 || subview.bounds.size.height < 4.0)
            continue;
        if (CGRectGetMidX(subview.frame) < halfWidth)
            continue;
        if (CGRectGetMinX(subview.frame) < minX) {
            anchor = subview;
            minX = CGRectGetMinX(subview.frame);
        }
    }
    return anchor;
}

static CGRect SPKInstantsGalleryButtonFrame(UIView *header, UIView *host) {
    CGFloat side = 44.0;
    CGFloat gap = 0.0;
    UIView *anchor = SPKInstantsHeaderArchiveButton(header) ?: SPKInstantsGalleryFallbackRightAnchor(header, host);

    if (anchor) {
        return CGRectMake(CGRectGetMinX(anchor.frame) - side - gap,
                          CGRectGetMidY(anchor.frame) - side / 2.0,
                          side,
                          side);
    }

    return CGRectMake(header.bounds.size.width - side - 12.0,
                      (header.bounds.size.height - side) / 2.0,
                      side,
                      side);
}

static NSString *SPKInstantsGalleryFrameKey(UIView *header, UIView *anchor, CGRect frame) {
    return [NSString stringWithFormat:@"%p|%@|%@",
                                      anchor ?: header,
                                      NSStringFromCGRect(anchor ? anchor.frame : CGRectZero),
                                      NSStringFromCGRect(frame)];
}

static void SPKRemoveInstantsGalleryButton(UIView *header) {
    UIView *host = [header viewWithTag:kSPKInstantsGalleryButtonTag];
    [host removeFromSuperview];
}

static void SPKInstantsInstallGalleryButton(UIView *header) {
    if (!header)
        return;
    UIView *host = [header viewWithTag:kSPKInstantsGalleryButtonTag];
    UIButton *button = [host isKindOfClass:UIView.class] ? objc_getAssociatedObject(host, kSPKInstantsGalleryButtonKey) : nil;
    if (!SPKInstantsUploadFromGalleryEnabled()) {
        SPKRemoveInstantsGalleryButton(header);
        return;
    }

    if (!SPKInstantsHeaderHasVisibleCreationView(header) || SPKInstantsHeaderHasVisibleSnapView(header)) {
        SPKRemoveInstantsGalleryButton(header);
        return;
    }

    if (![button isKindOfClass:UIButton.class]) {
        [host removeFromSuperview];
        host = [[UIView alloc] init];
        host.tag = kSPKInstantsGalleryButtonTag;
        host.translatesAutoresizingMaskIntoConstraints = YES;
        host.clipsToBounds = NO;

        SPKChromeCanvas *canvas = [[SPKChromeCanvas alloc] init];
        canvas.userInteractionEnabled = YES;
        [host addSubview:canvas];
        SPKInstantsPinEdges(canvas, host);

        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.showsMenuAsPrimaryAction = NO;
        button.adjustsImageWhenHighlighted = YES;
        UIImage *image = [SPKAssetUtils instagramIconNamed:@"photo_gallery" pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        [button setImage:image forState:UIControlStateNormal];
        button.tintColor = [UIColor whiteColor];
        [button addTarget:[SPKInstantsGalleryButtonTarget shared]
                      action:@selector(buttonTapped:)
            forControlEvents:UIControlEventTouchUpInside];
        [canvas.contentContainer addSubview:button];
        SPKInstantsPinEdges(button, canvas.contentContainer);
        objc_setAssociatedObject(host, kSPKInstantsGalleryButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [header addSubview:host];
    }

    UIView *anchor = SPKInstantsHeaderArchiveButton(header) ?: SPKInstantsGalleryFallbackRightAnchor(header, host);
    CGRect frame = SPKInstantsGalleryButtonFrame(header, host);
    NSString *frameKey = SPKInstantsGalleryFrameKey(header, anchor, frame);
    NSString *previousFrameKey = objc_getAssociatedObject(host, kSPKInstantsGalleryFrameKey);
    if ([previousFrameKey isEqualToString:frameKey] && SPKInstantsGalleryFrameMatches(host, frame)) {
        return;
    }

    if (!SPKInstantsGalleryFrameMatches(host, frame)) {
        host.frame = frame;
    }
    objc_setAssociatedObject(host, kSPKInstantsGalleryFrameKey, frameKey, OBJC_ASSOCIATION_COPY_NONATOMIC);

    host.hidden = NO;
    host.alpha = 1.0;
    [header bringSubviewToFront:host];
}

typedef void (*SPKInstantsCreationViewLayoutIMP)(id, SEL);
typedef void (*SPKInstantsCreationViewMoveIMP)(id, SEL, id);
typedef void (*SPKInstantsHeaderLayoutIMP)(id, SEL);
typedef void (*SPKInstantsSetSampleDelegateIMP)(id, SEL, id, dispatch_queue_t);

static SPKInstantsCreationViewLayoutIMP orig_creationViewLayoutSubviews = NULL;
static SPKInstantsCreationViewMoveIMP orig_creationViewWillMoveToWindow = NULL;
static SPKInstantsHeaderLayoutIMP orig_headerLayoutSubviews = NULL;
static SPKInstantsSetSampleDelegateIMP orig_setSampleBufferDelegate = NULL;

static void replaced_creationViewLayoutSubviews(id self, SEL _cmd) {
    if (orig_creationViewLayoutSubviews)
        orig_creationViewLayoutSubviews(self, _cmd);
    UIView *creationView = (UIView *)self;
    if (SPKInstantsViewIsVisible(creationView)) {
        sSPKInstantsVisibleCreationView = creationView;
        if (sSPKInstantsPendingImage && SPKInstantsCreationViewIsPostCapture(creationView)) {
            SPKInstantsClearPendingImageForCreationView(creationView);
            return;
        }
        UIView *header = SPKInstantsHeaderInWindow(SPKInstantsWindowForView(creationView));
        if (header)
            SPKInstantsInstallGalleryButton(header);
    }
}

static void replaced_creationViewWillMoveToWindow(id self, SEL _cmd, id window) {
    if (!window && sSPKInstantsPendingImage) {
        SPKInstantsClearPendingImageForCreationView((UIView *)self);
    }
    if (!window && sSPKInstantsVisibleCreationView == (UIView *)self) {
        sSPKInstantsVisibleCreationView = nil;
    }
    if (orig_creationViewWillMoveToWindow)
        orig_creationViewWillMoveToWindow(self, _cmd, window);
}

static void replaced_headerLayoutSubviews(id self, SEL _cmd) {
    if (orig_headerLayoutSubviews)
        orig_headerLayoutSubviews(self, _cmd);
    SPKInstantsInstallGalleryButton((UIView *)self);
}

static BOOL SPKInstantsConfirmCaptureEnabled(void) {
    return [SPKUtils getBoolPref:@"instants_confirm_capture"];
}

static void replaced_setSampleBufferDelegate(id self, SEL _cmd, id delegate, dispatch_queue_t queue) {
    // Wrap the camera's sample-buffer delegate when EITHER feature needs it:
    // gallery upload (replace the feed with a chosen image) or confirm-capture
    // (freeze the live frame while confirming so the sent frame is exact).
    BOOL wants = SPKInstantsUploadFromGalleryEnabled() || SPKInstantsConfirmCaptureEnabled();
    if (delegate && wants && ![delegate isKindOfClass:SPKInstantsVideoBufferInjector.class]) {
        SPKInstantsVideoBufferInjector *injector = [[SPKInstantsVideoBufferInjector alloc] init];
        injector.realDelegate = delegate;
        objc_setAssociatedObject(self, kSPKInstantsVideoInjectorKey, injector, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (orig_setSampleBufferDelegate)
            orig_setSampleBufferDelegate(self, _cmd, injector, queue);
        return;
    }
    if (orig_setSampleBufferDelegate)
        orig_setSampleBufferDelegate(self, _cmd, delegate, queue);
}

static void SPKHookInstanceMethod(const char *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!cls || !method) {
        SPKLog(@"Instants", @"[Sparkle] Missing hook target %s %@", className, NSStringFromSelector(selector));
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

extern "C" void SPKInstallInstantsGalleryUploadHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SPKHookInstanceMethod("_TtC29IGQuickSnapCreationController23IGQuickSnapCreationView",
                              @selector(layoutSubviews),
                              (IMP)replaced_creationViewLayoutSubviews,
                              (IMP *)&orig_creationViewLayoutSubviews);
        SPKHookInstanceMethod("_TtC29IGQuickSnapCreationController23IGQuickSnapCreationView",
                              @selector(willMoveToWindow:),
                              (IMP)replaced_creationViewWillMoveToWindow,
                              (IMP *)&orig_creationViewWillMoveToWindow);
        SPKHookInstanceMethod("_TtC45IGQuickSnapNavigationV3HeaderButtonController39IGQuickSnapNavigationV3HeaderButtonView",
                              @selector(layoutSubviews),
                              (IMP)replaced_headerLayoutSubviews,
                              (IMP *)&orig_headerLayoutSubviews);
        SPKHookInstanceMethod("AVCaptureVideoDataOutput",
                              @selector(setSampleBufferDelegate:queue:),
                              (IMP)replaced_setSampleBufferDelegate,
                              (IMP *)&orig_setSampleBufferDelegate);
        SPKLog(@"Instants", @"[Sparkle] Instants gallery upload hooks installed");
    });
}

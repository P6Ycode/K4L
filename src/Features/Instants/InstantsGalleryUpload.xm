#import <substrate.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Accelerate/Accelerate.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "../../Utils.h"
#import "../../AssetUtils.h"
#import "../../Shared/Gallery/SCIGalleryPickerViewController.h"
#import "../../Shared/Gallery/SCIGalleryFile.h"
#import "../../Shared/UI/SCIIGAlertPresenter.h"
#import "../../Shared/UI/SCIChrome.h"
#import "../../Settings/Topics/SCIInstantsSettingsProvider.h"
#import "../../Shared/Instants/SCIInstantsFrameInjector.h"

static NSString * const kSCIInstantsUploadFromGalleryPref = @"instants_upload_from_gallery";

static BOOL SCIInstantsUploadFromGalleryEnabled(void) {
    return [SCIUtils getBoolPref:kSCIInstantsUploadFromGalleryPref];
}

static UIImage *sSCIInstantsPendingImage = nil;
static CVPixelBufferRef sSCIInstantsCachedPixelBuffer = NULL;
static __weak UIImage *sSCIInstantsCachedImage = nil;
static int32_t sSCIInstantsCachedWidth = 0;
static int32_t sSCIInstantsCachedHeight = 0;
static OSType sSCIInstantsCachedFormat = 0;

// Confirm-capture freeze: the injector keeps the most recent live pixel buffer so
// freezeNow can snapshot it instantly. While frozen, that frame is replayed
// downstream so the preview (and the resulting capture) is the exact frame the
// user pressed the shutter on.
static CVPixelBufferRef sSCIInstantsLatestLivePixelBuffer = NULL;
static CVPixelBufferRef sSCIInstantsFrozenPixelBuffer = NULL;
static BOOL sSCIInstantsIsFrozen = NO;
static dispatch_queue_t SCIInstantsFreezeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.socuul.scinsta.instants.freeze", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static const void *kSCIInstantsGalleryButtonKey = &kSCIInstantsGalleryButtonKey;
static const void *kSCIInstantsGalleryFrameKey = &kSCIInstantsGalleryFrameKey;
static const void *kSCIInstantsVideoInjectorKey = &kSCIInstantsVideoInjectorKey;
static NSInteger const kSCIInstantsGalleryButtonTag = 921401;
static __weak UIView *sSCIInstantsVisibleCreationView = nil;

static void SCIInstantsPinEdges(UIView *view, UIView *host) {
    if (!view || !host) return;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:host.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
    ]];
}

static void SCIInstantsClearFrameCache(void) {
    if (sSCIInstantsCachedPixelBuffer) {
        CVPixelBufferRelease(sSCIInstantsCachedPixelBuffer);
        sSCIInstantsCachedPixelBuffer = NULL;
    }
    sSCIInstantsCachedImage = nil;
    sSCIInstantsCachedWidth = 0;
    sSCIInstantsCachedHeight = 0;
    sSCIInstantsCachedFormat = 0;
}

static UIImage *SCIInstantsNormalizedImage(UIImage *image) {
    if (!image || image.imageOrientation == UIImageOrientationUp) return image;
    UIGraphicsBeginImageContextWithOptions(image.size, YES, image.scale);
    [image drawInRect:(CGRect){CGPointZero, image.size}];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalized ?: image;
}

static void SCIInstantsSetPendingImage(UIImage *image) {
    sSCIInstantsPendingImage = SCIInstantsNormalizedImage(image);
    SCIInstantsClearFrameCache();
    UIImage *capturedImage = sSCIInstantsPendingImage;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sSCIInstantsPendingImage == capturedImage) {
            sSCIInstantsPendingImage = nil;
            SCIInstantsClearFrameCache();
        }
    });
}

static UIViewController *SCIInstantsTopPresenter(void) {
    UIViewController *presenter = topMostController();
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    return presenter;
}

static UIWindow *SCIInstantsWindowForView(UIView *view) {
    if (view.window) return view.window;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return nil;
}

static void SCIInstantsWalkViews(UIView *root, void (^visitor)(UIView *view, BOOL *stop)) {
    if (!root || !visitor) return;
    BOOL stop = NO;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count > 0 && !stop) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        visitor(view, &stop);
        if (stop) break;
        for (UIView *subview in view.subviews) {
            [queue addObject:subview];
        }
    }
}

static BOOL SCIInstantsViewIsVisible(UIView *view) {
    return view && view.window && !view.hidden && view.alpha >= 0.05 && view.bounds.size.width > 1.0 && view.bounds.size.height > 1.0;
}

static BOOL SCIInstantsHeaderHasVisibleCreationView(UIView *header) {
    if (SCIInstantsViewIsVisible(sSCIInstantsVisibleCreationView) &&
        SCIInstantsWindowForView(sSCIInstantsVisibleCreationView) == SCIInstantsWindowForView(header)) {
        return YES;
    }

    UIWindow *window = SCIInstantsWindowForView(header);
    if (!window) return NO;
    __block BOOL found = NO;
    SCIInstantsWalkViews(window, ^(UIView *view, BOOL *stop) {
        if (!SCIInstantsViewIsVisible(view)) return;
        if ([NSStringFromClass(view.class) containsString:@"IGQuickSnapCreationView"]) {
            found = YES;
            *stop = YES;
        }
    });
    return found;
}

static BOOL SCIInstantsHeaderHasVisibleSnapView(UIView *header) {
    UIWindow *window = SCIInstantsWindowForView(header);
    if (!window) return NO;
    __block BOOL found = NO;
    SCIInstantsWalkViews(window, ^(UIView *view, BOOL *stop) {
        if (!SCIInstantsViewIsVisible(view)) return;
        if ([NSStringFromClass(view.class) containsString:@"IGQuickSnapImmersiveViewerSingleSnapView"]) {
            found = YES;
            *stop = YES;
        }
    });
    return found;
}

static UIView *SCIInstantsHeaderOwnedView(UIView *header, NSString *key) {
    if (!header || key.length == 0) return nil;
    id view = nil;
    @try { view = [header valueForKey:key]; } @catch (__unused NSException *exception) {}
    if (![view isKindOfClass:UIView.class]) {
        Ivar ivar = class_getInstanceVariable(header.class, key.UTF8String);
        if (ivar) {
            @try { view = object_getIvar(header, ivar); } @catch (__unused NSException *exception) {}
        }
    }
    return [view isKindOfClass:UIView.class] ? (UIView *)view : nil;
}

static UIView *SCIInstantsHeaderArchiveButton(UIView *header) {
    UIView *archiveButton = SCIInstantsHeaderOwnedView(header, @"archiveButton");
    if (archiveButton && archiveButton.superview == header && !archiveButton.hidden && archiveButton.alpha >= 0.01) {
        return archiveButton;
    }
    return nil;
}

static UIView *SCIInstantsHeaderInWindow(UIWindow *window) {
    if (!window) return nil;
    __block UIView *header = nil;
    SCIInstantsWalkViews(window, ^(UIView *view, BOOL *stop) {
        if (!SCIInstantsViewIsVisible(view)) return;
        if ([NSStringFromClass(view.class) containsString:@"IGQuickSnapNavigationV3HeaderButtonView"]) {
            header = view;
            *stop = YES;
        }
    });
    return header;
}

static NSString *SCIInstantsControlText(UIView *view) {
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

static BOOL SCIInstantsCreationViewIsPostCapture(UIView *creationView) {
    if (!creationView) return NO;
    __block BOOL foundUndo = NO;
    SCIInstantsWalkViews(creationView, ^(UIView *view, BOOL *stop) {
        if (!SCIInstantsViewIsVisible(view)) return;
        NSString *text = [SCIInstantsControlText(view) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([text caseInsensitiveCompare:@"Undo"] == NSOrderedSame) {
            foundUndo = YES;
            *stop = YES;
        }
    });
    return foundUndo;
}

static void SCIInstantsClearPendingImageForCreationView(UIView *creationView) {
    (void)creationView;
    sSCIInstantsPendingImage = nil;
    SCIInstantsClearFrameCache();
}

@interface SCIInstantsCropViewController : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, copy) void (^completion)(UIImage *image);
@end

@implementation SCIInstantsCropViewController {
    UIScrollView *_scrollView;
    UIImageView *_imageView;
    UIView *_overlayView;
    CAShapeLayer *_dimLayer;
    CAShapeLayer *_borderLayer;
    UIButton *_cancelButton;
    UIButton *_useButton;
    CGRect _cropRect;
    BOOL _configured;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.modalPresentationStyle = UIModalPresentationFullScreen;

    _scrollView = [[UIScrollView alloc] init];
    _scrollView.delegate = self;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.bouncesZoom = YES;
    _scrollView.backgroundColor = UIColor.blackColor;
    [self.view addSubview:_scrollView];

    _imageView = [[UIImageView alloc] initWithImage:self.sourceImage];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    [_scrollView addSubview:_imageView];

    _overlayView = [[UIView alloc] init];
    _overlayView.userInteractionEnabled = NO;
    [self.view addSubview:_overlayView];

    _dimLayer = [CAShapeLayer layer];
    _dimLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.55].CGColor;
    _dimLayer.fillRule = kCAFillRuleEvenOdd;
    [_overlayView.layer addSublayer:_dimLayer];

    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = UIColor.clearColor.CGColor;
    _borderLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.75].CGColor;
    _borderLayer.lineWidth = 1.0;
    [_overlayView.layer addSublayer:_borderLayer];

    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    _cancelButton.tintColor = UIColor.whiteColor;
    _cancelButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
    [_cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelButton];

    _useButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_useButton setTitle:@"Use" forState:UIControlStateNormal];
    _useButton.tintColor = UIColor.whiteColor;
    _useButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    [_useButton addTarget:self action:@selector(useTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_useButton];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.sourceImage || self.sourceImage.size.width <= 0.0 || self.sourceImage.size.height <= 0.0) return;

    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat controlsHeight = 64.0 + safe.bottom;
    CGRect workArea = CGRectMake(0.0, safe.top, bounds.size.width, bounds.size.height - safe.top - controlsHeight);
    _scrollView.frame = workArea;
    _overlayView.frame = workArea;

    CGFloat cropSide = MIN(workArea.size.width - 48.0, workArea.size.height - 96.0);
    CGFloat cropWidth = cropSide;
    CGFloat cropHeight = cropSide;
    _cropRect = CGRectMake((workArea.size.width - cropWidth) / 2.0,
                           (workArea.size.height - cropHeight) / 2.0,
                           cropWidth,
                           cropHeight);

    UIBezierPath *dimPath = [UIBezierPath bezierPathWithRect:_overlayView.bounds];
    UIBezierPath *cropPath = [UIBezierPath bezierPathWithRect:_cropRect];
    [dimPath appendPath:cropPath];
    dimPath.usesEvenOddFillRule = YES;
    _dimLayer.frame = _overlayView.bounds;
    _dimLayer.path = dimPath.CGPath;
    _borderLayer.frame = _overlayView.bounds;
    _borderLayer.path = cropPath.CGPath;

    CGSize cancelSize = [_cancelButton intrinsicContentSize];
    CGSize useSize = [_useButton intrinsicContentSize];
    CGFloat buttonY = bounds.size.height - safe.bottom - 18.0;
    _cancelButton.frame = CGRectMake(safe.left + 24.0, buttonY - cancelSize.height, cancelSize.width, cancelSize.height);
    _useButton.frame = CGRectMake(bounds.size.width - safe.right - 24.0 - useSize.width, buttonY - useSize.height, useSize.width, useSize.height);

    if (_configured) return;
    _configured = YES;
    _imageView.frame = (CGRect){ CGPointZero, self.sourceImage.size };
    _scrollView.contentSize = self.sourceImage.size;
    CGFloat minZoom = MAX(_cropRect.size.width / self.sourceImage.size.width,
                          _cropRect.size.height / self.sourceImage.size.height);
    _scrollView.minimumZoomScale = minZoom;
    _scrollView.maximumZoomScale = MAX(minZoom * 4.0, 1.0);
    _scrollView.zoomScale = minZoom;
    _scrollView.contentInset = UIEdgeInsetsMake(CGRectGetMinY(_cropRect),
                                                CGRectGetMinX(_cropRect),
                                                workArea.size.height - CGRectGetMaxY(_cropRect),
                                                workArea.size.width - CGRectGetMaxX(_cropRect));
    CGFloat offsetX = (self.sourceImage.size.width * minZoom - CGRectGetWidth(_cropRect)) / 2.0 - CGRectGetMinX(_cropRect);
    CGFloat offsetY = (self.sourceImage.size.height * minZoom - CGRectGetHeight(_cropRect)) / 2.0 - CGRectGetMinY(_cropRect);
    _scrollView.contentOffset = CGPointMake(MAX(-_scrollView.contentInset.left, offsetX),
                                            MAX(-_scrollView.contentInset.top, offsetY));
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _imageView;
}

- (UIImage *)croppedImage {
    UIImage *source = self.sourceImage;
    if (!source.CGImage) return source;
    CGFloat zoom = _scrollView.zoomScale;
    CGPoint offset = _scrollView.contentOffset;
    CGRect visiblePoints = CGRectMake((CGRectGetMinX(_cropRect) + offset.x) / zoom,
                                      (CGRectGetMinY(_cropRect) + offset.y) / zoom,
                                      CGRectGetWidth(_cropRect) / zoom,
                                      CGRectGetHeight(_cropRect) / zoom);
    UIGraphicsBeginImageContextWithOptions(source.size, YES, source.scale);
    [source drawInRect:(CGRect){ CGPointZero, source.size }];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext() ?: source;
    UIGraphicsEndImageContext();

    CGFloat pixelWidth = (CGFloat)CGImageGetWidth(normalized.CGImage);
    CGFloat pixelHeight = (CGFloat)CGImageGetHeight(normalized.CGImage);
    CGFloat scaleX = pixelWidth / MAX(normalized.size.width, 1.0);
    CGFloat scaleY = pixelHeight / MAX(normalized.size.height, 1.0);
    CGRect pixelRect = CGRectMake(visiblePoints.origin.x * scaleX,
                                  visiblePoints.origin.y * scaleY,
                                  visiblePoints.size.width * scaleX,
                                  visiblePoints.size.height * scaleY);
    CGRect pixelBounds = CGRectMake(0.0, 0.0, pixelWidth, pixelHeight);
    pixelRect = CGRectIntersection(CGRectIntegral(pixelRect), pixelBounds);
    CGFloat side = floor(MIN(CGRectGetWidth(pixelRect), CGRectGetHeight(pixelRect)));
    if (side <= 1.0) return normalized;

    CGFloat centerX = CGRectGetMidX(pixelRect);
    CGFloat centerY = CGRectGetMidY(pixelRect);
    CGFloat originX = round(centerX - side / 2.0);
    CGFloat originY = round(centerY - side / 2.0);
    originX = MIN(MAX(0.0, originX), pixelWidth - side);
    originY = MIN(MAX(0.0, originY), pixelHeight - side);
    pixelRect = CGRectMake(originX, originY, side, side);

    CGImageRef cropped = CGImageCreateWithImageInRect(normalized.CGImage, pixelRect);
    if (!cropped) return normalized;
    UIImage *output = [UIImage imageWithCGImage:cropped scale:normalized.scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    if (!output.CGImage) return normalized;

    size_t outputWidth = CGImageGetWidth(output.CGImage);
    size_t outputHeight = CGImageGetHeight(output.CGImage);
    if (outputWidth == outputHeight) return output;

    CGFloat outputSide = MIN(output.size.width, output.size.height);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(outputSide, outputSide), YES, output.scale);
    [output drawInRect:CGRectMake(0.0, 0.0, outputSide, outputSide)];
    UIImage *squareOutput = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return squareOutput ?: output;
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)useTapped {
    UIImage *image = [self croppedImage];
    void (^completion)(UIImage *) = [self.completion copy];
    [self dismissViewControllerAnimated:YES completion:^{
        if (completion && image) completion(image);
    }];
}

@end

static void SCIInstantsPresentImageForPositioning(UIImage *image) {
    if (!image) return;
    SCIInstantsCropViewController *crop = [[SCIInstantsCropViewController alloc] init];
    crop.sourceImage = SCIInstantsNormalizedImage(image);
    crop.completion = ^(UIImage *croppedImage) {
        SCIInstantsSetPendingImage(croppedImage);
    };
    [SCIInstantsTopPresenter() presentViewController:crop animated:YES completion:nil];
}

static CVPixelBufferRef SCIInstantsRenderImageToPixelBuffer(UIImage *image,
                                                            int32_t width,
                                                            int32_t height,
                                                            OSType format) CF_RETURNS_RETAINED;
static CVPixelBufferRef SCIInstantsRenderImageToPixelBuffer(UIImage *image,
                                                            int32_t width,
                                                            int32_t height,
                                                            OSType format) {
    if (!image.CGImage || width <= 0 || height <= 0) return NULL;
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferOpenGLESCompatibilityKey: @YES
    };

    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          width,
                                          height,
                                          format,
                                          (__bridge CFDictionaryRef)attributes,
                                          &pixelBuffer);
    if (status != kCVReturnSuccess || !pixelBuffer) return NULL;

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
                        vImage_Buffer src = { bgra, (vImagePixelCount)height, (vImagePixelCount)width, bgraBytesPerRow };
                        vImage_Buffer yPlane = {
                            yBase,
                            CVPixelBufferGetHeightOfPlane(pixelBuffer, 0),
                            CVPixelBufferGetWidthOfPlane(pixelBuffer, 0),
                            CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                        };
                        vImage_Buffer cbcrPlane = {
                            cbcrBase,
                            CVPixelBufferGetHeightOfPlane(pixelBuffer, 1),
                            CVPixelBufferGetWidthOfPlane(pixelBuffer, 1),
                            CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
                        };
                        BOOL fullRange = (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
                        vImage_YpCbCrPixelRange range = fullRange
                            ? (vImage_YpCbCrPixelRange){ 0, 128, 255, 255, 255, 1, 255, 0 }
                            : (vImage_YpCbCrPixelRange){ 16, 128, 235, 240, 235, 16, 240, 16 };
                        vImage_ARGBToYpCbCr conversion;
                        if (vImageConvert_ARGBToYpCbCr_GenerateConversion(kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4,
                                                                          &range,
                                                                          &conversion,
                                                                          kvImageARGB8888,
                                                                          kvImage420Yp8_CbCr8,
                                                                          kvImageNoFlags) == kvImageNoError) {
                            const uint8_t permuteMap[4] = { 3, 2, 1, 0 };
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
static CMSampleBufferRef SCIInstantsSampleBufferForPixelBuffer(CVPixelBufferRef pixelBuffer,
                                                               CMSampleBufferRef templateBuffer) CF_RETURNS_RETAINED;
static CMSampleBufferRef SCIInstantsSampleBufferForPixelBuffer(CVPixelBufferRef pixelBuffer,
                                                               CMSampleBufferRef templateBuffer) {
    if (!pixelBuffer || !templateBuffer) return NULL;

    CMVideoFormatDescriptionRef formatDescription = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,
                                                     pixelBuffer,
                                                     &formatDescription) != noErr || !formatDescription) {
        return NULL;
    }

    CMSampleTimingInfo timing = { kCMTimeInvalid, kCMTimeZero, kCMTimeInvalid };
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

static CMSampleBufferRef SCIInstantsSampleBufferForImage(UIImage *image,
                                                         CMSampleBufferRef templateBuffer) CF_RETURNS_RETAINED;
static CMSampleBufferRef SCIInstantsSampleBufferForImage(UIImage *image,
                                                         CMSampleBufferRef templateBuffer) {
    if (!image.CGImage || !templateBuffer) return NULL;
    CMFormatDescriptionRef templateFormat = CMSampleBufferGetFormatDescription(templateBuffer);
    if (!templateFormat) return NULL;

    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(templateFormat);
    OSType format = CMFormatDescriptionGetMediaSubType(templateFormat);
    if (!sSCIInstantsCachedPixelBuffer ||
        sSCIInstantsCachedImage != image ||
        sSCIInstantsCachedWidth != dimensions.width ||
        sSCIInstantsCachedHeight != dimensions.height ||
        sSCIInstantsCachedFormat != format) {
        SCIInstantsClearFrameCache();
        sSCIInstantsCachedPixelBuffer = SCIInstantsRenderImageToPixelBuffer(image, dimensions.width, dimensions.height, format);
        sSCIInstantsCachedImage = image;
        sSCIInstantsCachedWidth = dimensions.width;
        sSCIInstantsCachedHeight = dimensions.height;
        sSCIInstantsCachedFormat = format;
    }
    if (!sSCIInstantsCachedPixelBuffer) return NULL;

    CMVideoFormatDescriptionRef formatDescription = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,
                                                     sSCIInstantsCachedPixelBuffer,
                                                     &formatDescription) != noErr || !formatDescription) {
        return NULL;
    }

    CMSampleTimingInfo timing = { kCMTimeInvalid, kCMTimeZero, kCMTimeInvalid };
    CMSampleBufferGetSampleTimingInfo(templateBuffer, 0, &timing);

    CMSampleBufferRef output = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                       sSCIInstantsCachedPixelBuffer,
                                       true,
                                       NULL,
                                       NULL,
                                       formatDescription,
                                       &timing,
                                       &output);
    CFRelease(formatDescription);
    return output;
}

@interface SCIInstantsVideoBufferInjector : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id realDelegate;
@end

@implementation SCIInstantsVideoBufferInjector
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
    if (!realDelegate) return;

    // Keep the most recent live frame so a confirm-capture freeze can snapshot it
    // instantly. Cheap: just retain the current pixel buffer (no conversion).
    CVPixelBufferRef livePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (livePixelBuffer) {
        CVPixelBufferRetain(livePixelBuffer);
        dispatch_sync(SCIInstantsFreezeQueue(), ^{
            if (sSCIInstantsLatestLivePixelBuffer) {
                CVPixelBufferRelease(sSCIInstantsLatestLivePixelBuffer);
            }
            sSCIInstantsLatestLivePixelBuffer = livePixelBuffer;
        });
    }

    // Gallery/files upload: when the user has positioned and cropped an image to send,
    // this pending image MUST take priority over everything else — including the
    // confirm-capture frozen frame. The pending image is the user's intended content.
    UIImage *pendingImage = SCIInstantsUploadFromGalleryEnabled() ? sSCIInstantsPendingImage : nil;
    if (pendingImage) {
        CMSampleBufferRef replacement = SCIInstantsSampleBufferForImage(pendingImage, sampleBuffer);
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
    if (sSCIInstantsIsFrozen) {
        dispatch_sync(SCIInstantsFreezeQueue(), ^{
            if (sSCIInstantsFrozenPixelBuffer) {
                frozen = CVPixelBufferRetain(sSCIInstantsFrozenPixelBuffer);
            }
        });
    }
    if (frozen) {
        CMSampleBufferRef replacement = SCIInstantsSampleBufferForPixelBuffer(frozen, sampleBuffer);
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

@implementation SCIInstantsFrameInjector

+ (BOOL)hasLiveFrame {
    __block BOOL has = NO;
    dispatch_sync(SCIInstantsFreezeQueue(), ^{
        has = (sSCIInstantsLatestLivePixelBuffer != NULL);
    });
    return has;
}

+ (void)freezeNow {
    dispatch_sync(SCIInstantsFreezeQueue(), ^{
        if (!sSCIInstantsLatestLivePixelBuffer) return;
        if (sSCIInstantsFrozenPixelBuffer) {
            CVPixelBufferRelease(sSCIInstantsFrozenPixelBuffer);
        }
        sSCIInstantsFrozenPixelBuffer = CVPixelBufferRetain(sSCIInstantsLatestLivePixelBuffer);
        sSCIInstantsIsFrozen = YES;
    });
}

+ (void)clearFrozen {
    dispatch_sync(SCIInstantsFreezeQueue(), ^{
        sSCIInstantsIsFrozen = NO;
        if (sSCIInstantsFrozenPixelBuffer) {
            CVPixelBufferRelease(sSCIInstantsFrozenPixelBuffer);
            sSCIInstantsFrozenPixelBuffer = NULL;
        }
    });
}

+ (BOOL)isFrozen {
    return sSCIInstantsIsFrozen;
}

@end

@interface SCIInstantsImagePickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@implementation SCIInstantsImagePickerDelegate
+ (instancetype)shared {
    static SCIInstantsImagePickerDelegate *delegate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegate = [[SCIInstantsImagePickerDelegate alloc] init];
    });
    return delegate;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (image) SCIInstantsPresentImageForPositioning(image);
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
@end

@interface SCIInstantsDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@end

@implementation SCIInstantsDocumentPickerDelegate
+ (instancetype)shared {
    static SCIInstantsDocumentPickerDelegate *delegate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegate = [[SCIInstantsDocumentPickerDelegate alloc] init];
    });
    return delegate;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    if (scoped) [url stopAccessingSecurityScopedResource];
    [controller dismissViewControllerAnimated:YES completion:^{
        if (image) SCIInstantsPresentImageForPositioning(image);
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self documentPicker:controller didPickDocumentsAtURLs:(url ? @[url] : @[])];
}
@end

@interface SCIInstantsGalleryButtonTarget : NSObject
+ (instancetype)shared;
- (void)buttonTapped:(UIButton *)sender;
@end

static void SCIPresentInstantsSourcePicker(__unused UIView *sourceView) {
    UIViewController *presenter = SCIInstantsTopPresenter();
    NSMutableArray<SCIIGAlertAction *> *actions = [NSMutableArray array];

    [actions addObject:[SCIIGAlertAction actionWithTitle:@"Select from Photos" style:SCIIGAlertActionStyleDefault handler:^{
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.mediaTypes = @[@"public.image"];
        picker.delegate = [SCIInstantsImagePickerDelegate shared];
        picker.modalPresentationStyle = UIModalPresentationFullScreen;
        [SCIInstantsTopPresenter() presentViewController:picker animated:YES completion:nil];
    }]];

    if ([SCIGalleryPickerViewController hasSelectableFilesForAllowedMediaTypes:[NSSet setWithObject:@(SCIGalleryMediaTypeImage)]]) {
        [actions addObject:[SCIIGAlertAction actionWithTitle:@"Select from Gallery" style:SCIIGAlertActionStyleDefault handler:^{
            [SCIGalleryPickerViewController presentFromViewController:SCIInstantsTopPresenter()
                                                                title:@"Choose Photo"
                                                    allowedMediaTypes:[NSSet setWithObject:@(SCIGalleryMediaTypeImage)]
                                              allowsMultipleSelection:NO
                                                           completion:^(NSArray<SCIGalleryFile *> *selectedFiles) {
                SCIGalleryFile *file = selectedFiles.firstObject;
                UIImage *image = file ? [UIImage imageWithContentsOfFile:file.filePath] : nil;
                if (image) SCIInstantsPresentImageForPositioning(image);
            }];
        }]];
    }

    [actions addObject:[SCIIGAlertAction actionWithTitle:@"Select from Files" style:SCIIGAlertActionStyleDefault handler:^{
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeImage ] asCopy:YES];
        picker.allowsMultipleSelection = NO;
        picker.delegate = [SCIInstantsDocumentPickerDelegate shared];
        [SCIInstantsTopPresenter() presentViewController:picker animated:YES completion:nil];
    }]];

    [actions addObject:[SCIIGAlertAction actionWithTitle:@"Instants Settings" style:SCIIGAlertActionStyleDefault handler:^{
        [SCIUtils showSettingsForTopicTitle:@"Instants"];
    }]];

    [actions addObject:[SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil]];
    if (![SCIIGAlertPresenter presentActionSheetFromViewController:presenter
                                                            title:@"Upload Photo"
                                                          message:@"Choose a photo to position and crop, then send as an Instant."
                                                          actions:actions]) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
}

@implementation SCIInstantsGalleryButtonTarget
+ (instancetype)shared {
    static SCIInstantsGalleryButtonTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [[SCIInstantsGalleryButtonTarget alloc] init];
    });
    return target;
}

- (void)buttonTapped:(UIButton *)sender {
    SCIPresentInstantsSourcePicker(sender);
}
@end

static BOOL SCIInstantsGalleryFrameMatches(UIView *view, CGRect frame) {
    if (![view isKindOfClass:UIView.class] || view.hidden || !view.superview) return NO;
    return ABS(CGRectGetMinX(view.frame) - CGRectGetMinX(frame)) < 0.5 &&
           ABS(CGRectGetMinY(view.frame) - CGRectGetMinY(frame)) < 0.5 &&
           ABS(CGRectGetWidth(view.frame) - CGRectGetWidth(frame)) < 0.5 &&
           ABS(CGRectGetHeight(view.frame) - CGRectGetHeight(frame)) < 0.5;
}

static UIView *SCIInstantsGalleryFallbackRightAnchor(UIView *header, UIView *host) {
    CGFloat halfWidth = header.bounds.size.width / 2.0;
    UIView *anchor = nil;
    CGFloat minX = CGFLOAT_MAX;

    for (UIView *subview in header.subviews) {
        if (subview == host || subview.hidden || subview.alpha < 0.01) continue;
        if (subview.bounds.size.width < 4.0 || subview.bounds.size.height < 4.0) continue;
        if (CGRectGetMidX(subview.frame) < halfWidth) continue;
        if (CGRectGetMinX(subview.frame) < minX) {
            anchor = subview;
            minX = CGRectGetMinX(subview.frame);
        }
    }
    return anchor;
}

static CGRect SCIInstantsGalleryButtonFrame(UIView *header, UIView *host) {
    CGFloat side = 44.0;
    CGFloat gap = 0.0;
    UIView *anchor = SCIInstantsHeaderArchiveButton(header) ?: SCIInstantsGalleryFallbackRightAnchor(header, host);

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

static NSString *SCIInstantsGalleryFrameKey(UIView *header, UIView *anchor, CGRect frame) {
    return [NSString stringWithFormat:@"%p|%@|%@",
            anchor ?: header,
            NSStringFromCGRect(anchor ? anchor.frame : CGRectZero),
            NSStringFromCGRect(frame)];
}

static void SCIRemoveInstantsGalleryButton(UIView *header) {
    UIView *host = [header viewWithTag:kSCIInstantsGalleryButtonTag];
    [host removeFromSuperview];
}

static void SCIInstantsInstallGalleryButton(UIView *header) {
    if (!header) return;
    UIView *host = [header viewWithTag:kSCIInstantsGalleryButtonTag];
    UIButton *button = [host isKindOfClass:UIView.class] ? objc_getAssociatedObject(host, kSCIInstantsGalleryButtonKey) : nil;
    if (!SCIInstantsUploadFromGalleryEnabled()) {
        SCIRemoveInstantsGalleryButton(header);
        return;
    }

    if (!SCIInstantsHeaderHasVisibleCreationView(header) || SCIInstantsHeaderHasVisibleSnapView(header)) {
        SCIRemoveInstantsGalleryButton(header);
        return;
    }

    if (![button isKindOfClass:UIButton.class]) {
        [host removeFromSuperview];
        host = [[UIView alloc] init];
        host.tag = kSCIInstantsGalleryButtonTag;
        host.translatesAutoresizingMaskIntoConstraints = YES;
        host.clipsToBounds = NO;

        SCIChromeCanvas *canvas = [[SCIChromeCanvas alloc] init];
        canvas.userInteractionEnabled = YES;
        [host addSubview:canvas];
        SCIInstantsPinEdges(canvas, host);

        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.showsMenuAsPrimaryAction = NO;
        button.adjustsImageWhenHighlighted = YES;
        UIImage *image = [SCIAssetUtils instagramIconNamed:@"photo_gallery" pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        [button setImage:image forState:UIControlStateNormal];
        button.tintColor = [UIColor whiteColor];
        [button addTarget:[SCIInstantsGalleryButtonTarget shared]
                   action:@selector(buttonTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        [canvas.contentContainer addSubview:button];
        SCIInstantsPinEdges(button, canvas.contentContainer);
        objc_setAssociatedObject(host, kSCIInstantsGalleryButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [header addSubview:host];
    }

    UIView *anchor = SCIInstantsHeaderArchiveButton(header) ?: SCIInstantsGalleryFallbackRightAnchor(header, host);
    CGRect frame = SCIInstantsGalleryButtonFrame(header, host);
    NSString *frameKey = SCIInstantsGalleryFrameKey(header, anchor, frame);
    NSString *previousFrameKey = objc_getAssociatedObject(host, kSCIInstantsGalleryFrameKey);
    if ([previousFrameKey isEqualToString:frameKey] && SCIInstantsGalleryFrameMatches(host, frame)) {
        return;
    }

    if (!SCIInstantsGalleryFrameMatches(host, frame)) {
        host.frame = frame;
    }
    objc_setAssociatedObject(host, kSCIInstantsGalleryFrameKey, frameKey, OBJC_ASSOCIATION_COPY_NONATOMIC);

    host.hidden = NO;
    host.alpha = 1.0;
    [header bringSubviewToFront:host];
}

typedef void (*SCIInstantsCreationViewLayoutIMP)(id, SEL);
typedef void (*SCIInstantsCreationViewMoveIMP)(id, SEL, id);
typedef void (*SCIInstantsHeaderLayoutIMP)(id, SEL);
typedef void (*SCIInstantsSetSampleDelegateIMP)(id, SEL, id, dispatch_queue_t);

static SCIInstantsCreationViewLayoutIMP orig_creationViewLayoutSubviews = NULL;
static SCIInstantsCreationViewMoveIMP orig_creationViewWillMoveToWindow = NULL;
static SCIInstantsHeaderLayoutIMP orig_headerLayoutSubviews = NULL;
static SCIInstantsSetSampleDelegateIMP orig_setSampleBufferDelegate = NULL;

static void replaced_creationViewLayoutSubviews(id self, SEL _cmd) {
    if (orig_creationViewLayoutSubviews) orig_creationViewLayoutSubviews(self, _cmd);
    UIView *creationView = (UIView *)self;
    if (SCIInstantsViewIsVisible(creationView)) {
        sSCIInstantsVisibleCreationView = creationView;
        if (sSCIInstantsPendingImage && SCIInstantsCreationViewIsPostCapture(creationView)) {
            SCIInstantsClearPendingImageForCreationView(creationView);
            return;
        }
        UIView *header = SCIInstantsHeaderInWindow(SCIInstantsWindowForView(creationView));
        if (header) SCIInstantsInstallGalleryButton(header);
    }
}

static void replaced_creationViewWillMoveToWindow(id self, SEL _cmd, id window) {
    if (!window && sSCIInstantsPendingImage) {
        SCIInstantsClearPendingImageForCreationView((UIView *)self);
    }
    if (!window && sSCIInstantsVisibleCreationView == (UIView *)self) {
        sSCIInstantsVisibleCreationView = nil;
    }
    if (orig_creationViewWillMoveToWindow) orig_creationViewWillMoveToWindow(self, _cmd, window);
}

static void replaced_headerLayoutSubviews(id self, SEL _cmd) {
    if (orig_headerLayoutSubviews) orig_headerLayoutSubviews(self, _cmd);
    SCIInstantsInstallGalleryButton((UIView *)self);
}

static BOOL SCIInstantsConfirmCaptureEnabled(void) {
    return [SCIUtils getBoolPref:@"instants_confirm_capture"];
}

static void replaced_setSampleBufferDelegate(id self, SEL _cmd, id delegate, dispatch_queue_t queue) {
    // Wrap the camera's sample-buffer delegate when EITHER feature needs it:
    // gallery upload (replace the feed with a chosen image) or confirm-capture
    // (freeze the live frame while confirming so the sent frame is exact).
    BOOL wants = SCIInstantsUploadFromGalleryEnabled() || SCIInstantsConfirmCaptureEnabled();
    if (delegate && wants && ![delegate isKindOfClass:SCIInstantsVideoBufferInjector.class]) {
        SCIInstantsVideoBufferInjector *injector = [[SCIInstantsVideoBufferInjector alloc] init];
        injector.realDelegate = delegate;
        objc_setAssociatedObject(self, kSCIInstantsVideoInjectorKey, injector, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (orig_setSampleBufferDelegate) orig_setSampleBufferDelegate(self, _cmd, injector, queue);
        return;
    }
    if (orig_setSampleBufferDelegate) orig_setSampleBufferDelegate(self, _cmd, delegate, queue);
}

static void SCIHookInstanceMethod(const char *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!cls || !method) {
        SCILog(@"Instants", @"[SCInsta] Missing hook target %s %@", className, NSStringFromSelector(selector));
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

extern "C" void SCIInstallInstantsGalleryUploadHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCIHookInstanceMethod("_TtC29IGQuickSnapCreationController23IGQuickSnapCreationView",
                              @selector(layoutSubviews),
                              (IMP)replaced_creationViewLayoutSubviews,
                              (IMP *)&orig_creationViewLayoutSubviews);
        SCIHookInstanceMethod("_TtC29IGQuickSnapCreationController23IGQuickSnapCreationView",
                              @selector(willMoveToWindow:),
                              (IMP)replaced_creationViewWillMoveToWindow,
                              (IMP *)&orig_creationViewWillMoveToWindow);
        SCIHookInstanceMethod("_TtC45IGQuickSnapNavigationV3HeaderButtonController39IGQuickSnapNavigationV3HeaderButtonView",
                              @selector(layoutSubviews),
                              (IMP)replaced_headerLayoutSubviews,
                              (IMP *)&orig_headerLayoutSubviews);
        SCIHookInstanceMethod("AVCaptureVideoDataOutput",
                              @selector(setSampleBufferDelegate:queue:),
                              (IMP)replaced_setSampleBufferDelegate,
                              (IMP *)&orig_setSampleBufferDelegate);
        SCILog(@"Instants", @"[SCInsta] Instants gallery upload hooks installed");
    });
}

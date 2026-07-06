#import "SPKPhotoEditorViewController.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../UI/SPKChipBar.h"
#import "../UI/SPKMediaChrome.h"

#pragma mark - Configuration

@implementation SPKPhotoEditorDoneOption
+ (instancetype)optionWithTitle:(NSString *)title
                     identifier:(NSString *)identifier
                       iconName:(NSString *)iconName {
    SPKPhotoEditorDoneOption *o = [self new];
    o.title = title;
    o.identifier = identifier;
    o.iconName = iconName;
    return o;
}
@end

@implementation SPKPhotoEditorConfiguration

+ (instancetype)lockedSquareConfiguration {
    SPKPhotoEditorConfiguration *c = [SPKPhotoEditorConfiguration new];
    c.aspectMode = SPKPhotoEditorAspectModeLockedSquare;
    c.confirmButtonTitle = @"Use";
    return c;
}

+ (instancetype)freeformConfiguration {
    SPKPhotoEditorConfiguration *c = [SPKPhotoEditorConfiguration new];
    c.aspectMode = SPKPhotoEditorAspectModeFreeform;
    c.confirmButtonTitle = @"Done";
    return c;
}

@end

#pragma mark - Aspect presets

typedef NS_ENUM(NSInteger, SPKPhotoEditorAspect) {
    SPKPhotoEditorAspectOriginal = 0,
    SPKPhotoEditorAspectFreeform,
    SPKPhotoEditorAspectSquare,
    SPKPhotoEditorAspectPortrait23,   // 2:3
    SPKPhotoEditorAspectLandscape32,  // 3:2
    SPKPhotoEditorAspectPortrait34,   // 3:4
    SPKPhotoEditorAspectLandscape43,  // 4:3
    SPKPhotoEditorAspectPortrait45,   // 4:5
    SPKPhotoEditorAspectLandscape54,  // 5:4
    SPKPhotoEditorAspectPortrait916,  // 9:16
    SPKPhotoEditorAspectLandscape169, // 16:9
};

// Order of the aspect chips (freeform mode). Index in this array == chip index.
// Original leads (it's the default selection); each ratio is paired with its
// landscape counterpart.
static const SPKPhotoEditorAspect kSPKAspectOrder[] = {
    SPKPhotoEditorAspectOriginal, SPKPhotoEditorAspectFreeform, SPKPhotoEditorAspectSquare,
    SPKPhotoEditorAspectPortrait23, SPKPhotoEditorAspectLandscape32,
    SPKPhotoEditorAspectPortrait34, SPKPhotoEditorAspectLandscape43,
    SPKPhotoEditorAspectPortrait45, SPKPhotoEditorAspectLandscape54,
    SPKPhotoEditorAspectPortrait916, SPKPhotoEditorAspectLandscape169};
static const NSInteger kSPKAspectCount = sizeof(kSPKAspectOrder) / sizeof(kSPKAspectOrder[0]);

static NSString *SPKPhotoEditorAspectTitle(SPKPhotoEditorAspect aspect) {
    switch (aspect) {
    case SPKPhotoEditorAspectOriginal:
        return @"Original";
    case SPKPhotoEditorAspectFreeform:
        return @"Free";
    case SPKPhotoEditorAspectSquare:
        return @"1:1";
    case SPKPhotoEditorAspectPortrait23:
        return @"2:3";
    case SPKPhotoEditorAspectLandscape32:
        return @"3:2";
    case SPKPhotoEditorAspectPortrait34:
        return @"3:4";
    case SPKPhotoEditorAspectLandscape43:
        return @"4:3";
    case SPKPhotoEditorAspectPortrait45:
        return @"4:5";
    case SPKPhotoEditorAspectLandscape54:
        return @"5:4";
    case SPKPhotoEditorAspectPortrait916:
        return @"9:16";
    case SPKPhotoEditorAspectLandscape169:
        return @"16:9";
    }
    return @"";
}

// Ratio (width / height) for a fixed-ratio preset, or 0 for freeform / original
// (which derive their ratio from the working image).
static CGFloat SPKPhotoEditorAspectRatio(SPKPhotoEditorAspect aspect) {
    switch (aspect) {
    case SPKPhotoEditorAspectSquare:
        return 1.0;
    case SPKPhotoEditorAspectPortrait23:
        return 2.0 / 3.0;
    case SPKPhotoEditorAspectLandscape32:
        return 3.0 / 2.0;
    case SPKPhotoEditorAspectPortrait34:
        return 3.0 / 4.0;
    case SPKPhotoEditorAspectLandscape43:
        return 4.0 / 3.0;
    case SPKPhotoEditorAspectPortrait45:
        return 4.0 / 5.0;
    case SPKPhotoEditorAspectLandscape54:
        return 5.0 / 4.0;
    case SPKPhotoEditorAspectPortrait916:
        return 9.0 / 16.0;
    case SPKPhotoEditorAspectLandscape169:
        return 16.0 / 9.0;
    case SPKPhotoEditorAspectFreeform:
    case SPKPhotoEditorAspectOriginal:
        return 0.0;
    }
    return 0.0;
}

static const CGFloat kSPKEditorCropInsetH = 24.0;
static const CGFloat kSPKEditorCropInsetV = 24.0;
static const CGFloat kSPKEditorHandleTouch = 44.0;
static const CGFloat kSPKEditorMinCropSide = 64.0;
static const CGFloat kSPKEditorControlsRow = 56.0;

#pragma mark - Image helpers

// Redraws to a straight (orientation-Up) bitmap so all crop math works in pixel
// space without worrying about EXIF orientation.
static UIImage *SPKPhotoEditorNormalized(UIImage *image) {
    if (!image || image.imageOrientation == UIImageOrientationUp)
        return image;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:(CGRect){CGPointZero, image.size}];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalized ?: image;
}

// Bakes a 90° rotation (clockwise / counter-clockwise) into a fresh Up-oriented
// bitmap, keeping the crop pipeline rotation-agnostic.
static UIImage *SPKPhotoEditorRotated(UIImage *image, BOOL clockwise) {
    if (!image.CGImage)
        return image;
    CGSize size = image.size;
    CGSize rotated = CGSizeMake(size.height, size.width);
    UIGraphicsBeginImageContextWithOptions(rotated, NO, image.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return image;
    }
    CGContextTranslateCTM(ctx, rotated.width / 2.0, rotated.height / 2.0);
    CGContextRotateCTM(ctx, clockwise ? (M_PI / 2.0) : (-M_PI / 2.0));
    [image drawInRect:CGRectMake(-size.width / 2.0, -size.height / 2.0, size.width, size.height)];
    UIImage *output = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return output ?: image;
}

static UIImage *SPKPhotoEditorFlipped(UIImage *image) {
    if (!image.CGImage)
        return image;
    CGSize size = image.size;
    UIGraphicsBeginImageContextWithOptions(size, NO, image.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return image;
    }
    CGContextTranslateCTM(ctx, size.width, 0.0);
    CGContextScaleCTM(ctx, -1.0, 1.0);
    [image drawInRect:(CGRect){CGPointZero, size}];
    UIImage *output = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return output ?: image;
}

// Mirrors a glyph horizontally and/or vertically, preserving scale and rendering
// mode. The rotate-left/right tool icons share one base asset
// (arrow_bottom_right_bend), flipped to point the right way.
static UIImage *SPKPhotoEditorMirror(UIImage *image, BOOL horizontal, BOOL vertical) {
    if (!image || (!horizontal && !vertical))
        return image;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = image.scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format];
    UIImage *output = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef ctx = rendererContext.CGContext;
        CGContextTranslateCTM(ctx, horizontal ? image.size.width : 0.0, vertical ? image.size.height : 0.0);
        CGContextScaleCTM(ctx, horizontal ? -1.0 : 1.0, vertical ? -1.0 : 1.0);
        [image drawInRect:CGRectMake(0.0, 0.0, image.size.width, image.size.height)];
    }];
    return [output imageWithRenderingMode:image.renderingMode];
}

#pragma mark - Controller

@interface SPKPhotoEditorViewController () <UIScrollViewDelegate, SPKChipBarDelegate>
@end

@implementation SPKPhotoEditorViewController {
    UIImage *_workingImage; // normalized + baked rotations/flips
    UIView *_cropContainer; // the crop pane (like the trim player pane)
    UIScrollView *_scrollView;
    UIImageView *_imageView;
    UIView *_overlayView;
    CAShapeLayer *_dimLayer;
    CAShapeLayer *_borderLayer;
    UIView *_bottomControls;     // rotate / flip row
    SPKChipBar *_aspectChips;    // freeform only
    NSArray<UIView *> *_handles; // freeform corner handles

    SPKPhotoEditorAspect _aspect;
    CGRect _cropRect; // in crop-container coordinates
    BOOL _configured;
}

+ (void)presentWithSourceImage:(UIImage *)image
                 configuration:(SPKPhotoEditorConfiguration *)configuration
                          from:(UIViewController *)presenter
                    completion:(void (^)(UIImage *))completion {
    if (!image || !presenter)
        return;
    SPKPhotoEditorViewController *editor = [[self alloc] init];
    editor.configuration = configuration ?: [SPKPhotoEditorConfiguration freeformConfiguration];
    editor.sourceImage = image;
    editor.completion = completion;
    // Hosted in a navigation controller so the top bar is a native component —
    // Liquid Glass on iOS 26, standard translucent bar earlier. Always dark (like
    // Photos / the trim editor) so black canvas + light controls read correctly.
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [presenter presentViewController:nav animated:YES completion:nil];
}

+ (void)presentWithSourceImage:(UIImage *)image
                 configuration:(SPKPhotoEditorConfiguration *)configuration
                          from:(UIViewController *)presenter
         destinationCompletion:(void (^)(UIImage *, NSString *))destinationCompletion {
    if (!image || !presenter)
        return;
    SPKPhotoEditorViewController *editor = [[self alloc] init];
    editor.configuration = configuration ?: [SPKPhotoEditorConfiguration freeformConfiguration];
    editor.sourceImage = image;
    editor.destinationCompletion = destinationCompletion;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [presenter presentViewController:nav animated:YES completion:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.configuration) {
        self.configuration = [SPKPhotoEditorConfiguration freeformConfiguration];
    }
    self.title = @"Edit";
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramBackground] ?: [UIColor blackColor];

    _workingImage = SPKPhotoEditorNormalized(self.sourceImage);
    _aspect = (self.configuration.aspectMode == SPKPhotoEditorAspectModeLockedSquare)
                  ? SPKPhotoEditorAspectSquare
                  : SPKPhotoEditorAspectOriginal;

    [self setupChrome];
    [self setupCropContainer];
    [self setupBottomControls];
    [self setupAspectChipsIfNeeded];
    [self setupHandlesIfNeeded];
}

#pragma mark - Chrome

- (void)setupChrome {
    UIBarButtonItem *cancelItem = SPKMediaChromeTopBarButtonItem(@"close", self, @selector(cancelTapped));
    cancelItem.accessibilityLabel = @"Cancel";
    // When the caller supplies destinations, Done is a menu (pick where to save
    // without dismissing first); otherwise it's a plain confirm that just returns
    // the edited image to the caller.
    UIBarButtonItem *doneItem;
    if (self.configuration.doneOptions.count > 0) {
        doneItem = SPKMediaChromeTopBarMenuButtonItem(
            @"check", [self buildDoneMenu], self.configuration.confirmButtonTitle ?: @"Done");
    } else {
        doneItem = SPKMediaChromeTopBarButtonItemWithStyle(
            @"check", self, @selector(confirmTapped), UIBarButtonItemStyleDone,
            [SPKUtils SPKColor_InstagramBlue], self.configuration.confirmButtonTitle ?: @"Done");
    }
    SPKMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ cancelItem ]);
    SPKMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ doneItem ]);
}

- (void)setupCropContainer {
    _cropContainer = [[UIView alloc] init];
    _cropContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _cropContainer.backgroundColor = [UIColor blackColor];
    _cropContainer.clipsToBounds = YES;
    [self.view addSubview:_cropContainer];
    [NSLayoutConstraint activateConstraints:@[
        [_cropContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_cropContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_cropContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    _scrollView = [[UIScrollView alloc] init];
    _scrollView.delegate = self;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.bouncesZoom = YES;
    _scrollView.backgroundColor = [UIColor blackColor];
    [_cropContainer addSubview:_scrollView];

    _imageView = [[UIImageView alloc] initWithImage:_workingImage];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    [_scrollView addSubview:_imageView];

    _overlayView = [[UIView alloc] init];
    _overlayView.userInteractionEnabled = NO;
    [_cropContainer addSubview:_overlayView];

    _dimLayer = [CAShapeLayer layer];
    _dimLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.55].CGColor;
    _dimLayer.fillRule = kCAFillRuleEvenOdd;
    [_overlayView.layer addSublayer:_dimLayer];

    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = UIColor.clearColor.CGColor;
    _borderLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.75].CGColor;
    _borderLayer.lineWidth = 1.0;
    [_overlayView.layer addSublayer:_borderLayer];
}

- (UIButton *)toolButtonWithImage:(UIImage *)image
                    accessibility:(NSString *)accessibility
                           action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    if (image) {
        [button setImage:image forState:UIControlStateNormal];
    } else {
        [button setTitle:accessibility forState:UIControlStateNormal];
    }
    button.tintColor = [SPKUtils SPKColor_InstagramPrimaryText] ?: [UIColor whiteColor];
    button.accessibilityLabel = accessibility;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    // A comfortable 44pt tap target around the 24pt glyph.
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:44.0],
        [button.heightAnchor constraintEqualToConstant:44.0],
    ]];
    return button;
}

- (void)setupBottomControls {
    // rotate_left / rotate_right resolve to one shared base arrow asset, flipped
    // into the two directions. The modern bend arrow needs a vertical flip to
    // point upward; the IG 410 fallback (arrow_right_bend_filled) already points
    // the right way, so it skips the vertical flip. "Left" is always the
    // horizontal mirror of "right".
    UIImage *rotBase = [SPKAssetUtils instagramIconNamed:@"rotate_right"
                                               pointSize:24.0
                                           renderingMode:UIImageRenderingModeAlwaysTemplate];
    NSString *resolvedRotate = [SPKAssetUtils resolvedInstagramIconNameForName:@"rotate_right"];
    BOOL verticalFlip = ![resolvedRotate isEqualToString:@"ig_icon_arrow_right_bend_filled_24"];
    UIImage *rotateRight = SPKPhotoEditorMirror(rotBase, NO, verticalFlip);
    UIImage *rotateLeft = SPKPhotoEditorMirror(rotBase, YES, verticalFlip);
    UIImage *mirror = [SPKAssetUtils instagramIconNamed:@"mirror"
                                              pointSize:24.0
                                          renderingMode:UIImageRenderingModeAlwaysTemplate];
    NSArray<UIButton *> *buttons = @[
        [self toolButtonWithImage:rotateLeft
                    accessibility:@"Rotate Left"
                           action:@selector(rotateLeftTapped)],
        [self toolButtonWithImage:mirror
                    accessibility:@"Flip"
                           action:@selector(flipTapped)],
        [self toolButtonWithImage:rotateRight
                    accessibility:@"Rotate Right"
                           action:@selector(rotateRightTapped)],
    ];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionEqualCentering;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    _bottomControls = [[UIView alloc] init];
    _bottomControls.translatesAutoresizingMaskIntoConstraints = NO;
    [_bottomControls addSubview:stack];
    [self.view addSubview:_bottomControls];

    [NSLayoutConstraint activateConstraints:@[
        [_bottomControls.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor
                                                      constant:48.0],
        [_bottomControls.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor
                                                       constant:-48.0],
        [_bottomControls.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
                                                     constant:-8.0],
        [_bottomControls.heightAnchor constraintEqualToConstant:kSPKEditorControlsRow],
        [stack.leadingAnchor constraintEqualToAnchor:_bottomControls.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:_bottomControls.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:_bottomControls.centerYAnchor],
    ]];
}

- (void)setupAspectChipsIfNeeded {
    if (self.configuration.aspectMode != SPKPhotoEditorAspectModeFreeform) {
        // No chip row: the crop pane pins directly above the controls.
        [_cropContainer.bottomAnchor constraintEqualToAnchor:_bottomControls.topAnchor constant:-8.0].active = YES;
        return;
    }

    _aspectChips = [[SPKChipBar alloc] init];
    _aspectChips.translatesAutoresizingMaskIntoConstraints = NO;
    _aspectChips.delegate = self;
    // Content-sized (scrolling) rather than fill-equally: the fill-equally mode
    // shrinks the wider "Original" chip's font to fit its share, leaving the
    // shorter chips at full size. Content sizing keeps every chip's font uniform.
    _aspectChips.distributesToFit = NO;
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:kSPKAspectCount];
    for (NSInteger i = 0; i < kSPKAspectCount; i++) {
        [titles addObject:SPKPhotoEditorAspectTitle(kSPKAspectOrder[i])];
    }
    [_aspectChips setItems:titles symbols:@[]];
    _aspectChips.selectedIndex = 0; // Original (first)
    [self.view addSubview:_aspectChips];

    [NSLayoutConstraint activateConstraints:@[
        [_aspectChips.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [_aspectChips.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [_aspectChips.bottomAnchor constraintEqualToAnchor:_bottomControls.topAnchor
                                                  constant:-4.0],
        [_cropContainer.bottomAnchor constraintEqualToAnchor:_aspectChips.topAnchor
                                                    constant:-4.0],
    ]];
}

- (void)setupHandlesIfNeeded {
    if (self.configuration.aspectMode != SPKPhotoEditorAspectModeFreeform)
        return;
    NSMutableArray<UIView *> *handles = [NSMutableArray arrayWithCapacity:4];
    for (NSInteger i = 0; i < 4; i++) {
        UIView *handle = [[UIView alloc] init];
        handle.backgroundColor = UIColor.clearColor;
        handle.tag = i; // 0=TL 1=TR 2=BL 3=BR
        handle.hidden = YES;
        CALayer *knob = [CALayer layer];
        knob.backgroundColor = UIColor.whiteColor.CGColor;
        knob.cornerRadius = 5.0;
        knob.frame = CGRectMake((kSPKEditorHandleTouch - 10.0) / 2.0,
                                (kSPKEditorHandleTouch - 10.0) / 2.0, 10.0, 10.0);
        [handle.layer addSublayer:knob];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [handle addGestureRecognizer:pan];
        [_cropContainer addSubview:handle];
        [handles addObject:handle];
    }
    _handles = handles;
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = _cropContainer.bounds;
    if (_workingImage.size.width <= 0.0 || _workingImage.size.height <= 0.0 ||
        bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        return;
    }
    _scrollView.frame = bounds;
    _overlayView.frame = bounds;

    if (!_configured) {
        _configured = YES;
        [self resetCropRectForCurrentAspect];
        [self configureScrollForCropRect];
    }
    [self updateOverlay];
    [self layoutHandles];
}

- (CGRect)cropBounds {
    return _cropContainer.bounds;
}

// The largest centred crop rect for the current aspect, fitted inside the crop
// pane with padding. Also the bound a ratio-locked grabber can grow back to.
- (CGRect)maxCropRectForCurrentAspect {
    CGRect area = [self cropBounds];
    CGFloat maxW = area.size.width - kSPKEditorCropInsetH * 2.0;
    CGFloat maxH = area.size.height - kSPKEditorCropInsetV * 2.0;
    if (maxW <= 0 || maxH <= 0)
        return area;

    CGFloat ratio = SPKPhotoEditorAspectRatio(_aspect);
    if (ratio <= 0.0) {
        ratio = _workingImage.size.width / MAX(_workingImage.size.height, 1.0);
    }
    CGFloat w = maxW;
    CGFloat h = w / ratio;
    if (h > maxH) {
        h = maxH;
        w = h * ratio;
    }
    return CGRectMake(area.size.width / 2.0 - w / 2.0,
                      area.size.height / 2.0 - h / 2.0, w, h);
}

- (void)resetCropRectForCurrentAspect {
    _cropRect = [self maxCropRectForCurrentAspect];
}

// Sets zoom + inset so the working image can pan to fill the current crop rect.
- (void)configureScrollForCropRect {
    CGRect area = [self cropBounds];
    // Reset to an unzoomed baseline first. Reconfiguring (aspect change / rotate /
    // flip) while the scroll view still holds the previous zoomScale makes each
    // call re-scale the already-scaled image view, zooming in without bound.
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.maximumZoomScale = 1.0;
    _scrollView.zoomScale = 1.0;
    _imageView.transform = CGAffineTransformIdentity;
    _imageView.frame = (CGRect){CGPointZero, _workingImage.size};
    _scrollView.contentSize = _workingImage.size;
    CGFloat minZoom = MAX(_cropRect.size.width / _workingImage.size.width,
                          _cropRect.size.height / _workingImage.size.height);
    _scrollView.minimumZoomScale = minZoom;
    _scrollView.maximumZoomScale = MAX(minZoom * 4.0, 1.0);
    _scrollView.zoomScale = minZoom;
    _scrollView.contentInset = UIEdgeInsetsMake(CGRectGetMinY(_cropRect),
                                                CGRectGetMinX(_cropRect),
                                                area.size.height - CGRectGetMaxY(_cropRect),
                                                area.size.width - CGRectGetMaxX(_cropRect));
    CGFloat offsetX = (_workingImage.size.width * minZoom - CGRectGetWidth(_cropRect)) / 2.0 - CGRectGetMinX(_cropRect);
    CGFloat offsetY = (_workingImage.size.height * minZoom - CGRectGetHeight(_cropRect)) / 2.0 - CGRectGetMinY(_cropRect);
    _scrollView.contentOffset = CGPointMake(MAX(-_scrollView.contentInset.left, offsetX),
                                            MAX(-_scrollView.contentInset.top, offsetY));
}

// Keeps scroll insets in sync when the crop rect is resized by a grabber, without
// changing zoom, so the image can still pan under the new rect.
- (void)syncScrollInsetForCropRect {
    CGRect area = [self cropBounds];
    _scrollView.contentInset = UIEdgeInsetsMake(CGRectGetMinY(_cropRect),
                                                CGRectGetMinX(_cropRect),
                                                area.size.height - CGRectGetMaxY(_cropRect),
                                                area.size.width - CGRectGetMaxX(_cropRect));
}

- (void)updateOverlay {
    UIBezierPath *dimPath = [UIBezierPath bezierPathWithRect:_overlayView.bounds];
    UIBezierPath *cropPath = [UIBezierPath bezierPathWithRect:_cropRect];
    [dimPath appendPath:cropPath];
    dimPath.usesEvenOddFillRule = YES;
    _dimLayer.frame = _overlayView.bounds;
    _dimLayer.path = dimPath.CGPath;
    _borderLayer.frame = _overlayView.bounds;
    _borderLayer.path = cropPath.CGPath;
}

- (void)layoutHandles {
    if (_handles.count != 4)
        return;
    CGRect r = _cropRect; // already in crop-container coordinates
    CGPoint corners[4] = {
        CGPointMake(CGRectGetMinX(r), CGRectGetMinY(r)),
        CGPointMake(CGRectGetMaxX(r), CGRectGetMinY(r)),
        CGPointMake(CGRectGetMinX(r), CGRectGetMaxY(r)),
        CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r)),
    };
    for (NSInteger i = 0; i < 4; i++) {
        UIView *handle = _handles[i];
        handle.hidden = NO; // grabbers show for every aspect (ratio-locked resize)
        handle.frame = CGRectMake(corners[i].x - kSPKEditorHandleTouch / 2.0,
                                  corners[i].y - kSPKEditorHandleTouch / 2.0,
                                  kSPKEditorHandleTouch, kSPKEditorHandleTouch);
    }
}

#pragma mark - Grabber drag

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint p = [pan locationInView:_cropContainer];
    NSInteger corner = pan.view.tag; // 0=TL 1=TR 2=BL 3=BR
    if (_aspect == SPKPhotoEditorAspectFreeform) {
        [self freeformResizeToPoint:p corner:corner];
    } else {
        [self ratioLockedResizeToPoint:p corner:corner];
    }
    [self syncScrollInsetForCropRect];
    [self updateOverlay];
    [self layoutHandles];
}

// Freeform: each corner moves independently, clamped to the image's on-screen
// frame so the selection can't drag into empty/letterboxed area.
- (void)freeformResizeToPoint:(CGPoint)p corner:(NSInteger)corner {
    CGRect imageRect = [_imageView convertRect:_imageView.bounds toView:_cropContainer];
    CGRect area = CGRectIntersection(imageRect, [self cropBounds]);
    if (CGRectIsNull(area) || CGRectIsEmpty(area))
        area = [self cropBounds];
    p.x = MIN(MAX(p.x, CGRectGetMinX(area)), CGRectGetMaxX(area));
    p.y = MIN(MAX(p.y, CGRectGetMinY(area)), CGRectGetMaxY(area));

    CGFloat left = CGRectGetMinX(_cropRect), right = CGRectGetMaxX(_cropRect);
    CGFloat top = CGRectGetMinY(_cropRect), bottom = CGRectGetMaxY(_cropRect);
    BOOL isLeft = (corner == 0 || corner == 2);
    BOOL isTop = (corner == 0 || corner == 1);
    if (isLeft)
        left = MIN(p.x, right - kSPKEditorMinCropSide);
    else
        right = MAX(p.x, left + kSPKEditorMinCropSide);
    if (isTop)
        top = MIN(p.y, bottom - kSPKEditorMinCropSide);
    else
        bottom = MAX(p.y, top + kSPKEditorMinCropSide);
    _cropRect = CGRectMake(left, top, right - left, bottom - top);
}

// Fixed ratios (and Original): the grabber shrinks/grows the crop while keeping
// its aspect ratio, anchored at the opposite corner and bounded by the aspect's
// max-fit rect (so the image always covers it — only shrink/regrow, no reshape).
- (void)ratioLockedResizeToPoint:(CGPoint)p corner:(NSInteger)corner {
    CGRect bounds = [self maxCropRectForCurrentAspect];
    CGFloat ratio = SPKPhotoEditorAspectRatio(_aspect);
    if (ratio <= 0.0)
        ratio = _cropRect.size.width / MAX(_cropRect.size.height, 1.0);

    p.x = MIN(MAX(p.x, CGRectGetMinX(bounds)), CGRectGetMaxX(bounds));
    p.y = MIN(MAX(p.y, CGRectGetMinY(bounds)), CGRectGetMaxY(bounds));

    BOOL isLeft = (corner == 0 || corner == 2);
    BOOL isTop = (corner == 0 || corner == 1);
    CGFloat anchorX = isLeft ? CGRectGetMaxX(_cropRect) : CGRectGetMinX(_cropRect);
    CGFloat anchorY = isTop ? CGRectGetMaxY(_cropRect) : CGRectGetMinY(_cropRect);

    // Largest ratio-correct box that fits between the anchor and the drag point.
    CGFloat w = fabs(p.x - anchorX);
    CGFloat h = w / ratio;
    if (h > fabs(p.y - anchorY)) {
        h = fabs(p.y - anchorY);
        w = h * ratio;
    }
    // Enforce a minimum, keeping the ratio.
    if (h < kSPKEditorMinCropSide) {
        h = kSPKEditorMinCropSide;
        w = h * ratio;
    }
    if (w < kSPKEditorMinCropSide) {
        w = kSPKEditorMinCropSide;
        h = w / ratio;
    }

    CGFloat newLeft = isLeft ? (anchorX - w) : anchorX;
    CGFloat newTop = isTop ? (anchorY - h) : anchorY;
    _cropRect = CGRectMake(newLeft, newTop, w, h);
}

#pragma mark - SPKChipBarDelegate (aspect)

- (void)chipBar:(SPKChipBar *)bar didSelectIndex:(NSInteger)index {
    if (index < 0 || index >= kSPKAspectCount)
        return;
    _aspect = kSPKAspectOrder[index];
    [self resetCropRectForCurrentAspect];
    [self configureScrollForCropRect];
    [self updateOverlay];
    [self layoutHandles];
}

#pragma mark - Rotate / flip

- (void)rotateLeftTapped {
    [self applyTransform:^{
        self->_workingImage = SPKPhotoEditorRotated(self->_workingImage, NO);
    }];
}
- (void)rotateRightTapped {
    [self applyTransform:^{
        self->_workingImage = SPKPhotoEditorRotated(self->_workingImage, YES);
    }];
}
- (void)flipTapped {
    [self applyTransform:^{
        self->_workingImage = SPKPhotoEditorFlipped(self->_workingImage);
    }];
}

- (void)applyTransform:(void (^)(void))mutate {
    mutate();
    _imageView.image = _workingImage;
    [self resetCropRectForCurrentAspect];
    [self configureScrollForCropRect];
    [self updateOverlay];
    [self layoutHandles];
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _imageView;
}

#pragma mark - Output

- (UIImage *)editedImage {
    UIImage *source = _workingImage;
    if (!source.CGImage)
        return source;
    CGFloat zoom = _scrollView.zoomScale;
    CGPoint offset = _scrollView.contentOffset;
    CGRect visiblePoints = CGRectMake((CGRectGetMinX(_cropRect) + offset.x) / zoom,
                                      (CGRectGetMinY(_cropRect) + offset.y) / zoom,
                                      CGRectGetWidth(_cropRect) / zoom,
                                      CGRectGetHeight(_cropRect) / zoom);

    UIGraphicsBeginImageContextWithOptions(source.size, YES, source.scale);
    [source drawInRect:(CGRect){CGPointZero, source.size}];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext() ?: source;
    UIGraphicsEndImageContext();
    if (!normalized.CGImage)
        return source;

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
    if (CGRectIsEmpty(pixelRect) || CGRectIsNull(pixelRect))
        return normalized;

    CGImageRef cropped = CGImageCreateWithImageInRect(normalized.CGImage, pixelRect);
    if (!cropped)
        return normalized;
    UIImage *output = [UIImage imageWithCGImage:cropped scale:normalized.scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return output.CGImage ? output : normalized;
}

#pragma mark - Confirm / cancel

- (void)cancelTapped {
    // In destination-menu mode, signal the cancel as a nil image so the caller
    // (which retains itself across the async flow) can release. Plain-confirm
    // callers documented that `completion` is not called on cancel, so leave it.
    void (^destinationCompletion)(UIImage *, NSString *) = [self.destinationCompletion copy];
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 if (destinationCompletion)
                                     destinationCompletion(nil, nil);
                             }];
}

- (void)confirmTapped {
    UIImage *image = [self editedImage];
    void (^completion)(UIImage *) = [self.completion copy];
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 if (completion && image)
                                     completion(image);
                             }];
}

- (UIMenu *)buildDoneMenu {
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (SPKPhotoEditorDoneOption *option in self.configuration.doneOptions) {
        NSString *identifier = option.identifier;
        UIImage *image = option.iconName.length > 0
                             ? [SPKAssetUtils instagramIconNamed:option.iconName pointSize:22.0]
                             : nil;
        UIAction *action = [UIAction actionWithTitle:option.title
                                               image:image
                                          identifier:nil
                                             handler:^(__unused UIAction *a) {
                                                 [weakSelf finishWithDestinationTag:identifier];
                                             }];
        [children addObject:action];
    }
    return [UIMenu menuWithTitle:@"" children:children];
}

- (void)finishWithDestinationTag:(NSString *)destinationTag {
    UIImage *image = [self editedImage];
    void (^completion)(UIImage *, NSString *) = [self.destinationCompletion copy];
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 if (completion && image)
                                     completion(image, destinationTag);
                             }];
}

@end

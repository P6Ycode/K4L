#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#include <UIKit/UIKit.h>

#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../ActionButton/ActionButtonCore.h"
#import "../Downloads/SCIDownloadHelpers.h"
#import "../Gallery/SCIGalleryCoreDataStack.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGalleryManager.h"
#import "../Gallery/SCIGalleryOriginController.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../Gallery/SCIGalleryViewController.h"
#import "../MediaDownload/SCIMediaQualityManager.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../UI/SCIMediaChrome.h"
#import "SCIFullScreenImageViewController.h"
#import "SCIFullScreenMediaPlayer.h"
#import "SCIFullScreenVideoViewController.h"
#import "SCIMediaCacheManager.h"
#import "SCIMediaItem.h"

static CGFloat const kDismissAxisLockSlop = 20.0;
static CGFloat const kDismissDistanceRatio = 50.0 / 667.0;
static CGFloat const kDismissMaximumDuration = 0.45;
static CGFloat const kDismissReturnVelocityAnimationRatio = 0.00007;
static CGFloat const kDismissMinimumVelocity = 1.0;
static CGFloat const kDismissMinimumDuration = 0.12;
static CGFloat const kDismissFinalBackdropAlpha = 0.1;
static NSTimeInterval const kPresentationFadeDuration = 0.22;
static NSTimeInterval const kDismissFadeDuration = 0.18;
static NSTimeInterval const kPreviewChromeAnimationDuration = 0.25;
// The bottom toolbar is a real UIToolbar now, so the navigation controller
// folds it into the safe area that AVPlayerViewController already respects. No
// manual control inset is needed; keep it at zero so the scrubber sits just
// above it.
static CGFloat const kVideoPlayerControlBottomInset = 0.0;
static CGFloat const kGalleryPreviewMenuIconPointSize = 22.0;

static UIImage *SCIGalleryPreviewMenuIcon(NSString *resourceName) {
  return [SCIAssetUtils
      instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
               pointSize:kGalleryPreviewMenuIconPointSize];
}

static SCIActionButtonSource SCIActionButtonSourceForPlaybackSource(
    SCIFullScreenPlaybackSource playbackSource) {
  switch (playbackSource) {
  case SCIFullScreenPlaybackSourceFeed:
    return SCIActionButtonSourceFeed;
  case SCIFullScreenPlaybackSourceReels:
    return SCIActionButtonSourceReels;
  case SCIFullScreenPlaybackSourceStories:
    return SCIActionButtonSourceStories;
  case SCIFullScreenPlaybackSourceDirect:
    return SCIActionButtonSourceDirect;
  case SCIFullScreenPlaybackSourceProfile:
    return SCIActionButtonSourceProfile;
  case SCIFullScreenPlaybackSourceInstants:
    return SCIActionButtonSourceInstants;
  case SCIFullScreenPlaybackSourceUnknown:
  default:
    return SCIActionButtonSourceFeed;
  }
}

static SCIDownloadSourceSurface SCIDownloadSurfaceForPlaybackSource(
    SCIFullScreenPlaybackSource playbackSource) {
  return [SCIDownloadHelpers
      sourceSurfaceForActionButtonSource:SCIActionButtonSourceForPlaybackSource(
                                             playbackSource)];
}

static SCIGallerySource SCIGallerySourceForPlaybackSource(
    SCIFullScreenPlaybackSource playbackSource) {
  switch (playbackSource) {
  case SCIFullScreenPlaybackSourceFeed:
    return SCIGallerySourceFeed;
  case SCIFullScreenPlaybackSourceReels:
    return SCIGallerySourceReels;
  case SCIFullScreenPlaybackSourceStories:
    return SCIGallerySourceStories;
  case SCIFullScreenPlaybackSourceDirect:
    return SCIGallerySourceDMs;
  case SCIFullScreenPlaybackSourceProfile:
    return SCIGallerySourceProfile;
  case SCIFullScreenPlaybackSourceInstants:
    return SCIGallerySourceInstants;
  case SCIFullScreenPlaybackSourceUnknown:
  default:
    return SCIGallerySourceOther;
  }
}

static NSString *SCICopiedDownloadURLTitleForPlaybackSource(
    SCIFullScreenPlaybackSource playbackSource, BOOL plural) {
  NSString *noun = nil;
  switch (playbackSource) {
  case SCIFullScreenPlaybackSourceStories:
    noun = @"Story";
    break;
  case SCIFullScreenPlaybackSourceReels:
    noun = @"Reel";
    break;
  case SCIFullScreenPlaybackSourceFeed:
  case SCIFullScreenPlaybackSourceProfile:
    noun = @"Post";
    break;
  case SCIFullScreenPlaybackSourceDirect:
  case SCIFullScreenPlaybackSourceInstants:
  case SCIFullScreenPlaybackSourceUnknown:
  default:
    noun = nil;
    break;
  }

  NSString *urlWord = plural ? @"URLs" : @"URL";
  return noun.length > 0
             ? [NSString
                   stringWithFormat:@"%@ download %@ copied", noun, urlWord]
             : [NSString stringWithFormat:@"Download %@ copied", urlWord];
}

static UIViewController *
SCIPreviewPresenterForContext(SCIFullScreenPlaybackSource playbackSource,
                              UIViewController *sourceController) {
  if ((playbackSource == SCIFullScreenPlaybackSourceStories ||
       playbackSource == SCIFullScreenPlaybackSourceDirect) &&
      sourceController.view.window) {
    return sourceController;
  }

  return topMostController();
}

static CGPoint SCICenterForBounds(CGRect bounds) {
  return CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
}

@interface SCIFullScreenMediaPlayer () <
    UIPageViewControllerDataSource, UIPageViewControllerDelegate,
    UIGestureRecognizerDelegate, UIViewControllerTransitioningDelegate,
    UIViewControllerAnimatedTransitioning,
    UIViewControllerInteractiveTransitioning, SCIFullScreenContentDelegate>

@property(nonatomic, strong) NSArray<SCIMediaItem *> *items;
@property(nonatomic, assign) NSInteger currentIndex;
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber *, UIViewController *> *controllerCache;

@property(nonatomic, strong) UIPageViewController *pageViewController;

@property(nonatomic, strong) UIBarButtonItem *topFavoriteItem;

@property(nonatomic, strong) UIBarButtonItem *savePhotosItem;
@property(nonatomic, strong) UIBarButtonItem *saveGalleryItem;
@property(nonatomic, strong) UIBarButtonItem *deleteGalleryItem;
@property(nonatomic, strong) UIBarButtonItem *shareItem;
@property(nonatomic, strong) UIBarButtonItem *clipboardItem;
@property(nonatomic, strong) UIBarButtonItem *bulkActionsItem;
@property(nonatomic, strong) UIBarButtonItem *galleryOriginItem;
@property(nonatomic, assign) BOOL bulkActionsItemVisible;
@property(nonatomic, assign) BOOL galleryOriginItemVisible;

@property(nonatomic, assign) BOOL isToolbarVisible;
@property(nonatomic, assign) BOOL isSingleItemMode;

@property(nonatomic, assign) BOOL dismissPanDecided;
@property(nonatomic, assign) BOOL dismissPanIsVertical;
@property(nonatomic, weak) UIScrollView *pageScrollView;
@property(nonatomic, assign) BOOL interactiveDismissalInProgress;
@property(nonatomic, assign) CGPoint interactiveDismissAnchorPoint;
@property(nonatomic, strong, nullable) id<UIViewControllerContextTransitioning>
    interactiveDismissTransitionContext;
@property(nonatomic, assign) BOOL presentingTransition;

@property(nonatomic, assign) SCIFullScreenPlaybackSource playbackSource;
@property(nonatomic, weak, nullable) UIView *playbackSourceView;
@property(nonatomic, weak, nullable) UIViewController *playbackSourceController;
@property(nonatomic, copy, nullable)
    SCIMediaPreviewPlaybackBlock pausePlaybackBlock;
@property(nonatomic, copy, nullable)
    SCIMediaPreviewPlaybackBlock resumePlaybackBlock;
@property(nonatomic, assign) BOOL explicitPlaybackPauseActive;

/// Opaque black behind page content (letterboxing); alpha fades during
/// interactive dismiss.
@property(nonatomic, strong) UIView *presentationBackdropView;

@end

@implementation SCIFullScreenMediaPlayer

#pragma mark - Convenience Factories

+ (void)showFileURL:(NSURL *)fileURL {
  [self showFileURL:fileURL fromGallery:NO];
}

+ (void)showFileURL:(NSURL *)fileURL
           metadata:(SCIGallerySaveMetadata *)metadata {
  SCIMediaItem *item = [SCIMediaItem itemWithFileURL:fileURL];
  item.isFromGallery = NO;
  item.galleryMetadata = metadata;

  SCIFullScreenMediaPlayer *player = [[SCIFullScreenMediaPlayer alloc] init];
  player.isFromGallery = NO;

  UIViewController *presenter = topMostController();
  [player playItems:@[ item ] startingAtIndex:0 fromViewController:presenter];
}

+ (void)showFileURL:(NSURL *)fileURL fromGallery:(BOOL)fromGallery {
  SCIMediaItem *item = [SCIMediaItem itemWithFileURL:fileURL];
  item.isFromGallery = fromGallery;

  SCIFullScreenMediaPlayer *player = [[SCIFullScreenMediaPlayer alloc] init];
  player.isFromGallery = fromGallery;

  UIViewController *presenter = topMostController();
  [player playItems:@[ item ] startingAtIndex:0 fromViewController:presenter];
}

+ (void)showGalleryFiles:(NSArray<SCIGalleryFile *> *)files
         startingAtIndex:(NSInteger)index
      fromViewController:(UIViewController *)presenter {
  if (files.count == 0)
    return;

  NSMutableArray<SCIMediaItem *> *items =
      [NSMutableArray arrayWithCapacity:files.count];
  for (SCIGalleryFile *file in files) {
    if (![file fileExists])
      continue;
    SCIMediaItem *item = [SCIMediaItem itemWithGalleryFile:file];
    [items addObject:item];
  }

  if (items.count == 0) {
    SCINotify(kSCINotificationMediaPreviewOpenGallery, @"No files found", nil,
              @"search", SCINotificationToneError);
    return;
  }

  NSInteger adjustedIndex = MAX(0, MIN(index, (NSInteger)items.count - 1));
  SCINotify(kSCINotificationMediaPreviewOpenGallery, @"Opened Gallery media",
            nil, @"media", SCINotificationToneInfo);

  SCIFullScreenMediaPlayer *player = [[SCIFullScreenMediaPlayer alloc] init];
  player.isFromGallery = YES;
  [player playItems:items
         startingAtIndex:adjustedIndex
      fromViewController:presenter];
}

+ (void)showPhotoURLs:(NSArray<NSURL *> *)urls initialIndex:(NSInteger)index {
  [self showPhotoURLs:urls initialIndex:index metadata:nil];
}

+ (void)showPhotoURLs:(NSArray<NSURL *> *)urls
         initialIndex:(NSInteger)index
             metadata:(SCIGallerySaveMetadata *)metadata {
  if (urls.count == 0)
    return;

  NSMutableArray<SCIMediaItem *> *items =
      [NSMutableArray arrayWithCapacity:urls.count];
  for (NSURL *url in urls) {
    SCIMediaItem *item = [SCIMediaItem itemWithFileURL:url];
    item.galleryMetadata = metadata;
    [items addObject:item];
  }

  NSInteger adjustedIndex = MAX(0, MIN(index, (NSInteger)items.count - 1));

  SCIFullScreenMediaPlayer *player = [[SCIFullScreenMediaPlayer alloc] init];
  UIViewController *presenter = topMostController();
  [player playItems:items
         startingAtIndex:adjustedIndex
      fromViewController:presenter];
}

+ (void)showMediaItems:(NSArray<SCIMediaItem *> *)items
       startingAtIndex:(NSInteger)index
              metadata:(SCIGallerySaveMetadata *)metadata {
  [self showMediaItems:items
       startingAtIndex:index
              metadata:metadata
        playbackSource:SCIFullScreenPlaybackSourceUnknown
            sourceView:nil
            controller:nil
         pausePlayback:nil
        resumePlayback:nil];
}

+ (void)showMediaItems:(NSArray<SCIMediaItem *> *)items
       startingAtIndex:(NSInteger)index
              metadata:(SCIGallerySaveMetadata *)metadata
        playbackSource:(SCIFullScreenPlaybackSource)playbackSource
            sourceView:(UIView *)sourceView
            controller:(UIViewController *)controller
         pausePlayback:(SCIMediaPreviewPlaybackBlock)pausePlayback
        resumePlayback:(SCIMediaPreviewPlaybackBlock)resumePlayback {
  if (items.count == 0)
    return;

  if (metadata) {
    for (SCIMediaItem *item in items) {
      if (item && !item.galleryMetadata) {
        item.galleryMetadata = metadata;
      }
    }
  }

  NSInteger adjustedIndex = MAX(0, MIN(index, (NSInteger)items.count - 1));

  SCIFullScreenMediaPlayer *player = [[SCIFullScreenMediaPlayer alloc] init];
  player.isFromGallery = NO;
  [player configurePlaybackContextWithSource:playbackSource
                                  sourceView:sourceView
                                  controller:controller
                               pausePlayback:pausePlayback
                              resumePlayback:resumePlayback];
  UIViewController *presenter =
      SCIPreviewPresenterForContext(playbackSource, controller);
  [player playItems:items
         startingAtIndex:adjustedIndex
      fromViewController:presenter];
}

+ (void)showImage:(UIImage *)image {
  [self showImage:image metadata:nil];
}

+ (void)showImage:(UIImage *)image metadata:(SCIGallerySaveMetadata *)metadata {
  [self showImage:image
            metadata:metadata
      playbackSource:SCIFullScreenPlaybackSourceUnknown
          sourceView:nil
          controller:nil
       pausePlayback:nil
      resumePlayback:nil];
}

+ (void)showImage:(UIImage *)image
          metadata:(SCIGallerySaveMetadata *)metadata
    playbackSource:(SCIFullScreenPlaybackSource)playbackSource
        sourceView:(UIView *)sourceView
        controller:(UIViewController *)controller
     pausePlayback:(SCIMediaPreviewPlaybackBlock)pausePlayback
    resumePlayback:(SCIMediaPreviewPlaybackBlock)resumePlayback {
  if (!image)
    return;
  SCIMediaItem *item = [SCIMediaItem itemWithImage:image];
  item.galleryMetadata = metadata;
  if (metadata.sourceUsername.length > 0) {
    item.title = metadata.sourceUsername;
  }
  item.gallerySaveSource = metadata ? (NSInteger)metadata.source : -1;

  SCIFullScreenMediaPlayer *player = [[SCIFullScreenMediaPlayer alloc] init];
  [player configurePlaybackContextWithSource:playbackSource
                                  sourceView:sourceView
                                  controller:controller
                               pausePlayback:pausePlayback
                              resumePlayback:resumePlayback];
  UIViewController *presenter =
      SCIPreviewPresenterForContext(playbackSource, controller);
  [player playItems:@[ item ] startingAtIndex:0 fromViewController:presenter];
}

+ (void)showRemoteImageURL:(NSURL *)url {
  [self showRemoteImageURL:url metadata:nil];
}

+ (void)showRemoteImageURL:(NSURL *)url
                  metadata:(SCIGallerySaveMetadata *)metadata {
  [self showRemoteImageURL:url
                  metadata:metadata
            playbackSource:SCIFullScreenPlaybackSourceUnknown
                sourceView:nil
                controller:nil
             pausePlayback:nil
            resumePlayback:nil];
}

+ (void)showRemoteImageURL:(NSURL *)url
                  metadata:(SCIGallerySaveMetadata *)metadata
            playbackSource:(SCIFullScreenPlaybackSource)playbackSource
                sourceView:(UIView *)sourceView
                controller:(UIViewController *)controller
             pausePlayback:(SCIMediaPreviewPlaybackBlock)pausePlayback
            resumePlayback:(SCIMediaPreviewPlaybackBlock)resumePlayback {
  if (!url)
    return;

  SCIMediaItem *item = [SCIMediaItem itemWithFileURL:url];
  item.galleryMetadata = metadata;
  if (metadata.sourceUsername.length > 0) {
    item.title = metadata.sourceUsername;
  }
  item.gallerySaveSource = metadata ? (NSInteger)metadata.source : -1;

  SCIFullScreenMediaPlayer *player = [[SCIFullScreenMediaPlayer alloc] init];
  [player configurePlaybackContextWithSource:playbackSource
                                  sourceView:sourceView
                                  controller:controller
                               pausePlayback:pausePlayback
                              resumePlayback:resumePlayback];
  UIViewController *presenter =
      SCIPreviewPresenterForContext(playbackSource, controller);
  [player playItems:@[ item ] startingAtIndex:0 fromViewController:presenter];
}

+ (void)showRemoteImageURL:(NSURL *)url profileUsername:(NSString *)username {
  if (!url)
    return;
  SCIGallerySaveMetadata *meta = [[SCIGallerySaveMetadata alloc] init];
  meta.source = (int16_t)SCIGallerySourceProfile;
  [SCIGalleryOriginController populateProfileMetadata:meta
                                             username:username
                                                 user:nil];
  [self showRemoteImageURL:url metadata:meta];
}

#pragma mark - Playback Context

- (void)configurePlaybackContextWithSource:
            (SCIFullScreenPlaybackSource)playbackSource
                                sourceView:(UIView *)sourceView
                                controller:(UIViewController *)controller
                             pausePlayback:
                                 (SCIMediaPreviewPlaybackBlock)pausePlayback
                            resumePlayback:
                                (SCIMediaPreviewPlaybackBlock)resumePlayback {
  self.playbackSource = playbackSource;
  self.playbackSourceView = sourceView;
  self.playbackSourceController = controller;
  self.pausePlaybackBlock = pausePlayback;
  self.resumePlaybackBlock = resumePlayback;
  self.explicitPlaybackPauseActive = NO;
}

#pragma mark - Present

- (void)playItems:(NSArray<SCIMediaItem *> *)items
       startingAtIndex:(NSInteger)index
    fromViewController:(UIViewController *)presenter {
  _items = [items copy];
  _currentIndex = MAX(0, MIN(index, (NSInteger)items.count - 1));
  _controllerCache = [NSMutableDictionary dictionary];
  _isSingleItemMode = (items.count <= 1);
  _isToolbarVisible = YES;

  [self beginPreviewPlaybackSuppressionIfNeeded];
  UINavigationController *navigationController =
      [[UINavigationController alloc] initWithRootViewController:self];
  navigationController.navigationBar.prefersLargeTitles = NO;
  navigationController.navigationBar.tintColor =
      [SCIUtils SCIColor_InstagramPrimaryText];
  navigationController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
  navigationController.modalPresentationStyle =
      [self shouldUseLifecycleSuppressingPresentation]
          ? UIModalPresentationFullScreen
          : UIModalPresentationOverFullScreen;
  navigationController.modalPresentationCapturesStatusBarAppearance = YES;
  navigationController.transitioningDelegate = self;
  [presenter presentViewController:navigationController
                          animated:YES
                        completion:nil];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
  [super viewDidLoad];
  self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
  self.edgesForExtendedLayout = UIRectEdgeAll;
  self.extendedLayoutIncludesOpaqueBars = YES;
  self.view.backgroundColor = [UIColor clearColor];
  [self setupPresentationBackdrop];

  [self setupTopNavigationItems];
  [self setupBottomBar];
  [self setupPageViewController];
  [self setupDismissGesture];
  [self updateUI];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self prepareViewControllerForDisplay:self.pageViewController.viewControllers
                                            .firstObject];
  [self prepareAdjacentViewControllersAroundIndex:self.currentIndex];
}

- (BOOL)prefersStatusBarHidden {
  return !self.isToolbarVisible;
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation {
  return UIStatusBarAnimationFade;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
  return YES;
}

- (void)setupPresentationBackdrop {
  _presentationBackdropView = [[UIView alloc] initWithFrame:CGRectZero];
  _presentationBackdropView.backgroundColor = [UIColor blackColor];
  _presentationBackdropView.translatesAutoresizingMaskIntoConstraints = NO;
  _presentationBackdropView.alpha = 1.0;
  [self.view addSubview:_presentationBackdropView];
  [NSLayoutConstraint activateConstraints:@[
    [_presentationBackdropView.topAnchor
        constraintEqualToAnchor:self.view.topAnchor],
    [_presentationBackdropView.leadingAnchor
        constraintEqualToAnchor:self.view.leadingAnchor],
    [_presentationBackdropView.trailingAnchor
        constraintEqualToAnchor:self.view.trailingAnchor],
    [_presentationBackdropView.bottomAnchor
        constraintEqualToAnchor:self.view.bottomAnchor],
  ]];
  [self.view sendSubviewToBack:_presentationBackdropView];
}

#pragma mark - Top Navigation

- (void)setupTopNavigationItems {
  UIBarButtonItem *closeItem = SCIMediaChromeTopBarButtonItemWithTint(
      @"xmark", self, @selector(closeTapped), [UIColor labelColor], @"Close");
  SCIMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ closeItem ]);

  if (_isFromGallery) {
    _topFavoriteItem = SCIMediaChromeTopBarButtonItemWithTint(
        @"heart", self, @selector(favoriteTapped), [UIColor labelColor],
        @"Favorite");
  } else {
    _topFavoriteItem = nil;
  }
  [self updateFavoriteButton];
}

#pragma mark - Bottom Bar

- (void)setupBottomBar {
  UINavigationController *nav = self.navigationController;
  SCIMediaChromeConfigureBottomToolbar(nav.toolbar);

  _savePhotosItem = SCIMediaChromeBottomBarButtonItem(
      @"download", @"Save to Photos", self, @selector(saveToPhotos));
  _shareItem = SCIMediaChromeBottomBarButtonItem(@"share", @"Share", self,
                                                 @selector(shareMedia));
  _clipboardItem = SCIMediaChromeBottomBarButtonItem(@"copy", @"Copy", self,
                                                     @selector(copyMedia));

  if (!_isFromGallery && _items.count > 1) {
    _bulkActionsItem =
        SCIMediaChromeBottomBarButtonItem(@"more", @"Download All", nil, nil);
  }

  if (_isFromGallery) {
    _galleryOriginItem =
        SCIMediaChromeBottomBarButtonItem(@"more", @"More", nil, nil);

    _deleteGalleryItem = SCIMediaChromeBottomBarButtonItem(
        @"trash", @"Delete from Gallery", self, @selector(deleteFromGallery));
    _deleteGalleryItem.tintColor = [SCIUtils SCIColor_InstagramDestructive];
  } else {
    _saveGalleryItem = SCIMediaChromeBottomBarButtonItem(
        @"media", @"Save to Gallery", self, @selector(saveToGallery));
  }

  [self rebuildBottomToolbarItems];
  [nav setToolbarHidden:NO animated:NO];

  // Start with transparent bars (letterboxed content). On iOS <= 18 we switch
  // to a material backing when the image is zoomed in behind the bars.
  SCIMediaChromeSetBarsMaterialActive(nav, NO);
}

- (void)rebuildBottomToolbarItems {
  NSMutableArray<UIBarButtonItem *> *primary = [NSMutableArray array];
  NSMutableArray<UIBarButtonItem *> *trailing = [NSMutableArray array];
  [primary addObject:_savePhotosItem];
  [primary addObject:_shareItem];
  [primary addObject:_clipboardItem];

  if (_isFromGallery) {
    // Delete stays in the primary group; "more" breaks out into its own
    // trailing capsule, sitting after the trash icon.
    if (_deleteGalleryItem) {
      [primary addObject:_deleteGalleryItem];
    }
    if (_galleryOriginItem && _galleryOriginItemVisible) {
      [trailing addObject:_galleryOriginItem];
    }
  } else {
    if (_saveGalleryItem) {
      [primary addObject:_saveGalleryItem];
    }
    // "Download all" / bulk actions overflow gets its own trailing capsule.
    if (_bulkActionsItem && _bulkActionsItemVisible) {
      [trailing addObject:_bulkActionsItem];
    }
  }

  self.toolbarItems =
      SCIMediaChromeBottomToolbarItemsWithTrailingGroup(primary, trailing);
}

/// Anchor view for popovers/action sheets presented from the bottom toolbar.
- (UIView *)bottomBarAnchorView {
  return self.navigationController.toolbar ?: self.view;
}

#pragma mark - Page View Controller

- (void)setupPageViewController {
  _pageViewController = [[UIPageViewController alloc]
      initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
        navigationOrientation:
            UIPageViewControllerNavigationOrientationHorizontal
                      options:nil];
  _pageViewController.dataSource = self;
  _pageViewController.delegate = self;

  [self addChildViewController:_pageViewController];
  _pageViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view insertSubview:_pageViewController.view
              aboveSubview:_presentationBackdropView];
  [_pageViewController didMoveToParentViewController:self];

  [NSLayoutConstraint activateConstraints:@[
    [_pageViewController.view.topAnchor
        constraintEqualToAnchor:self.view.topAnchor],
    [_pageViewController.view.bottomAnchor
        constraintEqualToAnchor:self.view.bottomAnchor],
    [_pageViewController.view.leadingAnchor
        constraintEqualToAnchor:self.view.leadingAnchor],
    [_pageViewController.view.trailingAnchor
        constraintEqualToAnchor:self.view.trailingAnchor],
  ]];

  for (UIView *subview in _pageViewController.view.subviews) {
    if ([subview isKindOfClass:[UIScrollView class]]) {
      _pageScrollView = (UIScrollView *)subview;
      break;
    }
  }

  UIViewController *initialVC = [self viewControllerForIndex:_currentIndex];
  if (initialVC) {
    [_pageViewController
        setViewControllers:@[ initialVC ]
                 direction:UIPageViewControllerNavigationDirectionForward
                  animated:NO
                completion:nil];
  }
}

- (UIViewController *)createViewControllerForIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)_items.count)
    return nil;

  SCIMediaItem *item = _items[index];

  if (item.mediaType == SCIMediaItemTypeVideo ||
      item.mediaType == SCIMediaItemTypeAudio) {
    SCIFullScreenVideoViewController *vc =
        [[SCIFullScreenVideoViewController alloc] initWithMediaItem:item];
    vc.delegate = self;
    return vc;
  }

  SCIFullScreenImageViewController *vc =
      [[SCIFullScreenImageViewController alloc] initWithMediaItem:item];
  vc.delegate = self;
  return vc;
}

- (UIViewController *)viewControllerForIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)_items.count)
    return nil;

  NSNumber *cacheKey = @(index);
  UIViewController *cachedController = self.controllerCache[cacheKey];
  if (cachedController) {
    return cachedController;
  }

  UIViewController *controller = [self createViewControllerForIndex:index];
  if (controller) {
    self.controllerCache[cacheKey] = controller;
  }
  return controller;
}

- (NSInteger)indexOfViewController:(UIViewController *)vc {
  SCIMediaItem *item = nil;
  if ([vc isKindOfClass:[SCIFullScreenImageViewController class]]) {
    item = ((SCIFullScreenImageViewController *)vc).mediaItem;
  } else if ([vc isKindOfClass:[SCIFullScreenVideoViewController class]]) {
    item = ((SCIFullScreenVideoViewController *)vc).mediaItem;
  }
  if (!item)
    return NSNotFound;
  return [_items indexOfObjectIdenticalTo:item];
}

- (void)prepareViewControllerForDisplay:(UIViewController *)controller {
  SCIMediaItem *item = nil;
  if ([controller isKindOfClass:[SCIFullScreenImageViewController class]]) {
    item = ((SCIFullScreenImageViewController *)controller).mediaItem;
  } else if ([controller
                 isKindOfClass:[SCIFullScreenVideoViewController class]]) {
    item = ((SCIFullScreenVideoViewController *)controller).mediaItem;
  }
  if (item) {
    [[SCIMediaCacheManager sharedManager] prefetchItem:item];
  }

  if ([controller isKindOfClass:[SCIFullScreenVideoViewController class]]) {
    [self updatePlayerControlInsetsForVideoController:
              (SCIFullScreenVideoViewController *)controller
                                             animated:NO];
    [(SCIFullScreenVideoViewController *)controller prepareForDisplay];
  } else if ([controller
                 isKindOfClass:[SCIFullScreenImageViewController class]]) {
    [(SCIFullScreenImageViewController *)controller preloadContent];
  }
}

- (void)prepareAdjacentViewControllersAroundIndex:(NSInteger)index {
  for (NSInteger resolvedIndex = index - 2; resolvedIndex <= index + 2;
       resolvedIndex++) {
    if (resolvedIndex == index)
      continue;
    if (resolvedIndex < 0 || resolvedIndex >= (NSInteger)self.items.count)
      continue;

    [[SCIMediaCacheManager sharedManager]
        prefetchItem:self.items[resolvedIndex]];
    UIViewController *controller = [self viewControllerForIndex:resolvedIndex];
    if ([controller isKindOfClass:[SCIFullScreenVideoViewController class]]) {
      [(SCIFullScreenVideoViewController *)controller preloadContent];
    } else if ([controller
                   isKindOfClass:[SCIFullScreenImageViewController class]]) {
      [(SCIFullScreenImageViewController *)controller preloadContent];
    }
  }

  [self trimControllerCacheAroundIndex:index];
}

- (void)trimControllerCacheAroundIndex:(NSInteger)index {
  NSArray<NSNumber *> *cachedIndexes = self.controllerCache.allKeys.copy;
  for (NSNumber *cachedIndex in cachedIndexes) {
    NSInteger value = cachedIndex.integerValue;
    if (ABS(value - index) <= 2)
      continue;

    UIViewController *controller = self.controllerCache[cachedIndex];
    if ([controller respondsToSelector:@selector(cleanup)]) {
      [(id)controller cleanup];
    }
    [self.controllerCache removeObjectForKey:cachedIndex];
  }
}

- (SCIFullScreenVideoViewController *)currentVideoViewController {
  UIViewController *currentVC =
      self.pageViewController.viewControllers.firstObject;
  return [currentVC isKindOfClass:[SCIFullScreenVideoViewController class]]
             ? (SCIFullScreenVideoViewController *)currentVC
             : nil;
}

- (void)updatePlayerControlInsetsForVideoController:
            (SCIFullScreenVideoViewController *)videoController
                                           animated:(BOOL)animated {
  UIEdgeInsets insets =
      UIEdgeInsetsMake(0.0, 0.0, kVideoPlayerControlBottomInset, 0.0);
  [videoController setPlayerControlOverlayInsets:insets animated:animated];
}

- (void)updateCurrentVideoPlayerControlInsetsAnimated:(BOOL)animated {
  SCIFullScreenVideoViewController *videoController =
      [self currentVideoViewController];
  if (!videoController)
    return;
  [self updatePlayerControlInsetsForVideoController:videoController
                                           animated:animated];
}

#pragma mark - UIPageViewControllerDataSource

- (UIViewController *)pageViewController:
                          (UIPageViewController *)pageViewController
      viewControllerBeforeViewController:(UIViewController *)viewController {
  NSInteger index = [self indexOfViewController:viewController];
  if (index == NSNotFound || index == 0)
    return nil;
  return [self viewControllerForIndex:index - 1];
}

- (UIViewController *)pageViewController:
                          (UIPageViewController *)pageViewController
       viewControllerAfterViewController:(UIViewController *)viewController {
  NSInteger index = [self indexOfViewController:viewController];
  if (index == NSNotFound || index >= (NSInteger)_items.count - 1)
    return nil;
  return [self viewControllerForIndex:index + 1];
}

#pragma mark - UIPageViewControllerDelegate

- (void)pageViewController:(UIPageViewController *)pageViewController
         didFinishAnimating:(BOOL)finished
    previousViewControllers:
        (NSArray<UIViewController *> *)previousViewControllers
        transitionCompleted:(BOOL)completed {
  if (!completed)
    return;

  UIViewController *currentVC = pageViewController.viewControllers.firstObject;
  NSInteger newIndex = [self indexOfViewController:currentVC];
  if (newIndex == NSNotFound)
    return;

  _currentIndex = newIndex;
  [self updateUI];
  [self prepareViewControllerForDisplay:currentVC];
  [self prepareAdjacentViewControllersAroundIndex:newIndex];

  // Match the bar material to the newly visible page's zoom state.
  BOOL zoomed =
      [currentVC isKindOfClass:[SCIFullScreenImageViewController class]] &&
      ((SCIFullScreenImageViewController *)currentVC).isZoomed;
  SCIMediaChromeSetBarsMaterialActive(self.navigationController, zoomed);

  for (UIViewController *prevVC in previousViewControllers) {
    if ([prevVC isKindOfClass:[SCIFullScreenVideoViewController class]]) {
      [(SCIFullScreenVideoViewController *)prevVC pause];
    }
  }
}

#pragma mark - SCIFullScreenContentDelegate

- (void)mediaContentDidTap:(UIViewController *)controller {
  [self toggleToolbar];
}

- (void)mediaContent:(UIViewController *)controller
    didFailWithError:(NSError *)error {
}

- (void)mediaContent:(UIViewController *)controller
    didChangeZoomState:(BOOL)isZoomed {
  // Only adapt for the visible page.
  if (controller != self.pageViewController.viewControllers.firstObject)
    return;
  SCIMediaChromeSetBarsMaterialActive(self.navigationController, isZoomed);
}

#pragma mark - UI Updates

- (void)updateUI {
  [self updateCounter];
  [self updateFavoriteButton];
  [self updateGalleryOriginButton];
  if (self.bulkActionsItem) {
    UIMenu *menu = [self bulkActionsMenu];
    self.bulkActionsItem.menu = menu;
    self.bulkActionsItemVisible = (menu != nil);
    [self rebuildBottomToolbarItems];
  }
}

- (void)updateCounter {
  if (_isSingleItemMode) {
    self.title = nil;
    return;
  }
  self.title =
      [NSString stringWithFormat:@"%ld of %lu", (long)_currentIndex + 1,
                                 (unsigned long)_items.count];
}

- (void)updateFavoriteButton {
  if (!_topFavoriteItem)
    return;

  SCIMediaItem *item = [self currentItem];
  BOOL isFav = item.galleryFile.isFavorite;
  UIImage *img = isFav ? SCIMediaChromeTopBarIcon(@"heart_filled")
                       : SCIMediaChromeTopBarIcon(@"heart");

  if (!item.galleryFile) {
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[]);
    return;
  }

  _topFavoriteItem.image = img;
  _topFavoriteItem.tintColor =
      isFav ? [UIColor systemPinkColor] : [UIColor labelColor];
  _topFavoriteItem.accessibilityLabel = isFav ? @"Unfavorite" : @"Favorite";
  SCIMediaChromeSetTrailingTopBarItems(self.navigationItem,
                                       @[ _topFavoriteItem ]);
}

- (void)showGalleryOpenFailureMessage:(NSString *)title
                     actionIdentifier:(NSString *)actionIdentifier {
  SCINotify(actionIdentifier, title,
            @"The original content may no longer exist.", @"error_filled",
            SCINotificationToneError);
}

- (void)dismissGalleryFlowForOriginOpenWithCompletion:
    (void (^)(void))completion {
  UIViewController *previewContainer = self.navigationController ?: self;
  UIViewController *galleryPresenter =
      previewContainer.presentingViewController;
  UIViewController *galleryContainer =
      galleryPresenter.navigationController ?: galleryPresenter;

  if (self.isFromGallery && galleryContainer) {
    [self cleanupAll];
    [self restorePreviewPlaybackIfNeeded];
    if ([SCIGalleryManager sharedManager].isLockEnabled) {
      [[SCIGalleryManager sharedManager] lockGallery];
    }
    [previewContainer
        dismissViewControllerAnimated:NO
                           completion:^{
                             [galleryContainer
                                 dismissViewControllerAnimated:YES
                                                    completion:^{
                                                      if ([self.delegate
                                                              respondsToSelector:
                                                                  @selector
                                                              (fullScreenMediaPlayerDidDismiss
                                                                  )]) {
                                                        [self.delegate
                                                                fullScreenMediaPlayerDidDismiss];
                                                      }
                                                      if (completion) {
                                                        completion();
                                                      }
                                                    }];
                           }];
    return;
  }

  [previewContainer
      dismissViewControllerAnimated:YES
                         completion:^{
                           [self cleanupAll];
                           dispatch_async(dispatch_get_main_queue(), ^{
                             [self restorePreviewPlaybackIfNeeded];
                           });
                           if ([self.delegate
                                   respondsToSelector:@selector
                                   (fullScreenMediaPlayerDidDismiss)]) {
                             [self.delegate fullScreenMediaPlayerDidDismiss];
                           }
                           if (completion) {
                             completion();
                           }
                         }];
}

- (void)openOriginalPostForCurrentGalleryItem {
  SCIGalleryFile *file = self.currentItem.galleryFile;
  if ([SCIGalleryOriginController openOriginalPostForGalleryFile:file]) {
    [self dismissGalleryFlowForOriginOpenWithCompletion:^{
      SCINotify(kSCINotificationGalleryOpenOriginal, @"Opened original post",
                nil, @"external_link",
                SCINotificationToneForIconResource(@"external_link"));
    }];
  } else {
    [self showGalleryOpenFailureMessage:@"Unable to open original post"
                       actionIdentifier:kSCINotificationGalleryOpenOriginal];
  }
}

- (void)openProfileForCurrentGalleryItem {
  SCIGalleryFile *file = self.currentItem.galleryFile;
  if ([SCIGalleryOriginController openProfileForGalleryFile:file]) {
    [self dismissGalleryFlowForOriginOpenWithCompletion:^{
      SCINotify(kSCINotificationGalleryOpenProfile, @"Opened profile", nil,
                @"user_circle",
                SCINotificationToneForIconResource(@"user_circle"));
    }];
  } else {
    [self showGalleryOpenFailureMessage:@"Unable to open profile"
                       actionIdentifier:kSCINotificationGalleryOpenProfile];
  }
}

- (UIMenu *)galleryOriginMenuForCurrentItem {
  SCIGalleryFile *file = self.currentItem.galleryFile;
  NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
  __weak typeof(self) weakSelf = self;

  if (file.hasOpenableOriginalMedia) {
    [actions addObject:[UIAction
                           actionWithTitle:@"Open Original Post"
                                     image:SCIGalleryPreviewMenuIcon(
                                               @"external_link")
                                identifier:nil
                                   handler:^(__unused UIAction *action) {
                                     [weakSelf
                                         openOriginalPostForCurrentGalleryItem];
                                   }]];
  }

  if (file.hasOpenableProfile) {
    [actions
        addObject:[UIAction
                      actionWithTitle:@"Open Profile"
                                image:SCIGalleryPreviewMenuIcon(@"user_circle")
                           identifier:nil
                              handler:^(__unused UIAction *action) {
                                [weakSelf openProfileForCurrentGalleryItem];
                              }]];
  }

  if (actions.count == 0) {
    UIAction *empty = [UIAction actionWithTitle:@"No origin actions available"
                                          image:nil
                                     identifier:nil
                                        handler:^(__unused UIAction *action){
                                        }];
    empty.attributes = UIMenuElementAttributesDisabled;
    [actions addObject:empty];
  }

  return [UIMenu menuWithTitle:@"" children:actions];
}

- (void)performSingleGalleryOriginAction {
  SCIGalleryFile *file = self.currentItem.galleryFile;
  if (file.hasOpenableProfile && !file.hasOpenableOriginalMedia) {
    [self openProfileForCurrentGalleryItem];
    return;
  }
  if (file.hasOpenableOriginalMedia && !file.hasOpenableProfile) {
    [self openOriginalPostForCurrentGalleryItem];
  }
}

- (void)updateGalleryOriginButton {
  if (!_galleryOriginItem)
    return;

  SCIGalleryFile *file = self.currentItem.galleryFile;
  BOOL hasOriginal = file.hasOpenableOriginalMedia;
  BOOL hasProfile = file.hasOpenableProfile;
  NSInteger actionCount = (hasOriginal ? 1 : 0) + (hasProfile ? 1 : 0);

  _galleryOriginItemVisible = (file != nil);
  _galleryOriginItem.target = nil;
  _galleryOriginItem.action = nil;

  if (actionCount <= 0) {
    _galleryOriginItem.image = SCIMediaChromeBottomBarIcon(@"more");
    _galleryOriginItem.accessibilityLabel = @"More";
    _galleryOriginItem.enabled = NO;
    _galleryOriginItem.menu = nil;
    [self rebuildBottomToolbarItems];
    return;
  }

  _galleryOriginItem.enabled = YES;

  if (actionCount == 1) {
    NSString *resourceName = hasProfile ? @"user_circle" : @"external_link";
    NSString *label = hasProfile ? @"Open Profile" : @"Open Original Post";
    _galleryOriginItem.image = SCIMediaChromeBottomBarIcon(resourceName);
    _galleryOriginItem.accessibilityLabel = label;
    _galleryOriginItem.menu = nil;
    _galleryOriginItem.target = self;
    _galleryOriginItem.action = @selector(performSingleGalleryOriginAction);
    [self rebuildBottomToolbarItems];
    return;
  }

  _galleryOriginItem.image = SCIMediaChromeBottomBarIcon(@"more");
  _galleryOriginItem.accessibilityLabel = @"More";
  _galleryOriginItem.menu = [self galleryOriginMenuForCurrentItem];
  [self rebuildBottomToolbarItems];
}

#pragma mark - Toolbar Toggle

- (void)toggleToolbar {
  _isToolbarVisible = !_isToolbarVisible;
  UINavigationController *navigationController = self.navigationController;
  BOOL visible = _isToolbarVisible;
  [navigationController setNavigationBarHidden:NO animated:NO];

  navigationController.navigationBar.userInteractionEnabled = visible;
  navigationController.toolbar.userInteractionEnabled = visible;
  [self updateCurrentVideoPlayerControlInsetsAnimated:YES];

  UIToolbar *toolbar = navigationController.toolbar;
  BOOL fadeToolbarAlpha = YES;
  if (@available(iOS 26.0, *)) {
    // iOS 26's floating glass toolbar ignores alpha; drive it through the
    // navigation controller's own hide transition instead.
    fadeToolbarAlpha = NO;
    if (visible)
      toolbar.alpha = 1.0;
    [navigationController setToolbarHidden:!visible animated:YES];
  } else if (visible) {
    // Unhide and reset to transparent, then settle layout so the upcoming
    // fade starts from alpha 0 instead of being snapped by a layout pass
    // that re-asserts the managed toolbar alpha.
    [navigationController setToolbarHidden:NO animated:NO];
    toolbar.alpha = 0.0;
    [navigationController.view layoutIfNeeded];
  }

  [UIView animateWithDuration:kPreviewChromeAnimationDuration
      delay:0.0
      options:UIViewAnimationOptionCurveEaseInOut |
              UIViewAnimationOptionBeginFromCurrentState
      animations:^{
        [self setNeedsStatusBarAppearanceUpdate];
        [navigationController setNeedsStatusBarAppearanceUpdate];
        CGFloat alpha = visible ? 1.0 : 0.0;
        navigationController.navigationBar.alpha = alpha;
        if (fadeToolbarAlpha) {
          toolbar.alpha = alpha;
        }
      }
      completion:^(__unused BOOL finished) {
        // On iOS <= 18 keep the hidden model in sync once the fade-out
        // finishes, otherwise the controller re-asserts toolbar.alpha = 1 on a
        // later layout pass and the bar pops back. Leave alpha at 0 - the show
        // path resets it.
        if (fadeToolbarAlpha && !visible) {
          [navigationController setToolbarHidden:YES animated:NO];
        }
        [self updateCurrentVideoPlayerControlInsetsAnimated:NO];
      }];
}

#pragma mark - Current Item

- (SCIMediaItem *)currentItem {
  if (_currentIndex < 0 || _currentIndex >= (NSInteger)_items.count)
    return nil;
  return _items[_currentIndex];
}

- (NSURL *)currentFileURL {
  SCIMediaItem *item = [self currentItem];
  NSURL *bestURL =
      [[SCIMediaCacheManager sharedManager] bestAvailableFileURLForItem:item];
  return bestURL ?: item.fileURL;
}

- (NSURL *)currentOperationURL {
  SCIMediaItem *item = [self currentItem];
  if (item.fileURL && !item.fileURL.isFileURL) {
    return item.fileURL;
  }
  return [self currentFileURL];
}

- (SCIGallerySaveMetadata *)metadataForMediaItem:(SCIMediaItem *)item {
  if (item.galleryMetadata) {
    if (item.sourceMediaObject && !item.galleryMetadata.importPostedDate) {
      [SCIGalleryOriginController populateMetadata:item.galleryMetadata
                                         fromMedia:item.sourceMediaObject];
    }
    return item.galleryMetadata;
  }

  if (item.title.length == 0 && item.gallerySaveSource < 0) {
    return nil;
  }

  SCIGallerySaveMetadata *meta = [[SCIGallerySaveMetadata alloc] init];
  SCIGallerySource fallbackSource =
      SCIGallerySourceForPlaybackSource(self.playbackSource);
  meta.source = item.gallerySaveSource >= 0 ? (int16_t)item.gallerySaveSource
                                            : (int16_t)fallbackSource;
  if (item.title.length > 0) {
    meta.sourceUsername = item.title;
  }
  if (item.sourceMediaObject) {
    [SCIGalleryOriginController populateMetadata:meta
                                       fromMedia:item.sourceMediaObject];
  }
  return meta;
}

- (SCIGallerySaveMetadata *)metadataForCurrentItem {
  return [self metadataForMediaItem:[self currentItem]];
}

- (void)showCompletedPillForActionIdentifier:(NSString *)identifier
                                       title:(NSString *)title
                                    subtitle:(NSString *)subtitle
                                completedTap:(void (^)(void))completedTap {
  SCINotificationPillView *pill = SCINotifyProgress(identifier, title, nil);
  if (!pill) {
    SCINotificationTriggerHaptic(identifier, SCINotificationToneSuccess);
    return;
  }
  [pill setProgress:1.0f animated:NO];
  [pill showSuccessWithTitle:title subtitle:subtitle icon:nil];
  pill.onTapWhenCompleted = completedTap;
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(SCINotificationPillDuration() * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [pill dismiss];
      });
}

- (void)saveLocalFileURLToPhotos:(NSURL *)fileURL
                   temporaryFile:(BOOL)temporaryFile {
  if (!fileURL)
    return;

  SCIMediaItem *item = [self currentItem];
  SCIGallerySaveMetadata *meta = [self metadataForCurrentItem];
  NSString *ext =
      fileURL.pathExtension.length
          ? fileURL.pathExtension
          : (item.mediaType == SCIMediaItemTypeVideo ? @"mp4" : @"jpg");
  [SCIDownloadHelpers
      submitLocalFileURL:fileURL
               extension:ext
             destination:SCIDownloadDestinationPhotos
                metadata:meta
          notificationID:kSCINotificationMediaPreviewSavePhotos
               presenter:self
              anchorView:[self bottomBarAnchorView]
           sourceSurface:SCIDownloadSurfaceForPlaybackSource(
                             self.playbackSource)];
  if (temporaryFile) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        });
  }
}

#pragma mark - Playback Suppression

- (BOOL)shouldUseLifecycleSuppressingPresentation {
  if (self.isFromGallery) {
    return YES;
  }

  switch (self.playbackSource) {
  case SCIFullScreenPlaybackSourceFeed:
  case SCIFullScreenPlaybackSourceReels:
  case SCIFullScreenPlaybackSourceProfile:
  case SCIFullScreenPlaybackSourceStories:
  case SCIFullScreenPlaybackSourceDirect:
  case SCIFullScreenPlaybackSourceInstants:
    return YES;
  case SCIFullScreenPlaybackSourceUnknown:
  default:
    return NO;
  }
}

- (BOOL)shouldUseExplicitPlaybackCallbacks {
  switch (self.playbackSource) {
  case SCIFullScreenPlaybackSourceStories:
  case SCIFullScreenPlaybackSourceDirect:
  case SCIFullScreenPlaybackSourceInstants:
    return YES;
  case SCIFullScreenPlaybackSourceFeed:
  case SCIFullScreenPlaybackSourceReels:
  case SCIFullScreenPlaybackSourceProfile:
  case SCIFullScreenPlaybackSourceUnknown:
  default:
    return NO;
  }
}

- (void)beginPreviewPlaybackSuppressionIfNeeded {
  if ([self shouldUseExplicitPlaybackCallbacks] && self.pausePlaybackBlock &&
      !self.explicitPlaybackPauseActive) {
    self.pausePlaybackBlock();
    self.explicitPlaybackPauseActive = YES;
  }
}

- (void)restorePreviewPlaybackIfNeeded {
  if (self.explicitPlaybackPauseActive && self.resumePlaybackBlock) {
    self.resumePlaybackBlock();
  }
  self.explicitPlaybackPauseActive = NO;
}

#pragma mark - Actions

- (void)closeTapped {
  UIViewController *dismissTarget = self.navigationController ?: self;
  [dismissTarget
      dismissViewControllerAnimated:YES
                         completion:^{
                           [self cleanupAll];
                           dispatch_async(dispatch_get_main_queue(), ^{
                             [self restorePreviewPlaybackIfNeeded];
                           });
                           if ([self.delegate
                                   respondsToSelector:@selector
                                   (fullScreenMediaPlayerDidDismiss)]) {
                             [self.delegate fullScreenMediaPlayerDidDismiss];
                           }
                         }];
}

- (void)favoriteTapped {
  SCIMediaItem *item = [self currentItem];
  if (!item.galleryFile)
    return;

  item.galleryFile.isFavorite = !item.galleryFile.isFavorite;
  [[SCIGalleryCoreDataStack shared] saveContext];
  [self updateFavoriteButton];

  UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc]
      initWithStyle:UIImpactFeedbackStyleLight];
  [haptic impactOccurred];
}

- (NSArray<SCIDownloadItemRequest *> *)bulkDownloadItemsForPreview {
  NSMutableArray<SCIDownloadItemRequest *> *items = [NSMutableArray array];
  NSInteger index = 0;
  for (SCIMediaItem *mediaItem in self.items) {
    SCIDownloadMediaKind kind = (mediaItem.mediaType == SCIMediaItemTypeVideo)
                                    ? SCIDownloadMediaKindVideo
                                    : SCIDownloadMediaKindImage;
    SCIGallerySaveMetadata *metadata = [self metadataForMediaItem:mediaItem];
    if (mediaItem.image && !mediaItem.fileURL) {
      NSString *staged =
          [SCIDownloadHelpers stageImageForDownload:mediaItem.image];
      if (staged) {
        SCIDownloadItemRequest *req = [SCIDownloadItemRequest
            itemWithLocalPath:staged
                    mediaKind:SCIDownloadMediaKindImage];
        req.preferredFileExtension = @"png";
        req.metadata = metadata;
        req.index = index;
        req.expectedFilenameStem = [[SCIDownloadHelpers
            preferredFilenameForURL:[NSURL fileURLWithPath:staged]
                          mediaKind:SCIDownloadMediaKindImage
                           metadata:metadata]
            stringByDeletingPathExtension];
        [items addObject:req];
      }
      index++;
      continue;
    }
    NSURL *resolvedURL = [[SCIMediaCacheManager sharedManager]
                             bestAvailableFileURLForItem:mediaItem]
                             ?: mediaItem.fileURL;
    if (!resolvedURL) {
      index++;
      continue;
    }
    NSString *extension =
        resolvedURL.pathExtension.length > 0
            ? resolvedURL.pathExtension
            : (kind == SCIDownloadMediaKindVideo ? @"mp4" : @"jpg");
    SCIDownloadItemRequest *req =
        resolvedURL.isFileURL
            ? [SCIDownloadItemRequest itemWithLocalPath:resolvedURL.path
                                              mediaKind:kind]
            : [SCIDownloadItemRequest itemWithRemoteURL:resolvedURL
                                              mediaKind:kind];
    req.preferredFileExtension = extension;
    req.metadata = metadata;
    req.index = index;
    req.linkString = mediaItem.fileURL.absoluteString.length
                         ? mediaItem.fileURL.absoluteString
                         : resolvedURL.absoluteString;
    req.expectedFilenameStem = [[SCIDownloadHelpers
        preferredFilenameForURL:resolvedURL
                      mediaKind:kind
                       metadata:metadata]
        stringByDeletingPathExtension];
    [items addObject:req];
    index++;
  }
  return items;
}

- (NSArray<NSString *> *)bulkDownloadLinksForPreview {
  NSMutableOrderedSet<NSString *> *links = [NSMutableOrderedSet orderedSet];
  for (SCIMediaItem *item in self.items) {
    NSString *linkString = item.fileURL.absoluteString;
    if (linkString.length == 0) {
      NSURL *resolvedURL = [[SCIMediaCacheManager sharedManager]
          bestAvailableFileURLForItem:item];
      linkString = resolvedURL.absoluteString;
    }
    if (linkString.length > 0) {
      [links addObject:linkString];
    }
  }
  return links.array;
}

- (void)copyAllDownloadLinks {
  NSArray<NSString *> *links = [self bulkDownloadLinksForPreview];
  if (links.count == 0) {
    SCINotify(kSCIActionCopyDownloadLink, @"No links available", nil,
              @"error_filled", SCINotificationToneError);
    return;
  }

  [UIPasteboard generalPasteboard].string =
      [links componentsJoinedByString:@"\n"];
  SCINotify(
      kSCIActionCopyDownloadLink,
      SCICopiedDownloadURLTitleForPlaybackSource(self.playbackSource, YES),
      [NSString stringWithFormat:@"%lu item%@", (unsigned long)links.count,
                                 links.count == 1 ? @"" : @"s"],
      @"circle_check_filled", SCINotificationToneSuccess);
}

- (UIMenu *)bulkActionsMenu {
  NSArray<SCIDownloadItemRequest *> *bulkItems =
      [self bulkDownloadItemsForPreview];
  if (bulkItems.count < 2)
    return nil;

  SCIActionButtonSource source =
      SCIActionButtonSourceForPlaybackSource(self.playbackSource);
  NSArray<NSString *> *identifiers =
      SCIConfiguredBulkActionIdentifiersForSource(source);
  if (identifiers.count == 0)
    return nil;

  SCIDownloadSourceSurface surface =
      SCIDownloadSurfaceForPlaybackSource(self.playbackSource);
  NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
  for (NSString *identifier in identifiers) {
    NSString *title = SCIActionButtonTitleForIdentifier(identifier);
    UIImage *image = SCIActionButtonMenuIconForIdentifier(identifier, 22.0);
    UIAction *action = [UIAction
        actionWithTitle:title
                  image:image
             identifier:nil
                handler:^(__unused UIAction *a) {
                  if ([identifier
                          isEqualToString:kSCIActionDownloadAllLibrary]) {
                    [SCIDownloadHelpers
                              performBulkItems:bulkItems
                                   destination:SCIDownloadDestinationPhotos
                              actionIdentifier:kSCIActionDownloadAllLibrary
                                     presenter:self
                                    anchorView:[self bottomBarAnchorView]
                                 sourceSurface:surface
                            finalizeBatchShare:NO
                        finalizeBatchClipboard:NO];
                  } else if ([identifier
                                 isEqualToString:kSCIActionDownloadAllShare]) {
                    [SCIDownloadHelpers
                              performBulkItems:bulkItems
                                   destination:SCIDownloadDestinationCacheOnly
                              actionIdentifier:kSCIActionDownloadAllShare
                                     presenter:self
                                    anchorView:[self bottomBarAnchorView]
                                 sourceSurface:surface
                            finalizeBatchShare:YES
                        finalizeBatchClipboard:NO];
                  } else if ([identifier isEqualToString:
                                             kSCIActionDownloadAllGallery]) {
                    [SCIDownloadHelpers
                              performBulkItems:bulkItems
                                   destination:SCIDownloadDestinationGallery
                              actionIdentifier:kSCIActionDownloadAllGallery
                                     presenter:self
                                    anchorView:[self bottomBarAnchorView]
                                 sourceSurface:surface
                            finalizeBatchShare:NO
                        finalizeBatchClipboard:NO];
                  } else if ([identifier isEqualToString:
                                             kSCIActionDownloadAllClipboard]) {
                    [SCIDownloadHelpers
                              performBulkItems:bulkItems
                                   destination:SCIDownloadDestinationCacheOnly
                              actionIdentifier:kSCIActionDownloadAllClipboard
                                     presenter:self
                                    anchorView:[self bottomBarAnchorView]
                                 sourceSurface:surface
                            finalizeBatchShare:NO
                        finalizeBatchClipboard:YES];
                  } else if ([identifier
                                 isEqualToString:kSCIActionDownloadAllLinks]) {
                    [self copyAllDownloadLinks];
                  }
                }];
    [children addObject:action];
  }
  return [UIMenu menuWithTitle:@"" children:children];
}

- (void)saveToPhotos {
  if ([self handleRemoteOperationWithAction:SCIDownloadDestinationPhotos
                         feedbackIdentifier:
                             kSCINotificationMediaPreviewSavePhotos]) {
    return;
  }

  NSURL *url = [self currentOperationURL];
  SCIMediaItem *item = [self currentItem];
  if (!url && !item.image)
    return;

  if (url.isFileURL) {
    [self saveLocalFileURLToPhotos:url temporaryFile:NO];
    return;
  }

  if (!url && item.image) {
    NSData *jpegData = UIImageJPEGRepresentation(item.image, 0.95);
    if (jpegData) {
      SCIGallerySaveMetadata *meta = [self metadataForCurrentItem];
      NSString *fileName =
          SCIFileNameForMedia([NSURL fileURLWithPath:@"preview.jpg"],
                              SCIGalleryMediaTypeImage, meta);
      NSURL *tempURL =
          [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                     stringByAppendingPathComponent:fileName]];
      if ([jpegData writeToURL:tempURL atomically:YES]) {
        [self saveLocalFileURLToPhotos:tempURL temporaryFile:YES];
        return;
      }
    }
    return;
  }

  NSString *ext = url.pathExtension;
  if (ext.length == 0)
    ext = item.mediaType == SCIMediaItemTypeVideo ? @"mp4" : @"jpg";

  [SCIDownloadHelpers
         downloadURL:url
           extension:ext
         destination:SCIDownloadDestinationPhotos
            metadata:[self metadataForCurrentItem]
      notificationID:kSCINotificationMediaPreviewSavePhotos
           presenter:self
       sourceSurface:SCIDownloadSurfaceForPlaybackSource(self.playbackSource)];
}

- (void)showSaveResult:(BOOL)success error:(NSError *)error {
  if (success) {
    SCINotify(kSCINotificationMediaPreviewSavePhotos, @"Saved to Photos", nil,
              @"circle_check_filled", SCINotificationToneSuccess);
  } else {
    SCINotify(kSCINotificationMediaPreviewSavePhotos, @"Failed to save",
              error.localizedDescription, @"error_filled",
              SCINotificationToneError);
  }
}

- (BOOL)handleRemoteOperationWithAction:(SCIDownloadDestination)destination
                     feedbackIdentifier:(NSString *)feedbackIdentifier {
  SCIMediaItem *item = [self currentItem];
  NSURL *url = [self currentOperationURL];
  if (!item.sourceMediaObject || !item.fileURL || item.fileURL.isFileURL) {
    return NO;
  }

  NSURL *sourceURL = item.fileURL ?: url;
  NSURL *photoURL = item.mediaType == SCIMediaItemTypeImage ? sourceURL : nil;
  NSURL *videoURL = item.mediaType == SCIMediaItemTypeVideo ? sourceURL : nil;
  BOOL showProgress = SCINotificationIsEnabled(feedbackIdentifier);
  return [SCIMediaQualityManager
      handleDownloadDestination:destination
                     identifier:feedbackIdentifier
                      presenter:self
                     sourceView:[self bottomBarAnchorView]
                    mediaObject:item.sourceMediaObject
                       photoURL:photoURL
                       videoURL:videoURL
                galleryMetadata:[self metadataForCurrentItem]
                   showProgress:showProgress
                  sourceSurface:SCIDownloadSurfaceForPlaybackSource(
                                    self.playbackSource)];
}

- (BOOL)handleRemoteCopyOperation {
  SCIMediaItem *item = [self currentItem];
  if (!item.sourceMediaObject || !item.fileURL || item.fileURL.isFileURL) {
    return NO;
  }

  NSURL *sourceURL = item.fileURL;
  BOOL showProgress =
      SCINotificationIsEnabled(kSCINotificationMediaPreviewCopy);
  return [SCIMediaQualityManager
      handleCopyActionWithIdentifier:kSCINotificationMediaPreviewCopy
                           presenter:self
                          sourceView:[self bottomBarAnchorView]
                         mediaObject:item.sourceMediaObject
                            photoURL:(item.mediaType == SCIMediaItemTypeImage
                                          ? sourceURL
                                          : nil)
                            videoURL:(item.mediaType == SCIMediaItemTypeVideo
                                          ? sourceURL
                                          : nil)
                     galleryMetadata:[self metadataForCurrentItem]
                        showProgress:showProgress
                       sourceSurface:SCIDownloadSurfaceForPlaybackSource(
                                         self.playbackSource)];
}

- (void)saveToGallery {
  if ([self handleRemoteOperationWithAction:SCIDownloadDestinationGallery
                         feedbackIdentifier:
                             kSCINotificationMediaPreviewSaveGallery]) {
    return;
  }

  NSURL *targetURL = [self currentOperationURL];
  SCIMediaItem *item = [self currentItem];

  if (!targetURL && !item.image) {
    SCINotify(kSCINotificationMediaPreviewSaveGallery, @"No media to save", nil,
              @"media", SCINotificationToneError);
    return;
  }

  SCIGalleryMediaType galleryType =
      (item.mediaType == SCIMediaItemTypeVideo && targetURL)
          ? SCIGalleryMediaTypeVideo
          : SCIGalleryMediaTypeImage;

  if (targetURL.isFileURL &&
      [[NSFileManager defaultManager] fileExistsAtPath:targetURL.path]) {
    [self gallerySaveLocalFile:targetURL mediaType:galleryType];
    return;
  } else if (!targetURL && item.image) {
    NSData *jpegData = UIImageJPEGRepresentation(item.image, 0.95);
    if (jpegData) {
      NSString *tempPath = [NSTemporaryDirectory()
          stringByAppendingPathComponent:
              [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"]];
      NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
      [jpegData writeToURL:tempURL atomically:YES];
      [self gallerySaveLocalFile:tempURL mediaType:SCIGalleryMediaTypeImage];
      [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
      return;
    }
  }

  NSString *ext = targetURL.pathExtension;
  if (ext.length == 0)
    ext = galleryType == SCIGalleryMediaTypeVideo ? @"mp4" : @"jpg";

  SCIGallerySaveMetadata *meta = [self metadataForCurrentItem];

  [SCIDownloadHelpers
         downloadURL:targetURL
           extension:ext
         destination:SCIDownloadDestinationGallery
            metadata:meta
      notificationID:kSCINotificationMediaPreviewSaveGallery
           presenter:self
       sourceSurface:SCIDownloadSurfaceForPlaybackSource(self.playbackSource)];
}

- (void)gallerySaveLocalFile:(NSURL *)localURL
                   mediaType:(SCIGalleryMediaType)galleryType {
  SCIGallerySaveMetadata *meta = [self metadataForCurrentItem];
  NSString *ext =
      localURL.pathExtension.length
          ? localURL.pathExtension
          : (galleryType == SCIGalleryMediaTypeVideo ? @"mp4" : @"jpg");
  [SCIDownloadHelpers
      submitLocalFileURL:localURL
               extension:ext
             destination:SCIDownloadDestinationGallery
                metadata:meta
          notificationID:kSCINotificationMediaPreviewSaveGallery
               presenter:self
              anchorView:[self bottomBarAnchorView]
           sourceSurface:SCIDownloadSurfaceForPlaybackSource(
                             self.playbackSource)];
}

- (void)shareMedia {
  if ([self
          handleRemoteOperationWithAction:SCIDownloadDestinationShare
                       feedbackIdentifier:kSCINotificationMediaPreviewShare]) {
    return;
  }

  NSURL *url = [self currentOperationURL];
  SCIMediaItem *item = [self currentItem];
  if (!url && !item.image)
    return;

  if (url.isFileURL || (!url && item.image)) {
    id activityItem = url;
    SCIGallerySaveMetadata *meta = [self metadataForCurrentItem];
    if (url.isFileURL) {
      SCIGalleryMediaType mediaType = (item.mediaType == SCIMediaItemTypeVideo)
                                          ? SCIGalleryMediaTypeVideo
                                          : SCIGalleryMediaTypeImage;
      NSString *fileName = SCIFileNameForMedia(url, mediaType, meta);
      if (![url.lastPathComponent isEqualToString:fileName]) {
        NSURL *targetURL = [NSURL
            fileURLWithPath:[NSTemporaryDirectory()
                                stringByAppendingPathComponent:fileName]];
        [[NSFileManager defaultManager] removeItemAtURL:targetURL error:nil];
        if ([[NSFileManager defaultManager] copyItemAtURL:url
                                                    toURL:targetURL
                                                    error:nil]) {
          activityItem = targetURL;
        }
      }
    } else if (item.image) {
      NSData *jpegData = UIImageJPEGRepresentation(item.image, 0.95);
      NSString *fileName =
          SCIFileNameForMedia([NSURL fileURLWithPath:@"preview.jpg"],
                              SCIGalleryMediaTypeImage, meta);
      NSURL *targetURL =
          [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                     stringByAppendingPathComponent:fileName]];
      [[NSFileManager defaultManager] removeItemAtURL:targetURL error:nil];
      if (jpegData && [jpegData writeToURL:targetURL atomically:YES]) {
        activityItem = targetURL;
      } else {
        activityItem = item.image;
      }
    }
    SCINotify(kSCINotificationMediaPreviewShare, @"Opened share sheet", nil,
              @"share", SCINotificationToneInfo);
    UIActivityViewController *acVC = [[UIActivityViewController alloc]
        initWithActivityItems:@[ activityItem ]
        applicationActivities:nil];
    if ([UIDevice currentDevice].userInterfaceIdiom ==
        UIUserInterfaceIdiomPad) {
      UIView *anchor = [self bottomBarAnchorView];
      acVC.popoverPresentationController.sourceView = anchor;
      acVC.popoverPresentationController.sourceRect = anchor.bounds;
    }
    [self presentViewController:acVC animated:YES completion:nil];
    return;
  }

  NSString *ext = url.pathExtension;
  if (ext.length == 0)
    ext = item.mediaType == SCIMediaItemTypeVideo ? @"mp4" : @"jpg";

  [SCIDownloadHelpers
         downloadURL:url
           extension:ext
         destination:SCIDownloadDestinationShare
            metadata:[self metadataForCurrentItem]
      notificationID:kSCINotificationMediaPreviewShare
           presenter:self
       sourceSurface:SCIDownloadSurfaceForPlaybackSource(self.playbackSource)];
}

- (void)copyMedia {
  if ([self handleRemoteCopyOperation]) {
    return;
  }

  SCIMediaItem *item = [self currentItem];
  NSURL *url = [self currentFileURL];
  if (!url && !item.image)
    return;

  if (item.mediaType == SCIMediaItemTypeImage || (!url && item.image)) {
    NSData *imageData = url ? [NSData dataWithContentsOfURL:url] : nil;
    UIImage *image = item.image ?: [UIImage imageWithData:imageData];
    if (image) {
      [[UIPasteboard generalPasteboard] setImage:image];
      SCINotify(kSCINotificationMediaPreviewCopy, @"Copied photo to clipboard",
                nil, @"circle_check_filled", SCINotificationToneSuccess);
    }
  } else {
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data) {
      [[UIPasteboard generalPasteboard] setData:data
                              forPasteboardType:@"public.mpeg-4"];
      SCINotify(kSCINotificationMediaPreviewCopy, @"Copied video to clipboard",
                nil, @"circle_check_filled", SCINotificationToneSuccess);
    }
  }
}

- (void)deleteFromGallery {
  SCIMediaItem *item = [self currentItem];
  if (!item.galleryFile)
    return;

  __weak typeof(self) weakSelf = self;
  [SCIIGAlertPresenter
      presentAlertFromViewController:self
                               title:@"Delete from Gallery"
                             message:@"This will permanently remove this file."
                             actions:@[
                               [SCIIGAlertAction
                                   actionWithTitle:@"Cancel"
                                             style:SCIIGAlertActionStyleCancel
                                           handler:nil],
                               [SCIIGAlertAction
                                   actionWithTitle:@"Delete"
                                             style:
                                                 SCIIGAlertActionStyleDestructive
                                           handler:^{
                                             [weakSelf
                                                 performDeleteCurrentItem];
                                           }],
                             ]];
}

- (void)performDeleteCurrentItem {
  SCIMediaItem *item = [self currentItem];
  if (!item.galleryFile)
    return;

  NSInteger deletedIndex = _currentIndex;
  NSError *err;
  [item.galleryFile removeWithError:&err];
  if (err) {
    SCINotify(kSCINotificationMediaPreviewDeleteGallery, @"Failed to delete",
              err.localizedDescription, @"error_filled",
              SCINotificationToneError);
    return;
  }

  NSMutableArray *mutableItems = [_items mutableCopy];
  [mutableItems removeObjectAtIndex:deletedIndex];
  _items = [mutableItems copy];
  _isSingleItemMode = (_items.count <= 1);

  if ([self.delegate respondsToSelector:@selector
                     (fullScreenMediaPlayerDidDeleteFileAtIndex:)]) {
    [self.delegate fullScreenMediaPlayerDidDeleteFileAtIndex:deletedIndex];
  }

  if (_items.count == 0) {
    SCINotify(kSCINotificationMediaPreviewDeleteGallery,
              @"Deleted from Gallery", nil, @"circle_check_filled",
              SCINotificationToneSuccess);
    [self closeTapped];
    return;
  }

  for (UIViewController *controller in self.controllerCache.allValues) {
    if ([controller respondsToSelector:@selector(cleanup)]) {
      [(id)controller cleanup];
    }
  }
  [self.controllerCache removeAllObjects];

  _currentIndex = MIN(deletedIndex, (NSInteger)_items.count - 1);
  UIViewController *newVC = [self viewControllerForIndex:_currentIndex];
  if (newVC) {
    [_pageViewController
        setViewControllers:@[ newVC ]
                 direction:UIPageViewControllerNavigationDirectionForward
                  animated:YES
                completion:nil];
  }
  [self prepareViewControllerForDisplay:newVC];
  [self prepareAdjacentViewControllersAroundIndex:_currentIndex];
  [self updateUI];
  SCINotify(kSCINotificationMediaPreviewDeleteGallery, @"Deleted from Gallery",
            nil, @"circle_check_filled", SCINotificationToneSuccess);
}

#pragma mark - Swipe to Dismiss

- (void)setupDismissGesture {
  UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handlePanDismiss:)];
  pan.delegate = self;
  pan.maximumNumberOfTouches = 1;
  [self.view addGestureRecognizer:pan];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
  UIViewController *currentVC = _pageViewController.viewControllers.firstObject;
  if ([currentVC isKindOfClass:[SCIFullScreenImageViewController class]] &&
      [(SCIFullScreenImageViewController *)currentVC isZoomed]) {
    return NO;
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:
        (UIGestureRecognizer *)otherGestureRecognizer {
  return YES;
}

- (void)handlePanDismiss:(UIPanGestureRecognizer *)pan {
  CGPoint translation = [pan translationInView:self.view];
  CGPoint velocity = [pan velocityInView:self.view];

  if (pan.state == UIGestureRecognizerStateBegan) {
    _dismissPanDecided = NO;
    _dismissPanIsVertical = NO;
    _pageScrollView.scrollEnabled = YES;
    return;
  }

  CGFloat tx = translation.x;
  CGFloat ty = translation.y;

  if (!_dismissPanDecided) {
    CGFloat mag = hypot(tx, ty);
    if (mag < kDismissAxisLockSlop) {
      if (pan.state == UIGestureRecognizerStateEnded ||
          pan.state == UIGestureRecognizerStateCancelled) {
        [self resetDismissInteractiveStateAnimated:NO];
      }
      return;
    }
    _dismissPanDecided = YES;
    _dismissPanIsVertical = fabs(ty) >= fabs(tx);
    _pageScrollView.scrollEnabled = !_dismissPanIsVertical;
  }

  if (!_dismissPanIsVertical) {
    if (pan.state == UIGestureRecognizerStateEnded ||
        pan.state == UIGestureRecognizerStateCancelled) {
      [self resetDismissInteractiveStateAnimated:NO];
    }
    return;
  }

  [self beginInteractiveDismissalIfNeeded];
  if (!self.interactiveDismissTransitionContext)
    return;

  CGFloat dy = ty;
  CGFloat absDy = fabs(dy);
  CGFloat maximumBackdropDelta =
      MAX(1.0, CGRectGetHeight(self.view.bounds) / 2.0);
  CGFloat deltaRatio = MIN(1.0, absDy / maximumBackdropDelta);
  CGFloat backdropAlpha =
      1.0 - (deltaRatio * (1.0 - kDismissFinalBackdropAlpha));

  switch (pan.state) {
  case UIGestureRecognizerStateChanged: {
    [self updateInteractiveDismissalWithVerticalDelta:dy
                                        backdropAlpha:backdropAlpha];
    break;
  }
  case UIGestureRecognizerStateEnded:
  case UIGestureRecognizerStateCancelled: {
    CGFloat dismissDistance =
        kDismissDistanceRatio * CGRectGetHeight(self.view.bounds);
    BOOL commit = pan.state != UIGestureRecognizerStateCancelled &&
                  absDy > dismissDistance;
    if (commit) {
      CGFloat direction = dy >= 0.0 ? 1.0 : -1.0;
      CGFloat finalCenterY = self.interactiveDismissAnchorPoint.y +
                             direction * CGRectGetHeight(self.view.bounds);
      CGFloat vy = MAX(fabs(velocity.y), kDismissMinimumVelocity);
      CGFloat duration =
          fabs(finalCenterY - _pageViewController.view.center.y) / vy;
      duration = MIN(duration, kDismissMaximumDuration);
      duration = MAX(kDismissMinimumDuration, duration);

      // iOS 26's glass toolbar ignores alpha; hide its platter directly
      // so it doesn't linger over the dismissing content.
      if (@available(iOS 26.0, *)) {
        [self.navigationController setToolbarHidden:YES animated:YES];
      }

      [UIView animateWithDuration:duration
          delay:0
          options:UIViewAnimationOptionCurveEaseOut |
                  UIViewAnimationOptionBeginFromCurrentState
          animations:^{
            self->_pageViewController.view.center =
                CGPointMake(self.interactiveDismissAnchorPoint.x, finalCenterY);
            self.presentationBackdropView.alpha = 0.0;
            self.navigationController.navigationBar.alpha = 0.0;
            self.navigationController.toolbar.alpha = 0.0;
          }
          completion:^(BOOL finished) {
            [self finishInteractiveDismissal];
          }];
    } else {
      CGFloat duration =
          fabs(velocity.y) * kDismissReturnVelocityAnimationRatio + 0.2;
      [self removeTransitionToViewForCancelledInteractiveDismissalIfNeeded];
      [UIView animateWithDuration:duration
          delay:0
          options:UIViewAnimationOptionCurveEaseOut |
                  UIViewAnimationOptionBeginFromCurrentState
          animations:^{
            self->_pageViewController.view.center =
                self.interactiveDismissAnchorPoint;
            self.presentationBackdropView.alpha = 1.0;
            CGFloat alpha = self->_isToolbarVisible ? 1.0 : 0.0;
            self.navigationController.navigationBar.alpha = alpha;
            self.navigationController.toolbar.alpha = alpha;
          }
          completion:^(BOOL finished) {
            UIViewController *currentVC =
                self->_pageViewController.viewControllers.firstObject;
            if ([currentVC
                    isKindOfClass:[SCIFullScreenImageViewController class]]) {
              [(SCIFullScreenImageViewController *)currentVC resetZoomIfNeeded];
            }
            [self cancelInteractiveDismissal];
          }];
    }
    _dismissPanDecided = NO;
    _pageScrollView.scrollEnabled = YES;
    break;
  }
  case UIGestureRecognizerStateFailed: {
    if (self.interactiveDismissTransitionContext) {
      [self removeTransitionToViewForCancelledInteractiveDismissalIfNeeded];
      [self cancelInteractiveDismissal];
    } else if (_dismissPanDecided && _dismissPanIsVertical) {
      [self resetDismissInteractiveStateAnimated:YES];
    }
    _dismissPanDecided = NO;
    _dismissPanIsVertical = NO;
    _pageScrollView.scrollEnabled = YES;
    break;
  }
  default:
    break;
  }
}

- (void)resetDismissInteractiveStateAnimated:(BOOL)animated {
  _dismissPanDecided = NO;
  _dismissPanIsVertical = NO;
  _pageScrollView.scrollEnabled = YES;
  void (^animations)(void) = ^{
    self->_pageViewController.view.transform = CGAffineTransformIdentity;
    self->_pageViewController.view.center =
        SCICenterForBounds(self.view.bounds);
    self.presentationBackdropView.alpha = 1.0;
    CGFloat alpha = self->_isToolbarVisible ? 1.0 : 0.0;
    self.navigationController.navigationBar.alpha = alpha;
    self.navigationController.toolbar.alpha = alpha;
  };
  if (animated) {
    [UIView animateWithDuration:0.25 animations:animations];
  } else {
    animations();
  }
}

#pragma mark - Interactive Dismissal Transition

- (void)beginInteractiveDismissalIfNeeded {
  if (self.interactiveDismissalInProgress)
    return;

  self.interactiveDismissalInProgress = YES;
  self.interactiveDismissAnchorPoint = self.pageViewController.view.center;
  UIViewController *dismissTarget = self.navigationController ?: self;
  [dismissTarget dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateInteractiveDismissalWithVerticalDelta:(CGFloat)verticalDelta
                                      backdropAlpha:(CGFloat)backdropAlpha {
  id<UIViewControllerContextTransitioning> transitionContext =
      self.interactiveDismissTransitionContext;
  UIView *fromView =
      [transitionContext viewForKey:UITransitionContextFromViewKey];
  UIView *toView = [transitionContext viewForKey:UITransitionContextToViewKey];

  if (toView && !toView.superview) {
    UIViewController *toViewController = [transitionContext
        viewControllerForKey:UITransitionContextToViewControllerKey];
    toView.frame =
        [transitionContext finalFrameForViewController:toViewController];
    if (![toView isDescendantOfView:transitionContext.containerView]) {
      [transitionContext.containerView addSubview:toView];
    }
    [transitionContext.containerView bringSubviewToFront:fromView ?: self.view];
  }

  self.pageViewController.view.center =
      CGPointMake(self.interactiveDismissAnchorPoint.x,
                  self.interactiveDismissAnchorPoint.y + verticalDelta);
  self.presentationBackdropView.alpha = backdropAlpha;
  CGFloat fade = (self.isToolbarVisible ? 1.0 : 0.0) * backdropAlpha;
  self.navigationController.navigationBar.alpha = MAX(0.0, fade);
  self.navigationController.toolbar.alpha = MAX(0.0, fade);
}

- (void)removeTransitionToViewForCancelledInteractiveDismissalIfNeeded {
  id<UIViewControllerContextTransitioning> transitionContext =
      self.interactiveDismissTransitionContext;
  if (transitionContext.presentationStyle != UIModalPresentationFullScreen)
    return;

  UIView *toView = [transitionContext viewForKey:UITransitionContextToViewKey];
  [toView removeFromSuperview];
}

- (void)finishInteractiveDismissal {
  id<UIViewControllerContextTransitioning> transitionContext =
      self.interactiveDismissTransitionContext;
  [transitionContext finishInteractiveTransition];
  [transitionContext
      completeTransition:!transitionContext.transitionWasCancelled];
  self.interactiveDismissTransitionContext = nil;
  self.interactiveDismissalInProgress = NO;

  [self cleanupAll];
  dispatch_async(dispatch_get_main_queue(), ^{
    [self restorePreviewPlaybackIfNeeded];
  });
  if ([self.delegate
          respondsToSelector:@selector(fullScreenMediaPlayerDidDismiss)]) {
    [self.delegate fullScreenMediaPlayerDidDismiss];
  }
}

- (void)cancelInteractiveDismissal {
  id<UIViewControllerContextTransitioning> transitionContext =
      self.interactiveDismissTransitionContext;
  [transitionContext cancelInteractiveTransition];
  [transitionContext completeTransition:NO];
  self.interactiveDismissTransitionContext = nil;
  self.interactiveDismissalInProgress = NO;
  self.pageViewController.view.transform = CGAffineTransformIdentity;
  self.pageViewController.view.center = SCICenterForBounds(self.view.bounds);
}

- (id<UIViewControllerAnimatedTransitioning>)
    animationControllerForPresentedController:(UIViewController *)presented
                         presentingController:(UIViewController *)presenting
                             sourceController:(UIViewController *)source {
  self.presentingTransition = YES;
  return self;
}

- (id<UIViewControllerAnimatedTransitioning>)
    animationControllerForDismissedController:(UIViewController *)dismissed {
  self.presentingTransition = NO;
  return self;
}

- (id<UIViewControllerInteractiveTransitioning>)
    interactionControllerForDismissal:
        (id<UIViewControllerAnimatedTransitioning>)animator {
  return self.interactiveDismissalInProgress ? self : nil;
}

- (NSTimeInterval)transitionDuration:
    (id<UIViewControllerContextTransitioning>)transitionContext {
  return self.presentingTransition ? kPresentationFadeDuration
                                   : kDismissFadeDuration;
}

- (void)animateTransition:
    (id<UIViewControllerContextTransitioning>)transitionContext {
  if (self.presentingTransition) {
    UIView *toView =
        [transitionContext viewForKey:UITransitionContextToViewKey];
    UIViewController *toViewController = [transitionContext
        viewControllerForKey:UITransitionContextToViewControllerKey];
    toView.frame =
        [transitionContext finalFrameForViewController:toViewController];
    toView.alpha = 0.0;
    [transitionContext.containerView addSubview:toView];

    [UIView animateWithDuration:kPresentationFadeDuration
        delay:0
        options:UIViewAnimationOptionCurveEaseOut
        animations:^{
          toView.alpha = 1.0;
        }
        completion:^(__unused BOOL finished) {
          [transitionContext
              completeTransition:!transitionContext.transitionWasCancelled];
        }];
    return;
  }

  UIView *fromView =
      [transitionContext viewForKey:UITransitionContextFromViewKey];
  [UIView animateWithDuration:kDismissFadeDuration
      delay:0
      options:UIViewAnimationOptionCurveEaseOut
      animations:^{
        fromView.alpha = 0.0;
      }
      completion:^(__unused BOOL finished) {
        BOOL completed = !transitionContext.transitionWasCancelled;
        if (!completed) {
          fromView.alpha = 1.0;
        }
        [transitionContext completeTransition:completed];
      }];
}

- (void)startInteractiveTransition:
    (id<UIViewControllerContextTransitioning>)transitionContext {
  self.interactiveDismissTransitionContext = transitionContext;
}

#pragma mark - Cleanup

- (void)cleanupAll {
  for (UIViewController *controller in self.controllerCache.allValues) {
    if ([controller respondsToSelector:@selector(cleanup)]) {
      [(id)controller cleanup];
    }
  }
  [self.controllerCache removeAllObjects];
}

@end

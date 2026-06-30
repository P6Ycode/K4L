#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import "SPKFullScreenImageViewController.h"

@class SPKMediaItem;

NS_ASSUME_NONNULL_BEGIN

@interface SPKFullScreenVideoViewController : UIViewController

@property (nonatomic, strong, readonly) SPKMediaItem *mediaItem;
@property (nonatomic, weak) id<SPKFullScreenContentDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) UIView *contentOverlayView;

- (instancetype)initWithMediaItem:(SPKMediaItem *)item;
- (void)preloadContent;
- (void)prepareForDisplay;
- (void)cleanup;
- (void)setPlayerControlOverlayInsets:(UIEdgeInsets)insets animated:(BOOL)animated;
- (void)play;
- (void)pause;

@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>

@class SPKMediaItem;

@protocol SPKFullScreenContentDelegate <NSObject>
@optional
- (void)mediaContentDidTap:(UIViewController *)controller;
- (void)mediaContent:(UIViewController *)controller didFailWithError:(NSError *)error;
/// Reports the zoom state of the content so the host can adapt chrome (e.g.
/// show a material backing behind the bars when content fills behind them).
- (void)mediaContent:(UIViewController *)controller didChangeZoomState:(BOOL)isZoomed;
@end

NS_ASSUME_NONNULL_BEGIN

@interface SPKFullScreenImageViewController : UIViewController

@property (nonatomic, strong, readonly) SPKMediaItem *mediaItem;
@property (nonatomic, weak) id<SPKFullScreenContentDelegate> delegate;
@property (nonatomic, readonly) BOOL isZoomed;

- (instancetype)initWithMediaItem:(SPKMediaItem *)item;
- (void)preloadContent;
- (void)cleanup;
- (void)resetZoomIfNeeded;

@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>

@class SPKMediaItem, SPKGalleryFile, SPKGallerySaveMetadata;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPKFullScreenPlaybackSource) {
    SPKFullScreenPlaybackSourceUnknown = 0,
    SPKFullScreenPlaybackSourceFeed = 1,
    SPKFullScreenPlaybackSourceReels = 2,
    SPKFullScreenPlaybackSourceStories = 3,
    SPKFullScreenPlaybackSourceDirect = 4,
    SPKFullScreenPlaybackSourceProfile = 5,
    SPKFullScreenPlaybackSourceInstants = 6,
};

typedef void (^SPKMediaPreviewPlaybackBlock)(void);

@protocol SPKFullScreenMediaPlayerDelegate <NSObject>
@optional
- (void)fullScreenMediaPlayerDidDismiss;
- (void)fullScreenMediaPlayerDidDeleteFileAtIndex:(NSInteger)index;
@end

@interface SPKFullScreenMediaPlayer : UIViewController

@property (nonatomic, assign) BOOL isFromGallery;
@property (nonatomic, weak, nullable) id<SPKFullScreenMediaPlayerDelegate> delegate;

- (void)playItems:(NSArray<SPKMediaItem *> *)items
       startingAtIndex:(NSInteger)index
    fromViewController:(UIViewController *)presenter;

+ (void)showFileURL:(NSURL *)fileURL;
+ (void)showFileURL:(NSURL *)fileURL metadata:(nullable SPKGallerySaveMetadata *)metadata;
+ (void)showFileURL:(NSURL *)fileURL fromGallery:(BOOL)fromGallery;

/// Bare, read-only preview of a local file: media + close + zoom only, no action toolbar and no
/// metadata (so nothing attempts remote resolution). Used by the Files-import queue.
+ (void)showLocalFilePreview:(NSURL *)fileURL;

+ (void)showGalleryFiles:(NSArray<SPKGalleryFile *> *)files
         startingAtIndex:(NSInteger)index
      fromViewController:(UIViewController *)presenter;

+ (void)showPhotoURLs:(NSArray<NSURL *> *)urls initialIndex:(NSInteger)index;
+ (void)showPhotoURLs:(NSArray<NSURL *> *)urls initialIndex:(NSInteger)index metadata:(nullable SPKGallerySaveMetadata *)metadata;

/// Ordered carousel / album: images and videos as `SPKMediaItem` (matches gallery `playItems` behavior).
+ (void)showMediaItems:(NSArray<SPKMediaItem *> *)items
       startingAtIndex:(NSInteger)index
              metadata:(nullable SPKGallerySaveMetadata *)metadata;
+ (void)showMediaItems:(NSArray<SPKMediaItem *> *)items
       startingAtIndex:(NSInteger)index
              metadata:(nullable SPKGallerySaveMetadata *)metadata
        playbackSource:(SPKFullScreenPlaybackSource)playbackSource
            sourceView:(nullable UIView *)sourceView
            controller:(nullable UIViewController *)controller
         pausePlayback:(nullable SPKMediaPreviewPlaybackBlock)pausePlayback
        resumePlayback:(nullable SPKMediaPreviewPlaybackBlock)resumePlayback;

+ (void)showImage:(UIImage *)image;
+ (void)showImage:(UIImage *)image metadata:(nullable SPKGallerySaveMetadata *)metadata;
+ (void)showImage:(UIImage *)image
          metadata:(nullable SPKGallerySaveMetadata *)metadata
    playbackSource:(SPKFullScreenPlaybackSource)playbackSource
        sourceView:(nullable UIView *)sourceView
        controller:(nullable UIViewController *)controller
     pausePlayback:(nullable SPKMediaPreviewPlaybackBlock)pausePlayback
    resumePlayback:(nullable SPKMediaPreviewPlaybackBlock)resumePlayback;
+ (void)showRemoteImageURL:(NSURL *)url;
+ (void)showRemoteImageURL:(NSURL *)url metadata:(nullable SPKGallerySaveMetadata *)metadata;
+ (void)showRemoteImageURL:(NSURL *)url
                  metadata:(nullable SPKGallerySaveMetadata *)metadata
            playbackSource:(SPKFullScreenPlaybackSource)playbackSource
                sourceView:(nullable UIView *)sourceView
                controller:(nullable UIViewController *)controller
             pausePlayback:(nullable SPKMediaPreviewPlaybackBlock)pausePlayback
            resumePlayback:(nullable SPKMediaPreviewPlaybackBlock)resumePlayback;
/// Profile / avatar long-press: sets Gallery source + optional username for “Save to Gallery”.
+ (void)showRemoteImageURL:(NSURL *)url profileUsername:(nullable NSString *)username;

@end

NS_ASSUME_NONNULL_END

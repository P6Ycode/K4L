#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "SCIAudioItem.h"
#import "../MediaPreview/SCIFullScreenMediaPlayer.h"

@class SCIGallerySaveMetadata;

NS_ASSUME_NONNULL_BEGIN

@interface SCIAudioDownloadCoordinator : NSObject

+ (void)performAction:(SCIAudioAction)action
                 item:(SCIAudioItem *)item
            presenter:(nullable UIViewController *)presenter
           sourceView:(nullable UIView *)sourceView
             metadata:(nullable SCIGallerySaveMetadata *)metadata
 notificationIdentifier:(nullable NSString *)notificationIdentifier;

+ (void)performAction:(SCIAudioAction)action
                 item:(SCIAudioItem *)item
            presenter:(nullable UIViewController *)presenter
           sourceView:(nullable UIView *)sourceView
             metadata:(nullable SCIGallerySaveMetadata *)metadata
 notificationIdentifier:(nullable NSString *)notificationIdentifier
       playbackSource:(SCIFullScreenPlaybackSource)playbackSource
        pausePlayback:(nullable SCIMediaPreviewPlaybackBlock)pausePlayback
       resumePlayback:(nullable SCIMediaPreviewPlaybackBlock)resumePlayback;

+ (nullable SCIAudioItem *)audioItemFromMediaObject:(nullable id)mediaObject
                                             source:(SCIAudioSource)source;

+ (nullable SCIAudioItem *)audioItemFromMediaObject:(nullable id)mediaObject
                                             source:(SCIAudioSource)source
                                allowVideoFallback:(BOOL)allowVideoFallback;

+ (nullable NSURL *)bestAudioURLFromMediaObject:(nullable id)mediaObject;

+ (nullable NSURL *)bestAudioDownloadURLFromMediaObject:(nullable id)mediaObject;

@end

NS_ASSUME_NONNULL_END

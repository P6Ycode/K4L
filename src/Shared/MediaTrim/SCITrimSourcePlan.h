#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Resolved plan for trimming a piece of feed/reel/story media, honoring the
/// user's `downloads_video_quality` setting (built by SCIMediaQualityManager).
@interface SCITrimSourcePlan : NSObject

/// Progressive (ready-to-play) URL to scrub in the editor — small/fast. Falls
/// back to the final video URL when no progressive representation exists.
@property (nonatomic, copy) NSURL *editURL;

/// The chosen-quality video to render the final cut from.
@property (nonatomic, copy) NSURL *finalVideoURL;

/// Separate DASH audio stream to merge in, when `needsMerge` is YES.
@property (nonatomic, copy, nullable) NSURL *finalAudioURL;

/// YES when the chosen option is a DASH video that must be merged with
/// `finalAudioURL`; NO for a progressive (already-muxed) source.
@property (nonatomic, assign) BOOL needsMerge;

@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) double duration;

@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SPKTrimScrubberView;

@protocol SPKTrimScrubberViewDelegate <NSObject>
@optional
/// Fired when the user first touches a handle or the track.
- (void)trimScrubberDidBeginInteraction:(SPKTrimScrubberView *)scrubber;
/// Selection start (in) moved. `startTime` is seconds on the source timeline.
- (void)trimScrubber:(SPKTrimScrubberView *)scrubber didChangeStartTime:(NSTimeInterval)startTime;
/// Selection end (out) moved.
- (void)trimScrubber:(SPKTrimScrubberView *)scrubber didChangeEndTime:(NSTimeInterval)endTime;
/// Playhead (or single-frame marker) scrubbed to `time`.
- (void)trimScrubber:(SPKTrimScrubberView *)scrubber didScrubToTime:(NSTimeInterval)time;
/// Fired when the active touch ends.
- (void)trimScrubberDidEndInteraction:(SPKTrimScrubberView *)scrubber;
@end

/// Photos-style trim bar: a filmstrip of thumbnails with two draggable in/out
/// handles, a dimmed region outside the selection, and a draggable playhead.
/// Toggling `singleFrameMode` collapses the UI to a single frame-picker marker.
@interface SPKTrimScrubberView : UIView

@property (nonatomic, weak) id<SPKTrimScrubberViewDelegate> delegate;

/// Total asset duration in seconds. Set once the asset is loaded.
@property (nonatomic, assign) NSTimeInterval duration;
/// Shortest selectable clip in seconds.
@property (nonatomic, assign) NSTimeInterval minimumDuration;

@property (nonatomic, assign, readonly) NSTimeInterval startTime;
@property (nonatomic, assign, readonly) NSTimeInterval endTime;

/// Moves the playhead indicator without notifying the delegate. Use to reflect
/// playback position. In single-frame mode this is the picked frame time.
@property (nonatomic, assign) NSTimeInterval playheadTime;

/// When YES, hides the in/out handles and shows a single frame-picker marker.
@property (nonatomic, assign, getter=isSingleFrameMode) BOOL singleFrameMode;

/// Convenience: the frame time when in single-frame mode (== playheadTime).
@property (nonatomic, assign, readonly) NSTimeInterval frameTime;

/// Kicks off async thumbnail generation for the filmstrip.
- (void)loadThumbnailsForAsset:(AVAsset *)asset;

/// Sets both handles at once (e.g. to initialize the full range).
- (void)setStartTime:(NSTimeInterval)start endTime:(NSTimeInterval)end;

@end

NS_ASSUME_NONNULL_END

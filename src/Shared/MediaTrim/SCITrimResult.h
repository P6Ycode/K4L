#import <Foundation/Foundation.h>

#import "SCITrimTypes.h"

NS_ASSUME_NONNULL_BEGIN

/// A confirmed trim request from the editor. The editor returns this immediately
/// on confirm (no rendering); the save coordinator renders it in the background
/// and fills `outputURL`.
@interface SCITrimResult : NSObject

@property (nonatomic, assign) SCITrimResultMode mode;

/// Source media to render from.
@property (nonatomic, copy) NSURL *sourceURL;

/// Selection on the source timeline. For a single frame, `startSeconds` is the
/// frame time and `durationSeconds` is 0.
@property (nonatomic, assign) NSTimeInterval startSeconds;
@property (nonatomic, assign) NSTimeInterval durationSeconds;

/// Optional render overrides (set by the save-flow entry to render the final
/// cut from the chosen-quality stream(s) instead of the edited preview file).
/// When `renderVideoURL` is set it replaces `sourceURL` for rendering; when
/// `renderAudioURL` is also set, the two are merged (DASH) in one pass.
@property (nonatomic, copy, nullable) NSURL *renderVideoURL;
@property (nonatomic, copy, nullable) NSURL *renderAudioURL;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;

/// Filled by the renderer once the temp output exists.
@property (nonatomic, copy, nullable) NSURL *outputURL;

/// The destination chosen from the editor's Done menu (save flow), or nil when
/// Done was a plain confirm (gallery flow).
@property (nonatomic, copy, nullable) NSString *destinationTag;

+ (instancetype)requestWithMode:(SCITrimResultMode)mode
                      sourceURL:(NSURL *)sourceURL
                   startSeconds:(NSTimeInterval)startSeconds
                durationSeconds:(NSTimeInterval)durationSeconds;

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SPKMediaFFmpegProgressBlock)(double progress, NSString *stage);
typedef void (^SPKMediaFFmpegCompletionBlock)(NSURL *_Nullable outputURL, NSError *_Nullable error);
typedef void (^SPKMediaFFmpegCancelBlockPublisher)(dispatch_block_t cancelBlock);

@interface SPKMediaFFmpeg : NSObject

+ (BOOL)isAvailable;
+ (void)cancelAll;
+ (UIViewController *)logsViewController;

+ (void)mergeVideoFileURL:(NSURL *)videoFileURL
             audioFileURL:(nullable NSURL *)audioFileURL
        preferredBasename:(NSString *)preferredBasename
        estimatedDuration:(NSTimeInterval)estimatedDuration
                    width:(NSInteger)width
                   height:(NSInteger)height
            sourceBitrate:(NSInteger)sourceBitrate
                 progress:(nullable SPKMediaFFmpegProgressBlock)progress
               completion:(SPKMediaFFmpegCompletionBlock)completion
                cancelOut:(nullable SPKMediaFFmpegCancelBlockPublisher)cancelOut;

+ (void)extractAudioFileURL:(NSURL *)audioFileURL
          preferredBasename:(NSString *)preferredBasename
                   progress:(nullable SPKMediaFFmpegProgressBlock)progress
                 completion:(SPKMediaFFmpegCompletionBlock)completion
                  cancelOut:(nullable SPKMediaFFmpegCancelBlockPublisher)cancelOut;

/// Frame-accurate re-encode trim. Encodes `[startSeconds, startSeconds +
/// durationSeconds)` of the source with libx264 (preset from
/// `downloads_encoding_speed`), then relocates the moov atom (+faststart).
/// Audio is re-encoded to AAC, falling back to stream-copy then dropped if the
/// bundled FFmpeg can't decode the source track.
+ (void)trimVideoFileURL:(NSURL *)videoFileURL
            startSeconds:(NSTimeInterval)startSeconds
         durationSeconds:(NSTimeInterval)durationSeconds
       preferredBasename:(NSString *)preferredBasename
                progress:(nullable SPKMediaFFmpegProgressBlock)progress
              completion:(SPKMediaFFmpegCompletionBlock)completion
               cancelOut:(nullable SPKMediaFFmpegCancelBlockPublisher)cancelOut;

/// Single-pass trim + merge of a separate DASH video and audio source (local
/// paths or remote http(s) URLs). With remote inputs the `-ss` input seek makes
/// FFmpeg fetch only the selected window via HTTP range requests, so cost scales
/// with the clip length, not the full video. Honors the encoding settings.
+ (void)trimMergeVideoURL:(NSURL *)videoURL
                 audioURL:(NSURL *)audioURL
             startSeconds:(NSTimeInterval)startSeconds
          durationSeconds:(NSTimeInterval)durationSeconds
        preferredBasename:(NSString *)preferredBasename
                    width:(NSInteger)width
                   height:(NSInteger)height
                 progress:(nullable SPKMediaFFmpegProgressBlock)progress
               completion:(SPKMediaFFmpegCompletionBlock)completion
                cancelOut:(nullable SPKMediaFFmpegCancelBlockPublisher)cancelOut;

@end

NS_ASSUME_NONNULL_END

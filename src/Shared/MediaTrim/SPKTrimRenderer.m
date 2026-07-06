#import "SPKTrimRenderer.h"
#import "../MediaDownload/SPKMediaFFmpeg.h"

#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>

static NSError *SPKTrimRendererError(NSString *description) {
    return [NSError errorWithDomain:@"Sparkle.TrimRenderer"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : description ?: @"Render failed"}];
}

@interface SPKTrimRenderer ()
+ (void)generateFrameForAsset:(AVAsset *)asset
                    atSeconds:(NSTimeInterval)seconds
                     basename:(NSString *)basename
               allowTolerance:(BOOL)allowTolerance
                   completion:(SPKTrimRenderCompletionBlock)completion;
@end

// Encodes a CGImage to a temp file. Prefers HEIC (much smaller — the whole
// point of reducing a "song over a photo" video to one frame), falls back to
// JPEG if the HEIC encoder is unavailable.
static NSURL *SPKTrimWriteCGImage(CGImageRef image, NSString *basename) {
    if (!image)
        return nil;
    NSString *tmp = NSTemporaryDirectory();

    NSURL *heicURL = [NSURL fileURLWithPath:[tmp stringByAppendingPathComponent:[basename stringByAppendingPathExtension:@"heic"]]];
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)heicURL, (CFStringRef) @"public.heic", 1, NULL);
    if (dest) {
        NSDictionary *props = @{(__bridge id)kCGImageDestinationLossyCompressionQuality : @0.9};
        CGImageDestinationAddImage(dest, image, (__bridge CFDictionaryRef)props);
        BOOL ok = CGImageDestinationFinalize(dest);
        CFRelease(dest);
        if (ok)
            return heicURL;
    }

    NSURL *jpgURL = [NSURL fileURLWithPath:[tmp stringByAppendingPathComponent:[basename stringByAppendingPathExtension:@"jpg"]]];
    NSData *data = UIImageJPEGRepresentation([UIImage imageWithCGImage:image], 0.95);
    if (data && [data writeToURL:jpgURL atomically:YES])
        return jpgURL;
    return nil;
}

@implementation SPKTrimRenderer

#pragma mark - Trim

+ (void)renderTrimForSourceURL:(NSURL *)sourceURL
                         asset:(AVAsset *)asset
                  startSeconds:(NSTimeInterval)startSeconds
               durationSeconds:(NSTimeInterval)durationSeconds
                      basename:(NSString *)basename
                      progress:(SPKTrimRenderProgressBlock)progress
                    completion:(SPKTrimRenderCompletionBlock)completion
                     cancelOut:(void (^)(dispatch_block_t))cancelOut {
    if ([SPKMediaFFmpeg isAvailable]) {
        [SPKMediaFFmpeg trimVideoFileURL:sourceURL
            startSeconds:startSeconds
            durationSeconds:durationSeconds
            preferredBasename:basename
            progress:^(double p, NSString *stage) {
                if (progress)
                    progress(p);
            }
            completion:^(NSURL *outputURL, NSError *error) {
                // FFmpegKit delivers its completion on a
                // background thread; the caller (editor) does
                // UIKit work, so hop to main.
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion)
                        completion(outputURL, error);
                });
            }
            cancelOut:cancelOut];
        return;
    }
    [self exportTrimWithAVFoundationForSourceURL:sourceURL
                                           asset:asset
                                    startSeconds:startSeconds
                                 durationSeconds:durationSeconds
                                        basename:basename
                                      completion:completion];
}

// AVFoundation fallback for builds without the FFmpeg frameworks (e.g. some
// sideload configs). AVAssetExportSession re-encodes and is frame-accurate.
+ (void)exportTrimWithAVFoundationForSourceURL:(NSURL *)sourceURL
                                         asset:(AVAsset *)asset
                                  startSeconds:(NSTimeInterval)startSeconds
                               durationSeconds:(NSTimeInterval)durationSeconds
                                      basename:(NSString *)basename
                                    completion:(SPKTrimRenderCompletionBlock)completion {
    AVAsset *workingAsset = asset ?: [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:workingAsset
                                                                    presetName:AVAssetExportPresetHighestQuality];
    if (!export) {
        if (completion)
            completion(nil, SPKTrimRendererError(@"Trimming is not available for this video."));
        return;
    }

    NSURL *output = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[basename stringByAppendingPathExtension:@"mp4"]]];
    [[NSFileManager defaultManager] removeItemAtURL:output error:nil];

    CMTime start = CMTimeMakeWithSeconds(startSeconds, 600);
    CMTime duration = CMTimeMakeWithSeconds(durationSeconds, 600);
    export.outputURL = output;
    export.outputFileType = AVFileTypeMPEG4;
    export.shouldOptimizeForNetworkUse = YES;
    export.timeRange = CMTimeRangeMake(start, duration);

    [export exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (export.status == AVAssetExportSessionStatusCompleted) {
                if (completion)
                    completion(output, nil);
            } else {
                NSString *desc = export.error.localizedDescription ?: @"The trim could not be completed.";
                if (completion)
                    completion(nil, SPKTrimRendererError(desc));
            }
        });
    }];
}

#pragma mark - Trim + merge (DASH)

+ (void)renderTrimMergeForVideoURL:(NSURL *)videoURL
                          audioURL:(NSURL *)audioURL
                      startSeconds:(NSTimeInterval)startSeconds
                   durationSeconds:(NSTimeInterval)durationSeconds
                             width:(NSInteger)width
                            height:(NSInteger)height
                          basename:(NSString *)basename
                          progress:(SPKTrimRenderProgressBlock)progress
                        completion:(SPKTrimRenderCompletionBlock)completion
                         cancelOut:(void (^)(dispatch_block_t))cancelOut {
    if (![SPKMediaFFmpeg isAvailable]) {
        if (completion)
            completion(nil, SPKTrimRendererError(@"FFmpeg is required to merge this quality."));
        return;
    }
    [SPKMediaFFmpeg trimMergeVideoURL:videoURL
        audioURL:audioURL
        startSeconds:startSeconds
        durationSeconds:durationSeconds
        preferredBasename:basename
        width:width
        height:height
        progress:^(double p, NSString *stage) {
            if (progress)
                progress(p);
        }
        completion:^(NSURL *outputURL, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion)
                    completion(outputURL, error);
            });
        }
        cancelOut:cancelOut];
}

#pragma mark - Audio

+ (void)renderTrimAudioForSourceURL:(NSURL *)sourceURL
                              asset:(AVAsset *)asset
                       startSeconds:(NSTimeInterval)startSeconds
                    durationSeconds:(NSTimeInterval)durationSeconds
                           basename:(NSString *)basename
                         completion:(SPKTrimRenderCompletionBlock)completion {
    AVAsset *workingAsset = asset ?: [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:workingAsset
                                                                    presetName:AVAssetExportPresetAppleM4A];
    if (!export) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion)
                completion(nil, SPKTrimRendererError(@"Trimming is not available for this audio."));
        });
        return;
    }

    NSURL *output = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[basename stringByAppendingPathExtension:@"m4a"]]];
    [[NSFileManager defaultManager] removeItemAtURL:output error:nil];

    CMTime start = CMTimeMakeWithSeconds(startSeconds, 600);
    CMTime duration = CMTimeMakeWithSeconds(durationSeconds, 600);
    export.outputURL = output;
    export.outputFileType = AVFileTypeAppleM4A;
    export.timeRange = CMTimeRangeMake(start, duration);

    [export exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (export.status == AVAssetExportSessionStatusCompleted) {
                if (completion)
                    completion(output, nil);
            } else {
                NSString *desc = export.error.localizedDescription ?: @"The audio trim could not be completed.";
                if (completion)
                    completion(nil, SPKTrimRendererError(desc));
            }
        });
    }];
}

#pragma mark - Frame

+ (void)renderFrameForAsset:(AVAsset *)asset
                  atSeconds:(NSTimeInterval)seconds
                   basename:(NSString *)basename
                 completion:(SPKTrimRenderCompletionBlock)completion {
    // Load tracks + duration up front. DASH video representations downloaded as
    // standalone fragmented MP4s expose unreliable timing until their metadata
    // is loaded, which is a common cause of AVAssetImageGenerator failing on
    // them. With the duration known we can also clamp the requested time so a
    // playhead parked at the very end doesn't ask for a frame past EOF.
    [asset loadValuesAsynchronouslyForKeys:@[ @"tracks", @"duration" ]
                         completionHandler:^{
                             NSTimeInterval clamped = seconds;
                             NSError *durationError = nil;
                             if ([asset statusOfValueForKey:@"duration" error:&durationError] == AVKeyValueStatusLoaded) {
                                 NSTimeInterval duration = CMTimeGetSeconds(asset.duration);
                                 if (duration > 0 && clamped > duration - 0.05) {
                                     clamped = MAX(0.0, duration - 0.05);
                                 }
                             }
                             if (clamped < 0)
                                 clamped = 0;
                             [self generateFrameForAsset:asset
                                               atSeconds:clamped
                                                basename:basename
                                          allowTolerance:NO
                                              completion:completion];
                         }];
}

// Photo only attempt. We first try an exact (zero-tolerance) extraction; on
// failure we retry once with a generous tolerance so AVFoundation can settle on
// the nearest decodable frame instead of giving up — exactness is irrelevant for
// a still, and zero tolerance is the usual reason DASH-derived clips fail here.
+ (void)generateFrameForAsset:(AVAsset *)asset
                    atSeconds:(NSTimeInterval)seconds
                     basename:(NSString *)basename
               allowTolerance:(BOOL)allowTolerance
                   completion:(SPKTrimRenderCompletionBlock)completion {
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    CMTime tolerance = allowTolerance ? CMTimeMakeWithSeconds(0.5, 600) : kCMTimeZero;
    generator.requestedTimeToleranceBefore = tolerance;
    generator.requestedTimeToleranceAfter = tolerance;

    CMTime cm = CMTimeMakeWithSeconds(seconds, 600);
    [generator generateCGImagesAsynchronouslyForTimes:@[ [NSValue valueWithCMTime:cm] ]
                                    completionHandler:^(CMTime requestedTime, CGImageRef _Nullable image,
                                                        CMTime actualTime, AVAssetImageGeneratorResult result,
                                                        NSError *_Nullable error) {
                                        NSURL *output = (result == AVAssetImageGeneratorSucceeded) ? SPKTrimWriteCGImage(image, basename) : nil;
                                        if (!output && result != AVAssetImageGeneratorCancelled && !allowTolerance) {
                                            // Exact extraction failed — retry once at the nearest decodable frame.
                                            [self generateFrameForAsset:asset
                                                              atSeconds:seconds
                                                               basename:basename
                                                         allowTolerance:YES
                                                             completion:completion];
                                            return;
                                        }
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            if (output) {
                                                if (completion)
                                                    completion(output, nil);
                                            } else {
                                                if (completion)
                                                    completion(nil, SPKTrimRendererError(@"Could not extract the selected frame."));
                                            }
                                        });
                                    }];
}

@end

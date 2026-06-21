#import "SCITrimRenderer.h"
#import "../MediaDownload/SCIMediaFFmpeg.h"

#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>

static NSError *SCITrimRendererError(NSString *description) {
    return [NSError errorWithDomain:@"SCInsta.TrimRenderer"
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: description ?: @"Render failed" }];
}

// Encodes a CGImage to a temp file. Prefers HEIC (much smaller — the whole
// point of reducing a "song over a photo" video to one frame), falls back to
// JPEG if the HEIC encoder is unavailable.
static NSURL *SCITrimWriteCGImage(CGImageRef image, NSString *basename) {
    if (!image) return nil;
    NSString *tmp = NSTemporaryDirectory();

    NSURL *heicURL = [NSURL fileURLWithPath:[tmp stringByAppendingPathComponent:[basename stringByAppendingPathExtension:@"heic"]]];
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)heicURL, (CFStringRef)@"public.heic", 1, NULL);
    if (dest) {
        NSDictionary *props = @{ (__bridge id)kCGImageDestinationLossyCompressionQuality: @0.9 };
        CGImageDestinationAddImage(dest, image, (__bridge CFDictionaryRef)props);
        BOOL ok = CGImageDestinationFinalize(dest);
        CFRelease(dest);
        if (ok) return heicURL;
    }

    NSURL *jpgURL = [NSURL fileURLWithPath:[tmp stringByAppendingPathComponent:[basename stringByAppendingPathExtension:@"jpg"]]];
    NSData *data = UIImageJPEGRepresentation([UIImage imageWithCGImage:image], 0.95);
    if (data && [data writeToURL:jpgURL atomically:YES]) return jpgURL;
    return nil;
}

@implementation SCITrimRenderer

#pragma mark - Trim

+ (void)renderTrimForSourceURL:(NSURL *)sourceURL
                         asset:(AVAsset *)asset
                  startSeconds:(NSTimeInterval)startSeconds
               durationSeconds:(NSTimeInterval)durationSeconds
                      basename:(NSString *)basename
                      progress:(SCITrimRenderProgressBlock)progress
                    completion:(SCITrimRenderCompletionBlock)completion
                     cancelOut:(void (^)(dispatch_block_t))cancelOut {
    if ([SCIMediaFFmpeg isAvailable]) {
        [SCIMediaFFmpeg trimVideoFileURL:sourceURL
                           startSeconds:startSeconds
                        durationSeconds:durationSeconds
                      preferredBasename:basename
                               progress:^(double p, NSString *stage) {
                                   if (progress) progress(p);
                               }
                             completion:^(NSURL *outputURL, NSError *error) {
                                 // FFmpegKit delivers its completion on a
                                 // background thread; the caller (editor) does
                                 // UIKit work, so hop to main.
                                 dispatch_async(dispatch_get_main_queue(), ^{
                                     if (completion) completion(outputURL, error);
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
                                    completion:(SCITrimRenderCompletionBlock)completion {
    AVAsset *workingAsset = asset ?: [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:workingAsset
                                                                   presetName:AVAssetExportPresetHighestQuality];
    if (!export) {
        if (completion) completion(nil, SCITrimRendererError(@"Trimming is not available for this video."));
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
                if (completion) completion(output, nil);
            } else {
                NSString *desc = export.error.localizedDescription ?: @"The trim could not be completed.";
                if (completion) completion(nil, SCITrimRendererError(desc));
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
                          progress:(SCITrimRenderProgressBlock)progress
                        completion:(SCITrimRenderCompletionBlock)completion
                         cancelOut:(void (^)(dispatch_block_t))cancelOut {
    if (![SCIMediaFFmpeg isAvailable]) {
        if (completion) completion(nil, SCITrimRendererError(@"FFmpeg is required to merge this quality."));
        return;
    }
    [SCIMediaFFmpeg trimMergeVideoURL:videoURL
                            audioURL:audioURL
                        startSeconds:startSeconds
                     durationSeconds:durationSeconds
                   preferredBasename:basename
                               width:width
                              height:height
                            progress:^(double p, NSString *stage) {
                                if (progress) progress(p);
                            }
                          completion:^(NSURL *outputURL, NSError *error) {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  if (completion) completion(outputURL, error);
                              });
                          }
                           cancelOut:cancelOut];
}

#pragma mark - Frame

+ (void)renderFrameForAsset:(AVAsset *)asset
                  atSeconds:(NSTimeInterval)seconds
                   basename:(NSString *)basename
                 completion:(SCITrimRenderCompletionBlock)completion {
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.requestedTimeToleranceBefore = kCMTimeZero;
    generator.requestedTimeToleranceAfter = kCMTimeZero;

    CMTime cm = CMTimeMakeWithSeconds(seconds, 600);
    [generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:cm]]
                                    completionHandler:^(CMTime requestedTime, CGImageRef _Nullable image,
                                                        CMTime actualTime, AVAssetImageGeneratorResult result,
                                                        NSError *_Nullable error) {
        NSURL *output = (result == AVAssetImageGeneratorSucceeded) ? SCITrimWriteCGImage(image, basename) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (output) {
                if (completion) completion(output, nil);
            } else {
                if (completion) completion(nil, SCITrimRendererError(@"Could not extract the selected frame."));
            }
        });
    }];
}

@end

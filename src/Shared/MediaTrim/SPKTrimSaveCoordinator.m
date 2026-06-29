#import "SPKTrimSaveCoordinator.h"
#import "SPKTrimResult.h"
#import "SPKTrimRenderer.h"
#import "../UI/SPKIGAlertPresenter.h"
#import "../UI/SPKNotificationCenter.h"
#import "../Gallery/SPKGalleryViewController.h"
#import "../Gallery/SPKGallerySaveMetadata.h"
#import "../Downloads/SPKDownloadDestinationWriter.h"
#import "../../Utils.h"

#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SPKTrimSaveCoordinator ()
+ (void)extractFrameFromURLs:(NSArray<NSURL *> *)urls
                   atSeconds:(NSTimeInterval)seconds
                    basename:(NSString *)basename
                  completion:(void (^)(NSURL *_Nullable, NSError *_Nullable))completion;
@end

@implementation SPKTrimSaveCoordinator

+ (void)saveResult:(SPKTrimResult *)result
        originFile:(SPKGalleryFile *)originFile
    fallbackSource:(SPKGallerySource)fallbackSource
        folderPath:(NSString *)folderPath
         presenter:(UIViewController *)presenter
        completion:(void (^)(BOOL))completion {
    SPKGalleryMediaType mediaType = (result.mode == SPKTrimResultModeSingleFrame)
                                        ? SPKGalleryMediaTypeImage
                                        : SPKGalleryMediaTypeVideo;

    SPKTrimStoreBlock copyStore = ^(NSURL *rendered, void (^done)(BOOL, NSString *)) {
        SPKGallerySource source = originFile ? (SPKGallerySource)originFile.source : fallbackSource;
        NSString *folder = originFile ? originFile.folderPath : folderPath;
        // Carry the original's origin metadata onto the copy so its filename and
        // Open Profile/Post links match (otherwise it falls back to media_other_...).
        SPKGallerySaveMetadata *metadata = originFile ? [originFile saveMetadata] : nil;
        NSError *error = nil;
        SPKGalleryFile *saved = [SPKGalleryFile saveFileToGallery:rendered
                                                           source:source
                                                        mediaType:mediaType
                                                       folderPath:folder
                                                         metadata:metadata
                                                            error:&error];
        if (saved) {
            done(YES, (mediaType == SPKGalleryMediaTypeImage) ? @"Frame saved to Gallery" : @"Trimmed clip saved to Gallery");
        } else {
            done(NO, error.localizedDescription ?: @"Could not save the trimmed file.");
        }
    };

    BOOL shouldPrompt = (originFile != nil) && [SPKUtils getBoolPref:@"trim_gallery_prompt_replace"];
    if (!shouldPrompt) {
        [self renderResult:result progressTitle:nil existingPill:nil store:copyStore onSuccessTap:^{ [SPKGalleryViewController presentGallery]; } completion:completion];
        return;
    }

    SPKTrimStoreBlock replaceStore = ^(NSURL *rendered, void (^done)(BOOL, NSString *)) {
        NSError *error = nil;
        BOOL ok = [originFile replaceMediaWithFileURL:rendered mediaType:mediaType error:&error];
        done(ok, ok ? @"Original replaced" : (error.localizedDescription ?: @"Could not replace the original."));
    };

    NSString *title = (result.mode == SPKTrimResultModeSingleFrame) ? @"Save Frame" : @"Save Trimmed Clip";
    SPKIGAlertAction *replace = [SPKIGAlertAction actionWithTitle:@"Replace Original"
                                                            style:SPKIGAlertActionStyleDestructive
                                                          handler:^{
        [self renderResult:result progressTitle:nil existingPill:nil store:replaceStore onSuccessTap:^{ [SPKGalleryViewController presentGallery]; } completion:completion];
    }];
    SPKIGAlertAction *copy = [SPKIGAlertAction actionWithTitle:@"Save as Copy"
                                                         style:SPKIGAlertActionStyleDefault
                                                       handler:^{
        [self renderResult:result progressTitle:nil existingPill:nil store:copyStore onSuccessTap:^{ [SPKGalleryViewController presentGallery]; } completion:completion];
    }];
    SPKIGAlertAction *cancel = [SPKIGAlertAction actionWithTitle:@"Cancel"
                                                           style:SPKIGAlertActionStyleCancel
                                                         handler:^{
        if (completion) completion(NO);
    }];

    BOOL presented = [SPKIGAlertPresenter presentActionSheetFromViewController:presenter
                                                                        title:title
                                                                      message:@"Replace the original file, or keep both?"
                                                                      actions:@[ replace, copy, cancel ]];
    if (!presented) {
        [self renderResult:result progressTitle:nil existingPill:nil store:copyStore onSuccessTap:^{ [SPKGalleryViewController presentGallery]; } completion:completion];
    }
}

#pragma mark - Destination routing

+ (void)routeResult:(SPKTrimResult *)result
      toDestination:(NSString *)destination
           metadata:(SPKGallerySaveMetadata *)metadata
          presenter:(UIViewController *)presenter
       existingPill:(SPKNotificationPillView *)existingPill
         completion:(void (^)(BOOL))completion {
    SPKGalleryMediaType mediaType = (result.mode == SPKTrimResultModeSingleFrame)
                                        ? SPKGalleryMediaTypeImage
                                        : SPKGalleryMediaTypeVideo;

    SPKTrimStoreBlock store;
    if ([destination isEqualToString:@"photos"]) {
        store = ^(NSURL *rendered, SPKTrimStoreCompletion done) {
            [SPKDownloadDestinationWriter saveFileURLToPhotos:rendered
                                                     metadata:metadata
                                                   completion:^(BOOL ok, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    done(ok, ok ? @"Saved to Photos" : (error.localizedDescription ?: @"Could not save to Photos."));
                });
            }];
        };
    } else if ([destination isEqualToString:@"clipboard"]) {
        store = ^(NSURL *rendered, SPKTrimStoreCompletion done) {
            NSString *ext = rendered.pathExtension.lowercaseString;
            BOOL isVideo = [ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"];
            if (isVideo) {
                NSData *data = [NSData dataWithContentsOfURL:rendered options:NSDataReadingMappedIfSafe error:nil];
                if (data) {
                    [UIPasteboard generalPasteboard].items = @[ @{ UTTypeMovie.identifier: data } ];
                    done(YES, @"Copied clip to clipboard");
                } else {
                    done(NO, @"Could not copy the clip.");
                }
            } else {
                UIImage *image = [UIImage imageWithContentsOfFile:rendered.path];
                if (image) {
                    [[UIPasteboard generalPasteboard] setImage:image];
                    done(YES, @"Copied frame to clipboard");
                } else {
                    done(NO, @"Could not copy the frame.");
                }
            }
        };
    } else if ([destination isEqualToString:@"share"]) {
        store = ^(NSURL *rendered, SPKTrimStoreCompletion done) {
            UIViewController *host = presenter ?: topMostController();
            if (!host) { done(NO, @"Could not present share sheet."); return; }
            UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[ rendered ]
                                                                            applicationActivities:nil];
            vc.completionWithItemsHandler = ^(UIActivityType _Nullable type, BOOL completed,
                                              NSArray *_Nullable items, NSError *_Nullable err) {
                done(YES, completed ? @"Shared" : nil);
            };
            if (vc.popoverPresentationController) {
                vc.popoverPresentationController.sourceView = host.view;
                vc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds),
                                                                         CGRectGetMidY(host.view.bounds), 1, 1);
                vc.popoverPresentationController.permittedArrowDirections = 0;
            }
            [host presentViewController:vc animated:YES completion:nil];
        };
    } else {
        store = ^(NSURL *rendered, SPKTrimStoreCompletion done) {
            SPKGallerySource source = metadata ? (SPKGallerySource)metadata.source : SPKGallerySourceOther;
            NSError *error = nil;
            SPKGalleryFile *saved = [SPKGalleryFile saveFileToGallery:rendered
                                                               source:source
                                                            mediaType:mediaType
                                                           folderPath:nil
                                                             metadata:metadata
                                                                error:&error];
            if (saved) done(YES, (mediaType == SPKGalleryMediaTypeImage) ? @"Frame saved to Gallery" : @"Trimmed clip saved to Gallery");
            else done(NO, error.localizedDescription ?: @"Could not save to Gallery.");
        };
    }

    void (^onSuccessTap)(void) = nil;
    if ([destination isEqualToString:@"gallery"]) {
        onSuccessTap = ^{ [SPKGalleryViewController presentGallery]; };
    } else if ([destination isEqualToString:@"photos"]) {
        onSuccessTap = ^{ [SPKUtils openPhotosApp]; };
    }

    [self renderResult:result
         progressTitle:nil
          existingPill:existingPill
                 store:store
          onSuccessTap:onSuccessTap
            completion:completion];
}

#pragma mark - Background render

// Renders in the background behind a progress pill (cancellable), then stores
// the output. The app stays usable throughout.
+ (void)renderResult:(SPKTrimResult *)result
       progressTitle:(NSString *)progressTitle
        existingPill:(SPKNotificationPillView *)existingPill
               store:(SPKTrimStoreBlock)store
         onSuccessTap:(void (^)(void))onSuccessTap
          completion:(void (^)(BOOL))completion {
    BOOL isFrame = (result.mode == SPKTrimResultModeSingleFrame);
    NSString *basename = [NSString stringWithFormat:@"SPKTrim-%@", NSUUID.UUID.UUIDString];
    NSString *title = progressTitle.length > 0 ? progressTitle : (isFrame ? @"Extracting frame..." : @"Trimming...");

    // Continue an in-flight pill (e.g. from a preceding download) instead of
    // stacking a second notification.
    SPKNotificationPillView *pill = existingPill;
    if (pill) {
        [pill updateProgressTitle:title subtitle:nil];
        [pill setProgress:0.0f animated:NO];
    } else {
        pill = [[SPKNotificationCenter shared] beginUnmanagedProgressWithTitle:title onCancel:nil];
    }

    __block dispatch_block_t cancelRender = nil;
    __block BOOL cancelled = NO;
    __weak SPKNotificationPillView *weakPill = pill;
    pill.onCancel = ^{
        // Confirm first (mirrors the download cancel). The pill's close button
        // calls onCancel without dismissing, so dismiss on confirm.
        [SPKTrimSaveCoordinator confirmCancelThen:^{
            cancelled = YES;
            if (cancelRender) cancelRender();
            [weakPill dismiss];
        }];
    };

    void (^onRendered)(NSURL *, NSError *) = ^(NSURL *renderedURL, NSError *error) {
        if (cancelled) {
            if (renderedURL) [[NSFileManager defaultManager] removeItemAtURL:renderedURL error:nil];
            if (completion) completion(NO);
            return;
        }
        if (!renderedURL) {
            [pill showError:error.localizedDescription ?: @"Trim failed"];
            if (completion) completion(NO);
            return;
        }
        store(renderedURL, ^(BOOL ok, NSString *message) {
            [[NSFileManager defaultManager] removeItemAtURL:renderedURL error:nil];
            if (ok) {
                [pill showSuccessWithTitle:message subtitle:(onSuccessTap ? @"Tap to view" : nil) icon:nil];
                if (onSuccessTap) pill.onTapWhenCompleted = onSuccessTap;
            } else {
                [pill showError:message ?: @"Save failed"];
            }
            if (completion) completion(ok);
        });
    };

    void (^progressToPill)(double) = ^(double p) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [pill setProgress:(float)MAX(0.0, MIN(1.0, p)) animated:YES];
        });
    };

    if (isFrame) {
        // Extract from the chosen-quality video when overridden, else the edit
        // file. For DASH the chosen-quality source is a standalone fragmented
        // MP4 that AVFoundation can occasionally fail to decode a still from, so
        // fall back to the muxed edit file the user actually scrubbed (always
        // AVFoundation-friendly) before giving up.
        NSMutableArray<NSURL *> *frameSources = [NSMutableArray array];
        if (result.renderVideoURL) [frameSources addObject:result.renderVideoURL];
        if (result.sourceURL && ![result.sourceURL isEqual:result.renderVideoURL]) {
            [frameSources addObject:result.sourceURL];
        }
        [self extractFrameFromURLs:frameSources
                         atSeconds:result.startSeconds
                          basename:basename
                        completion:onRendered];
    } else if (result.renderAudioURL) {
        // DASH: merge the chosen-quality video + audio over the selected range.
        [SPKTrimRenderer renderTrimMergeForVideoURL:result.renderVideoURL
                                           audioURL:result.renderAudioURL
                                       startSeconds:result.startSeconds
                                    durationSeconds:result.durationSeconds
                                              width:result.width
                                             height:result.height
                                           basename:basename
                                           progress:progressToPill
                                         completion:onRendered
                                          cancelOut:^(dispatch_block_t cancel) {
            cancelRender = cancel;
        }];
    } else {
        [SPKTrimRenderer renderTrimForSourceURL:(result.renderVideoURL ?: result.sourceURL)
                                          asset:nil
                                   startSeconds:result.startSeconds
                                durationSeconds:result.durationSeconds
                                       basename:basename
                                       progress:progressToPill
                                     completion:onRendered
                                      cancelOut:^(dispatch_block_t cancel) {
            cancelRender = cancel;
        }];
    }
}

#pragma mark - Frame extraction (with source fallback)

// Tries each candidate URL in order, returning the first frame that decodes.
// Lets us prefer the chosen-quality video but fall back to the muxed edit file
// when AVFoundation can't pull a still from a DASH fragment.
+ (void)extractFrameFromURLs:(NSArray<NSURL *> *)urls
                   atSeconds:(NSTimeInterval)seconds
                    basename:(NSString *)basename
                  completion:(void (^)(NSURL *_Nullable, NSError *_Nullable))completion {
    if (urls.count == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"Sparkle.TrimSave"
                                                code:1
                                            userInfo:@{ NSLocalizedDescriptionKey: @"Could not extract the selected frame." }]);
        }
        return;
    }
    NSURL *candidate = urls.firstObject;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:candidate options:nil];
    [SPKTrimRenderer renderFrameForAsset:asset
                               atSeconds:seconds
                                basename:basename
                              completion:^(NSURL *output, NSError *error) {
        if (output) {
            if (completion) completion(output, nil);
            return;
        }
        if (urls.count <= 1) {
            if (completion) completion(nil, error);
            return;
        }
        [self extractFrameFromURLs:[urls subarrayWithRange:NSMakeRange(1, urls.count - 1)]
                         atSeconds:seconds
                          basename:basename
                        completion:completion];
    }];
}

#pragma mark - Cancel confirmation

+ (void)confirmCancelThen:(void (^)(void))onConfirm {
    UIViewController *host = topMostController();
    if (!host) {
        if (onConfirm) onConfirm();
        return;
    }
    SPKIGAlertAction *keep = [SPKIGAlertAction actionWithTitle:@"Keep Trimming"
                                                         style:SPKIGAlertActionStyleCancel
                                                       handler:nil];
    SPKIGAlertAction *stop = [SPKIGAlertAction actionWithTitle:@"Cancel Trim"
                                                         style:SPKIGAlertActionStyleDestructive
                                                       handler:^{ if (onConfirm) onConfirm(); }];
    [SPKIGAlertPresenter presentAlertFromViewController:host
                                                 title:@"Cancel Trim"
                                               message:@"Stop trimming and discard progress?"
                                               actions:@[ keep, stop ]];
}

@end

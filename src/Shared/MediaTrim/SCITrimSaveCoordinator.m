#import "SCITrimSaveCoordinator.h"
#import "SCITrimResult.h"
#import "SCITrimRenderer.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../UI/SCINotificationCenter.h"
#import "../Gallery/SCIGalleryViewController.h"
#import "../../Utils.h"

#import <AVFoundation/AVFoundation.h>

@implementation SCITrimSaveCoordinator

+ (void)saveResult:(SCITrimResult *)result
        originFile:(SCIGalleryFile *)originFile
    fallbackSource:(SCIGallerySource)fallbackSource
        folderPath:(NSString *)folderPath
         presenter:(UIViewController *)presenter
        completion:(void (^)(BOOL))completion {
    SCIGalleryMediaType mediaType = (result.mode == SCITrimResultModeSingleFrame)
                                        ? SCIGalleryMediaTypeImage
                                        : SCIGalleryMediaTypeVideo;

    SCITrimStoreBlock copyStore = ^(NSURL *rendered, void (^done)(BOOL, NSString *)) {
        SCIGallerySource source = originFile ? (SCIGallerySource)originFile.source : fallbackSource;
        NSString *folder = originFile ? originFile.folderPath : folderPath;
        // Carry the original's origin metadata onto the copy so its filename and
        // Open Profile/Post links match (otherwise it falls back to media_other_…).
        SCIGallerySaveMetadata *metadata = originFile ? [originFile saveMetadata] : nil;
        NSError *error = nil;
        SCIGalleryFile *saved = [SCIGalleryFile saveFileToGallery:rendered
                                                           source:source
                                                        mediaType:mediaType
                                                       folderPath:folder
                                                         metadata:metadata
                                                            error:&error];
        if (saved) {
            done(YES, (mediaType == SCIGalleryMediaTypeImage) ? @"Frame saved to Gallery" : @"Trimmed clip saved to Gallery");
        } else {
            done(NO, error.localizedDescription ?: @"Could not save the trimmed file.");
        }
    };

    BOOL shouldPrompt = (originFile != nil) && [SCIUtils getBoolPref:@"trim_gallery_prompt_replace"];
    if (!shouldPrompt) {
        [self renderResult:result progressTitle:nil existingPill:nil store:copyStore onSuccessTap:^{ [SCIGalleryViewController presentGallery]; } completion:completion];
        return;
    }

    SCITrimStoreBlock replaceStore = ^(NSURL *rendered, void (^done)(BOOL, NSString *)) {
        NSError *error = nil;
        BOOL ok = [originFile replaceMediaWithFileURL:rendered mediaType:mediaType error:&error];
        done(ok, ok ? @"Original replaced" : (error.localizedDescription ?: @"Could not replace the original."));
    };

    NSString *title = (result.mode == SCITrimResultModeSingleFrame) ? @"Save Frame" : @"Save Trimmed Clip";
    SCIIGAlertAction *replace = [SCIIGAlertAction actionWithTitle:@"Replace Original"
                                                            style:SCIIGAlertActionStyleDestructive
                                                          handler:^{
        [self renderResult:result progressTitle:nil existingPill:nil store:replaceStore onSuccessTap:^{ [SCIGalleryViewController presentGallery]; } completion:completion];
    }];
    SCIIGAlertAction *copy = [SCIIGAlertAction actionWithTitle:@"Save as Copy"
                                                         style:SCIIGAlertActionStyleDefault
                                                       handler:^{
        [self renderResult:result progressTitle:nil existingPill:nil store:copyStore onSuccessTap:^{ [SCIGalleryViewController presentGallery]; } completion:completion];
    }];
    SCIIGAlertAction *cancel = [SCIIGAlertAction actionWithTitle:@"Cancel"
                                                           style:SCIIGAlertActionStyleCancel
                                                         handler:^{
        if (completion) completion(NO);
    }];

    BOOL presented = [SCIIGAlertPresenter presentActionSheetFromViewController:presenter
                                                                        title:title
                                                                      message:@"Replace the original file, or keep both?"
                                                                      actions:@[ replace, copy, cancel ]];
    if (!presented) {
        [self renderResult:result progressTitle:nil existingPill:nil store:copyStore onSuccessTap:^{ [SCIGalleryViewController presentGallery]; } completion:completion];
    }
}

#pragma mark - Background render

// Renders in the background behind a progress pill (cancellable), then stores
// the output. The app stays usable throughout.
+ (void)renderResult:(SCITrimResult *)result
       progressTitle:(NSString *)progressTitle
        existingPill:(SCINotificationPillView *)existingPill
               store:(SCITrimStoreBlock)store
         onSuccessTap:(void (^)(void))onSuccessTap
          completion:(void (^)(BOOL))completion {
    BOOL isFrame = (result.mode == SCITrimResultModeSingleFrame);
    NSString *basename = [NSString stringWithFormat:@"SCITrim-%@", NSUUID.UUID.UUIDString];
    NSString *title = progressTitle.length > 0 ? progressTitle : (isFrame ? @"Extracting frame…" : @"Trimming…");

    // Continue an in-flight pill (e.g. from a preceding download) instead of
    // stacking a second notification.
    SCINotificationPillView *pill = existingPill;
    if (pill) {
        [pill updateProgressTitle:title subtitle:nil];
        [pill setProgress:0.0f animated:NO];
    } else {
        pill = [[SCINotificationCenter shared] beginUnmanagedProgressWithTitle:title onCancel:nil];
    }

    __block dispatch_block_t cancelRender = nil;
    __block BOOL cancelled = NO;
    __weak SCINotificationPillView *weakPill = pill;
    pill.onCancel = ^{
        // Confirm first (mirrors the download cancel). The pill's close button
        // calls onCancel without dismissing, so dismiss on confirm.
        [SCITrimSaveCoordinator confirmCancelThen:^{
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
        // Extract from the chosen-quality video when overridden, else the edit file.
        NSURL *frameURL = result.renderVideoURL ?: result.sourceURL;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:frameURL options:nil];
        [SCITrimRenderer renderFrameForAsset:asset
                                   atSeconds:result.startSeconds
                                    basename:basename
                                  completion:onRendered];
    } else if (result.renderAudioURL) {
        // DASH: merge the chosen-quality video + audio over the selected range.
        [SCITrimRenderer renderTrimMergeForVideoURL:result.renderVideoURL
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
        [SCITrimRenderer renderTrimForSourceURL:(result.renderVideoURL ?: result.sourceURL)
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

#pragma mark - Cancel confirmation

+ (void)confirmCancelThen:(void (^)(void))onConfirm {
    UIViewController *host = topMostController();
    if (!host) {
        if (onConfirm) onConfirm();
        return;
    }
    SCIIGAlertAction *keep = [SCIIGAlertAction actionWithTitle:@"Keep Trimming"
                                                         style:SCIIGAlertActionStyleCancel
                                                       handler:nil];
    SCIIGAlertAction *stop = [SCIIGAlertAction actionWithTitle:@"Cancel Trim"
                                                         style:SCIIGAlertActionStyleDestructive
                                                       handler:^{ if (onConfirm) onConfirm(); }];
    [SCIIGAlertPresenter presentAlertFromViewController:host
                                                 title:@"Cancel Trim"
                                               message:@"Stop trimming and discard progress?"
                                               actions:@[ keep, stop ]];
}

@end

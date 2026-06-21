#import "SCITrimEntry.h"
#import "SCITrimConfiguration.h"
#import "SCITrimResult.h"
#import "SCITrimSourcePlan.h"
#import "SCITrimEditorViewController.h"
#import "SCITrimSaveCoordinator.h"

#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGalleryViewController.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../Downloads/SCIDownloadDestinationWriter.h"
#import "../MediaDownload/SCIMediaQualityManager.h"
#import "../UI/SCINotificationCenter.h"
#import "../../Utils.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SCITrimEntry () <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, strong) SCINotificationPillView *prepPill;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, strong, nullable) SCIGallerySaveMetadata *metadata;
@property (nonatomic, strong, nullable) id mediaObject;
@property (nonatomic, copy, nullable) NSURL *photoURL;
@property (nonatomic, copy, nullable) NSURL *videoURL;
@property (nonatomic, strong) SCITrimSourcePlan *plan;
@property (nonatomic, strong) NSMutableArray<NSString *> *tempPaths;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, strong, nullable) SCITrimEntry *selfRetain;

// Sequential download queue state.
@property (nonatomic, strong) NSMutableArray<NSURL *> *pendingURLs;
@property (nonatomic, strong) NSMutableArray<NSURL *> *downloadedURLs;
@property (nonatomic, assign) BOOL ownsPrepPill;
@property (nonatomic, copy, nullable) void (^queueCompletion)(NSArray<NSURL *> *_Nullable localURLs);
@end

@implementation SCITrimEntry

+ (void)beginTrimAndSaveForMediaObject:(id)mediaObject
                              photoURL:(NSURL *)photoURL
                              videoURL:(NSURL *)videoURL
                              metadata:(SCIGallerySaveMetadata *)metadata
                             presenter:(UIViewController *)presenter {
    if (!presenter) {
        return;
    }
    SCITrimEntry *entry = [[self alloc] init];
    entry.presenter = presenter;
    entry.metadata = metadata;
    entry.mediaObject = mediaObject;
    entry.photoURL = photoURL;
    entry.videoURL = videoURL;
    entry.tempPaths = [NSMutableArray array];
    entry.selfRetain = entry;  // keep alive across the async flow

    NSString *quality = [SCIUtils getStringPref:@"downloads_video_quality"];
    if ([quality isEqualToString:@"always_ask"]) {
        // Reuse the download flow's own quality picker (audio-only rows hidden).
        [SCIMediaQualityManager presentTrimQualityPickerForMediaObject:mediaObject
                                                              photoURL:photoURL
                                                              videoURL:videoURL
                                                                  from:presenter
                                                            completion:^(SCITrimSourcePlan *plan) {
            if (!plan) { [entry finish]; return; }  // dismissed
            entry.plan = plan;
            [entry startWithPlan];
        }];
        return;
    }

    SCITrimSourcePlan *plan = [SCIMediaQualityManager trimSourcePlanForMediaObject:mediaObject
                                                                          photoURL:photoURL
                                                                          videoURL:videoURL
                                                                   qualityOverride:nil];
    if (!plan) {
        SCINotify(@"sci.trim.entry", @"No video to trim", nil, @"error_filled", SCINotificationToneError);
        [entry finish];
        return;
    }
    entry.plan = plan;
    [entry startWithPlan];
}

#pragma mark - Start

- (void)startWithPlan {
    // Scrub on a small muxed preview (has audio — important for cutting to
    // music). For progressive quality the chosen file is the final, so edit and
    // final are the same download.
    NSURL *editURL = self.plan.needsMerge ? self.plan.editURL : self.plan.finalVideoURL;
    if (editURL.isFileURL) {
        [self presentEditorForLocalURL:editURL];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self downloadURLs:@[ editURL ] title:@"Preparing video…" pill:nil completion:^(NSArray<NSURL *> *locals) {
        if (locals.count > 0) {
            [weakSelf presentEditorForLocalURL:locals[0]];
        }
    }];
}

#pragma mark - Download queue

// When `pill` is non-nil the queue continues that pill (a stage hand-off) and
// does not dismiss it on completion — the next stage finalizes it. Otherwise a
// fresh pill is created and dismissed when the queue finishes.
- (void)downloadURLs:(NSArray<NSURL *> *)urls
               title:(NSString *)title
                pill:(SCINotificationPillView *)pill
          completion:(void (^)(NSArray<NSURL *> *_Nullable))completion {
    self.pendingURLs = [urls mutableCopy];
    self.downloadedURLs = [NSMutableArray array];
    self.queueCompletion = completion;

    __weak typeof(self) weakSelf = self;
    void (^onCancel)(void) = ^{
        // Confirm first (mirrors the download cancel); the pill's close button
        // calls onCancel without dismissing.
        [SCITrimSaveCoordinator confirmCancelThen:^{
            __strong typeof(weakSelf) self = weakSelf;
            self.cancelled = YES;
            [self.task cancel];
            [self.prepPill dismiss];
            self.prepPill = nil;
            [self cleanupAndFinish];
        }];
    };
    if (pill) {
        self.prepPill = pill;
        self.ownsPrepPill = NO;
        [pill updateProgressTitle:title subtitle:nil];
        [pill setProgress:0.0f animated:NO];
        pill.onCancel = onCancel;
    } else {
        self.ownsPrepPill = YES;
        self.prepPill = [[SCINotificationCenter shared] beginUnmanagedProgressWithTitle:title
                                                                               onCancel:onCancel];
    }

    if (!self.session) {
        self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                     delegate:self
                                                delegateQueue:nil];
    }
    [self startNextDownload];
}

- (void)startNextDownload {
    if (self.cancelled) return;
    if (self.pendingURLs.count == 0) {
        // Only dismiss a pill we own; a handed-off pill continues into the next
        // stage (which finalizes it).
        if (self.ownsPrepPill) {
            [self.prepPill dismiss];
        }
        self.prepPill = nil;
        void (^completion)(NSArray<NSURL *> *) = self.queueCompletion;
        self.queueCompletion = nil;
        if (completion) completion([self.downloadedURLs copy]);
        return;
    }
    NSURL *next = self.pendingURLs.firstObject;
    [self.pendingURLs removeObjectAtIndex:0];
    self.task = [self.session downloadTaskWithURL:next];
    [self.task resume];
}

- (void)URLSession:(NSURLSession *)session
              downloadTask:(NSURLSessionDownloadTask *)downloadTask
              didWriteData:(int64_t)bytesWritten
         totalBytesWritten:(int64_t)totalBytesWritten
 totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite <= 0) return;
    float p = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.prepPill setProgress:MAX(0.0f, MIN(1.0f, p)) animated:YES];
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSString *dest = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"SCITrimSrc-%@.mp4", NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
    if ([[NSFileManager defaultManager] moveItemAtPath:location.path toPath:dest error:nil]) {
        @synchronized (self) {
            [self.downloadedURLs addObject:[NSURL fileURLWithPath:dest]];
            [self.tempPaths addObject:dest];
        }
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cancelled) return;
        BOOL gotFile = self.downloadedURLs.count > 0 &&
                       [[NSFileManager defaultManager] fileExistsAtPath:self.downloadedURLs.lastObject.path];
        if (error || !gotFile) {
            [self.prepPill showError:error.localizedDescription ?: @"Could not download the video."];
            self.prepPill = nil;
            [self cleanupAndFinish];
            return;
        }
        [self startNextDownload];
    });
}

#pragma mark - Editor

- (void)presentEditorForLocalURL:(NSURL *)localURL {
    UIViewController *presenter = self.presenter;
    if (!presenter) {
        [self cleanupAndFinish];
        return;
    }
    SCITrimConfiguration *config = [SCITrimConfiguration configurationWithVideoURL:localURL];
    // Done becomes a menu of destinations (chosen without dismissing first).
    config.doneOptions = @[
        [SCITrimDoneOption optionWithTitle:@"Save to Photos" identifier:@"photos" iconName:@"download"],
        [SCITrimDoneOption optionWithTitle:@"Save to Gallery" identifier:@"gallery" iconName:@"media"],
        [SCITrimDoneOption optionWithTitle:@"Share" identifier:@"share" iconName:@"share"],
        [SCITrimDoneOption optionWithTitle:@"Copy" identifier:@"clipboard" iconName:@"copy"],
    ];
    __weak typeof(self) weakSelf = self;
    [SCITrimEditorViewController presentWithConfiguration:config
                                                    from:presenter
                                              completion:^(SCITrimResult *result) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (!result) {
            [self cleanupAndFinish];  // cancelled
            return;
        }
        [self renderResult:result toDestination:(result.destinationTag ?: @"gallery")];
    }];
}

#pragma mark - Render

// DASH needs its high-res video + audio fetched to local files first — the
// bundled FFmpeg has no TLS, so it can't read the https stream URLs directly.
- (void)renderResult:(SCITrimResult *)result toDestination:(NSString *)destination {
    if (self.plan.needsMerge && !result.renderVideoURL) {
        // One continuous pill spans the high-quality download and the render —
        // hand it off rather than stacking a second notification.
        SCINotificationPillView *pill =
            [[SCINotificationCenter shared] beginUnmanagedProgressWithTitle:@"Downloading…" onCancel:nil];
        __weak typeof(self) weakSelf = self;
        [self downloadURLs:@[ self.plan.finalVideoURL, self.plan.finalAudioURL ]
                     title:@"Downloading high quality…"
                      pill:pill
                completion:^(NSArray<NSURL *> *locals) {
            __strong typeof(weakSelf) self = weakSelf;
            if (locals.count < 2) { [self cleanupAndFinish]; return; }
            result.renderVideoURL = locals[0];
            result.renderAudioURL = locals[1];
            result.width = self.plan.width;
            result.height = self.plan.height;
            [self performRenderResult:result toDestination:destination pill:pill];
        }];
        return;
    }
    [self performRenderResult:result toDestination:destination pill:nil];
}

- (void)performRenderResult:(SCITrimResult *)result toDestination:(NSString *)destination pill:(SCINotificationPillView *)pill {
    SCIGalleryMediaType mediaType = (result.mode == SCITrimResultModeSingleFrame)
                                        ? SCIGalleryMediaTypeImage
                                        : SCIGalleryMediaTypeVideo;
    SCIGallerySaveMetadata *metadata = self.metadata;
    UIViewController *presenter = self.presenter;
    __weak typeof(self) weakSelf = self;

    SCITrimStoreBlock store;
    if ([destination isEqualToString:@"photos"]) {
        store = ^(NSURL *rendered, SCITrimStoreCompletion done) {
            [SCIDownloadDestinationWriter saveFileURLToPhotos:rendered
                                                     metadata:metadata
                                                   completion:^(BOOL ok, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    done(ok, ok ? @"Saved to Photos" : (error.localizedDescription ?: @"Could not save to Photos."));
                });
            }];
        };
    } else if ([destination isEqualToString:@"clipboard"]) {
        store = ^(NSURL *rendered, SCITrimStoreCompletion done) {
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
        store = ^(NSURL *rendered, SCITrimStoreCompletion done) {
            UIViewController *host = presenter;
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
        store = ^(NSURL *rendered, SCITrimStoreCompletion done) {
            SCIGallerySource source = metadata ? (SCIGallerySource)metadata.source : SCIGallerySourceOther;
            NSError *error = nil;
            SCIGalleryFile *saved = [SCIGalleryFile saveFileToGallery:rendered
                                                               source:source
                                                            mediaType:mediaType
                                                           folderPath:nil
                                                             metadata:metadata
                                                                error:&error];
            if (saved) done(YES, (mediaType == SCIGalleryMediaTypeImage) ? @"Frame saved to Gallery" : @"Trimmed clip saved to Gallery");
            else done(NO, error.localizedDescription ?: @"Could not save to Gallery.");
        };
    }

    void (^onSuccessTap)(void) = nil;
    if ([destination isEqualToString:@"gallery"]) {
        onSuccessTap = ^{ [SCIGalleryViewController presentGallery]; };
    } else if ([destination isEqualToString:@"photos"]) {
        onSuccessTap = ^{ [SCIUtils openPhotosApp]; };
    }

    [SCITrimSaveCoordinator renderResult:result
                           progressTitle:nil
                            existingPill:pill
                                   store:store
                            onSuccessTap:onSuccessTap
                              completion:^(BOOL ok) {
        [weakSelf cleanupAndFinish];
    }];
}

#pragma mark - Lifecycle

- (void)cleanupAndFinish {
    for (NSString *path in self.tempPaths) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    [self.tempPaths removeAllObjects];
    [self finish];
}

- (void)finish {
    [self.session finishTasksAndInvalidate];
    self.session = nil;
    self.selfRetain = nil;  // allow deallocation
}

@end

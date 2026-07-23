from __future__ import annotations

import re
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"Could not find {label}")
    return text.replace(old, new, 1)


def replace_pattern(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise RuntimeError(f"Could not replace {label}; matches={count}")
    return updated


# ---------------------------------------------------------------------------
# Download destination writer header
# ---------------------------------------------------------------------------
header_path = Path("src/Shared/Downloads/SPKDownloadDestinationWriter.h")
header = header_path.read_text()
header_marker = "+ (BOOL)isAudioFileAtURL:(NSURL *)fileURL;\n"
header_declarations = """+ (BOOL)isAudioFileAtURL:(NSURL *)fileURL;
+ (void)preparePhotoCompatibleVideoAtURL:(NSURL *)fileURL
+                              completion:(void (^)(NSURL *_Nullable preparedURL,
+                                                   BOOL temporaryFile,
+                                                   NSError *_Nullable error))completion;
+ (void)presentShareSheetForFileURL:(NSURL *)fileURL
+                          presenter:(nullable UIViewController *)presenter
+                         anchorView:(nullable UIView *)anchorView
+                         completion:(nullable void (^)(NSError *_Nullable error))completion;
"""
header = replace_once(header, header_marker, header_declarations, "writer header insertion point")
header_path.write_text(header)


# ---------------------------------------------------------------------------
# Download destination writer implementation
# ---------------------------------------------------------------------------
writer_path = Path("src/Shared/Downloads/SPKDownloadDestinationWriter.m")
writer = writer_path.read_text()
writer = replace_once(
    writer,
    '#import "SPKDownloadDuplicatePolicy.h"\n#import <Photos/Photos.h>',
    '#import "SPKDownloadDuplicatePolicy.h"\n#import <AVFoundation/AVFoundation.h>\n#import <Photos/Photos.h>',
    "AVFoundation import",
)

error_helper = """
static NSError *SPKPhotosCompatibilityError(NSInteger code,
                                             NSString *description) {
    return [NSError errorWithDomain:@"com.k4l.photos.compatibility"
                               code:code
                           userInfo:@{
                               NSLocalizedDescriptionKey :
                                   description ?: @"Could not prepare the video for Photos."
                           }];
}

"""
writer = replace_once(writer, "@interface SPKDownloadDestinationWriter ()\n", error_helper + "@interface SPKDownloadDestinationWriter ()\n", "Photos error helper insertion point")

helper_methods = r'''
+ (void)preparePhotoCompatibleVideoAtURL:(NSURL *)fileURL
                              completion:(void (^)(NSURL *preparedURL,
                                                   BOOL temporaryFile,
                                                   NSError *error))completion {
    BOOL isDirectory = NO;
    BOOL exists = fileURL.isFileURL &&
                  [[NSFileManager defaultManager] fileExistsAtPath:fileURL.path
                                                       isDirectory:&isDirectory] &&
                  !isDirectory;
    if (!exists) {
        if (completion) {
            completion(nil, NO,
                       SPKPhotosCompatibilityError(
                           1, @"The Gallery video file is missing."));
        }
        return;
    }

    AVURLAsset *asset = [AVURLAsset
        URLAssetWithURL:fileURL
                options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @YES}];
    AVAssetTrack *videoTrack =
        [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!videoTrack || !CMTIME_IS_NUMERIC(asset.duration) ||
        CMTimeCompare(asset.duration, kCMTimeZero) <= 0) {
        if (completion) {
            completion(nil, NO,
                       SPKPhotosCompatibilityError(
                           2, @"The saved file does not contain a valid video track."));
        }
        return;
    }

    NSArray<NSString *> *presets =
        [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSString *preset =
        [presets containsObject:AVAssetExportPresetHighestQuality]
            ? AVAssetExportPresetHighestQuality
            : ([presets containsObject:AVAssetExportPresetMediumQuality]
                   ? AVAssetExportPresetMediumQuality
                   : nil);
    if (!preset) {
        if (completion) {
            completion(nil, NO,
                       SPKPhotosCompatibilityError(
                           3, @"iOS could not create a Photos-compatible version of this video."));
        }
        return;
    }

    AVAssetExportSession *session =
        [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    AVFileType outputType = nil;
    NSString *outputExtension = nil;
    if ([session.supportedFileTypes containsObject:AVFileTypeMPEG4]) {
        outputType = AVFileTypeMPEG4;
        outputExtension = @"mp4";
    } else if ([session.supportedFileTypes
                   containsObject:AVFileTypeQuickTimeMovie]) {
        outputType = AVFileTypeQuickTimeMovie;
        outputExtension = @"mov";
    }
    if (!session || !outputType) {
        if (completion) {
            completion(nil, NO,
                       SPKPhotosCompatibilityError(
                           4, @"No supported Photos video format is available."));
        }
        return;
    }

    NSString *name = [NSString
        stringWithFormat:@"K4L-Photos-%@.%@", NSUUID.UUID.UUIDString,
                         outputExtension];
    NSURL *outputURL = [NSURL
        fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    session.outputURL = outputURL;
    session.outputFileType = outputType;
    session.shouldOptimizeForNetworkUse = YES;

    [session exportAsynchronouslyWithCompletionHandler:^{
        NSError *exportError = session.error;
        NSDictionary *attributes = [[NSFileManager defaultManager]
            attributesOfItemAtPath:outputURL.path
                             error:nil];
        BOOL validOutput =
            session.status == AVAssetExportSessionStatusCompleted &&
            [attributes[NSFileSize] longLongValue] > 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (validOutput) {
                if (completion)
                    completion(outputURL, YES, nil);
                return;
            }
            [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
            if (completion) {
                completion(nil, NO,
                           exportError ?: SPKPhotosCompatibilityError(
                                              5, @"The Photos-compatible video export failed."));
            }
        });
    }];
}

+ (void)presentShareSheetForFileURL:(NSURL *)fileURL
                          presenter:(UIViewController *)presenter
                         anchorView:(UIView *)anchorView
                         completion:(void (^)(NSError *error))completion {
    void (^presentURL)(NSURL *, BOOL) = ^(NSURL *shareURL, BOOL temporaryFile) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *host = presenter ?: topMostController();
            if (!host || !shareURL) {
                if (temporaryFile && shareURL) {
                    [[NSFileManager defaultManager] removeItemAtURL:shareURL
                                                              error:nil];
                }
                if (completion) {
                    completion(SPKPhotosCompatibilityError(
                        6, @"Could not open the share sheet."));
                }
                return;
            }

            UIActivityViewController *controller =
                [[UIActivityViewController alloc]
                    initWithActivityItems:@[ shareURL ]
                    applicationActivities:nil];
            if (UIDevice.currentDevice.userInterfaceIdiom ==
                UIUserInterfaceIdiomPad) {
                UIView *anchor = anchorView ?: host.view;
                controller.popoverPresentationController.sourceView = anchor;
                controller.popoverPresentationController.sourceRect =
                    anchor.bounds;
            }
            controller.completionWithItemsHandler =
                ^(__unused UIActivityType activityType,
                  __unused BOOL completed,
                  __unused NSArray *returnedItems,
                  NSError *activityError) {
                    if (temporaryFile) {
                        [[NSFileManager defaultManager]
                            removeItemAtURL:shareURL
                                     error:nil];
                    }
                    if (completion)
                        completion(activityError);
                };
            [host presentViewController:controller animated:YES completion:nil];
        });
    };

    if ([self isVideoFileAtURL:fileURL]) {
        [self preparePhotoCompatibleVideoAtURL:fileURL
                                    completion:^(NSURL *preparedURL,
                                                 BOOL temporaryFile,
                                                 NSError *error) {
                                        if (!preparedURL || error) {
                                            if (completion) {
                                                completion(error ?: SPKPhotosCompatibilityError(
                                                                        7, @"Could not prepare the video for sharing."));
                                            }
                                            return;
                                        }
                                        presentURL(preparedURL, temporaryFile);
                                    }];
        return;
    }
    presentURL(fileURL, NO);
}

+ (void)_savePreparedFileURLToPhotos:(NSURL *)fileURL
                              isVideo:(BOOL)isVideo
                             metadata:(SPKGallerySaveMetadata *)metadata
                        temporaryFile:(BOOL)temporaryFile
                           completion:(void (^)(BOOL success,
                                                NSError *error))completion {
    void (^performSave)(void) = ^{
        __block NSString *assetLocalIdentifier = nil;
        [[PHPhotoLibrary sharedPhotoLibrary]
            performChanges:^{
                PHAssetCreationRequest *request =
                    [PHAssetCreationRequest creationRequestForAsset];
                PHAssetResourceCreationOptions *options =
                    [PHAssetResourceCreationOptions new];
                options.originalFilename = fileURL.lastPathComponent;
                options.shouldMoveFile = NO;
                [request addResourceWithType:(isVideo ? PHAssetResourceTypeVideo
                                                       : PHAssetResourceTypePhoto)
                                     fileURL:fileURL
                                     options:options];
                assetLocalIdentifier =
                    request.placeholderForCreatedAsset.localIdentifier;
            }
            completionHandler:^(BOOL success, NSError *error) {
                if (temporaryFile) {
                    [[NSFileManager defaultManager] removeItemAtURL:fileURL
                                                              error:nil];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        [SPKDownloadDuplicatePolicy
                            recordPhotosSaveWithMetadata:metadata
                                               mediaType:(isVideo
                                                              ? SPKGalleryMediaTypeVideo
                                                              : SPKGalleryMediaTypeImage)
                                    assetLocalIdentifier:assetLocalIdentifier];
                    }
                    if (completion)
                        completion(success, error);
                });
            }];
    };

    if (@available(iOS 14, *)) {
        PHAuthorizationStatus status =
            [PHPhotoLibrary authorizationStatusForAccessLevel:
                                PHAccessLevelAddOnly];
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary
                requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                            handler:^(PHAuthorizationStatus nextStatus) {
                                                if (nextStatus ==
                                                        PHAuthorizationStatusAuthorized ||
                                                    nextStatus ==
                                                        PHAuthorizationStatusLimited) {
                                                    performSave();
                                                } else {
                                                    if (temporaryFile) {
                                                        [[NSFileManager defaultManager]
                                                            removeItemAtURL:fileURL
                                                                     error:nil];
                                                    }
                                                    if (completion) {
                                                        completion(
                                                            NO,
                                                            SPKPhotosCompatibilityError(
                                                                8, @"Instagram does not have permission to add videos to Photos."));
                                                    }
                                                }
                                            }];
            return;
        }
        if (status != PHAuthorizationStatusAuthorized &&
            status != PHAuthorizationStatusLimited) {
            if (temporaryFile) {
                [[NSFileManager defaultManager] removeItemAtURL:fileURL
                                                          error:nil];
            }
            if (completion) {
                completion(NO, SPKPhotosCompatibilityError(
                                   8, @"Instagram does not have permission to add videos to Photos."));
            }
            return;
        }
    }
    performSave();
}
'''
writer = replace_once(
    writer,
    "\n+ (void)saveFileURLToPhotos:(NSURL *)fileURL\n",
    "\n" + helper_methods + "\n+ (void)saveFileURLToPhotos:(NSURL *)fileURL\n",
    "writer helper method insertion point",
)

new_save_method = r'''+ (void)saveFileURLToPhotos:(NSURL *)fileURL
                    metadata:(SPKGallerySaveMetadata *)metadata
                  completion:(void (^)(BOOL success, NSError *error))completion {
    BOOL isVideo = [self isVideoFileAtURL:fileURL];
    if (isVideo) {
        [self preparePhotoCompatibleVideoAtURL:fileURL
                                    completion:^(NSURL *preparedURL,
                                                 BOOL temporaryFile,
                                                 NSError *error) {
                                        if (!preparedURL || error) {
                                            if (completion)
                                                completion(NO, error);
                                            return;
                                        }
                                        [self _savePreparedFileURLToPhotos:preparedURL
                                                                  isVideo:YES
                                                                 metadata:metadata
                                                            temporaryFile:temporaryFile
                                                               completion:completion];
                                    }];
        return;
    }

    [self _savePreparedFileURLToPhotos:fileURL
                              isVideo:NO
                             metadata:metadata
                        temporaryFile:NO
                           completion:completion];
}
'''
writer = replace_pattern(
    writer,
    r"\+ \(void\)saveFileURLToPhotos:\(NSURL \*\)fileURL\n.*?\n}\n(?=\n\+ \(SPKGalleryFile \*\)saveFileURLToGallery:)",
    new_save_method.rstrip("\n"),
    "saveFileURLToPhotos implementation",
)
writer_path.write_text(writer)


# ---------------------------------------------------------------------------
# Gallery share actions
# ---------------------------------------------------------------------------
gallery_path = Path("src/Shared/Gallery/SPKGalleryViewController.m")
gallery = gallery_path.read_text()
gallery = replace_once(
    gallery,
    '#import "../Account/SPKAccountManager.h"\n#import "../MediaPreview/SPKFullScreenMediaPlayer.h"',
    '#import "../Account/SPKAccountManager.h"\n#import "../Downloads/SPKDownloadDestinationWriter.h"\n#import "../MediaPreview/SPKFullScreenMediaPlayer.h"',
    "Gallery writer import",
)

share_selected = r'''- (void)shareSelectedFiles {
    NSArray<SPKGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) {
        return;
    }

    if (files.count == 1) {
        SPKGalleryFile *file = files.firstObject;
        [SPKDownloadDestinationWriter
            presentShareSheetForFileURL:file.fileURL
                              presenter:self
                             anchorView:self.view
                             completion:^(NSError *error) {
                                 if (error) {
                                     SPKNotify(@"gallery_share",
                                               @"Could not share video",
                                               error.localizedDescription,
                                               @"error_filled",
                                               SPKNotificationToneError);
                                 }
                             }];
        return;
    }

    NSMutableArray<NSURL *> *urls =
        [NSMutableArray arrayWithCapacity:files.count];
    for (SPKGalleryFile *file in files) {
        [urls addObject:file.fileURL];
    }

    UIActivityViewController *controller =
        [[UIActivityViewController alloc] initWithActivityItems:urls
                                         applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        controller.popoverPresentationController.sourceView = self.view;
        controller.popoverPresentationController.sourceRect = self.view.bounds;
    }
    [self presentViewController:controller animated:YES completion:nil];
}
'''
gallery = replace_pattern(
    gallery,
    r"- \(void\)shareSelectedFiles \{.*?\n}\n(?=\n- \(void\)moveSelectedFiles)",
    share_selected.rstrip("\n"),
    "shareSelectedFiles",
)

old_menu_share = r'''    UIImage *shareImg = SPKGalleryMenuActionIcon(@"share");
    UIAction *shareAction = [UIAction actionWithTitle:@"Share"
                                                image:shareImg
                                           identifier:nil
                                              handler:^(UIAction *a) {
                                                  NSURL *url = [file fileURL];
                                                  UIActivityViewController *acVC = [[UIActivityViewController alloc] initWithActivityItems:@[ url ] applicationActivities:nil];
                                                  [weakSelf presentViewController:acVC animated:YES completion:nil];
                                              }];
'''
new_menu_share = r'''    UIImage *shareImg = SPKGalleryMenuActionIcon(@"share");
    UIAction *shareAction = [UIAction actionWithTitle:@"Share"
                                                image:shareImg
                                           identifier:nil
                                              handler:^(__unused UIAction *action) {
                                                  NSURL *url = file.fileURL;
                                                  [SPKDownloadDestinationWriter
                                                      presentShareSheetForFileURL:url
                                                                        presenter:weakSelf
                                                                       anchorView:weakSelf.view
                                                                       completion:^(NSError *error) {
                                                                           if (error) {
                                                                               SPKNotify(@"gallery_share",
                                                                                         @"Could not share video",
                                                                                         error.localizedDescription,
                                                                                         @"error_filled",
                                                                                         SPKNotificationToneError);
                                                                           }
                                                                       }];
                                              }];
'''
gallery = replace_once(gallery, old_menu_share, new_menu_share, "Gallery context-menu Share action")
gallery_path.write_text(gallery)


# ---------------------------------------------------------------------------
# Full-screen preview share action
# ---------------------------------------------------------------------------
preview_path = Path("src/Shared/MediaPreview/SPKFullScreenMediaPlayer.m")
preview = preview_path.read_text()
preview = replace_once(
    preview,
    '#import "../ActionButton/SPKBulkMediaSelectionViewController.h"\n#import "../Downloads/SPKDownloadHelpers.h"',
    '#import "../ActionButton/SPKBulkMediaSelectionViewController.h"\n#import "../Downloads/SPKDownloadDestinationWriter.h"\n#import "../Downloads/SPKDownloadHelpers.h"',
    "preview writer import",
)

share_start = preview.index("- (void)shareMedia {")
share_end = preview.index("\n- (void)copyMedia {", share_start)
share_method = preview[share_start:share_end]
local_marker = "    if (url.isFileURL || (!url && item.image)) {\n"
video_share = r'''    if (url.isFileURL || (!url && item.image)) {
        if (url.isFileURL && item.mediaType == SPKMediaItemTypeVideo) {
            SPKNotify(kSPKNotificationMediaPreviewShare,
                      @"Preparing video",
                      nil,
                      @"share",
                      SPKNotificationToneInfo);
            [SPKDownloadDestinationWriter
                presentShareSheetForFileURL:url
                                  presenter:self
                                 anchorView:[self bottomBarAnchorView]
                                 completion:^(NSError *error) {
                                     if (error) {
                                         SPKNotify(kSPKNotificationMediaPreviewShare,
                                                   @"Could not share video",
                                                   error.localizedDescription,
                                                   @"error_filled",
                                                   SPKNotificationToneError);
                                     }
                                 }];
            return;
        }
'''
share_method = replace_once(share_method, local_marker, video_share, "preview local-video share branch")
preview = preview[:share_start] + share_method + preview[share_end:]
preview_path.write_text(preview)


# ---------------------------------------------------------------------------
# TestFlight popup suppression for existing sideload installs
# ---------------------------------------------------------------------------
testflight_path = Path("src/Features/Tools/HideTestFlightPopup.x")
testflight_path.write_text(r'''#import "../../Utils.h"

#import <Foundation/Foundation.h>

static NSString *const kSPKHideTestFlightPopupMigrationKey =
    @"tools_hide_testflight_popup_sideload_default_v2";

%group SPKHideTestFlightNagReceipt
%hook NSBundle

- (NSURL *)appStoreReceiptURL {
    NSURL *url = %orig;
    if (self != NSBundle.mainBundle) {
        return url;
    }

    // Sideloading tools and newer iOS versions do not always expose a receipt
    // named sandboxReceipt. Normalize the main bundle receipt URL so Instagram
    // treats the install as a normal App Store build instead of a beta build.
    NSURL *directory = url
                           ? url.URLByDeletingLastPathComponent
                           : [self.bundleURL URLByAppendingPathComponent:@"StoreKit"
                                                            isDirectory:YES];
    return [directory URLByAppendingPathComponent:@"receipt"];
}

%end
%end

%ctor {
#if SPK_SIDELOAD
    // Registered defaults do not replace an older saved OFF value. Enable the
    // feature once for existing sideload installs, then honor the toggle later.
    if (![SPKPreferenceObjectForKey(kSPKHideTestFlightPopupMigrationKey)
            boolValue]) {
        SPKPreferenceSetObject(@YES, @"tools_hide_testflight_popup");
        SPKPreferenceSetObject(@YES,
                               kSPKHideTestFlightPopupMigrationKey);
    }
#endif

    if ([SPKUtils getBoolPref:@"tools_hide_testflight_popup"]) {
        %init(SPKHideTestFlightNagReceipt);
    }
}
''')

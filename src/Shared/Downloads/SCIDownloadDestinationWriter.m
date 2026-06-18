#import "SCIDownloadDestinationWriter.h"

#import "../../Utils.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "SCIDownloadDuplicatePolicy.h"
#import "../UI/SCINotificationCenter.h"
#import <Photos/Photos.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation SCIDownloadDestinationWriter

+ (BOOL)isVideoFileAtURL:(NSURL *)fileURL {
  NSString *ext = fileURL.pathExtension.lowercaseString;
  NSSet<NSString *> *videoExtensions = [NSSet setWithArray:@[
    @"mp4", @"mov", @"m4v", @"avi", @"webm", @"mkv", @"3gp"
  ]];
  return [videoExtensions containsObject:ext];
}

+ (BOOL)isAudioFileAtURL:(NSURL *)fileURL {
  NSString *ext = fileURL.pathExtension.lowercaseString;
  NSSet<NSString *> *audioExtensions = [NSSet setWithArray:@[
    @"m4a", @"aac", @"mp3", @"wav", @"caf", @"aiff", @"flac", @"opus", @"ogg"
  ]];
  return [audioExtensions containsObject:ext];
}

+ (void)saveFileURLToPhotos:(NSURL *)fileURL
                   metadata:(SCIGallerySaveMetadata *)metadata
                 completion:(void (^)(BOOL success, NSError *error))completion {
  BOOL isVideo = [self isVideoFileAtURL:fileURL];
  SCIGalleryMediaType mediaType =
      [self isAudioFileAtURL:fileURL]
          ? SCIGalleryMediaTypeAudio
          : (isVideo ? SCIGalleryMediaTypeVideo : SCIGalleryMediaTypeImage);
  __block NSString *assetLocalIdentifier = nil;

  [[PHPhotoLibrary sharedPhotoLibrary]
      performChanges:^{
        PHAssetChangeRequest *request = nil;
        if (isVideo) {
          request = [PHAssetChangeRequest
              creationRequestForAssetFromVideoAtFileURL:fileURL];
        } else {
          request = [PHAssetChangeRequest
              creationRequestForAssetFromImageAtFileURL:fileURL];
        }
        assetLocalIdentifier =
            request.placeholderForCreatedAsset.localIdentifier;
      }
      completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (success) {
            [SCIDownloadDuplicatePolicy
                recordPhotosSaveWithMetadata:metadata
                                   mediaType:mediaType
                        assetLocalIdentifier:assetLocalIdentifier];
          }
          if (completion)
            completion(success, error);
        });
      }];
}

+ (SCIGalleryFile *)saveFileURLToGallery:(NSURL *)fileURL
                                metadata:(SCIGallerySaveMetadata *)metadata
                                   error:(NSError **)error {
  SCIGalleryMediaType galleryType =
      [self isAudioFileAtURL:fileURL]
          ? SCIGalleryMediaTypeAudio
          : ([self isVideoFileAtURL:fileURL] ? SCIGalleryMediaTypeVideo
                                             : SCIGalleryMediaTypeImage);
  return [SCIGalleryFile saveFileToGallery:fileURL
                                    source:SCIGallerySourceOther
                                 mediaType:galleryType
                                folderPath:nil
                                  metadata:metadata
                                     error:error];
}

- (void)finalizeFileAtPath:(NSString *)stagedPath
                   request:(SCIDownloadRequest *)request
               itemRequest:(SCIDownloadItemRequest *)itemRequest
                 presenter:(UIViewController *)presenter
                anchorView:(UIView *)anchorView
                completion:(SCIDownloadDestinationCompletion)completion {
  NSURL *fileURL = [NSURL fileURLWithPath:stagedPath];
  SCIGallerySaveMetadata *metadata = itemRequest.metadata ?: request.metadata;
  switch (request.destination) {
  case SCIDownloadDestinationPhotos:
    [self saveToPhotos:fileURL
              metadata:metadata
           itemRequest:itemRequest
            completion:completion];
    break;
  case SCIDownloadDestinationGallery:
    [self saveToGallery:fileURL metadata:metadata completion:completion];
    break;
  case SCIDownloadDestinationShare:
    [self presentShare:fileURL
               request:request
             presenter:presenter
            anchorView:anchorView
            completion:completion];
    break;
  case SCIDownloadDestinationClipboard:
    [self copyToClipboard:fileURL
              itemRequest:itemRequest
               completion:completion];
    break;
  case SCIDownloadDestinationCacheOnly:
    if (completion)
      completion(stagedPath, nil, nil);
    break;
  }
}

- (void)saveToPhotos:(NSURL *)fileURL
            metadata:(SCIGallerySaveMetadata *)metadata
         itemRequest:(SCIDownloadItemRequest *)itemRequest
          completion:(SCIDownloadDestinationCompletion)completion {
  if (itemRequest.mediaKind == SCIDownloadMediaKindAudio ||
      [[self class] isAudioFileAtURL:fileURL]) {
    if (completion) {
      completion(nil, nil,
                 SCIDownloadError(SCIDownloadErrorAudioPhotosUnsupported,
                                  @"Audio cannot be saved to Photos.",
                                  @"Use Gallery or Share instead."));
    }
    return;
  }
  [[self class]
      saveFileURLToPhotos:fileURL
                 metadata:metadata
               completion:^(BOOL success, NSError *error) {
                 if (!success) {
                   NSString *desc = error.localizedDescription
                                        ?: @"Could not save to Photos. Check "
                                           @"photo library permission.";
                   if (completion)
                     completion(
                         nil, nil,
                         SCIDownloadError(SCIDownloadErrorPhotosSaveFailed,
                                          desc, nil));
                   return;
                 }
                 if (completion)
                   completion(fileURL.path, nil, nil);
               }];
}

- (void)saveToGallery:(NSURL *)fileURL
             metadata:(SCIGallerySaveMetadata *)metadata
           completion:(SCIDownloadDestinationCompletion)completion {
  NSError *error = nil;
  SCIGalleryFile *file = [[self class] saveFileURLToGallery:fileURL
                                                   metadata:metadata
                                                      error:&error];
  if (!file) {
    if (completion)
      completion(nil, nil,
                 SCIDownloadError(SCIDownloadErrorGallerySaveFailed,
                                  error.localizedDescription
                                      ?: @"Could not save to Gallery.",
                                  nil));
    return;
  }
  if (completion)
    completion(file.filePath, nil, nil);
}

- (void)presentShare:(NSURL *)fileURL
             request:(SCIDownloadRequest *)request
           presenter:(UIViewController *)presenter
          anchorView:(UIView *)anchorView
          completion:(SCIDownloadDestinationCompletion)completion {
  UIViewController *host = presenter ?: topMostController();
  if (!host) {
    if (completion)
      completion(nil, nil,
                 SCIDownloadError(SCIDownloadErrorSharePresentationFailed,
                                  @"Could not present share sheet.", nil));
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if (request.items.count > 1) {
      UIActivityViewController *vc =
          [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ]
                                            applicationActivities:nil];
      if (anchorView && UIDevice.currentDevice.userInterfaceIdiom ==
                            UIUserInterfaceIdiomPad) {
        vc.popoverPresentationController.sourceView = anchorView;
        vc.popoverPresentationController.sourceRect = anchorView.bounds;
      }
      [host presentViewController:vc animated:YES completion:nil];
    } else {
      [SCIUtils showShareVC:fileURL];
    }
    if (completion)
      completion(fileURL.path, nil, nil);
  });
}

- (void)copyToClipboard:(NSURL *)fileURL
            itemRequest:(SCIDownloadItemRequest *)itemRequest
             completion:(SCIDownloadDestinationCompletion)completion {
  if (itemRequest.linkString.length > 0 && !fileURL.isFileURL) {
    UIPasteboard.generalPasteboard.string = itemRequest.linkString;
    if (completion)
      completion(nil, nil, nil);
    return;
  }
  NSDictionary *attrs =
      [[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path
                                                       error:nil];
  int64_t size = [attrs[NSFileSize] longLongValue];
  if (size > 80 * 1024 * 1024) {
    if (completion)
      completion(nil, nil,
                 SCIDownloadError(
                     SCIDownloadErrorClipboardTooLarge,
                     @"File is too large to copy to the clipboard.", nil));
    return;
  }
  NSString *ext = fileURL.pathExtension.lowercaseString;
  NSString *uti = @"public.data";
  if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
    uti = UTTypeJPEG.identifier;
  else if ([ext isEqualToString:@"png"])
    uti = UTTypePNG.identifier;
  else if ([ext isEqualToString:@"gif"])
    uti = UTTypeGIF.identifier;
  else if ([ext isEqualToString:@"webp"])
    uti = UTTypeWebP.identifier;
  else if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"])
    uti = UTTypeMovie.identifier;
  else if ([ext isEqualToString:@"m4a"] || [ext isEqualToString:@"mp3"])
    uti = UTTypeAudio.identifier;
  NSData *data = [NSData dataWithContentsOfURL:fileURL
                                       options:NSDataReadingMappedIfSafe
                                         error:nil];
  if (!data) {
    if (completion)
      completion(nil, nil,
                 SCIDownloadError(SCIDownloadErrorFileMoveFailed,
                                  @"Could not read file for clipboard.", nil));
    return;
  }
  [UIPasteboard generalPasteboard].items = @[ @{uti : data} ];
  if (completion)
    completion(fileURL.path, nil, nil);
}

@end

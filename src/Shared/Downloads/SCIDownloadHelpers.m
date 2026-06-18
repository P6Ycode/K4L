#import "SCIDownloadHelpers.h"

#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../SCIStoragePaths.h"
#import "../UI/SCINotificationCenter.h"
#import "SCIDownloadService.h"

static NSString *SCIDownloadDisplayUsername(NSString *username) {
  NSString *trimmed =
      [username stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmed.length == 0 || trimmed.length > 30)
    return nil;
  NSString *lower = trimmed.lowercaseString;
  NSSet<NSString *> *blocked = [NSSet setWithArray:@[
    @"more", @"options", @"menu", @"close", @"done", @"cancel", @"all",
    @"active", @"queued", @"failed", @"completed", @"clipboard", @"download",
    @"save", @"share", @"copy", @"gallery", @"photos", @"instants"
  ]];
  if ([blocked containsObject:lower])
    return nil;
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"] invertedSet];
  return [trimmed rangeOfCharacterFromSet:invalid].location == NSNotFound ? trimmed : nil;
}

@implementation SCIDownloadHelpers

+ (SCIDownloadSourceSurface)sourceSurfaceForGallerySource:
    (SCIGallerySource)source {
  switch (source) {
  case SCIGallerySourceFeed:
    return SCIDownloadSourceSurfaceFeed;
  case SCIGallerySourceReels:
    return SCIDownloadSourceSurfaceReels;
  case SCIGallerySourceStories:
    return SCIDownloadSourceSurfaceStories;
  case SCIGallerySourceDMs:
    return SCIDownloadSourceSurfaceDirect;
  case SCIGallerySourceProfile:
    return SCIDownloadSourceSurfaceProfile;
  case SCIGallerySourceInstants:
    return SCIDownloadSourceSurfaceInstants;
  case SCIGallerySourceAudioPage:
    return SCIDownloadSourceSurfaceAudioPage;
  case SCIGallerySourceComments:
    return SCIDownloadSourceSurfaceComments;
  default:
    return SCIDownloadSourceSurfaceOther;
  }
}

+ (SCIDownloadSourceSurface)sourceSurfaceForActionButtonSource:
    (NSInteger)actionButtonSource {
  switch ((SCIActionButtonSource)actionButtonSource) {
  case SCIActionButtonSourceFeed:
    return SCIDownloadSourceSurfaceFeed;
  case SCIActionButtonSourceReels:
    return SCIDownloadSourceSurfaceReels;
  case SCIActionButtonSourceStories:
    return SCIDownloadSourceSurfaceStories;
  case SCIActionButtonSourceDirect:
    return SCIDownloadSourceSurfaceDirect;
  case SCIActionButtonSourceProfile:
    return SCIDownloadSourceSurfaceProfile;
  case SCIActionButtonSourceInstants:
    return SCIDownloadSourceSurfaceInstants;
  default:
    return SCIDownloadSourceSurfaceOther;
  }
}

+ (SCIDownloadSourceSurface)
    resolvedSourceSurface:(SCIDownloadSourceSurface)surface
                 metadata:(SCIGallerySaveMetadata *)metadata {
  if (surface != SCIDownloadSourceSurfaceOther)
    return surface;
  if (!metadata)
    return SCIDownloadSourceSurfaceOther;
  return [self sourceSurfaceForGallerySource:(SCIGallerySource)metadata.source];
}

+ (nullable NSString *)historyTitleForRequest:(SCIDownloadRequest *)request {
  if (request.items.count > 1) {
    NSMutableOrderedSet<NSString *> *usernames = [NSMutableOrderedSet orderedSet];
    for (SCIDownloadItemRequest *item in request.items) {
      NSString *username = SCIDownloadDisplayUsername(item.metadata.sourceUsername);
      if (username.length > 0)
        [usernames addObject:username];
    }
    if (usernames.count == 1)
      return usernames.firstObject;
    if (usernames.count > 1)
      return [NSString stringWithFormat:@"%@ + %lu more", usernames.firstObject,
                                        (unsigned long)(usernames.count - 1)];
    return nil;
  }

  NSString *requestUsername = SCIDownloadDisplayUsername(request.metadata.sourceUsername);
  if (requestUsername.length > 0)
    return requestUsername;
  for (SCIDownloadItemRequest *item in request.items) {
    NSString *itemUsername = SCIDownloadDisplayUsername(item.metadata.sourceUsername);
    if (itemUsername.length > 0)
      return itemUsername;
  }
  return nil;
}

+ (SCIGalleryMediaType)galleryMediaTypeForKind:(SCIDownloadMediaKind)kind {
  switch (kind) {
  case SCIDownloadMediaKindVideo:
    return SCIGalleryMediaTypeVideo;
  case SCIDownloadMediaKindAudio:
    return SCIGalleryMediaTypeAudio;
  default:
    return SCIGalleryMediaTypeImage;
  }
}

+ (NSString *)preferredFilenameForURL:(NSURL *)url
                            mediaKind:(SCIDownloadMediaKind)kind
                             metadata:(SCIGallerySaveMetadata *)metadata {
  if (!url)
    return nil;
  return SCIFileNameForMedia(url, [self galleryMediaTypeForKind:kind],
                             metadata);
}

+ (SCIDownloadMediaKind)mediaKindForExtension:(NSString *)ext {
  NSString *lower = ext.lowercaseString;
  NSSet *audio = [NSSet setWithArray:@[
    @"m4a", @"aac", @"mp3", @"wav", @"caf", @"aiff", @"flac", @"opus", @"ogg"
  ]];
  NSSet *video = [NSSet setWithArray:@[
    @"mp4", @"mov", @"m4v", @"avi", @"webm", @"mkv", @"3gp"
  ]];
  if ([audio containsObject:lower])
    return SCIDownloadMediaKindAudio;
  if ([video containsObject:lower])
    return SCIDownloadMediaKindVideo;
  return SCIDownloadMediaKindImage;
}

+ (nullable NSString *)stageImageForDownload:(UIImage *)image {
  NSData *data = UIImagePNGRepresentation(image);
  if (!data)
    return nil;
  NSString *directory = [[SCIStoragePaths downloadsDirectory]
      stringByAppendingPathComponent:@"v2/sources"];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  NSString *path = [directory
      stringByAppendingPathComponent:
          [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"png"]];
  return [data writeToFile:path atomically:YES] ? path : nil;
}

+ (void)submitRemoteURL:(NSURL *)url
              extension:(NSString *)extension
            destination:(SCIDownloadDestination)destination
               metadata:(SCIGallerySaveMetadata *)metadata
         notificationID:(NSString *)notificationID
              presenter:(UIViewController *)presenter
             anchorView:(UIView *)anchorView
          sourceSurface:(SCIDownloadSourceSurface)sourceSurface
           showProgress:(BOOL)showProgress {
  SCIDownloadMediaKind kind = [self mediaKindForExtension:extension];
  SCIDownloadItemRequest *item =
      [SCIDownloadItemRequest itemWithRemoteURL:url mediaKind:kind];
  item.preferredFileExtension = extension;
  item.metadata = metadata;
  item.expectedFilenameStem =
      [[self preferredFilenameForURL:url mediaKind:kind
                            metadata:metadata] stringByDeletingPathExtension];
  SCIDownloadRequest *request =
      [SCIDownloadRequest requestWithItems:@[ item ] destination:destination];
  request.metadata = metadata;
  request.notificationIdentifier = notificationID;
  request.presenter = presenter;
  request.anchorView = anchorView;
  request.sourceSurface = [self resolvedSourceSurface:sourceSurface
                                             metadata:metadata];
  request.presentationMode = showProgress ? SCIDownloadPresentationModeQueuePill
                                          : SCIDownloadPresentationModeQuiet;
  [[SCIDownloadService shared] submitRequest:request completion:nil];
}

+ (void)downloadURL:(NSURL *)url
          extension:(NSString *)extension
        destination:(SCIDownloadDestination)destination
           metadata:(SCIGallerySaveMetadata *)metadata
     notificationID:(NSString *)notificationID
          presenter:(UIViewController *)presenter
      sourceSurface:(SCIDownloadSourceSurface)sourceSurface {
  [self submitRemoteURL:url
              extension:extension
            destination:destination
               metadata:metadata
         notificationID:notificationID
              presenter:presenter
             anchorView:nil
          sourceSurface:sourceSurface
           showProgress:SCINotificationIsEnabled(notificationID)];
}

+ (void)performBulkItems:(NSArray<SCIDownloadItemRequest *> *)items
               destination:(SCIDownloadDestination)destination
          actionIdentifier:(NSString *)identifier
                 presenter:(UIViewController *)presenter
                anchorView:(UIView *)anchorView
             sourceSurface:(SCIDownloadSourceSurface)sourceSurface
        finalizeBatchShare:(BOOL)batchShare
    finalizeBatchClipboard:(BOOL)batchClipboard {
  if (items.count == 0) {
    SCINotify(identifier ?: kSCINotificationDownloadAllLibrary,
              @"No downloadable media", nil, @"error_filled",
              SCINotificationToneError);
    return;
  }

  SCIDownloadItemRequest *firstItem = items.firstObject;
  SCIDownloadRequest *request =
      [SCIDownloadRequest requestWithItems:items destination:destination];
  request.metadata = firstItem.metadata;
  request.notificationIdentifier = identifier;
  request.presenter = presenter;
  request.anchorView = anchorView;
  request.finalizeAsBatchShare = batchShare;
  request.finalizeAsBatchClipboard = batchClipboard;
  request.sourceSurface = sourceSurface;
  request.presentationMode = SCINotificationIsEnabled(identifier)
                                 ? SCIDownloadPresentationModeQueuePill
                                 : SCIDownloadPresentationModeQuiet;
  [[SCIDownloadService shared] submitRequest:request completion:nil];
}

+ (BOOL)performBulkDownloadIdentifier:(NSString *)identifier
                                items:(NSArray<SCIDownloadItemRequest *> *)items
                            presenter:(UIViewController *)presenter
                           anchorView:(UIView *)anchorView
                        sourceSurface:(SCIDownloadSourceSurface)sourceSurface {
  SCIDownloadDestination destination;
  BOOL batchShare = NO;
  BOOL batchClipboard = NO;

  if ([identifier isEqualToString:kSCIActionDownloadAllLibrary]) {
    destination = SCIDownloadDestinationPhotos;
  } else if ([identifier isEqualToString:kSCIActionDownloadAllShare]) {
    destination = SCIDownloadDestinationCacheOnly;
    batchShare = YES;
  } else if ([identifier isEqualToString:kSCIActionDownloadAllGallery]) {
    destination = SCIDownloadDestinationGallery;
  } else if ([identifier isEqualToString:kSCIActionDownloadAllClipboard]) {
    destination = SCIDownloadDestinationCacheOnly;
    batchClipboard = YES;
  } else {
    return NO;
  }

  [self performBulkItems:items
                 destination:destination
            actionIdentifier:identifier
                   presenter:presenter
                  anchorView:anchorView
               sourceSurface:sourceSurface
          finalizeBatchShare:batchShare
      finalizeBatchClipboard:batchClipboard];
  return YES;
}

+ (void)submitDashDownloadWithPrimaryURL:(NSURL *)primaryURL
                            secondaryURL:(NSURL *)secondaryURL
                              optionKind:(NSInteger)optionKind
                                basename:(NSString *)basename
                                duration:(double)duration
                                   width:(NSInteger)width
                                  height:(NSInteger)height
                           sourceBitrate:(NSInteger)bandwidth
                               extension:(NSString *)extension
                                metadata:(SCIGallerySaveMetadata *)metadata
                             destination:(SCIDownloadDestination)destination
                          notificationID:(NSString *)notificationID
                               presenter:(UIViewController *)presenter
                           sourceSurface:
                               (SCIDownloadSourceSurface)sourceSurface {
  SCIDownloadMediaKind kind = SCIDownloadMediaKindVideo;
  if (optionKind == 3)
    kind = SCIDownloadMediaKindAudio;
  SCIDownloadItemRequest *item =
      [SCIDownloadItemRequest itemWithRemoteURL:primaryURL mediaKind:kind];
  item.preferredFileExtension = extension;
  item.metadata = metadata;
  item.requiresDashMerge = YES;
  item.dashSecondaryURLString = secondaryURL.absoluteString;
  item.dashOptionKind = optionKind;
  item.dashDuration = duration;
  item.dashWidth = width;
  item.dashHeight = height;
  item.dashBandwidth = bandwidth;
  NSString *preferred = metadata ? [self preferredFilenameForURL:primaryURL
                                                       mediaKind:kind
                                                        metadata:metadata]
                                 : nil;
  item.expectedFilenameStem =
      preferred.length ? preferred.stringByDeletingPathExtension : basename;
  SCIDownloadRequest *request =
      [SCIDownloadRequest requestWithItems:@[ item ] destination:destination];
  request.metadata = metadata;
  request.notificationIdentifier = notificationID;
  request.presenter = presenter;
  request.sourceSurface = [self resolvedSourceSurface:sourceSurface
                                             metadata:metadata];
  request.presentationMode = SCINotificationIsEnabled(notificationID)
                                 ? SCIDownloadPresentationModeQueuePill
                                 : SCIDownloadPresentationModeQuiet;
  [[SCIDownloadService shared] submitRequest:request completion:nil];
}

+ (void)submitLocalFileURL:(NSURL *)fileURL
                 extension:(NSString *)extension
               destination:(SCIDownloadDestination)destination
                  metadata:(SCIGallerySaveMetadata *)metadata
            notificationID:(NSString *)notificationID
                 presenter:(UIViewController *)presenter
                anchorView:(UIView *)anchorView
             sourceSurface:(SCIDownloadSourceSurface)sourceSurface {
  SCIDownloadMediaKind kind = [self mediaKindForExtension:extension];
  SCIDownloadItemRequest *item =
      [SCIDownloadItemRequest itemWithLocalPath:fileURL.path mediaKind:kind];
  item.preferredFileExtension = extension;
  item.metadata = metadata;
  item.expectedFilenameStem =
      [[self preferredFilenameForURL:fileURL mediaKind:kind
                            metadata:metadata] stringByDeletingPathExtension];
  SCIDownloadRequest *request =
      [SCIDownloadRequest requestWithItems:@[ item ] destination:destination];
  request.metadata = metadata;
  request.notificationIdentifier = notificationID;
  request.presenter = presenter;
  request.anchorView = anchorView;
  request.sourceSurface = [self resolvedSourceSurface:sourceSurface
                                             metadata:metadata];
  request.presentationMode = SCINotificationIsEnabled(notificationID)
                                 ? SCIDownloadPresentationModeQueuePill
                                 : SCIDownloadPresentationModeQuiet;
  [[SCIDownloadService shared] submitRequest:request completion:nil];
}

@end

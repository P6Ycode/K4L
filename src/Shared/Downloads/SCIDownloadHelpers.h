/// Helpers for building download requests and mapping between legacy types.
/// Provides convenient wrappers around SCIDownloadService for common submission patterns.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "../Gallery/SCIGalleryFile.h"
#import "SCIDownloadRequest.h"
#import "SCIDownloadTypes.h"

@class SCIGallerySaveMetadata;

NS_ASSUME_NONNULL_BEGIN

@interface SCIDownloadHelpers : NSObject

+ (SCIDownloadSourceSurface)sourceSurfaceForGallerySource:
    (SCIGallerySource)source;
+ (SCIDownloadSourceSurface)sourceSurfaceForActionButtonSource:
    (NSInteger)actionButtonSource;
+ (SCIDownloadSourceSurface)
    resolvedSourceSurface:(SCIDownloadSourceSurface)surface
                 metadata:(nullable SCIGallerySaveMetadata *)metadata;

+ (nullable NSString *)historyTitleForRequest:(SCIDownloadRequest *)request;

+ (SCIDownloadMediaKind)mediaKindForExtension:(NSString *)ext;
+ (nullable NSString *)
    preferredFilenameForURL:(NSURL *)url
                  mediaKind:(SCIDownloadMediaKind)kind
                   metadata:(nullable SCIGallerySaveMetadata *)metadata;
+ (nullable NSString *)stageImageForDownload:(UIImage *)image;

+ (void)downloadURL:(NSURL *)url
          extension:(NSString *)extension
        destination:(SCIDownloadDestination)destination
           metadata:(nullable SCIGallerySaveMetadata *)metadata
     notificationID:(NSString *)notificationID
          presenter:(nullable UIViewController *)presenter
      sourceSurface:(SCIDownloadSourceSurface)sourceSurface;

+ (void)submitRemoteURL:(NSURL *)url
              extension:(NSString *)extension
            destination:(SCIDownloadDestination)destination
               metadata:(nullable SCIGallerySaveMetadata *)metadata
         notificationID:(NSString *)notificationID
              presenter:(nullable UIViewController *)presenter
             anchorView:(nullable UIView *)anchorView
          sourceSurface:(SCIDownloadSourceSurface)sourceSurface
           showProgress:(BOOL)showProgress;

+ (void)performBulkItems:(NSArray<SCIDownloadItemRequest *> *)items
               destination:(SCIDownloadDestination)destination
          actionIdentifier:(NSString *)identifier
                 presenter:(nullable UIViewController *)presenter
                anchorView:(nullable UIView *)anchorView
             sourceSurface:(SCIDownloadSourceSurface)sourceSurface
        finalizeBatchShare:(BOOL)batchShare
    finalizeBatchClipboard:(BOOL)batchClipboard;

+ (void)
    submitDashDownloadWithPrimaryURL:(NSURL *)primaryURL
                        secondaryURL:(nullable NSURL *)secondaryURL
                          optionKind:(NSInteger)optionKind
                            basename:(NSString *)basename
                            duration:(double)duration
                               width:(NSInteger)width
                              height:(NSInteger)height
                       sourceBitrate:(NSInteger)bandwidth
                           extension:(NSString *)extension
                            metadata:(nullable SCIGallerySaveMetadata *)metadata
                         destination:(SCIDownloadDestination)destination
                      notificationID:(NSString *)notificationID
                           presenter:(nullable UIViewController *)presenter
                       sourceSurface:(SCIDownloadSourceSurface)sourceSurface;

+ (void)submitLocalFileURL:(NSURL *)fileURL
                 extension:(NSString *)extension
               destination:(SCIDownloadDestination)destination
                  metadata:(nullable SCIGallerySaveMetadata *)metadata
            notificationID:(NSString *)notificationID
                 presenter:(nullable UIViewController *)presenter
                anchorView:(nullable UIView *)anchorView
             sourceSurface:(SCIDownloadSourceSurface)sourceSurface;

@end

NS_ASSUME_NONNULL_END

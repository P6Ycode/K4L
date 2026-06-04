#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "SCIDownloadRequest.h"
#import "SCIDownloadTypes.h"

@class SCIGallerySaveMetadata;
@class SCIGalleryFile;

NS_ASSUME_NONNULL_BEGIN

typedef void (^SCIDownloadDestinationCompletion)(
    NSString *_Nullable finalPath, NSString *_Nullable photosAssetID,
    NSError *_Nullable error);

@interface SCIDownloadDestinationWriter : NSObject

+ (BOOL)isVideoFileAtURL:(NSURL *)fileURL;
+ (BOOL)isAudioFileAtURL:(NSURL *)fileURL;
+ (void)saveFileURLToPhotos:(NSURL *)fileURL
                   metadata:(nullable SCIGallerySaveMetadata *)metadata
                 completion:(void (^)(BOOL success,
                                      NSError *_Nullable error))completion;
+ (nullable SCIGalleryFile *)
    saveFileURLToGallery:(NSURL *)fileURL
                metadata:(nullable SCIGallerySaveMetadata *)metadata
                   error:(NSError **)error;

- (void)finalizeFileAtPath:(NSString *)stagedPath
                   request:(SCIDownloadRequest *)request
               itemRequest:(SCIDownloadItemRequest *)itemRequest
                 presenter:(nullable UIViewController *)presenter
                anchorView:(nullable UIView *)anchorView
                completion:(SCIDownloadDestinationCompletion)completion;

@end

NS_ASSUME_NONNULL_END

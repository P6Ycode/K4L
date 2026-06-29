#import <Foundation/Foundation.h>

@class SPKGalleryFile;
@class SPKGallerySaveMetadata;

NS_ASSUME_NONNULL_BEGIN

@interface SPKGalleryOriginController : NSObject

+ (void)populateMetadata:(SPKGallerySaveMetadata *)metadata fromMedia:(id _Nullable)media;
+ (void)populateProfileMetadata:(SPKGallerySaveMetadata *)metadata username:(nullable NSString *)username user:(id _Nullable)user;
+ (BOOL)openOriginalPostForGalleryFile:(SPKGalleryFile *)file;
+ (BOOL)openProfileForGalleryFile:(SPKGalleryFile *)file;

@end

NS_ASSUME_NONNULL_END

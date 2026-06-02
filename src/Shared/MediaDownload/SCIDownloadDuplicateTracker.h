#import <Foundation/Foundation.h>

@class SCIGallerySaveMetadata;
@class UIViewController;

typedef NS_ENUM(NSInteger, SCIDownloadDuplicateDestination) {
    SCIDownloadDuplicateDestinationGallery = 1,
    SCIDownloadDuplicateDestinationPhotos = 2,
};

typedef NS_ENUM(NSInteger, SCIDownloadDuplicateDecision) {
    SCIDownloadDuplicateDecisionDownloadAgain = 1,
    SCIDownloadDuplicateDecisionDeleteExistingAndDownloadAgain = 2,
};

@interface SCIDownloadDuplicateTracker : NSObject

+ (BOOL)presentPreflightIfNeededForDestination:(SCIDownloadDuplicateDestination)destination
                                      metadata:(nullable SCIGallerySaveMetadata *)metadata
                                     mediaType:(NSInteger)mediaType
                                     presenter:(nullable UIViewController *)presenter
                                  continuation:(void (^)(SCIDownloadDuplicateDecision decision))continuation;
+ (void)deleteExistingForDestination:(SCIDownloadDuplicateDestination)destination
                            metadata:(nullable SCIGallerySaveMetadata *)metadata
                           mediaType:(NSInteger)mediaType
                          completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
+ (void)recordPhotosSaveWithMetadata:(nullable SCIGallerySaveMetadata *)metadata
                           mediaType:(NSInteger)mediaType
                assetLocalIdentifier:(nullable NSString *)assetLocalIdentifier;

@end

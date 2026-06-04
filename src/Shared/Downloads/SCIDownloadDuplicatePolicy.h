#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "SCIDownloadTypes.h"
#import "SCIDownloadRequest.h"

NS_ASSUME_NONNULL_BEGIN

@class SCIGallerySaveMetadata;

typedef NS_ENUM(NSInteger, SCIDownloadDuplicateDestination) {
    SCIDownloadDuplicateDestinationGallery = 1,
    SCIDownloadDuplicateDestinationPhotos = 2,
};

typedef NS_ENUM(NSInteger, SCIDownloadPreflightResult) {
    SCIDownloadPreflightContinue = 0,
    SCIDownloadPreflightSkipSucceeded,
    SCIDownloadPreflightCancelled,
};

typedef void (^SCIDownloadPreflightCompletion)(SCIDownloadPreflightResult result);

@interface SCIDownloadDuplicatePolicy : NSObject

- (BOOL)duplicateDestinationFor:(SCIDownloadDestination)destination
                       outValue:(SCIDownloadDuplicateDestination *)outValue;
- (NSInteger)mediaTypeForKind:(SCIDownloadMediaKind)kind;

- (void)runPreflightForRequest:(SCIDownloadRequest *)request
                      presenter:(nullable UIViewController *)presenter
                     completion:(SCIDownloadPreflightCompletion)completion;

// Low-level duplicate detection and ledger management
+ (BOOL)hasDuplicateForDestination:(SCIDownloadDuplicateDestination)destination
                          metadata:(nullable SCIGallerySaveMetadata *)metadata
                         mediaType:(NSInteger)mediaType;

+ (void)recordPhotosSaveWithMetadata:(nullable SCIGallerySaveMetadata *)metadata
                           mediaType:(NSInteger)mediaType
                assetLocalIdentifier:(nullable NSString *)assetLocalIdentifier;

@end

NS_ASSUME_NONNULL_END

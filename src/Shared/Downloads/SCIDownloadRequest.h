#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "SCIDownloadTypes.h"

@class SCIGallerySaveMetadata;

NS_ASSUME_NONNULL_BEGIN

@interface SCIDownloadItemRequest : NSObject <NSCopying>
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy, nullable) NSString *remoteURLString;
@property (nonatomic, copy, nullable) NSString *localSourcePath;
@property (nonatomic, assign) SCIDownloadMediaKind mediaKind;
@property (nonatomic, copy, nullable) NSString *preferredFileExtension;
@property (nonatomic, copy, nullable) NSString *expectedFilenameStem;
@property (nonatomic, copy, nullable) NSString *linkString;
@property (nonatomic, strong, nullable) SCIGallerySaveMetadata *metadata;
@property (nonatomic, assign) NSInteger index;
/// When YES, scheduler downloads the remote URL then converts to M4A before finalizing (audio page).
@property (nonatomic, assign) BOOL requiresAudioConversion;
@property (nonatomic, copy, nullable) NSString *audioProcessingBasename;
/// When YES, scheduler runs DASH download + FFmpeg merge (SCIMediaQualityManager).
@property (nonatomic, assign) BOOL requiresDashMerge;
@property (nonatomic, copy, nullable) NSString *dashSecondaryURLString;
@property (nonatomic, assign) NSInteger dashOptionKind;
@property (nonatomic, assign) double dashDuration;
@property (nonatomic, assign) NSInteger dashWidth;
@property (nonatomic, assign) NSInteger dashHeight;
@property (nonatomic, assign) NSInteger dashBandwidth;

+ (instancetype)itemWithRemoteURL:(NSURL *)url mediaKind:(SCIDownloadMediaKind)kind;
+ (instancetype)itemWithLocalPath:(NSString *)path mediaKind:(SCIDownloadMediaKind)kind;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface SCIDownloadRequest : NSObject <NSCopying>
@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, assign) NSTimeInterval createdAt;
@property (nonatomic, assign) SCIDownloadSourceSurface sourceSurface;
@property (nonatomic, assign) SCIDownloadDestination destination;
@property (nonatomic, assign) SCIDownloadPresentationMode presentationMode;
@property (nonatomic, copy) NSArray<SCIDownloadItemRequest *> *items;
@property (nonatomic, strong, nullable) SCIGallerySaveMetadata *metadata;
@property (nonatomic, copy, nullable) NSString *notificationIdentifier;
@property (nonatomic, weak, nullable) UIViewController *presenter;
@property (nonatomic, weak, nullable) UIView *anchorView;
@property (nonatomic, assign) SCIDownloadDuplicatePolicyMode duplicatePolicy;
@property (nonatomic, assign) SCIDownloadQualityPolicy qualityPolicy;
@property (nonatomic, copy, nullable) NSString *titleOverride;
/// Carousel share: download items to cache, present one share sheet when the job finishes.
@property (nonatomic, assign) BOOL finalizeAsBatchShare;
/// Carousel copy: download items to cache, copy all to the pasteboard when the job finishes.
@property (nonatomic, assign) BOOL finalizeAsBatchClipboard;

+ (instancetype)requestWithItems:(NSArray<SCIDownloadItemRequest *> *)items
                      destination:(SCIDownloadDestination)destination;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;
@end

NS_ASSUME_NONNULL_END

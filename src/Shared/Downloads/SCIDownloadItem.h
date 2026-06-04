#import <Foundation/Foundation.h>

#import "SCIDownloadTypes.h"
#import "SCIDownloadRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCIDownloadItem : NSObject <NSCopying>
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) SCIDownloadState state;
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) int64_t bytesWritten;
@property (nonatomic, assign) int64_t totalBytesExpected;
@property (nonatomic, copy, nullable) NSString *stagedPath;
@property (nonatomic, copy, nullable) NSString *finalPath;
@property (nonatomic, copy, nullable) NSString *photosAssetIdentifier;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, assign) SCIDownloadMediaKind mediaKind;
@property (nonatomic, copy, nullable) NSString *linkString;
@property (nonatomic, strong, nullable) SCIGallerySaveMetadata *metadata;
@property (nonatomic, assign) BOOL retryable;
@property (nonatomic, copy, nullable) NSString *detail;

@property (nonatomic, strong, readonly) SCIDownloadItemRequest *request;

- (instancetype)initWithRequest:(SCIDownloadItemRequest *)request;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict request:(SCIDownloadItemRequest *)request;
@end

@interface SCIDownloadMutableItemSnapshot : SCIDownloadItem
@end

NS_ASSUME_NONNULL_END

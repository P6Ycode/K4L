#import <Foundation/Foundation.h>

#import "SCIDownloadTypes.h"
#import "SCIDownloadRequest.h"
#import "SCIDownloadItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCIDownloadJob : NSObject <NSCopying>
@property (nonatomic, copy) NSString *jobID;
@property (nonatomic, assign) NSTimeInterval createdAt;
@property (nonatomic, assign) NSTimeInterval updatedAt;
@property (nonatomic, assign) SCIDownloadState state;
@property (nonatomic, assign) double aggregateProgress;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic, strong, readonly) SCIDownloadRequest *request;
@property (nonatomic, copy, readonly) NSArray<SCIDownloadItem *> *items;
/// Mutable backing store; scheduler/store use this for in-place updates.
@property (nonatomic, strong, readonly) NSMutableArray<SCIDownloadItem *> *mutableItems;
@property (nonatomic, copy, nullable) NSString *completionAction;

- (instancetype)initWithRequest:(SCIDownloadRequest *)request jobID:(NSString *)jobID;
- (void)recomputeDerivedState;
- (void)markActiveItemsInterrupted;
- (void)replaceItems:(NSArray<SCIDownloadItem *> *)items;
- (nullable SCIDownloadItem *)itemWithIdentifier:(NSString *)itemID;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;
@end

NS_ASSUME_NONNULL_END

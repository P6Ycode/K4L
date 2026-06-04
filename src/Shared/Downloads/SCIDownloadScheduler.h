#import <Foundation/Foundation.h>

#import "SCIDownloadTypes.h"
#import "SCIDownloadRequest.h"
#import "SCIDownloadJob.h"

@class SCIDownloadPresenter;
@class SCIDownloadStore;

NS_ASSUME_NONNULL_BEGIN

@interface SCIDownloadScheduler : NSObject

@property (nonatomic, weak, nullable) SCIDownloadPresenter *presenter;
@property (nonatomic, strong) SCIDownloadStore *store;

- (NSArray<SCIDownloadJob *> *)allJobs;
- (nullable SCIDownloadJob *)jobWithID:(NSString *)jobID;

- (void)submitRequest:(SCIDownloadRequest *)request completion:(void (^ _Nullable)(NSString * _Nullable jobID, NSError * _Nullable error))completion;
- (void)cancelJobID:(NSString *)jobID;
- (void)cancelItemID:(NSString *)itemID inJobID:(NSString *)jobID;
- (void)retryJobID:(NSString *)jobID;
- (void)retryItemID:(NSString *)itemID inJobID:(NSString *)jobID;
- (void)clearFinishedHistory;
- (void)refreshConcurrencyLimit;
- (void)removeJobID:(NSString *)jobID;

- (void)reportItemProgressForJobID:(NSString *)jobID
                            itemID:(NSString *)itemID
                             block:(void (^)(SCIDownloadItem *item))block;

@end

NS_ASSUME_NONNULL_END

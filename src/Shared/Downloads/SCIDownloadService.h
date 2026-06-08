#import <Foundation/Foundation.h>

#import "SCIDownloadTypes.h"
#import "SCIDownloadRequest.h"
#import "SCIDownloadJob.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^SCIDownloadSubmissionCompletion)(NSString * _Nullable jobID, NSError * _Nullable error);

@interface SCIDownloadService : NSObject

+ (instancetype)shared;

/// Same sheet UI used by queue pill "Tap to open Downloads" and in-app entry points.
+ (void)presentDownloadsHistorySheet;
+ (void)confirmCancelAllActive;

- (void)submitRequest:(SCIDownloadRequest *)request
           completion:(nullable SCIDownloadSubmissionCompletion)completion;

- (BOOL)hasActiveJobWithHiddenPill;
- (void)reshowProgressPill;
- (void)confirmCancelForJobID:(NSString *)jobID;

- (NSArray<SCIDownloadJob *> *)jobsMatchingFilter:(SCIDownloadHistoryFilter)filter;
- (nullable SCIDownloadJob *)jobWithID:(NSString *)jobID;

- (void)cancelJobID:(NSString *)jobID;
- (void)cancelAllActive;
- (void)cancelItemID:(NSString *)itemID inJobID:(NSString *)jobID;
- (void)retryJobID:(NSString *)jobID;
- (void)retryItemID:(NSString *)itemID inJobID:(NSString *)jobID;
- (void)clearFinishedHistory;
- (void)refreshSettings;
- (void)removeJobID:(NSString *)jobID;

@end

NS_ASSUME_NONNULL_END

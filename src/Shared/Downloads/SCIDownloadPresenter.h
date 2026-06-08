#import <Foundation/Foundation.h>

@class SCIDownloadJob;

NS_ASSUME_NONNULL_BEGIN

@interface SCIDownloadPresenter : NSObject

@property (nonatomic, copy, nullable) void (^openHistoryForJobID)(NSString * _Nullable jobID);
@property (nonatomic, copy, nullable) void (^cancelAllActiveHandler)(void);
@property (nonatomic, copy, readonly, nullable) NSString *activeJobID;
@property (nonatomic, copy, nullable) void (^cancelHandlerForActiveJob)(NSString *jobID);

- (void)handleJobSnapshot:(SCIDownloadJob *)job;
- (void)dismissProgress;
- (void)prepareForNewJobSubmission;

- (BOOL)jobIsActive:(SCIDownloadJob *)job;
- (BOOL)hasActiveJobWithoutPillForJobID:(NSString *)jobID;
- (void)reshowPillForJob:(SCIDownloadJob *)job;

@end

NS_ASSUME_NONNULL_END

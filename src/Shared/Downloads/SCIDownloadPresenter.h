#import <Foundation/Foundation.h>

@class SCIDownloadJob;

NS_ASSUME_NONNULL_BEGIN

@interface SCIDownloadPresenter : NSObject

@property (nonatomic, copy, nullable) void (^openHistoryForJobID)(NSString * _Nullable jobID);
@property (nonatomic, copy, nullable) void (^cancelAllActiveHandler)(void);

- (void)handleJobSnapshot:(SCIDownloadJob *)job;
- (void)dismissProgress;

@end

NS_ASSUME_NONNULL_END

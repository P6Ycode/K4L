#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SCIDownloadQueueDidChangeNotification;
FOUNDATION_EXPORT NSString * const kSCIDownloadMaxConcurrentKey;
FOUNDATION_EXPORT NSString * const kSCIDownloadHistoryLimitKey;

typedef void (^SCIDownloadQueueTaskStartBlock)(NSString *taskID);
typedef void (^SCIDownloadQueueTaskCancelBlock)(void);
typedef void (^SCIDownloadQueueActionRetryBlock)(void);
typedef void (^SCIDownloadQueueItemMutationBlock)(NSMutableDictionary *item);

@interface SCIDownloadQueueManager : NSObject

+ (instancetype)shared;

- (NSArray<NSDictionary *> *)jobs;

- (NSString *)createActionWithTitle:(NSString *)title
                             detail:(nullable NSString *)detail
                         descriptor:(nullable NSDictionary *)descriptor
                              items:(NSArray<NSDictionary *> *)items
                              retry:(nullable SCIDownloadQueueActionRetryBlock)retry;
- (void)setCancelBlock:(nullable SCIDownloadQueueTaskCancelBlock)cancelBlock forActionID:(NSString *)actionID;
- (void)setRetryBlock:(nullable SCIDownloadQueueActionRetryBlock)retryBlock forActionID:(NSString *)actionID;
- (void)reactivateActionID:(NSString *)actionID
                descriptor:(nullable NSDictionary *)descriptor
                    detail:(nullable NSString *)detail
           resetItemIndexes:(NSIndexSet *)indexes;
- (NSString *)enqueueTaskForActionID:(NSString *)actionID
                           itemIndex:(NSUInteger)itemIndex
                               title:(nullable NSString *)title
                               start:(SCIDownloadQueueTaskStartBlock)start;
- (void)setCancelBlock:(nullable SCIDownloadQueueTaskCancelBlock)cancelBlock forTaskID:(NSString *)taskID;
- (void)updateTaskID:(NSString *)taskID progress:(double)progress detail:(nullable NSString *)detail;
- (void)updateActionDescriptor:(NSDictionary *)descriptor forActionID:(NSString *)actionID;
- (void)updateActionDetail:(nullable NSString *)detail progress:(double)progress forActionID:(NSString *)actionID;
- (void)updateItemAtIndex:(NSUInteger)index forJobID:(NSString *)jobID usingBlock:(SCIDownloadQueueItemMutationBlock)block;
- (void)finishTaskID:(NSString *)taskID detail:(nullable NSString *)detail filePath:(nullable NSString *)filePath;
- (void)failTaskID:(NSString *)taskID error:(nullable NSError *)error;
- (void)cancelTaskID:(NSString *)taskID;

- (void)cancelJobID:(NSString *)jobID;
- (void)cancelAllPending;
- (void)retryJobID:(NSString *)jobID;
- (void)retryChildAtIndex:(NSUInteger)index forJobID:(NSString *)jobID;
- (void)retryAllFailed;
- (BOOL)canRetryJob:(NSDictionary *)job;
- (BOOL)canRetryChildAtIndex:(NSUInteger)index forJob:(NSDictionary *)job;
- (nullable NSString *)completionActionForJob:(NSDictionary *)job;
- (BOOL)shouldShowStandaloneProgressForActionID:(NSString *)actionID;
- (void)removeJobID:(NSString *)jobID;
- (void)clearHistory;
- (void)refreshConcurrencyLimit;

@end

NS_ASSUME_NONNULL_END

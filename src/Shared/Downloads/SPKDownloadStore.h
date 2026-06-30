#import <Foundation/Foundation.h>

@class SPKDownloadJob;

NS_ASSUME_NONNULL_BEGIN

@interface SPKDownloadStore : NSObject

+ (NSString *)v2RootDirectory;
+ (NSString *)historyFilePath;
+ (NSString *)stagingDirectoryForJobID:(NSString *)jobID;

- (NSArray<SPKDownloadJob *> *)loadJobsMarkingInterrupted:(BOOL)markInterrupted;
- (void)replaceJobs:(NSArray<SPKDownloadJob *> *)jobs;
- (void)persistJobs:(NSArray<SPKDownloadJob *> *)jobs immediately:(BOOL)immediately;
- (void)debouncedPersistJobs:(NSArray<SPKDownloadJob *> *)jobs;
- (void)ensureDirectories;

@end

NS_ASSUME_NONNULL_END

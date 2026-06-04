#import <Foundation/Foundation.h>

@class SCIDownloadJob;

NS_ASSUME_NONNULL_BEGIN

@interface SCIDownloadStore : NSObject

+ (NSString *)v2RootDirectory;
+ (NSString *)historyFilePath;
+ (NSString *)stagingDirectoryForJobID:(NSString *)jobID;
+ (NSString *)sourcesDirectoryForJobID:(NSString *)jobID;

- (NSArray<SCIDownloadJob *> *)loadJobsMarkingInterrupted:(BOOL)markInterrupted;
- (void)replaceJobs:(NSArray<SCIDownloadJob *> *)jobs;
- (void)persistJobs:(NSArray<SCIDownloadJob *> *)jobs immediately:(BOOL)immediately;
- (void)debouncedPersistJobs:(NSArray<SCIDownloadJob *> *)jobs;
- (void)ensureDirectories;

@end

NS_ASSUME_NONNULL_END

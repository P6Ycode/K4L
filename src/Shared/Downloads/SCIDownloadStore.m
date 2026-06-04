#import "SCIDownloadStore.h"

#import "SCIDownloadJob.h"
#import "SCIDownloadTypes.h"
#import "../SCIStoragePaths.h"

@interface SCIDownloadStore ()
@property (nonatomic, strong, nullable) NSTimer *debounceTimer;
@property (nonatomic, copy, nullable) NSArray<SCIDownloadJob *> *pendingJobs;
@end

@implementation SCIDownloadStore

+ (NSString *)v2RootDirectory {
    return [[SCIStoragePaths downloadsDirectory] stringByAppendingPathComponent:@"v2"];
}

+ (NSString *)historyFilePath {
    return [[self v2RootDirectory] stringByAppendingPathComponent:@"history.json"];
}

+ (NSString *)stagingDirectoryForJobID:(NSString *)jobID {
    return [[[self v2RootDirectory] stringByAppendingPathComponent:@"staging"] stringByAppendingPathComponent:jobID ?: @"unknown"];
}

+ (NSString *)sourcesDirectoryForJobID:(NSString *)jobID {
    return [[[self v2RootDirectory] stringByAppendingPathComponent:@"sources"] stringByAppendingPathComponent:jobID ?: @"unknown"];
}

- (void)ensureDirectories {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *paths = @[
        [SCIDownloadStore v2RootDirectory],
        [[SCIDownloadStore v2RootDirectory] stringByAppendingPathComponent:@"staging"],
        [[SCIDownloadStore v2RootDirectory] stringByAppendingPathComponent:@"sources"],
        [[SCIDownloadStore v2RootDirectory] stringByAppendingPathComponent:@"previews"],
    ];
    for (NSString *path in paths) {
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (NSArray<SCIDownloadJob *> *)loadJobsMarkingInterrupted:(BOOL)markInterrupted {
    [self ensureDirectories];
    NSData *data = [NSData dataWithContentsOfFile:[SCIDownloadStore historyFilePath]];
    if (data.length == 0) return @[];
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class]) return @[];
    if ([root[@"schemaVersion"] integerValue] != SCIDownloadStoreSchemaVersion) return @[];
    NSMutableArray<SCIDownloadJob *> *jobs = [NSMutableArray array];
    for (NSDictionary *entry in root[@"jobs"] ?: @[]) {
        SCIDownloadJob *job = [SCIDownloadJob fromDictionary:entry];
        if (!job) continue;
        if (markInterrupted) {
            [job markActiveItemsInterrupted];
        }
        [jobs addObject:job];
    }
    return jobs;
}

- (void)replaceJobs:(NSArray<SCIDownloadJob *> *)jobs {
    [self persistJobs:jobs immediately:YES];
}

- (void)persistJobs:(NSArray<SCIDownloadJob *> *)jobs immediately:(BOOL)immediately {
    (void)immediately;
    [self ensureDirectories];
    NSMutableArray *serialized = [NSMutableArray array];
    for (SCIDownloadJob *job in jobs) {
        [serialized addObject:[job dictionaryRepresentation]];
    }
    NSDictionary *root = @{
        @"schemaVersion": @(SCIDownloadStoreSchemaVersion),
        @"jobs": serialized,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    if (!data) return;
    NSString *path = [SCIDownloadStore historyFilePath];
    NSString *tmp = [path stringByAppendingString:@".tmp"];
    if ([data writeToFile:tmp atomically:YES]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:path error:nil];
    }
}

- (void)debouncedPersistJobs:(NSArray<SCIDownloadJob *> *)jobs {
    self.pendingJobs = jobs;
    [self.debounceTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.debounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf.pendingJobs) return;
        [strongSelf persistJobs:strongSelf.pendingJobs immediately:YES];
        strongSelf.pendingJobs = nil;
    }];
}

@end

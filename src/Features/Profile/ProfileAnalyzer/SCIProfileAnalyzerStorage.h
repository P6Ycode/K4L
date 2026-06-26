#import <Foundation/Foundation.h>
#import "SCIProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

// Posted on every save/update/reset. userInfo carries @"user_pk" (the account
// the data belongs to), or an empty dict for whole-store resets.
extern NSNotificationName const SCIProfileAnalyzerDataDidChangeNotification;

// Per-account on-disk store under
//   Documents/SCInsta/ProfileAnalyzer/
// Layout (one set of files per account PK):
//   <pk>.current.json   — latest snapshot
//   <pk>.previous.json  — snapshot before the latest (for delta computation)
//   <pk>.baseline.json  — optional user-pinned reference snapshot
//   <pk>.header.json    — cached self-profile header info
//   <pk>.visits.json    — visited-profiles log (newest-first)
@interface SCIProfileAnalyzerStorage : NSObject

#pragma mark - Snapshots

+ (nullable SCIProfileAnalyzerSnapshot *)currentSnapshotForUserPK:(NSString *)userPK;
+ (nullable SCIProfileAnalyzerSnapshot *)previousSnapshotForUserPK:(NSString *)userPK;
+ (nullable SCIProfileAnalyzerSnapshot *)baselineSnapshotForUserPK:(NSString *)userPK;
+ (BOOL)saveBaselineSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK;
+ (void)clearBaselineForUserPK:(NSString *)userPK;

// Rotates current -> previous, then writes the new current.
+ (BOOL)saveSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK;
// Overwrites current without rotating — used for in-app follow/unfollow mutations.
+ (BOOL)updateCurrentSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK;

+ (void)resetForUserPK:(NSString *)userPK;
+ (void)resetAll;

#pragma mark - Header cache

+ (nullable NSDictionary *)headerInfoForUserPK:(NSString *)userPK;
+ (void)saveHeaderInfo:(NSDictionary *)info forUserPK:(NSString *)userPK;

#pragma mark - Visited profiles

+ (NSArray<SCIProfileAnalyzerVisit *> *)visitedProfilesForUserPK:(NSString *)userPK;
+ (void)recordVisitForUser:(SCIProfileAnalyzerUser *)user forUserPK:(NSString *)userPK;
+ (void)removeVisitForUserPK:(NSString *)userPK visitedPK:(NSString *)visitedPK;
+ (void)clearVisitsForUserPK:(NSString *)userPK;
// Refresh metadata for an existing visit without bumping last_seen / visit_count.
+ (void)refreshVisitedUser:(SCIProfileAnalyzerUser *)user forUserPK:(NSString *)userPK;

#pragma mark - Maintenance / backup

// Absolute path to the storage root. Used by backup/restore + storage stats.
+ (NSString *)storageRootPath;
// Total bytes on disk for one account (snapshots + visits + header).
+ (unsigned long long)storageSizeBytesForUserPK:(NSString *)userPK;
// Replace the entire store directory with the contents at sourcePath (import).
+ (BOOL)replaceStorageWithDirectoryAtPath:(NSString *)sourcePath error:(NSError **)error;

// Non-destructive import: per account, the visited-profiles log is unioned (dedup by
// visited pk, existing entries kept), and the snapshots (current/previous/baseline/
// header) are adopted ONLY for accounts with no local snapshot — never overwriting
// existing analysis or a pinned baseline. When `ownerFilterPK` is non-nil, only that
// account is merged. Returns the number of visits added, or -1 on a hard failure.
+ (NSInteger)mergeFromStorageDirectory:(NSString *)sourcePath
                         ownerFilterPK:(nullable NSString *)ownerFilterPK
                                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

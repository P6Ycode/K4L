#import "SCIProfileAnalyzerStorage.h"
#import "../../../Shared/SCIStoragePaths.h"

NSNotificationName const SCIProfileAnalyzerDataDidChangeNotification = @"SCIProfileAnalyzerDataDidChangeNotification";

@implementation SCIProfileAnalyzerStorage

// Serial queue for visit-list reads + writes — prevents racing record / refresh
// / remove writes from resurrecting deleted entries.
static dispatch_queue_t sciVisitQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.scinsta.profileanalyzer.visits", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

// Strip NSNull recursively — NSJSONSerialization rejects it and IG payloads carry it.
static id sciStripNull(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:[obj count]];
        for (id k in obj) {
            id v = obj[k];
            if (v && ![v isKindOfClass:[NSNull class]]) out[k] = sciStripNull(v);
        }
        return out;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:[obj count]];
        for (id v in obj) if (v && ![v isKindOfClass:[NSNull class]]) [out addObject:sciStripNull(v)];
        return out;
    }
    return obj;
}

static void sciPostDataChanged(NSString *userPK) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIProfileAnalyzerDataDidChangeNotification
                                                            object:nil
                                                          userInfo:userPK.length ? @{ @"user_pk": userPK } : @{}];
    });
}

static NSString *sciSafePK(NSString *userPK) {
    if (!userPK.length) return @"anon";
    return [userPK stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
}

static NSString *sciStorageDir(void) {
    NSString *dir = [SCIStoragePaths profileAnalyzerDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *sciPath(NSString *userPK, NSString *slot) {
    return [sciStorageDir() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.%@.json", sciSafePK(userPK), slot]];
}

static NSDictionary *sciReadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static BOOL sciWriteJSON(NSString *path, NSDictionary *dict) {
    NSError *err = nil;
    id sanitized = sciStripNull(dict ?: @{});
    NSData *data = [NSJSONSerialization dataWithJSONObject:sanitized options:0 error:&err];
    if (!data) return NO;
    return [data writeToFile:path atomically:YES];
}

#pragma mark - Snapshots

+ (SCIProfileAnalyzerSnapshot *)currentSnapshotForUserPK:(NSString *)userPK {
    return [SCIProfileAnalyzerSnapshot snapshotFromJSONDict:sciReadJSON(sciPath(userPK, @"current"))];
}

+ (SCIProfileAnalyzerSnapshot *)previousSnapshotForUserPK:(NSString *)userPK {
    return [SCIProfileAnalyzerSnapshot snapshotFromJSONDict:sciReadJSON(sciPath(userPK, @"previous"))];
}

+ (SCIProfileAnalyzerSnapshot *)baselineSnapshotForUserPK:(NSString *)userPK {
    return [SCIProfileAnalyzerSnapshot snapshotFromJSONDict:sciReadJSON(sciPath(userPK, @"baseline"))];
}

+ (BOOL)saveBaselineSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
    if (!snapshot) return NO;
    BOOL ok = sciWriteJSON(sciPath(userPK, @"baseline"), [snapshot toJSONDict]);
    if (ok) sciPostDataChanged(userPK);
    return ok;
}

+ (void)clearBaselineForUserPK:(NSString *)userPK {
    [[NSFileManager defaultManager] removeItemAtPath:sciPath(userPK, @"baseline") error:nil];
    sciPostDataChanged(userPK);
}

+ (BOOL)saveSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
    if (!snapshot) return NO;
    NSString *cur = sciPath(userPK, @"current");
    NSString *prev = sciPath(userPK, @"previous");
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:cur]) {
        [fm removeItemAtPath:prev error:nil];
        [fm moveItemAtPath:cur toPath:prev error:nil];
    }
    BOOL ok = sciWriteJSON(cur, [snapshot toJSONDict]);
    if (ok) sciPostDataChanged(userPK);
    return ok;
}

+ (BOOL)updateCurrentSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
    if (!snapshot) return NO;
    BOOL ok = sciWriteJSON(sciPath(userPK, @"current"), [snapshot toJSONDict]);
    if (ok) sciPostDataChanged(userPK);
    return ok;
}

+ (void)resetForUserPK:(NSString *)userPK {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *slot in @[@"current", @"previous", @"baseline", @"header", @"visits"]) {
        [fm removeItemAtPath:sciPath(userPK, slot) error:nil];
    }
    sciPostDataChanged(userPK);
}

+ (void)resetAll {
    [[NSFileManager defaultManager] removeItemAtPath:sciStorageDir() error:nil];
    sciPostDataChanged(nil);
}

#pragma mark - Header cache

+ (NSDictionary *)headerInfoForUserPK:(NSString *)userPK {
    return sciReadJSON(sciPath(userPK, @"header"));
}

+ (void)saveHeaderInfo:(NSDictionary *)info forUserPK:(NSString *)userPK {
    if (![info isKindOfClass:[NSDictionary class]] || !info.count) return;
    NSMutableDictionary *stored = [info mutableCopy];
    stored[@"cached_at"] = @([[NSDate date] timeIntervalSince1970]);
    sciWriteJSON(sciPath(userPK, @"header"), stored);
}

#pragma mark - Visited profiles

+ (NSArray<SCIProfileAnalyzerVisit *> *)visitedProfilesForUserPK:(NSString *)userPK {
    __block NSArray *result = @[];
    dispatch_sync(sciVisitQueue(), ^{
        NSDictionary *root = sciReadJSON(sciPath(userPK, @"visits"));
        NSArray *list = root[@"visits"];
        if (![list isKindOfClass:[NSArray class]]) return;
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:list.count];
        for (NSDictionary *d in list) {
            if (![d isKindOfClass:[NSDictionary class]]) continue;
            SCIProfileAnalyzerVisit *v = [SCIProfileAnalyzerVisit visitFromJSONDict:d];
            if (v) [out addObject:v];
        }
        result = out;
    });
    return result;
}

// Locate a visit entry by pk with type-safe lookups; NSNotFound when absent.
static NSInteger sciVisitIndexForPK(NSArray *list, NSString *pk) {
    if (!pk.length) return NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)list.count; i++) {
        id entry = list[i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        id u = entry[@"user"];
        if (![u isKindOfClass:[NSDictionary class]]) continue;
        id storedPK = u[@"pk"];
        if (![storedPK isKindOfClass:[NSString class]]) continue;
        if ([(NSString *)storedPK isEqualToString:pk]) return i;
    }
    return NSNotFound;
}

+ (void)recordVisitForUser:(SCIProfileAnalyzerUser *)user forUserPK:(NSString *)userPK {
    if (!user.pk.length) return;
    dispatch_sync(sciVisitQueue(), ^{
        NSDictionary *root = sciReadJSON(sciPath(userPK, @"visits"));
        NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];

        NSDate *now = [NSDate date];
        NSInteger foundIdx = sciVisitIndexForPK(list, user.pk);
        if (foundIdx == NSNotFound) {
            SCIProfileAnalyzerVisit *v = [SCIProfileAnalyzerVisit new];
            v.user = user;
            v.firstSeen = now;
            v.lastSeen = now;
            v.visitCount = 1;
            [list insertObject:[v toJSONDict] atIndex:0];
        } else {
            // Merge: don't clobber known-good fields with empty values from a
            // half-loaded fieldCache. Booleans only flip on, never off.
            NSMutableDictionary *d = [list[foundIdx] mutableCopy];
            NSDictionary *prevUser = [d[@"user"] isKindOfClass:[NSDictionary class]] ? d[@"user"] : @{};
            NSMutableDictionary *merged = [prevUser mutableCopy];
            NSDictionary *fresh = [user toJSONDict];
            for (NSString *k in @[@"pk", @"username", @"full_name", @"profile_pic_url", @"profile_pic_id"]) {
                id v = fresh[k];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) merged[k] = v;
            }
            if ([fresh[@"is_verified"] boolValue]) merged[@"is_verified"] = @YES;
            if ([fresh[@"is_private"]  boolValue]) merged[@"is_private"]  = @YES;

            d[@"user"] = merged;
            d[@"last_seen"] = @([now timeIntervalSince1970]);
            d[@"visit_count"] = @([d[@"visit_count"] integerValue] + 1);
            [list removeObjectAtIndex:foundIdx];
            [list insertObject:d atIndex:0];   // most-recent first
        }
        sciWriteJSON(sciPath(userPK, @"visits"), @{ @"visits": list });
        sciPostDataChanged(userPK);
    });
}

+ (void)removeVisitForUserPK:(NSString *)userPK visitedPK:(NSString *)visitedPK {
    if (!visitedPK.length) return;
    dispatch_sync(sciVisitQueue(), ^{
        NSDictionary *root = sciReadJSON(sciPath(userPK, @"visits"));
        NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];
        NSInteger removeIdx = sciVisitIndexForPK(list, visitedPK);
        if (removeIdx == NSNotFound) return;
        [list removeObjectAtIndex:removeIdx];
        sciWriteJSON(sciPath(userPK, @"visits"), @{ @"visits": list });
        sciPostDataChanged(userPK);
    });
}

+ (void)clearVisitsForUserPK:(NSString *)userPK {
    dispatch_sync(sciVisitQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:sciPath(userPK, @"visits") error:nil];
        sciPostDataChanged(userPK);
    });
}

+ (void)refreshVisitedUser:(SCIProfileAnalyzerUser *)user forUserPK:(NSString *)userPK {
    if (!user.pk.length) return;
    dispatch_sync(sciVisitQueue(), ^{
        NSDictionary *root = sciReadJSON(sciPath(userPK, @"visits"));
        NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];
        NSInteger idx = sciVisitIndexForPK(list, user.pk);
        if (idx == NSNotFound) return;   // deleted between trigger + write
        NSMutableDictionary *d = [list[idx] mutableCopy];
        d[@"user"] = [user toJSONDict];
        list[idx] = d;
        sciWriteJSON(sciPath(userPK, @"visits"), @{ @"visits": list });
    });
}

#pragma mark - Maintenance / backup

+ (NSString *)storageRootPath {
    return sciStorageDir();
}

+ (unsigned long long)storageSizeBytesForUserPK:(NSString *)userPK {
    unsigned long long total = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *slot in @[@"current", @"previous", @"baseline", @"header", @"visits"]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:sciPath(userPK, slot) error:nil];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            total += [attrs[NSFileSize] unsignedLongLongValue];
        }
    }
    return total;
}

+ (BOOL)replaceStorageWithDirectoryAtPath:(NSString *)sourcePath error:(NSError **)error {
    if (sourcePath.length == 0) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *destination = sciStorageDir();
    if ([fm fileExistsAtPath:destination] && ![fm removeItemAtPath:destination error:error]) {
        return NO;
    }
    NSString *parent = [destination stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL copied = [fm copyItemAtPath:sourcePath toPath:destination error:error];
    if (copied) sciPostDataChanged(nil);
    return copied;
}

+ (NSInteger)mergeFromStorageDirectory:(NSString *)sourcePath
                         ownerFilterPK:(NSString *)ownerFilterPK
                                 error:(NSError **)error {
    if (sourcePath.length == 0) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:sourcePath error:error];
    if (!entries) return -1;

    // Distinct account PKs present in the archive ("<pk>.<slot>.json").
    NSArray<NSString *> *slots = @[@"current", @"previous", @"baseline", @"header", @"visits"];
    NSMutableSet<NSString *> *pks = [NSMutableSet set];
    for (NSString *entry in entries) {
        for (NSString *slot in slots) {
            NSString *suffix = [NSString stringWithFormat:@".%@.json", slot];
            if ([entry hasSuffix:suffix]) { [pks addObject:[entry substringToIndex:entry.length - suffix.length]]; break; }
        }
    }

    __block NSInteger added = 0;
    for (NSString *safePK in pks) {
        if (ownerFilterPK.length > 0 && ![safePK isEqualToString:sciSafePK(ownerFilterPK)]) continue;

        // Snapshots: fill-only — adopt the archive's set only when we have no current
        // snapshot, so an import never overwrites local analysis or a pinned baseline.
        if (![fm fileExistsAtPath:sciPath(safePK, @"current")]) {
            for (NSString *slot in @[@"current", @"previous", @"baseline", @"header"]) {
                NSString *src = [sourcePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@.json", safePK, slot]];
                if ([fm fileExistsAtPath:src]) [fm copyItemAtPath:src toPath:sciPath(safePK, slot) error:nil];
            }
        }

        // Visits: union, keeping local entries and adding archive ones we don't have.
        NSString *srcVisits = [sourcePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.visits.json", safePK]];
        if (![fm fileExistsAtPath:srcVisits]) continue;
        dispatch_sync(sciVisitQueue(), ^{
            NSMutableArray *liveList = [(sciReadJSON(sciPath(safePK, @"visits"))[@"visits"] ?: @[]) mutableCopy];
            NSArray *srcList = sciReadJSON(srcVisits)[@"visits"] ?: @[];
            BOOL changed = NO;
            for (id entry in srcList) {
                if (![entry isKindOfClass:[NSDictionary class]]) continue;
                id u = entry[@"user"];
                NSString *vpk = ([u isKindOfClass:[NSDictionary class]] && [u[@"pk"] isKindOfClass:[NSString class]]) ? u[@"pk"] : nil;
                if (vpk.length == 0 || sciVisitIndexForPK(liveList, vpk) != NSNotFound) continue;
                [liveList addObject:entry];
                changed = YES;
                added++;
            }
            if (changed) {
                [liveList sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                    double la = [a[@"last_seen"] doubleValue], lb = [b[@"last_seen"] doubleValue];
                    if (la > lb) return NSOrderedAscending;   // newest-first
                    if (la < lb) return NSOrderedDescending;
                    return NSOrderedSame;
                }];
                sciWriteJSON(sciPath(safePK, @"visits"), @{ @"visits": liveList });
                sciPostDataChanged(safePK);
            }
        });
    }
    return added;
}

@end

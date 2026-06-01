#import "SCIProfileAnalyzerService.h"
#import "SCIProfileAnalyzerStorage.h"
#import "../../../Networking/SCIInstagramAPI.h"
#import "../../../Utils.h"

// Refuse accounts above ~13k total connections; the same cushion keeps
// a single scan inside IG's friendships rate limits.
const NSInteger SCIProfileAnalyzerMaxConnectionCount = 13000;

NSNotificationName const SCIProfileAnalyzerProgressDidChangeNotification = @"SCIProfileAnalyzerProgressDidChangeNotification";

#define SCI_PA_PAGE_DELAY_S 0.5    // rate-limit cushion between pages
#define SCI_PA_MAX_PAGE_RETRIES 4  // retries for a throttled/empty page
#define SCI_PA_RETRY_BASE_DELAY_S 2.0  // backoff base; grows linearly per retry
// A stage is considered too incomplete to trust when it collects less than this
// fraction of the count IG reported in users/info. Persisting a short list would
// corrupt mutuals / not-following-back / unfollowed categories.
#define SCI_PA_MIN_COMPLETE_FRACTION 0.90

@interface SCIProfileAnalyzerService () {
@public
    NSInteger _expectedFollowers;
    NSInteger _expectedFollowing;
}
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) double currentFraction;
@property (nonatomic, copy, nullable) NSString *currentStatus;
@end

@implementation SCIProfileAnalyzerService

+ (instancetype)sharedService {
    static SCIProfileAnalyzerService *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (void)cancel { self.cancelled = YES; }

- (NSError *)errorWithCode:(SCIProfileAnalyzerError)code message:(NSString *)msg {
    return [NSError errorWithDomain:@"SCIProfileAnalyzer" code:code
                           userInfo:@{ NSLocalizedDescriptionKey: msg ?: @"" }];
}

- (void)finishWithSnapshot:(SCIProfileAnalyzerSnapshot *)s
                     error:(NSError *)e
                completion:(SCIPACompletion)completion {
    self.isRunning = NO;
    self.cancelled = NO;
    self.currentFraction = 0;
    self.currentStatus = nil;
    [self postProgressRunning:NO];
    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(s, e); });
}

- (void)reportProgress:(SCIPAProgress)p status:(NSString *)s fraction:(double)f {
    self.currentFraction = f;
    self.currentStatus = s;
    [self postProgressRunning:YES];
    if (!p) return;
    dispatch_async(dispatch_get_main_queue(), ^{ p(s, f); });
}

- (void)postProgressRunning:(BOOL)running {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"fraction"] = @(self.currentFraction);
    info[@"running"] = @(running);
    if (self.currentStatus) info[@"status"] = self.currentStatus;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIProfileAnalyzerProgressDidChangeNotification
                                                            object:nil
                                                          userInfo:info];
    });
}

- (void)runForSelfWithHeaderInfo:(SCIPAHeaderInfo)headerInfo
                        progress:(SCIPAProgress)progress
                      completion:(SCIPACompletion)completion {
    if (self.isRunning) {
        if (completion) completion(nil, [self errorWithCode:SCIProfileAnalyzerErrorAlreadyRunning
                                                    message:@"Another analysis is already running"]);
        return;
    }
    self.isRunning = YES;
    self.cancelled = NO;

    NSString *selfPK = [SCIUtils currentUserPK];
    if (!selfPK.length) {
        [self finishWithSnapshot:nil
                           error:[self errorWithCode:SCIProfileAnalyzerErrorNoSession message:@"No active Instagram session found"]
                      completion:completion];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self reportProgress:progress status:@"Fetching profile info…" fraction:0.02];

    [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"users/%@/info/", selfPK]
                                      body:nil
                                completion:^(NSDictionary *resp, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.cancelled) {
            [strongSelf finishWithSnapshot:nil
                                     error:[strongSelf errorWithCode:SCIProfileAnalyzerErrorCancelled message:@"Cancelled"]
                                completion:completion];
            return;
        }
        NSDictionary *user = [resp[@"user"] isKindOfClass:[NSDictionary class]] ? resp[@"user"] : nil;
        if (!user) {
            [strongSelf finishWithSnapshot:nil
                                     error:[strongSelf errorWithCode:SCIProfileAnalyzerErrorNetwork message:@"Couldn't fetch profile information"]
                                completion:completion];
            return;
        }

        NSInteger followerCount = [user[@"follower_count"] integerValue];
        NSInteger followingCount = [user[@"following_count"] integerValue];
        if (followerCount + followingCount > SCIProfileAnalyzerMaxConnectionCount) {
            [strongSelf finishWithSnapshot:nil
                                     error:[strongSelf errorWithCode:SCIProfileAnalyzerErrorTooManyFollowers
                                                             message:@"Too many connections to analyze"]
                                completion:completion];
            return;
        }

        SCIProfileAnalyzerSnapshot *snap = [SCIProfileAnalyzerSnapshot new];
        snap.selfPK = selfPK;
        snap.selfUsername = user[@"username"];
        snap.selfFullName = user[@"full_name"];
        snap.selfProfilePicURL = user[@"profile_pic_url"];
        snap.followerCount = followerCount;
        snap.followingCount = followingCount;
        snap.mediaCount = [user[@"media_count"] integerValue];
        snap.scanDate = [NSDate date];

        strongSelf->_expectedFollowers = followerCount;
        strongSelf->_expectedFollowing = followingCount;

        // Cache the header so the dashboard can paint identity even before the
        // scan completes, then notify the caller for an immediate header paint.
        [SCIProfileAnalyzerStorage saveHeaderInfo:user forUserPK:selfPK];
        if (headerInfo) dispatch_async(dispatch_get_main_queue(), ^{ headerInfo(user); });

        [strongSelf fetchFollowersForPK:selfPK snapshot:snap progress:progress completion:completion];
    }];
}

#pragma mark - Paginated fetchers

- (void)fetchFollowersForPK:(NSString *)pk
                   snapshot:(SCIProfileAnalyzerSnapshot *)snap
                   progress:(SCIPAProgress)progress
                 completion:(SCIPACompletion)completion {
    NSMutableArray *acc = [NSMutableArray array];
    [self pagePath:[NSString stringWithFormat:@"friendships/%@/followers/", pk]
               acc:acc
             maxId:nil
             total:snap.followerCount
             stage:@"followers"
          progress:progress
        completion:^(NSArray *users, NSError *error) {
        if (error || self.cancelled) {
            [self finishWithSnapshot:nil error:error ?: [self errorWithCode:SCIProfileAnalyzerErrorCancelled message:@"Cancelled"]
                          completion:completion];
            return;
        }
        if (![self stageCount:users.count plausibleForExpected:snap.followerCount]) {
            [self finishWithSnapshot:nil
                               error:[self errorWithCode:SCIProfileAnalyzerErrorNetwork
                                                 message:@"Couldn't fetch the full followers list (Instagram rate limit). Try again in a few minutes."]
                          completion:completion];
            return;
        }
        snap.followers = users;
        [self fetchFollowingForPK:pk snapshot:snap progress:progress completion:completion];
    }];
}

- (void)fetchFollowingForPK:(NSString *)pk
                   snapshot:(SCIProfileAnalyzerSnapshot *)snap
                   progress:(SCIPAProgress)progress
                 completion:(SCIPACompletion)completion {
    NSMutableArray *acc = [NSMutableArray array];
    [self pagePath:[NSString stringWithFormat:@"friendships/%@/following/", pk]
               acc:acc
             maxId:nil
             total:snap.followingCount
             stage:@"following"
          progress:progress
        completion:^(NSArray *users, NSError *error) {
        if (error || self.cancelled) {
            [self finishWithSnapshot:nil error:error ?: [self errorWithCode:SCIProfileAnalyzerErrorCancelled message:@"Cancelled"]
                          completion:completion];
            return;
        }
        if (![self stageCount:users.count plausibleForExpected:snap.followingCount]) {
            [self finishWithSnapshot:nil
                               error:[self errorWithCode:SCIProfileAnalyzerErrorNetwork
                                                 message:@"Couldn't fetch the full following list (Instagram rate limit). Try again in a few minutes."]
                          completion:completion];
            return;
        }
        snap.following = users;
        // Persist (rotates current -> previous) before reporting completion so
        // observers reading storage immediately see the new snapshot.
        [SCIProfileAnalyzerStorage saveSnapshot:snap forUserPK:snap.selfPK];
        [self finishWithSnapshot:snap error:nil completion:completion];
    }];
}

// Guards against persisting a truncated graph. IG's reported count can lag the
// real list slightly, so we allow a small shortfall but reject a big one.
- (BOOL)stageCount:(NSInteger)collected plausibleForExpected:(NSInteger)expected {
    if (expected <= 0) return YES;                       // nothing to compare against
    if (collected >= expected) return YES;               // got everything (or more)
    double fraction = (double)collected / (double)expected;
    return fraction >= SCI_PA_MIN_COMPLETE_FRACTION;
}

- (void)pagePath:(NSString *)basePath
             acc:(NSMutableArray *)acc
           maxId:(NSString *)maxId
           total:(NSInteger)total
           stage:(NSString *)stage
        progress:(SCIPAProgress)progress
      completion:(void(^)(NSArray *users, NSError *error))completion {
    [self pagePath:basePath acc:acc maxId:maxId total:total stage:stage retry:0 progress:progress completion:completion];
}

- (void)pagePath:(NSString *)basePath
             acc:(NSMutableArray *)acc
           maxId:(NSString *)maxId
           total:(NSInteger)total
           stage:(NSString *)stage
           retry:(NSInteger)retry
        progress:(SCIPAProgress)progress
      completion:(void(^)(NSArray *users, NSError *error))completion {
    if (self.cancelled) {
        completion(nil, [self errorWithCode:SCIProfileAnalyzerErrorCancelled message:@"Cancelled"]);
        return;
    }
    NSString *path = maxId.length ? [NSString stringWithFormat:@"%@?max_id=%@", basePath, maxId] : basePath;

    __weak typeof(self) weakSelf = self;
    [SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        // Detect a usable page. IG soft-throttles by returning HTTP 200 with a
        // non-"ok" status and neither `users` nor `next_max_id`. Treating that
        // as "end of list" silently truncates the graph and corrupts every
        // derived category, so we retry it with backoff instead.
        NSArray *users = [resp[@"users"] isKindOfClass:[NSArray class]] ? resp[@"users"] : nil;
        id next = resp[@"next_max_id"];
        NSString *nextMax = [next isKindOfClass:[NSString class]] ? next
            : ([next respondsToSelector:@selector(stringValue)] ? [next stringValue] : nil);

        NSString *status = [resp[@"status"] isKindOfClass:[NSString class]] ? resp[@"status"] : nil;
        BOOL statusOK = (status == nil) || [status isEqualToString:@"ok"];
        BOOL gotPage = (users != nil);   // empty array is a valid "no more users" page when status ok

        if (error || !gotPage || !statusOK) {
            // Transient: retry up to a few times with escalating backoff.
            if (retry < SCI_PA_MAX_PAGE_RETRIES && !strongSelf.cancelled) {
                double delay = SCI_PA_RETRY_BASE_DELAY_S * (double)(retry + 1);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [strongSelf pagePath:basePath acc:acc maxId:maxId total:total stage:stage
                                   retry:retry + 1 progress:progress completion:completion];
                });
                return;
            }
            // Out of retries — fail loudly rather than persist a partial list.
            NSString *msg = error.localizedDescription ?: @"Instagram is rate-limiting requests. Try again in a few minutes.";
            completion(nil, [strongSelf errorWithCode:SCIProfileAnalyzerErrorNetwork message:msg]);
            return;
        }

        for (NSDictionary *d in users) {
            SCIProfileAnalyzerUser *u = [SCIProfileAnalyzerUser userFromAPIDict:d];
            if (u) [acc addObject:u];
        }

        // Weight each stage by its share of expected work; 3% reserved for user-info.
        NSInteger followerTarget = strongSelf->_expectedFollowers;
        NSInteger followingTarget = strongSelf->_expectedFollowing;
        double total0 = MAX(1, followerTarget + followingTarget);
        BOOL isFollowers = [stage isEqualToString:@"followers"];
        double stageWeight = (isFollowers ? followerTarget : followingTarget) / total0;
        double stageOffset = isFollowers ? 0.0 : (double)followerTarget / total0;
        double stageLocal = total > 0 ? MIN(1.0, (double)acc.count / (double)total) : 0;
        double frac = 0.03 + (stageOffset + stageLocal * stageWeight) * 0.97;
        NSString *label = isFollowers
            ? [NSString stringWithFormat:@"Fetching followers (%lu/%ld)…", (unsigned long)acc.count, (long)total]
            : [NSString stringWithFormat:@"Fetching following (%lu/%ld)…", (unsigned long)acc.count, (long)total];
        [strongSelf reportProgress:progress status:label fraction:frac];

        if (!nextMax.length || strongSelf.cancelled) {
            completion(acc, strongSelf.cancelled ? [strongSelf errorWithCode:SCIProfileAnalyzerErrorCancelled message:@"Cancelled"] : nil);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SCI_PA_PAGE_DELAY_S * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [strongSelf pagePath:basePath acc:acc maxId:nextMax total:total stage:stage
                           retry:0 progress:progress completion:completion];
        });
    }];
}

@end

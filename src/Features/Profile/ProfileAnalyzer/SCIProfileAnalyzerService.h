#import <Foundation/Foundation.h>
#import "SCIProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIProfileAnalyzerError) {
    SCIProfileAnalyzerErrorNoSession = 1,
    SCIProfileAnalyzerErrorTooManyFollowers,
    SCIProfileAnalyzerErrorNetwork,
    SCIProfileAnalyzerErrorCancelled,
    SCIProfileAnalyzerErrorAlreadyRunning,
};

// Hard cap — refuse to run beyond this connection count to dodge IG rate limits.
extern const NSInteger SCIProfileAnalyzerMaxConnectionCount;

// Posted (main queue) whenever scan progress changes, and on start/finish.
// userInfo: @"fraction" (NSNumber 0–1), @"status" (NSString), @"running" (NSNumber).
// Lets observers (e.g. the dashboard) restore progress UI without owning the run.
extern NSNotificationName const SCIProfileAnalyzerProgressDidChangeNotification;

typedef void(^SCIPAProgress)(NSString *status, double fraction);
typedef void(^SCIPACompletion)(SCIProfileAnalyzerSnapshot * _Nullable snapshot, NSError * _Nullable error);
// Fires once after the self-user-info call so the header can paint immediately.
typedef void(^SCIPAHeaderInfo)(NSDictionary *userInfo);

// Singleton that runs a full followers + following scan for the logged-in
// account. The run is independent of any view controller's lifetime — starting
// a scan and leaving the screen does NOT cancel it. Progress/result are surfaced
// to callers via the blocks below (all delivered on the main queue).
@interface SCIProfileAnalyzerService : NSObject

@property (nonatomic, readonly) BOOL isRunning;
// Snapshot of the last reported progress (0–1) and status, for late observers
// (e.g. a VC that re-appears mid-scan).
@property (nonatomic, readonly) double currentFraction;
@property (nonatomic, readonly, copy, nullable) NSString *currentStatus;

+ (instancetype)sharedService;

- (void)runForSelfWithHeaderInfo:(nullable SCIPAHeaderInfo)headerInfo
                        progress:(nullable SCIPAProgress)progress
                      completion:(nullable SCIPACompletion)completion;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END

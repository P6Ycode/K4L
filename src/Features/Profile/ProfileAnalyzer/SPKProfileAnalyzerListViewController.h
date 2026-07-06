#import "SPKProfileAnalyzerModels.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPKPAListKind) {
    SPKPAListKindPlain,         // no action button (e.g. lost followers)
    SPKPAListKindUnfollow,      // you follow them — show Unfollow
    SPKPAListKindFollow,        // you don't follow them — show Follow
    SPKPAListKindProfileUpdate, // previous → current change rows
    SPKPAListKindVisited,       // visited-profiles tracker — last-seen subtitle
};

@interface SPKProfileAnalyzerListViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                        users:(NSArray<SPKProfileAnalyzerUser *> *)users
                         kind:(SPKPAListKind)kind;

- (instancetype)initWithTitle:(NSString *)title
               profileUpdates:(NSArray<SPKProfileAnalyzerProfileChange *> *)updates;

// Grouped variants — split a change category into "Latest" (unseen) above
// "Previous" (seen). Empty groups are omitted.
- (instancetype)initWithTitle:(NSString *)title
                  latestUsers:(NSArray<SPKProfileAnalyzerUser *> *)latestUsers
                previousUsers:(NSArray<SPKProfileAnalyzerUser *> *)previousUsers
                         kind:(SPKPAListKind)kind;

- (instancetype)initWithTitle:(NSString *)title
         latestProfileUpdates:(NSArray<SPKProfileAnalyzerProfileChange *> *)latestUpdates
       previousProfileUpdates:(NSArray<SPKProfileAnalyzerProfileChange *> *)previousUpdates;

- (instancetype)initVisitedListWithTitle:(NSString *)title
                                  visits:(NSArray<SPKProfileAnalyzerVisit *> *)visits;

// Visited-list only: invoked when the user swipes to remove a visit, so the
// owner can persist the deletion. Optional.
@property (nonatomic, copy, nullable) void (^onRemoveVisit)(SPKProfileAnalyzerVisit *visit);

@end

NS_ASSUME_NONNULL_END

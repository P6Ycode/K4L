#import <UIKit/UIKit.h>
#import "SPKProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPKPAListKind) {
    SPKPAListKindPlain,           // no action button (e.g. lost followers)
    SPKPAListKindUnfollow,        // you follow them — show Unfollow
    SPKPAListKindFollow,          // you don't follow them — show Follow
    SPKPAListKindProfileUpdate,   // previous → current change rows
    SPKPAListKindVisited,         // visited-profiles tracker — last-seen subtitle
};

@interface SPKProfileAnalyzerListViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                        users:(NSArray<SPKProfileAnalyzerUser *> *)users
                         kind:(SPKPAListKind)kind;

- (instancetype)initWithTitle:(NSString *)title
               profileUpdates:(NSArray<SPKProfileAnalyzerProfileChange *> *)updates;

- (instancetype)initVisitedListWithTitle:(NSString *)title
                                  visits:(NSArray<SPKProfileAnalyzerVisit *> *)visits;

// Visited-list only: invoked when the user swipes to remove a visit, so the
// owner can persist the deletion. Optional.
@property (nonatomic, copy, nullable) void (^onRemoveVisit)(SPKProfileAnalyzerVisit *visit);

@end

NS_ASSUME_NONNULL_END

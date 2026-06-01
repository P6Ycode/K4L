#import <UIKit/UIKit.h>
#import "SCIProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIPAListKind) {
    SCIPAListKindPlain,           // no action button (e.g. lost followers)
    SCIPAListKindUnfollow,        // you follow them — show Unfollow
    SCIPAListKindFollow,          // you don't follow them — show Follow
    SCIPAListKindProfileUpdate,   // previous → current change rows
    SCIPAListKindVisited,         // visited-profiles tracker — last-seen subtitle
};

@interface SCIProfileAnalyzerListViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                        users:(NSArray<SCIProfileAnalyzerUser *> *)users
                         kind:(SCIPAListKind)kind;

- (instancetype)initWithTitle:(NSString *)title
               profileUpdates:(NSArray<SCIProfileAnalyzerProfileChange *> *)updates;

- (instancetype)initVisitedListWithTitle:(NSString *)title
                                  visits:(NSArray<SCIProfileAnalyzerVisit *> *)visits;

// Visited-list only: invoked when the user swipes to remove a visit, so the
// owner can persist the deletion. Optional.
@property (nonatomic, copy, nullable) void (^onRemoveVisit)(SCIProfileAnalyzerVisit *visit);

@end

NS_ASSUME_NONNULL_END

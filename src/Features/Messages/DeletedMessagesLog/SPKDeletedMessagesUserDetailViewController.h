#import <UIKit/UIKit.h>
#import "SPKDeletedMessagesModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPKDeletedMessagesUserDetailViewController : UIViewController
- (instancetype)initWithGroup:(SPKDeletedMessageGroup *)group ownerPK:(nullable NSString *)ownerPK;
@end

NS_ASSUME_NONNULL_END

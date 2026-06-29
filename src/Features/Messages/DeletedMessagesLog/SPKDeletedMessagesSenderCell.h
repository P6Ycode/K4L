#import <UIKit/UIKit.h>
#import "SPKDeletedMessagesModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SPKDeletedMessagesSenderCellReuseID;

// Inbox-style row: circular avatar, @username + pin badge, kind glyph + last
// message preview, and a trailing "deleted N ago" timestamp. Blocked senders
// render dimmed.
@interface SPKDeletedMessagesSenderCell : UITableViewCell

- (void)configureWithGroup:(SPKDeletedMessageGroup *)group;

@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>
#import "SCIDeletedMessagesModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SCIDeletedMessagesSenderCellReuseID;

// Inbox-style row: circular avatar, @username + pin badge, kind glyph + last
// message preview, and a trailing "deleted N ago" timestamp. Blocked senders
// render dimmed.
@interface SCIDeletedMessagesSenderCell : UITableViewCell

- (void)configureWithGroup:(SCIDeletedMessageGroup *)group;

@end

NS_ASSUME_NONNULL_END

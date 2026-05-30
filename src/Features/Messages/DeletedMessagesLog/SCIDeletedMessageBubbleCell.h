#import <UIKit/UIKit.h>
#import "SCIDeletedMessagesModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SCIDeletedMessageBubbleCellReuseID;

@class SCIDeletedMessageBubbleCell;

@protocol SCIDeletedMessageBubbleCellDelegate <NSObject>
// Tapping a media bubble (photo/video/voice/etc) should open the full preview.
- (void)bubbleCell:(SCIDeletedMessageBubbleCell *)cell didTapMediaForMessage:(SCIDeletedMessage *)message;
@end

// Incoming-style message bubble for the per-sender detail view. Renders the
// captured content by kind: text bubble, media thumbnail with kind chip, voice
// pill with a play affordance + duration, or share/link card. The deleted
// timestamp sits under each bubble.
@interface SCIDeletedMessageBubbleCell : UITableViewCell

@property (nonatomic, weak) id<SCIDeletedMessageBubbleCellDelegate> delegate;

- (void)configureWithMessage:(SCIDeletedMessage *)message
                   thumbnail:(nullable UIImage *)thumbnail
                    outgoing:(BOOL)outgoing;

// Apply a thumbnail that arrived asynchronously, if the cell still shows
// `messageId`. Avoids a full row reload (which can miss during initial layout).
- (void)applyLoadedThumbnail:(UIImage *)thumbnail forMessageId:(NSString *)messageId;

@property (nonatomic, copy, readonly, nullable) NSString *messageId;

@end

NS_ASSUME_NONNULL_END

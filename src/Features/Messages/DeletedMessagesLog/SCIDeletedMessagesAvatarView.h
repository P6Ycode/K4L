#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Circular avatar view used in the sender list and detail header. Shows the
// cached profile picture when available, otherwise a neutral user-circle
// glyph on a tinted background. Handles its own async load + reuse safety.
@interface SCIDeletedMessagesAvatarView : UIView

- (void)configureWithPK:(nullable NSString *)pk
              urlString:(nullable NSString *)urlString;

- (void)prepareForReuse;

@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>
#import "../Shared/ActionButton/ActionButtonCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPKBulkActionMenuEditViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                       source:(SPKActionButtonSource)source
              supportedActions:(NSArray<NSString *> *)supportedActions
               configuredActions:(NSArray<NSString *> *)configuredActions
                        onSave:(void (^)(NSArray<NSString *> *actions))onSave;

@end

NS_ASSUME_NONNULL_END

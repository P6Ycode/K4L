#import <UIKit/UIKit.h>

#import "../Shared/ActionButton/ActionButtonCore.h"

NS_ASSUME_NONNULL_BEGIN

NSString *SPKActionButtonDefaultActionIdentifierForSource(SPKActionButtonSource source);
NSString *SPKActionButtonDefaultActionTitleForSource(SPKActionButtonSource source);
NSString *SPKActionButtonDefaultActionIconNameForSource(SPKActionButtonSource source);

@interface SPKActionButtonDefaultActionPickerViewController : UIViewController

- (instancetype)initWithSource:(SPKActionButtonSource)source;

@end

NS_ASSUME_NONNULL_END

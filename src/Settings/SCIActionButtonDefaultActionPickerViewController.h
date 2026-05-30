#import <UIKit/UIKit.h>

#import "../Shared/ActionButton/ActionButtonCore.h"

NS_ASSUME_NONNULL_BEGIN

NSString *SCIActionButtonDefaultActionIdentifierForSource(SCIActionButtonSource source);
NSString *SCIActionButtonDefaultActionTitleForSource(SCIActionButtonSource source);
NSString *SCIActionButtonDefaultActionIconNameForSource(SCIActionButtonSource source);

@interface SCIActionButtonDefaultActionPickerViewController : UIViewController

- (instancetype)initWithSource:(SCIActionButtonSource)source;

@end

NS_ASSUME_NONNULL_END

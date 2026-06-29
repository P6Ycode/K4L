#pragma once

#import <UIKit/UIKit.h>
#import "../Shared/ActionButton/SPKActionButtonConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPKEditActionsListViewController : UIViewController

- (instancetype)initWithSource:(SPKActionButtonSource)source topicTitle:(NSString *)topicTitle;

@end

NS_ASSUME_NONNULL_END

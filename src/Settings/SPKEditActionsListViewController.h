#pragma once

#import "../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKEditActionsListViewController : UIViewController

- (instancetype)initWithSource:(SPKActionButtonSource)source topicTitle:(NSString *)topicTitle;

@end

NS_ASSUME_NONNULL_END

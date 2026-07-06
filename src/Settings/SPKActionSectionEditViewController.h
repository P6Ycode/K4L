#pragma once

#import "../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKActionSectionEditViewController : UIViewController

- (instancetype)initWithConfiguration:(SPKActionButtonConfiguration *)configuration
                    sectionIdentifier:(NSString *)sectionIdentifier
                             onChange:(dispatch_block_t)onChange;

@end

NS_ASSUME_NONNULL_END

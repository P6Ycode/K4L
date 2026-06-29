#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKAppIconPickerViewController : UIViewController

- (instancetype)initWithSelectedIdentifier:(nullable NSString *)selectedIdentifier
                                  onSelect:(nullable void (^)(NSString *identifier))onSelect;

@end

NS_ASSUME_NONNULL_END

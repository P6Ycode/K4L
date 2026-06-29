#pragma once

#import <UIKit/UIKit.h>

#import "SPKIconPickerViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPKAppIconPickerViewController : SPKIconPickerViewController

- (instancetype)initWithSelectedIdentifier:(nullable NSString *)selectedIdentifier
                                  onSelect:(nullable void (^)(NSString *identifier))onSelect;

@end

NS_ASSUME_NONNULL_END

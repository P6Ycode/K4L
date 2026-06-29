#pragma once

#import <UIKit/UIKit.h>

#import "SPKIconPickerViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPKActionSectionIconPickerViewController : SPKIconPickerViewController

- (instancetype)initWithSelectedIconName:(NSString *)selectedIconName
                                onSelect:(void (^)(NSString *iconName))onSelect;

@end

NS_ASSUME_NONNULL_END

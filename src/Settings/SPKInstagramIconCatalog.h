#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKInstagramIconCatalog : NSObject

+ (NSArray<NSString *> *)availableInstagramIconNames;
+ (NSString *)displayNameForIconName:(NSString *)iconName;
+ (NSString *)searchTextForIconName:(NSString *)iconName;
+ (BOOL)isInstagramBundleIconName:(NSString *)iconName;

@end

NS_ASSUME_NONNULL_END

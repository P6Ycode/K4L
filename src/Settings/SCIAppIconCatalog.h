#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIAppIconItem : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSArray<NSString *> *iconFiles;
@property (nonatomic) BOOL isPrimary;

@end

@interface SCIAppIconCatalog : NSObject

+ (NSArray<SCIAppIconItem *> *)availableAppIcons;
+ (nullable SCIAppIconItem *)currentAppIcon;
+ (NSString *)currentAppIconIdentifier;
+ (nullable SCIAppIconItem *)appIconWithIdentifier:(nullable NSString *)identifier;
+ (nullable UIImage *)imageForAppIcon:(SCIAppIconItem *)item;

@end

NS_ASSUME_NONNULL_END

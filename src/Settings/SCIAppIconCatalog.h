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

/// Persist the user's chosen icon so the picker stays accurate even when
/// UIApplication.alternateIconName reads nil on re-signed/injected builds.
+ (void)setStoredSelectedIdentifier:(nullable NSString *)identifier;

/// Applies the persisted icon selection to the live app icon when it differs
/// from what's currently active. Used after a settings import, where the pref
/// is restored but UIApplication still shows the old icon (otherwise the user
/// would have to re-pick the icon to actually apply it).
+ (void)applyStoredIconIfNeeded;

@end

NS_ASSUME_NONNULL_END

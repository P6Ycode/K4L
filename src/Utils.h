#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <objc/message.h>

#import "InstagramHeaders.h"
#import "Shared/MediaPreview/SCIFullScreenMediaPlayer.h"
#import "Shared/UI/SCINotificationCenter.h"

#import "Settings/SCISettingsViewController.h"

FOUNDATION_EXPORT void SCILogMessage(NSString *category,
                                     os_log_type_t type,
                                     NSString *format, ...) NS_FORMAT_FUNCTION(3, 4);

#define SCILog(category, fmt, ...) SCILogMessage((category), OS_LOG_TYPE_DEFAULT, (fmt), ##__VA_ARGS__)
#define SCIWarnLog(category, fmt, ...) SCILogMessage((category), OS_LOG_TYPE_ERROR, (fmt), ##__VA_ARGS__)
#define SCIErrorLog(category, fmt, ...) SCILogMessage((category), OS_LOG_TYPE_FAULT, (fmt), ##__VA_ARGS__)
#define SCILogId(category, obj) SCILog((category), @"%@", (obj))

/*
 *  System Versioning Preprocessor Macros
 */ 

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

@interface SCIUtils : NSObject

// Preferences
+ (BOOL)getBoolPref:(NSString *)key;
+ (double)getDoublePref:(NSString *)key;
+ (NSString *)getStringPref:(NSString *)key;

// Misc
+ (BOOL)tabOrderSetTo:(NSString *)ordering;
+ (NSString *)IGVersionString;
+ (BOOL)isNotch;

+ (BOOL)existingLongPressGestureRecognizerForView:(UIView *)view;

/// IGDSLauncherConfig hooks: when Liquid Glass is on, returns YES; otherwise returns `fallback` (stock).
+ (_Bool)sci_liquidGlassLauncherPrefKey:(NSString *)key orig:(_Bool)fallback;

typedef BOOL (*SCILiquidGlassBoolMsg)(id, SEL);
/// Runtime hooks: unset uses `orig`; when the pref exists and is on, returns YES.
+ (BOOL)sci_liquidGlassHookPrefKey:(NSString *)key orig:(SCILiquidGlassBoolMsg)orig selfPtr:(id)selfPtr sel:(SEL)sel;

/// True when any liquid-glass-related preference is explicitly enabled.
+ (BOOL)sci_anyLiquidGlassEnabled;

/// Calls Instagram navigation experiment override when the helper class exists.
+ (void)applyLiquidGlassNavigationExperimentOverride;

+ (void)cleanCache;
+ (NSString *)cacheAutoClearMode;
+ (BOOL)shouldAutomaticallyClearCacheNow;
+ (void)markCacheClearedNow;
+ (void)evaluateAutomaticCacheClearIfNeeded;

// Display View Controllers
+ (void)showMediaPreview:(NSURL *)fileURL;
+ (void)showShareVC:(id)item;
+ (void)showSettingsVC:(UIWindow *)window;
+ (void)showSettingsForTopicTitle:(NSString *)title;

// Colours
+ (UIColor *)SCIColor_Primary;
+ (UIColor *)SCIColor_InstagramBackground;
+ (UIColor *)SCIColor_InstagramSecondaryBackground;
+ (UIColor *)SCIColor_InstagramTertiaryBackground;
+ (UIColor *)SCIColor_InstagramGroupedBackground;
+ (UIColor *)SCIColor_InstagramPrimaryText;
+ (UIColor *)SCIColor_InstagramSecondaryText;
+ (UIColor *)SCIColor_InstagramTertiaryText;
+ (UIColor *)SCIColor_InstagramSeparator;
+ (UIColor *)SCIColor_InstagramFavorite;
+ (UIColor *)SCIColor_InstagramDestructive;
+ (UIColor *)SCIColor_InstagramPressedBackground;
+ (UIColor *)SCIColor_SettingsSwitchOnTint;
+ (UIColor *)SCIColor_SettingsSwitchThumbTint;
+ (UIColor *)SCIColor_SettingsSwitchOnTintForTraitCollection:(UITraitCollection *)traitCollection;
+ (UIColor *)SCIColor_SettingsSwitchThumbTintForTraitCollection:(UITraitCollection *)traitCollection;

// Errors
+ (NSError *)errorWithDescription:(NSString *)errorDesc;
+ (NSError *)errorWithDescription:(NSString *)errorDesc code:(NSInteger)errorCode;
+ (BOOL)openURL:(NSURL *)url;
+ (BOOL)openInstagramProfileForUsername:(NSString *)username;
+ (BOOL)openInstagramMediaURL:(NSURL *)url;
+ (BOOL)openPhotosApp;
+ (nullable NSURL *)sanitizedInstagramShareURL:(NSURL *)url;

// Media
+ (NSURL *)getPhotoUrl:(IGPhoto *)photo;
+ (NSURL *)getPhotoUrlForMedia:(IGMedia *)media;
+ (NSURL *)getBestProfilePictureURLForUser:(id)user;

+ (NSURL *)getVideoUrl:(IGVideo *)video;
+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media;

// View Controller Helpers
+ (UIViewController *)viewControllerForView:(UIView *)view;
+ (UIViewController *)viewControllerForAncestralView:(UIView *)view;
+ (UIViewController *)nearestViewControllerForView:(UIView *)view;

// Alerts
+ (BOOL)showConfirmation:(void(^)(void))okHandler title:(NSString *)title;
+ (BOOL)showConfirmation:(void(^)(void))okHandler title:(NSString *)title message:(NSString *)message;
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler title:(NSString *)title;
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler title:(NSString *)title message:(NSString *)message;
+ (BOOL)showConfirmation:(void(^)(void))okHandler;
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler;
+ (void)showRestartConfirmation;

// Math
+ (NSUInteger)decimalPlacesInDouble:(double)value;

// Dynamic selector helpers
+ (nullable NSNumber *)numericValueForObj:(id)obj selectorName:(NSString *)selectorName;

// Ivars
+ (id)getIvarForObj:(id)obj name:(const char *)name;
+ (void)setIvarForObj:(id)obj name:(const char *)name value:(id)value;

@end

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

/// Master toggle for per-account preferences (global, default off).
FOUNDATION_EXPORT NSString * const kSCIPrefPerAccountSettings;

/// Maps a preference key to the key actually stored/read. When per-account mode
/// is on and the key isn't forced-global, returns a `u_<accountPK>_<key>`
/// namespaced key; otherwise returns `key` unchanged. Writers MUST route through
/// this so reads and writes stay in sync.
FOUNDATION_EXPORT NSString *SCIEffectivePreferenceKey(NSString *key);

/// Namespaced NSUserDefaults access for code that reads/writes preferences
/// directly (not via getBoolPref:/getStringPref:/...). Applies the same
/// per-account → global inheritance as the accessors.
FOUNDATION_EXPORT id SCIPreferenceObjectForKey(NSString *key);
FOUNDATION_EXPORT void SCIPreferenceSetObject(id _Nullable value, NSString *key);

/// Canonical "per-account mode is active" gate: the global toggle is on AND an
/// account PK is resolved. Single source of truth for whether per-account scoping
/// applies (export prompt, gallery/downloads filtering, etc.).
FOUNDATION_EXPORT BOOL SCIPerAccountModeActive(void);

/// YES when `key` is forced device-global (app icon, appearance, tab layout, …) and
/// therefore never stored per-account. Used to decide what a per-account export carries.
FOUNDATION_EXPORT BOOL SCIPreferenceKeyIsGlobal(NSString *key);

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

// Session / user
// Active IG user session (walks connected scenes for the first window with a
// non-nil `userSession`).
+ (nullable id)activeUserSession;
// PK string read from an IGUser object's `_pk` ivar (walks the superclass chain).
+ (nullable NSString *)pkFromIGUser:(nullable id)user;
// Current logged-in user's PK via the active session, or nil when unavailable.
+ (nullable NSString *)currentUserPK;

+ (BOOL)existingLongPressGestureRecognizerForView:(UIView *)view;

/// IGDSLauncherConfig hooks: when Liquid Glass is on, returns YES; otherwise returns `fallback` (stock).
+ (_Bool)sci_liquidGlassLauncherPrefKey:(NSString *)key orig:(_Bool)fallback;

/// True when Liquid Glass is enabled and runtime suppression is inactive.
+ (BOOL)sci_isLiquidGlassEffectivelyEnabled;

+ (void)cleanCache;
+ (unsigned long long)cacheSizeBytes;
+ (NSString *)formattedCacheSize;
+ (NSString *)cacheAutoClearMode;
+ (BOOL)shouldAutomaticallyClearCacheNow;
+ (void)markCacheClearedNow;
+ (void)evaluateAutomaticCacheClearIfNeeded;

// Display View Controllers
+ (void)showMediaPreview:(NSURL *)fileURL;
+ (void)showShareVC:(id)item;
+ (void)showSettingsVC:(UIWindow *)window;
+ (void)showSettingsForTopicTitle:(NSString *)title;
+ (void)presentViewControllerInSheet:(UIViewController *)vc;

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
+ (UIColor *)SCIColor_ListRowPressedOverlay;
+ (UIColor *)SCIColor_SettingsSwitchOnTint;
+ (UIColor *)SCIColor_SettingsSwitchThumbTint;
+ (UIColor *)SCIColor_SettingsSwitchOnTintForTraitCollection:(UITraitCollection *)traitCollection;
+ (UIColor *)SCIColor_SettingsSwitchThumbTintForTraitCollection:(UITraitCollection *)traitCollection;

// Errors
+ (NSError *)errorWithDescription:(NSString *)errorDesc;
+ (NSError *)errorWithDescription:(NSString *)errorDesc code:(NSInteger)errorCode;
+ (BOOL)openURL:(NSURL *)url;
+ (void)dismissPresentedViewControllers;
+ (BOOL)openInstagramProfileForUsername:(NSString *)username;
+ (BOOL)openInstagramMediaURL:(NSURL *)url;
+ (BOOL)openPhotosApp;
+ (nullable NSURL *)sanitizedInstagramShareURL:(NSURL *)url;
+ (nullable NSString *)appendImgIndex:(NSInteger)imgIndex toURLString:(nullable NSString *)urlString;
+ (nullable NSString *)instagramShortcodeForMediaPK:(NSString *)mediaPK;

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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main thread when the active Instagram account changes (login,
/// logout, or in-app account switch). userInfo carries @"pk"/@"username" of the
/// new account when available.
FOUNDATION_EXPORT NSNotificationName const SPKAccountDidChangeNotification;

/// Tracks the currently logged-in Instagram account for per-account features
/// (gallery ownership, per-account preferences).
///
/// Resolving the active account walks the scene/window graph, which is too heavy
/// to do on every preference read, so the PK is cached and refreshed on app
/// foreground and at major surface entry points via -refreshCurrentAccount.
///
/// A roster of every account seen logged-in is persisted so pickers and filters
/// can show usernames (and let the user target an account they aren't currently
/// switched to) without depending on Instagram's private multi-account stores.
@interface SPKAccountManager : NSObject

+ (instancetype)shared;

/// Cached PK of the active account (nil when logged out / not yet resolved).
@property (class, nonatomic, readonly, nullable) NSString *currentAccountPK;

/// Cached username of the active account, when known.
@property (class, nonatomic, readonly, nullable) NSString *currentAccountUsername;

/// Re-resolves the active account from the live session. Posts
/// SPKAccountDidChangeNotification if it changed. Cheap to over-call.
- (void)refreshCurrentAccount;

/// Authoritatively sets the active account from an in-app account switch (the
/// switch target PK is known before the session finishes swapping). Updates the
/// cache immediately, posts SPKAccountDidChangeNotification, and fills the
/// username from the live session once it settles.
- (void)noteSwitchedToAccountPK:(nullable NSString *)pk;

/// Every account Sparkle has seen logged-in, newest-seen first.
/// Each entry: @{ @"pk": NSString, @"username": NSString (may be empty),
/// @"lastSeen": NSNumber }.
+ (NSArray<NSDictionary *> *)knownAccounts;

/// Display username for a PK from the roster (nil if unknown).
+ (nullable NSString *)usernameForPK:(nullable NSString *)pk;

@end

NS_ASSUME_NONNULL_END

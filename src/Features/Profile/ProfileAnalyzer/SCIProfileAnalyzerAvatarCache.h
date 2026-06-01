#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Two-tier profile-picture cache for the Profile Analyzer lists.
//
// • In-memory NSCache keyed by user PK for instant cell reuse.
// • On-disk store under Documents/SCInsta/ProfileAnalyzer/avatars/,
//   keyed by PK, refreshed at most once per TTL window (default 24h) so we never
//   hammer the CDN on every scroll. A stale-but-present blob is served
//   immediately while a refresh runs in the background.
//
// All callbacks are delivered on the main queue.
@interface SCIProfileAnalyzerAvatarCache : NSObject

+ (instancetype)shared;

// Returns an in-memory image immediately when warm, otherwise nil.
- (nullable UIImage *)cachedImageForPK:(NSString *)pk;

// Resolves an avatar for `pk`, loading from disk / network as needed. The
// completion fires with the best available image (may be nil). `urlString` is
// the last-known profile-pic URL; it is only hit when the on-disk copy is
// missing or older than the TTL.
- (void)avatarForPK:(NSString *)pk
          urlString:(nullable NSString *)urlString
         completion:(void (^)(UIImage *_Nullable image))completion;

// Drops all cached avatars (memory + disk). Used by the reset action.
- (void)purge;

// Total size (bytes) of the on-disk avatar cache.
- (unsigned long long)diskSizeBytes;

@end

NS_ASSUME_NONNULL_END

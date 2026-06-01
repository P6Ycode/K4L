#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Two-tier profile-picture cache for the deleted-messages log.
//
// • In-memory NSCache keyed by sender PK for instant cell reuse.
// • On-disk store under Documents/SCInsta/DeletedMessages/avatars/
//   keyed by PK, refreshed at most once per TTL window (default 24h) so we
//   never hammer the CDN on every scroll. A stale-but-present blob is served
//   immediately while a refresh runs in the background.
//
// All callbacks are delivered on the main queue.
@interface SCIDeletedMessagesAvatarCache : NSObject

+ (instancetype)shared;

// Returns an in-memory image immediately when warm, otherwise nil.
- (nullable UIImage *)cachedImageForPK:(NSString *)pk;

// Resolves an avatar for `pk`, loading from disk / network as needed. The
// completion fires once with the best available image (may be nil). `urlString`
// is the last-known profile-pic URL captured with the message; it is only hit
// when the on-disk copy is missing or older than the TTL.
- (void)avatarForPK:(NSString *)pk
          urlString:(nullable NSString *)urlString
         completion:(void (^)(UIImage *_Nullable image))completion;

// Drops all cached avatars (memory + disk). Used by the Storage screen.
- (void)purge;

// Total size (bytes) of the on-disk avatar cache — surfaced in Storage.
- (unsigned long long)diskSizeBytes;

@end

NS_ASSUME_NONNULL_END

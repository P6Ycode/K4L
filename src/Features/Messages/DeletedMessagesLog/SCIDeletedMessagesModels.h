#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIDeletedMessageKind) {
    SCIDeletedMessageKindUnknown = 0,
    SCIDeletedMessageKindText,
    SCIDeletedMessageKindPhoto,
    SCIDeletedMessageKindVideo,
    SCIDeletedMessageKindVoice,
    SCIDeletedMessageKindGif,
    SCIDeletedMessageKindSticker,
    SCIDeletedMessageKindShare,
    SCIDeletedMessageKindLink,
    SCIDeletedMessageKindAudioShare,
    SCIDeletedMessageKindReaction,
    SCIDeletedMessageKindOther,
};

FOUNDATION_EXPORT NSString *SCIDeletedMessageKindToString(SCIDeletedMessageKind kind);
FOUNDATION_EXPORT SCIDeletedMessageKind SCIDeletedMessageKindFromString(NSString * _Nullable s);
FOUNDATION_EXPORT NSString *SCIDeletedMessageKindLocalizedName(SCIDeletedMessageKind kind);
FOUNDATION_EXPORT NSString *SCIDeletedMessageKindSymbol(SCIDeletedMessageKind kind);
// Variant that returns the filled glyph for photo/video/voice/gif when
// `filled` is YES; other kinds are unaffected (they have no filled variant).
FOUNDATION_EXPORT NSString *SCIDeletedMessageKindSymbolFilled(SCIDeletedMessageKind kind, BOOL filled);

@interface SCIDeletedMessage : NSObject

@property (nonatomic, copy)   NSString *messageId;
@property (nonatomic, copy)   NSString *threadId;
@property (nonatomic, copy, nullable) NSString *threadTitle;
// YES when this message belongs to a group thread (captured from the open
// thread's metadata). Grouping also falls back to a multi-sender heuristic.
@property (nonatomic, assign) BOOL isGroup;
// Group's custom photo URL when one is set (else nil — group has no photo).
@property (nonatomic, copy, nullable) NSString *threadPhotoURL;

@property (nonatomic, copy)   NSString *senderPk;
@property (nonatomic, copy, nullable) NSString *senderUsername;
@property (nonatomic, copy, nullable) NSString *senderFullName;
@property (nonatomic, copy, nullable) NSString *senderProfilePicURL;

@property (nonatomic, strong) NSDate   *sentAt;
@property (nonatomic, strong) NSDate   *capturedAt;
@property (nonatomic, strong) NSDate   *deletedAt;

@property (nonatomic, assign) SCIDeletedMessageKind kind;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *previewText;

@property (nonatomic, copy, nullable) NSString *mediaURL;
@property (nonatomic, copy, nullable) NSString *mediaPath;       // relative under media root
@property (nonatomic, copy, nullable) NSString *thumbnailURL;
@property (nonatomic, copy, nullable) NSString *thumbnailPath;
@property (nonatomic, copy, nullable) NSString *mediaMimeType;
@property (nonatomic, assign) NSInteger viewMode;             // -1 when not ephemeral / unknown
@property (nonatomic, copy, nullable) NSString *stagedMediaPath;
@property (nonatomic, copy, nullable) NSString *stagedThumbnailPath;
@property (nonatomic, strong, nullable) NSDate *mediaURLStaleAt;

@property (nonatomic, assign) double   durationSeconds;          // voice/video
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *waveform;
@property (nonatomic, assign) CGFloat  width;
@property (nonatomic, assign) CGFloat  height;

// Server id of the message this one was a reply to (when applicable).
// Captured best-effort from metadata / KVC probes.
@property (nonatomic, copy, nullable) NSString *replyToMessageId;

// Reaction unsends only: the emoji that was removed, and a short preview of the
// message it was reacting to (when resolvable).
@property (nonatomic, copy, nullable) NSString *reactionEmoji;
@property (nonatomic, copy, nullable) NSString *reactionTargetPreview;

+ (instancetype)messageFromJSONDict:(NSDictionary *)dict;
- (NSDictionary *)toJSONDict;

@end

// Convenience aggregate built on read for the top VC. Represents either a single
// sender (1:1 chats, keyed by senderPk) or a whole group thread (keyed by
// threadId, isGroup == YES) where messages span several senders.
@interface SCIDeletedMessageGroup : NSObject
@property (nonatomic, copy) NSString *senderPk;
@property (nonatomic, copy, nullable) NSString *senderUsername;
@property (nonatomic, copy, nullable) NSString *senderFullName;
@property (nonatomic, copy, nullable) NSString *senderProfilePicURL;
@property (nonatomic, assign) BOOL isPinned;
@property (nonatomic, assign) BOOL isBlocked;
// Group-thread fields. isGroup distinguishes a thread-keyed entry from a
// sender-keyed one; threadTitle is the resolved (or generated) group name.
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy, nullable) NSString *threadId;
@property (nonatomic, copy, nullable) NSString *threadTitle;
@property (nonatomic, copy, nullable) NSString *threadPhotoURL;
@property (nonatomic, strong) NSArray<SCIDeletedMessage *> *messages; // newest-first
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly, nullable) NSDate *lastDeletedAt;
@property (nonatomic, readonly, nullable) SCIDeletedMessage *latest;
// User-facing title: group name for group threads, else @username / full name.
@property (nonatomic, readonly, copy) NSString *displayName;
// Stable identity used for pin/block flags and deletion. Namespaced for groups
// so a threadId can never collide with a sender PK.
@property (nonatomic, readonly, copy) NSString *flagKey;
@end

NS_ASSUME_NONNULL_END

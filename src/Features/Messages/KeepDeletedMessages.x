#import "../../Utils.h"
#import "../../AssetUtils.h"
#import "../../InstagramHeaders.h"
#import "../../Shared/Messages/SCIDirectSeenContext.h"
#import "../../Shared/Messages/SCIDirectUserResolver.h"
#import "../../Shared/UI/SCINotificationCenter.h"
#import "DeletedMessagesLog/SCIDeletedMessagesCapture.h"
#import "DeletedMessagesLog/SCIDeletedMessagesStorage.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// Keep deleted messages — blocks unsend removal only.
// Reason 0 = unsend, reason 2 = delete-for-you.
// Lighter version: no class-list scan, uses the known remove mutation processor.

#define SCI_SENDER_MAP_MAX		3000
#define SCI_CONTENT_MAP_MAX		2500
#define SCI_PRESERVED_MAX		200
#define SCI_UNSENT_TOAST_DEDUPE_MAX	200
#define SCI_UNSENT_TOAST_DEDUPE_TTL	5.0
#define SCI_PRESERVED_IDS_KEY	@"SCIPreservedMsgIdsByPk"
#define SCI_PRESERVED_LEGACY_KEY	@"SCIPreservedMsgIds"
#define SCI_PRESERVED_TAG		1399

static NSMutableDictionary<NSString *, NSDate *> *sciDeleteForYouKeys;
static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *sciPreservedByPk;
static NSMutableDictionary<NSString *, NSString *> *sciSenderPkBySid;
static NSMutableDictionary<NSString *, NSString *> *sciSenderNameBySid;
static NSMutableDictionary<NSString *, NSString *> *sciContentClassBySid;
static NSMutableDictionary<NSString *, NSNumber *> *sciSentByOwnerBySid;
static NSMutableSet<NSString *> *sciPendingLocalSids;
static NSMutableDictionary<NSString *, NSDate *> *sciUnsentToastDedupe;
// Reaction unsend previews collected during a single _applyThreadUpdates pass,
// drained by new_applyUpdates to fire reaction toasts.
static NSMutableArray<NSDictionary *> *sciPendingReactionPreviews;
static char kSCIPreservedIndicatorOwnMessageKey;
static char kSCIPreservedIndicatorStyleKey;

static void sciUpdateCellIndicator(id cell);

static inline BOOL sciKeepDeletedEnabled(void) { return [SCIUtils getBoolPref:@"msgs_keep_deleted"]; }
static inline BOOL sciDeletedLogEnabled(void) { return [SCIUtils getBoolPref:@"msgs_deleted_log"]; }
static inline BOOL sciIndicatorEnabled(void) { return sciKeepDeletedEnabled(); }
static inline BOOL sciReactionLogEnabled(void) { return [SCIUtils getBoolPref:@"msgs_deleted_log_reactions"]; }

static BOOL sciThreadBlockedBySeenList(NSString *threadId) {
	if (![SCIUtils getBoolPref:@"msgs_deleted_log_respect_seen_list"]) return NO;
	if (threadId.length == 0) return NO;
	return SCIDirectManualSeenListContainsThreadId(threadId, [SCIUtils getBoolPref:@"msgs_manual_seen"]);
}

static id sciIvar(id obj, const char *name) {
	if (!obj || !name) return nil;
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return nil;
	@try { return object_getIvar(obj, iv); } @catch (__unused id e) { return nil; }
}

static void sciSetIvar(id obj, const char *name, id value) {
	if (!obj || !name) return;
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return;
	@try { object_setIvar(obj, iv, value); } @catch (__unused id e) {}
}

static long long sciIntegerIvar(id obj, const char *name, long long fallback) {
	if (!obj || !name) return fallback;
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return fallback;
	@try {
		ptrdiff_t off = ivar_getOffset(iv);
		return *(long long *)((char *)(__bridge void *)obj + off);
	} @catch (__unused id e) {
		return fallback;
	}
}

static NSString *sciStringValue(id value) {
	if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] ? value : nil;
	if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
	return nil;
}

static NSString *sciFirstStringIvar(id obj, const char **names, int count) {
	for (int i = 0; i < count; i++) {
		NSString *s = sciStringValue(sciIvar(obj, names[i]));
		if (s.length) return s;
	}
	return nil;
}

static NSString *sciServerIdFromKey(id key) {
	static const char *names[] = {"_messageServerId", "_serverId"};
	return sciFirstStringIvar(key, names, 2);
}

static NSString *sciServerIdFromMetadata(id meta) {
	static const char *names[] = {"_serverId", "_messageServerId"};
	NSString *sid = sciFirstStringIvar(meta, names, 2);
	if (sid.length) return sid;
	return sciServerIdFromKey(sciIvar(meta, "_key"));
}

static NSString *sciServerIdFromMessage(id message) {
	NSString *sid = sciServerIdFromMetadata(sciIvar(message, "_metadata"));
	if (sid.length) return sid;
	return sciServerIdFromMetadata(message);
}

static NSString *sciSenderPkFromMessage(id message) {
	id meta = sciIvar(message, "_metadata");
	NSString *pk = sciStringValue(sciIvar(meta, "_senderPk"));
	return pk.length ? pk : sciStringValue(sciIvar(message, "_senderPk"));
}

static void sciTrimMap(NSMutableDictionary *map, NSUInteger max) {
	if (map.count <= max) return;
	NSArray *keys = map.allKeys;
	NSUInteger removeCount = MAX((NSUInteger)1, keys.count / 10);
	for (NSUInteger i = 0; i < removeCount && i < keys.count; i++) [map removeObjectForKey:keys[i]];
}

static NSMutableDictionary<NSString *, NSString *> *sciSenderMap(void) {
	if (!sciSenderPkBySid) sciSenderPkBySid = NSMutableDictionary.dictionary;
	return sciSenderPkBySid;
}

static NSMutableDictionary<NSString *, NSString *> *sciSenderNameMap(void) {
	if (!sciSenderNameBySid) sciSenderNameBySid = NSMutableDictionary.dictionary;
	return sciSenderNameBySid;
}

static NSMutableDictionary<NSString *, NSString *> *sciContentMap(void) {
	if (!sciContentClassBySid) sciContentClassBySid = NSMutableDictionary.dictionary;
	return sciContentClassBySid;
}

static NSMutableDictionary<NSString *, NSNumber *> *sciSentByOwnerMap(void) {
	if (!sciSentByOwnerBySid) sciSentByOwnerBySid = NSMutableDictionary.dictionary;
	return sciSentByOwnerBySid;
}

static NSMutableSet<NSString *> *sciPendingLocalSet(void) {
	if (!sciPendingLocalSids) sciPendingLocalSids = NSMutableSet.set;
	return sciPendingLocalSids;
}

static void sciTrackSenderPk(NSString *sid, NSString *pk) {
	if (!sid.length || !pk.length) return;
	NSMutableDictionary *m = sciSenderMap();
	m[sid] = pk;
	sciTrimMap(m, SCI_SENDER_MAP_MAX);
}

static void sciTrackSenderName(NSString *sid, NSString *name) {
	if (!sid.length || !name.length) return;
	NSMutableDictionary *m = sciSenderNameMap();
	m[sid] = name;
	sciTrimMap(m, SCI_SENDER_MAP_MAX);
}

static void sciTrackContentClass(NSString *sid, NSString *cls) {
	if (!sid.length || !cls.length) return;
	NSMutableDictionary *m = sciContentMap();
	m[sid] = cls;
	sciTrimMap(m, SCI_CONTENT_MAP_MAX);
}

static void sciTrackSentByOwner(NSString *sid, BOOL sentByOwner) {
	if (!sid.length) return;
	NSMutableDictionary *m = sciSentByOwnerMap();
	m[sid] = @(sentByOwner);
	sciTrimMap(m, SCI_SENDER_MAP_MAX);
}

static BOOL sciIsReactionOrActionLog(NSString *sid) {
	NSString *cls = sid.length ? sciContentMap()[sid] : nil;
	if (!cls.length) return NO;
	return [cls localizedCaseInsensitiveContainsString:@"reaction"] || [cls localizedCaseInsensitiveContainsString:@"actionlog"];
}

static NSString *sciUserPKFromObject(id user) {
	return sciDirectUserResolverPKFromUser(user);
}

static NSString *sciOwningPkFromApplicator(id applicator) {
	return sciUserPKFromObject(sciIvar(applicator, "_user"));
}

static NSString *sciUsernameFromUserObject(id user) {
	if (!user) return nil;
	@try {
		id fc = sciIvar(user, "_fieldCache");
		if ([fc isKindOfClass:NSDictionary.class]) {
			NSString *un = sciStringValue(fc[@"username"]);
			if (un.length) return un;
		}
	} @catch (__unused id e) {}
	@try {
		NSString *un = sciStringValue([user valueForKey:@"username"]);
		if (un.length) return un;
	} @catch (__unused id e) {}
	return nil;
}

static NSString *sciOwnerUsernameFromApplicator(id applicator) {
	return sciUsernameFromUserObject(sciIvar(applicator, "_user"));
}

static NSString *sciCurrentUserPk(void) {
	@try {
		for (UIWindow *w in UIApplication.sharedApplication.windows) {
			id session = nil;
			@try { session = [w valueForKey:@"userSession"]; } @catch (__unused id e) {}
			id user = nil;
			@try { user = [session valueForKey:@"user"]; } @catch (__unused id e) {}
			NSString *pk = sciUserPKFromObject(user);
			if (pk.length) return pk;
		}
	} @catch (__unused id e) {}
	return nil;
}

static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *sciPreservedStore(void) {
	if (sciPreservedByPk) return sciPreservedByPk;

	sciPreservedByPk = NSMutableDictionary.dictionary;
	NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:SCI_PRESERVED_IDS_KEY];

	if ([saved isKindOfClass:NSDictionary.class]) {
		for (NSString *pk in saved) {
			NSArray *arr = [saved[pk] isKindOfClass:NSArray.class] ? saved[pk] : nil;
			if (arr.count) sciPreservedByPk[pk] = [NSMutableSet setWithArray:arr];
		}
	}

	NSArray *legacy = [NSUserDefaults.standardUserDefaults arrayForKey:SCI_PRESERVED_LEGACY_KEY];
	NSString *currentPk = legacy.count ? sciCurrentUserPk() : nil;

	if (legacy.count && currentPk.length) {
		NSMutableSet *bucket = sciPreservedByPk[currentPk] ?: NSMutableSet.set;
		[bucket addObjectsFromArray:legacy];
		sciPreservedByPk[currentPk] = bucket;
		[NSUserDefaults.standardUserDefaults removeObjectForKey:SCI_PRESERVED_LEGACY_KEY];
	}

	return sciPreservedByPk;
}

static NSMutableSet<NSString *> *sciBucketForPk(NSString *pk) {
	if (!pk.length) return nil;
	NSMutableDictionary *store = sciPreservedStore();
	NSMutableSet *bucket = store[pk];
	if (!bucket) {
		bucket = NSMutableSet.set;
		store[pk] = bucket;
	}
	return bucket;
}

NSMutableSet *sciGetPreservedIds(void) {
	NSString *pk = sciCurrentUserPk();
	return pk.length ? sciBucketForPk(pk) : NSMutableSet.set;
}

static void sciSavePreservedIds(void) {
	NSMutableDictionary *out = NSMutableDictionary.dictionary;

	for (NSString *pk in sciPreservedStore()) {
		NSMutableSet *set = sciPreservedByPk[pk];
		while (set.count > SCI_PRESERVED_MAX) [set removeObject:set.anyObject];
		if (set.count) out[pk] = set.allObjects;
	}

	if (out.count) [NSUserDefaults.standardUserDefaults setObject:out forKey:SCI_PRESERVED_IDS_KEY];
	else [NSUserDefaults.standardUserDefaults removeObjectForKey:SCI_PRESERVED_IDS_KEY];
}

void sciClearPreservedIds(void) {
	NSString *pk = sciCurrentUserPk();
	if (!pk.length) return;
	[sciPreservedStore() removeObjectForKey:pk];
	sciSavePreservedIds();
}

static void sciPruneDeleteForYouKeys(void) {
	if (!sciDeleteForYouKeys.count) return;
	NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-10.0];
	for (NSString *sid in sciDeleteForYouKeys.allKeys) {
		if ([sciDeleteForYouKeys[sid] compare:cutoff] == NSOrderedAscending) [sciDeleteForYouKeys removeObjectForKey:sid];
	}
}

static void sciCaptureMessage(id message) {
	NSString *sid = sciServerIdFromMessage(message);
	if (!sid.length) return;

	NSString *pk = sciSenderPkFromMessage(message);
	if (pk.length) sciTrackSenderPk(sid, pk);

	sciTrackContentClass(sid, NSStringFromClass([message class]));
}

static void sciCaptureMessagesFromUpdate(id update, NSString *ownerPk, NSString *threadId, BOOL persistCandidates) {
	NSArray *inserts = sciIvar(update, "_insertMessages");
	if ([inserts isKindOfClass:NSArray.class]) {
		for (id m in inserts) {
			sciCaptureMessage(m);
			sciDMCaptureNoteInsert(m, ownerPk, threadId, persistCandidates);
		}
	}

	NSArray *replaces = sciIvar(update, "_replaceMessages_messages");
	if ([replaces isKindOfClass:NSArray.class]) {
		for (id m in replaces) {
			sciCaptureMessage(m);
			sciDMCaptureNoteInsert(m, ownerPk, threadId, persistCandidates);
		}
	}
}

static BOOL sciKeysContainPendingLocalSid(NSArray *keys) {
	NSMutableSet *pending = sciPendingLocalSet();

	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length && [pending containsObject:sid]) return YES;
	}

	return NO;
}

static void sciRemovePendingSidsForKeys(NSArray *keys) {
	NSMutableSet *pending = sciPendingLocalSet();

	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length) [pending removeObject:sid];
	}
}

static BOOL sciKeysContainDeleteForYouSid(NSArray *keys) {
	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length && sciDeleteForYouKeys[sid]) return YES;
	}
	return NO;
}

static void sciRemoveDeleteForYouSids(NSArray *keys) {
	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length) [sciDeleteForYouKeys removeObjectForKey:sid];
	}
}

static void sciTrackDeleteForYouKeys(NSArray *keys) {
	if (!sciDeleteForYouKeys) sciDeleteForYouKeys = NSMutableDictionary.dictionary;
	NSDate *now = NSDate.date;

	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length) sciDeleteForYouKeys[sid] = now;
	}
}

static BOOL sciReactionNotifyEnabled(void) {
	return SCINotificationIsEnabled(kSCINotificationUnsentReaction);
}

// Resolve the message a reaction targeted, for a preview. Best-effort: the
// in-memory weak cache, then the applicator's per-thread state.
static id sciReactionTargetMessage(NSString *messageId, id applicator, NSString *threadId) {
	if (!messageId.length) return nil;
	@try {
		Ivar iv = class_getInstanceVariable([applicator class], "_cache");
		id cache = iv ? object_getIvar(applicator, iv) : nil;
		SEL sel = NSSelectorFromString(@"threadClientStateForThreadId:");
		if (cache && threadId.length && [cache respondsToSelector:sel]) {
			id state = ((id(*)(id, SEL, id))objc_msgSend)(cache, sel, threadId);
			if (state) {
				for (Class c = [state class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
					Ivar di = class_getInstanceVariable(c, "_messagesByServerId");
					if (!di) continue;
					id dict = object_getIvar(state, di);
					if ([dict isKindOfClass:NSDictionary.class]) return ((NSDictionary *)dict)[messageId];
					break;
				}
			}
		}
	} @catch (__unused id e) {}
	return nil;
}

// Examine one content mutation; if it is an "unreact by another user" event,
// capture + collect a toast preview. Returns YES when a reaction was handled.
static BOOL sciHandleReactionMutation(id mutation, NSString *messageId, NSString *ownerPk, NSString *threadId, id applicator) {
	if (!mutation) return NO;

	// Only "unreact by other" — `_unreact_reaction` is set when someone removes
	// a reaction they placed. `_unreactSelf_reaction` is the owner's own removal.
	id reaction = sciIvar(mutation, "_unreact_reaction");
	if (!reaction) return NO;

	NSString *reactorPk = sciStringValue(sciIvar(mutation, "_unreact_userPk"));
	if (!reactorPk.length) reactorPk = sciStringValue(sciIvar(reaction, "_userBasedReaction_userId"));
	// Skip the owner removing their own reaction.
	if (reactorPk.length && ownerPk.length && [reactorPk isEqualToString:ownerPk]) return NO;
	if (reactorPk.length && [SCIDeletedMessagesStorage isSenderBlocked:reactorPk ownerPK:ownerPk]) return YES;

	BOOL logOn = sciReactionLogEnabled();
	BOOL notifyOn = sciReactionNotifyEnabled();
	if (!logOn && !notifyOn) return YES;

	id target = sciReactionTargetMessage(messageId, applicator, threadId);

	NSDictionary *info = nil;
	if (logOn) {
		info = sciDMCaptureNoteReactionUnsend(reaction, reactorPk, target, messageId, applicator, ownerPk, threadId);
	}
	if (notifyOn) {
		// Build a lightweight preview even when logging is off.
		NSMutableDictionary *preview = info ? [info mutableCopy] : [NSMutableDictionary dictionary];
		if (!preview[@"senderPk"] && reactorPk.length) preview[@"senderPk"] = reactorPk;
		if (!preview[@"emoji"]) {
			NSString *emoji = sciStringValue(sciIvar(reaction, "_userBasedReaction_emojiUnicode"));
			if (emoji.length) preview[@"emoji"] = emoji;
		}
		if (!preview[@"senderUsername"] && reactorPk.length) {
			NSString *uname = sciDirectUserResolverUsernameForPK(reactorPk);
			if (uname.length) preview[@"senderUsername"] = uname;
		}
		if (preview.count) {
			if (!sciPendingReactionPreviews) sciPendingReactionPreviews = NSMutableArray.array;
			[sciPendingReactionPreviews addObject:preview.copy];
		}
	}
	return YES;
}

static void sciProcessReactionMutations(id update, NSString *ownerPk, NSString *threadId, id applicator) {
	if (!update) return;
	if (!sciReactionLogEnabled() && !sciReactionNotifyEnabled()) return;

	// Single mutation.
	id singleMutation = sciIvar(update, "_mutateMessage_contentMutation");
	if (singleMutation) {
		NSString *mid = sciStringValue(sciIvar(update, "_mutateMessage_messageId"));
		sciHandleReactionMutation(singleMutation, mid, ownerPk, threadId, applicator);
	}

	// Multiple mutations — array of IGDirectMessageContentMutationPair (KVC).
	id multi = sciIvar(update, "_mutateMultipleMessages_contentMutations");
	if ([multi isKindOfClass:NSArray.class]) {
		for (id pair in (NSArray *)multi) {
			NSString *mid = nil;
			id mutation = nil;
			@try { mid = sciStringValue([pair valueForKey:@"messageId"]); } @catch (__unused id e) {}
			@try { mutation = [pair valueForKey:@"contentMutation"]; } @catch (__unused id e) {}
			if (mutation) sciHandleReactionMutation(mutation, mid, ownerPk, threadId, applicator);
		}
	}
}

static BOOL sciProcessMessageUpdate(id update, NSString *ownerPk, NSString *threadId, id applicator, NSMutableSet<NSString *> *preserved, NSMutableSet<NSString *> *detected, NSMutableArray<NSDictionary *> *previews, BOOL loggingAllowed) {
	if (!update || !ownerPk.length) return NO;

	sciCaptureMessagesFromUpdate(update, ownerPk, threadId, loggingAllowed && sciDeletedLogEnabled());
	if (loggingAllowed) sciProcessReactionMutations(update, ownerPk, threadId, applicator);

	NSArray *keys = sciIvar(update, "_removeMessages_messageKeys");
	if (![keys isKindOfClass:NSArray.class] || !keys.count) return NO;

	long long reason = sciIntegerIvar(update, "_removeMessages_reason", -1);

	if (reason == 2) {
		sciTrackDeleteForYouKeys(keys);
		return NO;
	}

	if (reason != 0) return NO;

	if (sciKeysContainPendingLocalSid(keys)) {
		sciRemovePendingSidsForKeys(keys);
		return NO;
	}

	if (sciKeysContainDeleteForYouSid(keys)) {
		sciRemoveDeleteForYouSids(keys);
		return NO;
	}

	NSMutableSet *bucket = sciBucketForPk(ownerPk);
	NSMutableArray *unsendKeys = NSMutableArray.array;
	BOOL keepOn = sciKeepDeletedEnabled();
	BOOL logOn = loggingAllowed && sciDeletedLogEnabled();
	BOOL didPreserve = NO;

	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (!sid.length) continue;
		BOOL reactionOrActionLog = sciIsReactionOrActionLog(sid);
		if (reactionOrActionLog && !sciReactionLogEnabled()) continue;
		NSString *senderPk = sciSenderMap()[sid];
		if (senderPk.length && [SCIDeletedMessagesStorage isSenderBlocked:senderPk ownerPK:ownerPk]) continue;
		if (senderPk.length) sciTrackSentByOwner(sid, [senderPk isEqualToString:ownerPk]);

		if (keepOn && !reactionOrActionLog) {
			if (bucket) [bucket addObject:sid];
			[preserved addObject:sid];
			didPreserve = YES;
		}
		if (loggingAllowed) [detected addObject:sid];
		[unsendKeys addObject:key];
	}

	if (!unsendKeys.count) return NO;

	if (loggingAllowed && previews) {
		NSArray *resolvedPreviews = sciDMCapturePreviewMetadataForKeys(unsendKeys, applicator, ownerPk, threadId);
		if (resolvedPreviews.count) [previews addObjectsFromArray:resolvedPreviews];
	}
	if (logOn) sciDMCaptureNoteRemoveKeys(unsendKeys, applicator, ownerPk, threadId);
	if (keepOn && didPreserve) sciSetIvar(update, "_removeMessages_messageKeys", nil);

	return keepOn && didPreserve;
}

static id sciMessageUpdateFromThreadUpdate(id threadUpdate) {
	id msg = sciIvar(threadUpdate, "_messageUpdate");
	if (msg) return msg;

	@try {
		msg = [threadUpdate valueForKey:@"messageUpdate"];
		if (msg) return msg;
	} @catch (__unused id e) {}

	return nil;
}

static NSString *sciThreadIdFromCacheUpdate(id cacheUpdate) {
	NSString *tid = nil;

	@try {
		tid = sciStringValue([cacheUpdate valueForKey:@"threadId"]);
		if (tid.length) return tid;
	} @catch (__unused id e) {}

	tid = sciStringValue(sciIvar(cacheUpdate, "_threadId"));
	if (tid.length) return tid;

	id threadUpdate = sciIvar(cacheUpdate, "_threadUpdate");
	tid = sciStringValue(sciIvar(threadUpdate, "_removeThread_threadId"));

	return tid;
}

static NSArray *sciThreadUpdatesFromCacheUpdate(id cacheUpdate) {
	@try {
		id updates = [cacheUpdate valueForKey:@"threadUpdates"];
		if ([updates isKindOfClass:NSArray.class]) return updates;
	} @catch (__unused id e) {}

	id single = sciIvar(cacheUpdate, "_threadUpdate");
	return single ? @[single] : nil;
}

static NSSet<NSString *> *sciProcessCacheUpdate(id cacheUpdate, NSString *ownerPk, id applicator, NSMutableSet<NSString *> *detected, NSMutableArray<NSDictionary *> *previews) {
	NSMutableSet *preserved = NSMutableSet.set;
	NSString *threadId = sciThreadIdFromCacheUpdate(cacheUpdate);

	if (!cacheUpdate || !threadId.length) return preserved;
	BOOL loggingAllowed = !sciThreadBlockedBySeenList(threadId);

	if (!sciDeleteForYouKeys) sciDeleteForYouKeys = NSMutableDictionary.dictionary;
	sciPruneDeleteForYouKeys();

	NSArray *threadUpdates = sciThreadUpdatesFromCacheUpdate(cacheUpdate);
	if (![threadUpdates isKindOfClass:NSArray.class]) return preserved;

	for (id tu in threadUpdates) {
		id msgUpdate = sciMessageUpdateFromThreadUpdate(tu);
		if (msgUpdate) sciProcessMessageUpdate(msgUpdate, ownerPk, threadId, applicator, preserved, detected, previews, loggingAllowed);
	}

	return preserved;
}

static NSString *sciUnsentText(NSString *sender, NSString *deleter) {
	if (sender.length && deleter.length) {
		return [sender isEqualToString:deleter]
			? [NSString stringWithFormat:@"%@ unsent a message", sender]
			: [NSString stringWithFormat:@"%@ unsent a message from %@", deleter, sender];
	}
	if (sender.length) return [NSString stringWithFormat:@"Message from %@ was unsent", sender];
	if (deleter.length) return [NSString stringWithFormat:@"%@ unsent a message", deleter];
	return @"A message was unsent";
}

static NSString *sciNotificationKindPhrase(SCIDeletedMessageKind kind) {
	switch (kind) {
		case SCIDeletedMessageKindPhoto: return @"photo";
		case SCIDeletedMessageKindVideo: return @"video";
		case SCIDeletedMessageKindVoice: return @"voice message";
		case SCIDeletedMessageKindGif: return @"GIF";
		case SCIDeletedMessageKindSticker: return @"sticker";
		case SCIDeletedMessageKindShare: return @"share";
		case SCIDeletedMessageKindLink: return @"link";
		case SCIDeletedMessageKindAudioShare: return @"music share";
		case SCIDeletedMessageKindText:
		case SCIDeletedMessageKindUnknown:
		case SCIDeletedMessageKindOther:
		default: return @"message";
	}
}

static NSString *sciTrimmedSingleLinePreview(NSString *text) {
	if (![text isKindOfClass:NSString.class]) return nil;
	NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!trimmed.length) return nil;
	trimmed = [trimmed stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
	while ([trimmed containsString:@"  "]) trimmed = [trimmed stringByReplacingOccurrencesOfString:@"  " withString:@" "];
	if (trimmed.length > 120) trimmed = [[trimmed substringToIndex:117] stringByAppendingString:@"..."];
	return trimmed;
}

static NSString *sciDisplayNameForPreview(NSDictionary *preview, NSString *fallback) {
	NSString *username = [preview[@"senderUsername"] isKindOfClass:NSString.class] ? preview[@"senderUsername"] : nil;
	if (username.length) return [username hasPrefix:@"@"] ? username : [@"@" stringByAppendingString:username];
	NSString *fullName = [preview[@"senderFullName"] isKindOfClass:NSString.class] ? preview[@"senderFullName"] : nil;
	if (fullName.length) return fullName;
	return fallback.length ? fallback : @"Someone";
}

static NSString *sciUnsentToastDedupeComponent(NSString *value) {
	if (![value isKindOfClass:NSString.class]) return @"";
	NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!trimmed.length) return @"";
	trimmed = [trimmed lowercaseString];
	if (trimmed.length > 160) trimmed = [trimmed substringToIndex:160];
	return trimmed;
}

static NSArray<NSString *> *sciUnsentToastDedupeKeys(NSDictionary *preview, NSString *fallbackSid, NSString *sender, SCIDeletedMessageKind kind, NSString *text) {
	NSMutableArray<NSString *> *keys = NSMutableArray.array;
	NSString *messageId = [preview[@"messageId"] isKindOfClass:NSString.class] ? preview[@"messageId"] : nil;
	if (!messageId.length) messageId = fallbackSid;
	NSString *threadId = [preview[@"threadId"] isKindOfClass:NSString.class] ? preview[@"threadId"] : nil;
	if (messageId.length) {
		NSString *cleanMessageId = sciUnsentToastDedupeComponent(messageId);
		[keys addObject:[NSString stringWithFormat:@"id|%@", cleanMessageId]];
		if (threadId.length) {
			[keys addObject:[NSString stringWithFormat:@"idthread|%@|%@", sciUnsentToastDedupeComponent(threadId), cleanMessageId]];
		}
		return keys;
	}
	[keys addObject:[NSString stringWithFormat:@"fallback|%ld|%@|%@",
		(long)kind,
		sciUnsentToastDedupeComponent(sender),
		sciUnsentToastDedupeComponent(text)]];
	return keys;
}

static BOOL sciShouldShowUnsentToast(NSArray<NSString *> *dedupeKeys) {
	if (!dedupeKeys.count) return YES;
	if (!sciUnsentToastDedupe) sciUnsentToastDedupe = NSMutableDictionary.dictionary;

	NSDate *now = NSDate.date;
	for (NSString *key in [sciUnsentToastDedupe.allKeys copy]) {
		NSDate *date = sciUnsentToastDedupe[key];
		if (![date isKindOfClass:NSDate.class] || [now timeIntervalSinceDate:date] > SCI_UNSENT_TOAST_DEDUPE_TTL) {
			[sciUnsentToastDedupe removeObjectForKey:key];
		}
	}

	for (NSString *dedupeKey in dedupeKeys) {
		NSDate *existing = sciUnsentToastDedupe[dedupeKey];
		if ([existing isKindOfClass:NSDate.class] && [now timeIntervalSinceDate:existing] <= SCI_UNSENT_TOAST_DEDUPE_TTL) {
			return NO;
		}
	}

	while (sciUnsentToastDedupe.count >= SCI_UNSENT_TOAST_DEDUPE_MAX) {
		NSString *oldestKey = nil;
		NSDate *oldestDate = nil;
		for (NSString *key in sciUnsentToastDedupe) {
			NSDate *date = sciUnsentToastDedupe[key];
			if (![date isKindOfClass:NSDate.class] || !oldestDate || [date compare:oldestDate] == NSOrderedAscending) {
				oldestDate = [date isKindOfClass:NSDate.class] ? date : nil;
				oldestKey = key;
			}
		}
		if (!oldestKey.length) break;
		[sciUnsentToastDedupe removeObjectForKey:oldestKey];
	}

	for (NSString *dedupeKey in dedupeKeys) {
		if (dedupeKey.length) sciUnsentToastDedupe[dedupeKey] = now;
	}
	return YES;
}

static void sciShowUnsentToast(NSDictionary *preview, NSString *fallbackSender, NSString *ownerAccount, NSString *fallbackSid) {
	NSString *sender = preview ? sciDisplayNameForPreview(preview, fallbackSender) : (fallbackSender.length ? fallbackSender : @"Someone");
	SCIDeletedMessageKind kind = [preview[@"kind"] isKindOfClass:NSNumber.class] ? (SCIDeletedMessageKind)[preview[@"kind"] integerValue] : SCIDeletedMessageKindUnknown;
	NSString *text = sciTrimmedSingleLinePreview(preview[@"previewText"] ?: preview[@"text"]);
	NSArray<NSString *> *dedupeKeys = sciUnsentToastDedupeKeys(preview, fallbackSid, sender, kind, text);
	if (!sciShouldShowUnsentToast(dedupeKeys)) return;
	NSString *kindPhrase = sciNotificationKindPhrase(kind);
	NSString *title = [NSString stringWithFormat:@"%@ unsent a %@", sender, kindPhrase];
	NSString *subtitle = text.length ? [NSString stringWithFormat:@"\"%@\"", text] : nil;
	if (ownerAccount.length) {
		subtitle = subtitle.length ? [NSString stringWithFormat:@"%@ · %@", title, subtitle] : title;
		title = ownerAccount;
	}
	SCINotify(kSCINotificationUnsentMessage, title, subtitle, @"undo_filled", SCINotificationToneInfo);
}

static void sciShowUnsentReactionToast(NSDictionary *preview, NSString *ownerAccount) {
	if (![preview isKindOfClass:NSDictionary.class]) return;
	NSString *sender = sciDisplayNameForPreview(preview, @"Someone");
	NSString *emoji = [preview[@"emoji"] isKindOfClass:NSString.class] ? preview[@"emoji"] : nil;
	NSString *targetPreview = sciTrimmedSingleLinePreview(preview[@"targetPreview"]);

	// Dedupe on sender + emoji + target so rapid duplicate deltas don't spam.
	NSString *dedupeKey = [NSString stringWithFormat:@"reaction|%@|%@|%@",
		sciUnsentToastDedupeComponent(sender),
		sciUnsentToastDedupeComponent(emoji),
		sciUnsentToastDedupeComponent(targetPreview)];
	if (!sciShouldShowUnsentToast(@[dedupeKey])) return;

	NSString *title = emoji.length
		? [NSString stringWithFormat:@"%@ removed a %@ reaction", sender, emoji]
		: [NSString stringWithFormat:@"%@ removed a reaction", sender];
	NSString *subtitle = targetPreview.length ? [NSString stringWithFormat:@"On \"%@\"", targetPreview] : nil;
	if (ownerAccount.length) {
		subtitle = subtitle.length ? [NSString stringWithFormat:@"%@ · %@", title, subtitle] : title;
		title = ownerAccount;
	}
	SCINotify(kSCINotificationUnsentReaction, title, subtitle, @"reactions", SCINotificationToneInfo);
}

static void sciRefreshVisibleCellIndicators(void) {
	if (!sciIndicatorEnabled()) return;

	Class cellClass = NSClassFromString(@"IGDirectMessageCell");
	UIWindow *window = UIApplication.sharedApplication.keyWindow;
	if (!cellClass || !window) return;

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];

	while (stack.count) {
		UIView *v = stack.lastObject;
		[stack removeLastObject];

		if ([v isKindOfClass:cellClass]) {
			sciUpdateCellIndicator(v);
			continue;
		}

		for (UIView *sub in v.subviews) [stack addObject:sub];
	}
}

static void sciHandleApplyUpdates(id self, id updates, void (^invokeOriginal)(void)) {
	sciDirectUserResolverSetActiveApplicator(self);

	BOOL keepOn = sciKeepDeletedEnabled();
	BOOL logOn = sciDeletedLogEnabled();
	BOOL toastOn = SCINotificationIsEnabled(kSCINotificationUnsentMessage);
	BOOL reactionOn = sciReactionLogEnabled() || SCINotificationIsEnabled(kSCINotificationUnsentReaction);

	if (!keepOn && !logOn && !toastOn && !reactionOn) {
		invokeOriginal();
		return;
	}

	NSString *ownerPk = sciOwningPkFromApplicator(self);
	if (logOn && ownerPk.length) sciDMCaptureRetryPendingRemovals(self, ownerPk);
	NSMutableSet *preserved = NSMutableSet.set;
	NSMutableSet *detected = NSMutableSet.set;
	NSMutableArray<NSDictionary *> *previews = NSMutableArray.array;

	// Reaction previews accumulate into a global during processing; reset so we
	// only fire toasts for this pass.
	sciPendingReactionPreviews = NSMutableArray.array;

	if (ownerPk.length && [updates isKindOfClass:NSArray.class]) {
		for (id update in (NSArray *)updates) {
			NSSet *set = sciProcessCacheUpdate(update, ownerPk, self, detected, previews);
			if (set.count) [preserved unionSet:set];
		}
	}

	if (preserved.count) sciSavePreservedIds();

	invokeOriginal();
	if (logOn && ownerPk.length) sciDMCaptureRetryPendingRemovals(self, ownerPk);

	NSArray<NSDictionary *> *reactionPreviews = sciPendingReactionPreviews.count ? [sciPendingReactionPreviews copy] : nil;
	sciPendingReactionPreviews = nil;

	if (!preserved.count && !detected.count && !reactionPreviews.count) return;

	NSString *sid = preserved.anyObject ?: detected.anyObject;
	NSString *senderName = sid.length ? sciSenderNameMap()[sid] : nil;
	NSString *senderPk = sid.length ? sciSenderMap()[sid] : nil;

	if (!senderName.length && senderPk.length) {
		senderName = sciDirectUserResolverUsernameForPK(senderPk);
		if (senderName.length) sciTrackSenderName(sid, senderName);
	}

	NSString *currentPk = sciCurrentUserPk();
	BOOL foreground = currentPk.length && [currentPk isEqualToString:ownerPk];
	NSString *ownerName = foreground ? nil : sciOwnerUsernameFromApplicator(self);

	dispatch_async(dispatch_get_main_queue(), ^{
		if (foreground) sciRefreshVisibleCellIndicators();
		if (toastOn && detected.count) {
			if (previews.count) {
				for (NSDictionary *preview in previews) sciShowUnsentToast(preview, senderName, ownerName, sid);
			} else {
				sciShowUnsentToast(nil, senderName, ownerName, sid);
			}
		}
		if (reactionPreviews.count) {
			for (NSDictionary *preview in reactionPreviews) sciShowUnsentReactionToast(preview, ownerName);
		}
	});
}

static void (*orig_applyUpdatesUserAccess)(id, SEL, id, id, id);
static void new_applyUpdatesUserAccess(id self, SEL _cmd, id updates, id completion, id userAccess) {
	sciHandleApplyUpdates(self, updates, ^{
		orig_applyUpdatesUserAccess(self, _cmd, updates, completion, userAccess);
	});
}

static void (*orig_applyUpdatesCompletion)(id, SEL, id, id);
static void new_applyUpdatesCompletion(id self, SEL _cmd, id updates, id completion) {
	sciHandleApplyUpdates(self, updates, ^{
		orig_applyUpdatesCompletion(self, _cmd, updates, completion);
	});
}

static void (*orig_applyUpdatesOnly)(id, SEL, id);
static void new_applyUpdatesOnly(id self, SEL _cmd, id updates) {
	sciHandleApplyUpdates(self, updates, ^{
		orig_applyUpdatesOnly(self, _cmd, updates);
	});
}

static void (*orig_removeMutationExecute)(id, SEL, id, id);
static void new_removeMutationExecute(id self, SEL _cmd, id handler, id pkg) {
	NSArray *keys = sciIvar(self, "_messageKeys");
	long long reason = sciIntegerIvar(self, "_reason", -1);

	if ([keys isKindOfClass:NSArray.class]) {
		if (reason == 2) {
			sciTrackDeleteForYouKeys(keys);
		} else if (reason != 0) {
			for (id key in keys) {
				NSString *sid = sciServerIdFromKey(key);
				if (sid.length) [sciPendingLocalSet() addObject:sid];
			}
		}
	}

	orig_removeMutationExecute(self, _cmd, handler, pkg);
}

static NSString *sciCellServerId(id cell) {
	id vm = sciIvar(cell, "_viewModel");

	if (!vm && [cell respondsToSelector:@selector(viewModel)]) {
		@try { vm = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(viewModel)); } @catch (__unused id e) {}
	}

	if (!vm) return nil;

	id meta = nil;
	SEL metaSel = NSSelectorFromString(@"messageMetadata");

	if ([vm respondsToSelector:metaSel]) {
		@try { meta = ((id (*)(id, SEL))objc_msgSend)(vm, metaSel); } @catch (__unused id e) {}
	}

	return sciServerIdFromMetadata(meta);
}

static BOOL sciCellIsPreserved(id cell) {
	NSString *sid = sciCellServerId(cell);
	return sid.length && [sciGetPreservedIds() containsObject:sid];
}

static BOOL sciCellSenderIsCurrentUser(id cell) {
	NSString *sid = sciCellServerId(cell);
	if (!sid.length) return NO;
	NSNumber *sentByOwner = sciSentByOwnerMap()[sid];
	if ([sentByOwner isKindOfClass:NSNumber.class]) return sentByOwner.boolValue;
	NSString *senderPk = sciSenderMap()[sid];
	NSString *currentPk = sciCurrentUserPk();
	return senderPk.length && currentPk.length && [senderPk isEqualToString:currentPk];
}

static UIView *sciAccessoryWrapper(UIView *view) {
	UIView *cur = view;

	while (cur && cur.superview) {
		CGSize s = cur.frame.size;
		if (s.width >= 32.0 && s.width <= 64.0 && fabs(s.width - s.height) < 6.0) return cur;
		cur = cur.superview;
	}

	return view;
}

static void sciSetTrailingAccessoriesHidden(id cell, BOOL hidden) {
	NSArray *views = sciIvar(cell, "_tappableAccessoryViews");
	if (![views isKindOfClass:NSArray.class]) return;

	for (UIView *v in views) {
		if (![v isKindOfClass:UIView.class]) continue;
		UIView *wrap = sciAccessoryWrapper(v);
		wrap.hidden = hidden;
		if (wrap != v) v.hidden = hidden;
	}
}

static CGRect sciMessageContentRectInHost(id cell, UIView *content, UIView *host) {
	if (!content || !host) return CGRectZero;
	CGRect rect = [host convertRect:content.bounds fromView:content];
	if (CGRectGetWidth(rect) > 1.0 && CGRectGetHeight(rect) > 1.0) return rect;

	CGSize size = CGSizeZero;
	if ([cell respondsToSelector:@selector(messageContentSize)]) {
		@try { size = ((CGSize (*)(id, SEL))objc_msgSend)(cell, @selector(messageContentSize)); } @catch (__unused id e) {}
	}
	if (size.width <= 1.0 || size.height <= 1.0) return rect;

	CGFloat xOffset = 0.0;
	Ivar ivar = class_getInstanceVariable([cell class], "_messageBubbleXOffset");
	if (ivar) {
		@try {
			ptrdiff_t off = ivar_getOffset(ivar);
			xOffset = *(double *)((char *)(__bridge void *)cell + off);
		} @catch (__unused id e) {}
	}

	CGRect hostBounds = host.bounds;
	CGFloat x = xOffset;
	if (x <= 0.0 || x > CGRectGetWidth(hostBounds)) x = CGRectGetMinX(rect);
	CGFloat y = CGRectGetMidY(rect) - (size.height / 2.0);
	if (!isfinite(y) || y < 0.0 || y > CGRectGetHeight(hostBounds)) y = CGRectGetMidY(hostBounds) - (size.height / 2.0);
	return CGRectMake(x, y, size.width, size.height);
}

static void sciPositionIndicatorBadge(UIView *badge, id cell, UIView *content, UIView *host, BOOL sentByCurrentUser) {
	if (!badge || !content || !host) return;
	CGRect contentRect = sciMessageContentRectInHost(cell, content, host);
	CGFloat frameSize = 44.0;
	CGFloat x = sentByCurrentUser ? CGRectGetMinX(contentRect) - frameSize : CGRectGetMaxX(contentRect);
	CGFloat y = CGRectGetMidY(contentRect) - (frameSize / 2.0);

	if (!isfinite(x) || !isfinite(y)) {
		badge.hidden = YES;
		return;
	}

	badge.hidden = NO;
	badge.frame = CGRectMake(x, y, frameSize, frameSize);
}

static void sciUpdateCellIndicator(id cell) {
	if (![cell isKindOfClass:UIView.class]) return;

	UIView *view = (UIView *)cell;
	UIView *old = [view viewWithTag:SCI_PRESERVED_TAG];

	if (!sciIndicatorEnabled()) {
		if (old) [old removeFromSuperview];
		sciSetTrailingAccessoriesHidden(cell, NO);
		return;
	}

	BOOL preserved = sciCellIsPreserved(cell);

	if (!preserved) {
		if (old) [old removeFromSuperview];
		sciSetTrailingAccessoriesHidden(cell, NO);
		return;
	}

	sciSetTrailingAccessoriesHidden(cell, YES);
	BOOL sentByCurrentUser = sciCellSenderIsCurrentUser(cell);
	NSNumber *oldDirection = old ? objc_getAssociatedObject(old, &kSCIPreservedIndicatorOwnMessageKey) : nil;
	NSString *oldStyle = old ? objc_getAssociatedObject(old, &kSCIPreservedIndicatorStyleKey) : nil;
	UIView *content = sciIvar(cell, "_messageContentContainerView") ?: view;
	UIView *host = nil;
	if ([cell isKindOfClass:UICollectionViewCell.class]) host = ((UICollectionViewCell *)cell).contentView;
	if (!host) host = view;

	if (old && [oldDirection isKindOfClass:NSNumber.class] && oldDirection.boolValue == sentByCurrentUser && [oldStyle isEqualToString:@"undo_filled_secondary_circle_44"] && old.superview == host) {
		sciPositionIndicatorBadge(old, cell, content, host, sentByCurrentUser);
		return;
	}
	if (old) [old removeFromSuperview];

	UIView *badge = UIView.new;
	badge.tag = SCI_PRESERVED_TAG;
	badge.backgroundColor = UIColor.clearColor;
	badge.accessibilityLabel = @"Unsent";
	badge.userInteractionEnabled = NO;
	objc_setAssociatedObject(badge, &kSCIPreservedIndicatorOwnMessageKey, @(sentByCurrentUser), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(badge, &kSCIPreservedIndicatorStyleKey, @"undo_filled_secondary_circle_44", OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	UIView *background = UIView.new;
	background.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
	background.layer.cornerRadius = 16.0;
	background.layer.masksToBounds = YES;
	background.translatesAutoresizingMaskIntoConstraints = NO;
	[badge addSubview:background];

	UIImageView *icon = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"undo_filled"
	                                                                               pointSize:16.0
	                                                                           renderingMode:UIImageRenderingModeAlwaysTemplate]];
	icon.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
	icon.contentMode = UIViewContentModeScaleAspectFit;
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	[background addSubview:icon];

	[host addSubview:badge];
	sciPositionIndicatorBadge(badge, cell, content, host, sentByCurrentUser);

	[NSLayoutConstraint activateConstraints:@[
		[background.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
		[background.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
		[background.widthAnchor constraintEqualToConstant:32.0],
		[background.heightAnchor constraintEqualToConstant:32.0],
		[icon.centerXAnchor constraintEqualToAnchor:background.centerXAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:background.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:16.0],
		[icon.heightAnchor constraintEqualToConstant:16.0],
	]];
}

static void (*orig_configureCell)(id, SEL, id, id, id);
static void new_configureCell(id self, SEL _cmd, id vm, id ringSpec, id launcherSet) {
	orig_configureCell(self, _cmd, vm, ringSpec, launcherSet);

	NSString *sid = sciCellServerId(self);
	if (sid.length) {
		id meta = nil;
		SEL metaSel = NSSelectorFromString(@"messageMetadata");

		if ([vm respondsToSelector:metaSel]) {
			@try { meta = ((id (*)(id, SEL))objc_msgSend)(vm, metaSel); } @catch (__unused id e) {}
		}

		NSString *pk = sciStringValue(sciIvar(meta, "_senderPk"));
		if (pk.length) {
			sciTrackSenderPk(sid, pk);
			NSString *currentPk = sciCurrentUserPk();
			if (currentPk.length) sciTrackSentByOwner(sid, [pk isEqualToString:currentPk]);
		}
	}

	sciUpdateCellIndicator(self);
}

static void (*orig_cellLayoutSubviews)(id, SEL);
static void new_cellLayoutSubviews(id self, SEL _cmd) {
	orig_cellLayoutSubviews(self, _cmd);
	if (sciIndicatorEnabled()) sciUpdateCellIndicator(self);
}

static void (*orig_addAccessory)(id, SEL, id);
static void new_addAccessory(id self, SEL _cmd, id view) {
	orig_addAccessory(self, _cmd, view);

	if (!sciIndicatorEnabled() || !sciCellIsPreserved(self) || ![view isKindOfClass:UIView.class]) return;

	UIView *wrap = sciAccessoryWrapper(view);
	wrap.hidden = YES;
	if (wrap != view) ((UIView *)view).hidden = YES;
}

static id (*orig_actionLogInit)(id, SEL, id, id, id, id, id, BOOL, BOOL, id);
static id new_actionLogInit(id self, SEL _cmd, id message, id title, id attrs, id parts, id type, BOOL collapsible, BOOL hidden, id genAI) {
	id result = orig_actionLogInit(self, _cmd, message, title, attrs, parts, type, collapsible, hidden, genAI);

	@try {
		SEL sel = @selector(messageId);
		if ([result respondsToSelector:sel]) {
			NSString *sid = sciStringValue(((id (*)(id, SEL))objc_msgSend)(result, sel));
			if (sid.length) sciTrackContentClass(sid, @"IGDirectThreadActionLog");
		}
	} @catch (__unused id e) {}

	return result;
}

static BOOL sciHook(Class cls, SEL sel, IMP imp, IMP *orig) {
	if (!cls || !class_getInstanceMethod(cls, sel)) return NO;
	MSHookMessageEx(cls, sel, imp, orig);
	return YES;
}

%ctor {
	Class cacheCls = NSClassFromString(@"IGDirectCacheUpdatesApplicator");
	if (!sciHook(cacheCls, NSSelectorFromString(@"_applyThreadUpdates:completion:userAccess:"), (IMP)new_applyUpdatesUserAccess, (IMP *)&orig_applyUpdatesUserAccess)
		&& !sciHook(cacheCls, NSSelectorFromString(@"_applyThreadUpdates:completion:"), (IMP)new_applyUpdatesCompletion, (IMP *)&orig_applyUpdatesCompletion)) {
		sciHook(cacheCls, NSSelectorFromString(@"_applyThreadUpdates:"), (IMP)new_applyUpdatesOnly, (IMP *)&orig_applyUpdatesOnly);
	}

	Class removeCls = NSClassFromString(@"IGDirectMessageOutgoingUpdateRemoveMessagesMutationProcessor");
	sciHook(removeCls, NSSelectorFromString(@"executeWithResultHandler:accessoryPackage:"), (IMP)new_removeMutationExecute, (IMP *)&orig_removeMutationExecute);

	Class cellCls = NSClassFromString(@"IGDirectMessageCell");
	sciHook(cellCls, NSSelectorFromString(@"configureWithViewModel:ringViewSpecFactory:launcherSet:"), (IMP)new_configureCell, (IMP *)&orig_configureCell);
	sciHook(cellCls, @selector(layoutSubviews), (IMP)new_cellLayoutSubviews, (IMP *)&orig_cellLayoutSubviews);
	sciHook(cellCls, NSSelectorFromString(@"_addTappableAccessoryView:"), (IMP)new_addAccessory, (IMP *)&orig_addAccessory);

	Class actionLogCls = NSClassFromString(@"IGDirectThreadActionLog");
	sciHook(actionLogCls, NSSelectorFromString(@"initWithMessage:title:textAttributes:textParts:actionLogType:collapsible:hidden:genAIMetadata:"), (IMP)new_actionLogInit, (IMP *)&orig_actionLogInit);

	if (!sciIndicatorEnabled()) {
		sciPreservedByPk = NSMutableDictionary.dictionary;
		[NSUserDefaults.standardUserDefaults removeObjectForKey:SCI_PRESERVED_IDS_KEY];
		[NSUserDefaults.standardUserDefaults removeObjectForKey:SCI_PRESERVED_LEGACY_KEY];
	}
}

void SCIInstallKeepDeletedMessagesHooksIfEnabled(void) {
	// Hooks are installed from %ctor so logging can observe inserts even when
	// keep-deleted itself is disabled.
}

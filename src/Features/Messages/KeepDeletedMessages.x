#import "../../Utils.h"
#import "../../AssetUtils.h"
#import "../../InstagramHeaders.h"
#import "../../Shared/Messages/SCIDirectSeenContext.h"
#import "../../Shared/Messages/SCIDirectUserResolver.h"
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
#define SCI_PRESERVED_IDS_KEY	@"SCIPreservedMsgIdsByPk"
#define SCI_PRESERVED_LEGACY_KEY	@"SCIPreservedMsgIds"
#define SCI_PRESERVED_TAG		1399

static NSMutableDictionary<NSString *, NSDate *> *sciDeleteForYouKeys;
static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *sciPreservedByPk;
static NSMutableDictionary<NSString *, NSString *> *sciSenderPkBySid;
static NSMutableDictionary<NSString *, NSString *> *sciSenderNameBySid;
static NSMutableDictionary<NSString *, NSString *> *sciContentClassBySid;
static NSMutableSet<NSString *> *sciPendingLocalSids;
static char kSCIPreservedIndicatorOwnMessageKey;

static void sciUpdateCellIndicator(id cell);

static inline BOOL sciKeepDeletedEnabled(void) { return [SCIUtils getBoolPref:@"msgs_keep_deleted"]; }
static inline BOOL sciDeletedLogEnabled(void) { return [SCIUtils getBoolPref:@"msgs_deleted_log"]; }
static inline BOOL sciIndicatorEnabled(void) { return [SCIUtils getBoolPref:@"msgs_indicate_unsent"]; }
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

static void sciCaptureMessagesFromUpdate(id update) {
	NSArray *inserts = sciIvar(update, "_insertMessages");
	if ([inserts isKindOfClass:NSArray.class]) {
		for (id m in inserts) {
			sciCaptureMessage(m);
			sciDMCaptureNoteInsert(m);
		}
	}

	NSArray *replaces = sciIvar(update, "_replaceMessages_messages");
	if ([replaces isKindOfClass:NSArray.class]) {
		for (id m in replaces) {
			sciCaptureMessage(m);
			sciDMCaptureNoteInsert(m);
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

static BOOL sciProcessMessageUpdate(id update, NSString *ownerPk, NSString *threadId, id applicator, NSMutableSet<NSString *> *preserved, NSMutableSet<NSString *> *detected, NSMutableArray<NSDictionary *> *previews) {
	if (!update || !ownerPk.length) return NO;

	sciCaptureMessagesFromUpdate(update);

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
	BOOL logOn = sciDeletedLogEnabled();
	BOOL didPreserve = NO;

	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (!sid.length) continue;
		BOOL reactionOrActionLog = sciIsReactionOrActionLog(sid);
		if (reactionOrActionLog && !sciReactionLogEnabled()) continue;
		NSString *senderPk = sciSenderMap()[sid];
		if (senderPk.length && [SCIDeletedMessagesStorage isSenderBlocked:senderPk ownerPK:ownerPk]) continue;

		if (keepOn && !reactionOrActionLog) {
			if (bucket) [bucket addObject:sid];
			[preserved addObject:sid];
			didPreserve = YES;
		}
		[detected addObject:sid];
		[unsendKeys addObject:key];
	}

	if (!unsendKeys.count) return NO;

	if (previews) {
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

	if (!cacheUpdate || !threadId.length || sciThreadBlockedBySeenList(threadId)) return preserved;

	if (!sciDeleteForYouKeys) sciDeleteForYouKeys = NSMutableDictionary.dictionary;
	sciPruneDeleteForYouKeys();

	NSArray *threadUpdates = sciThreadUpdatesFromCacheUpdate(cacheUpdate);
	if (![threadUpdates isKindOfClass:NSArray.class]) return preserved;

	for (id tu in threadUpdates) {
		id msgUpdate = sciMessageUpdateFromThreadUpdate(tu);
		if (msgUpdate) sciProcessMessageUpdate(msgUpdate, ownerPk, threadId, applicator, preserved, detected, previews);
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

static void sciShowUnsentToast(NSDictionary *preview, NSString *fallbackSender, NSString *ownerAccount) {
	NSString *sender = preview ? sciDisplayNameForPreview(preview, fallbackSender) : (fallbackSender.length ? fallbackSender : @"Someone");
	SCIDeletedMessageKind kind = [preview[@"kind"] isKindOfClass:NSNumber.class] ? (SCIDeletedMessageKind)[preview[@"kind"] integerValue] : SCIDeletedMessageKindUnknown;
	NSString *text = sciTrimmedSingleLinePreview(preview[@"previewText"] ?: preview[@"text"]);
	NSString *kindPhrase = sciNotificationKindPhrase(kind);
	NSString *title = [NSString stringWithFormat:@"%@ unsent %@", sender, kindPhrase];
	NSString *subtitle = text.length ? [NSString stringWithFormat:@"\"%@\"", text] : nil;
	if (ownerAccount.length) {
		subtitle = subtitle.length ? [NSString stringWithFormat:@"%@ · %@", title, subtitle] : title;
		title = ownerAccount;
	}
	SCINotify(kSCINotificationUnsentMessage, title, subtitle, @"xmark", SCINotificationToneError);
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

static void (*orig_applyUpdates)(id, SEL, id, id, id);
static void new_applyUpdates(id self, SEL _cmd, id updates, id completion, id userAccess) {
	sciDirectUserResolverSetActiveApplicator(self);

	BOOL keepOn = sciKeepDeletedEnabled();
	BOOL logOn = sciDeletedLogEnabled();
	BOOL toastOn = [SCIUtils getBoolPref:@"msgs_unsent_toast"];

	if (!keepOn && !logOn && !toastOn) {
		orig_applyUpdates(self, _cmd, updates, completion, userAccess);
		return;
	}

	NSString *ownerPk = sciOwningPkFromApplicator(self);
	NSMutableSet *preserved = NSMutableSet.set;
	NSMutableSet *detected = NSMutableSet.set;
	NSMutableArray<NSDictionary *> *previews = NSMutableArray.array;

	if (ownerPk.length && [updates isKindOfClass:NSArray.class]) {
		for (id update in (NSArray *)updates) {
			NSSet *set = sciProcessCacheUpdate(update, ownerPk, self, detected, previews);
			if (set.count) [preserved unionSet:set];
		}
	}

	if (preserved.count) sciSavePreservedIds();

	orig_applyUpdates(self, _cmd, updates, completion, userAccess);

	if (!preserved.count && !detected.count) return;

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
		if (toastOn) {
			if (previews.count) {
				for (NSDictionary *preview in previews) sciShowUnsentToast(preview, senderName, ownerName);
			} else {
				sciShowUnsentToast(nil, senderName, ownerName);
			}
		}
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
	if (old && [oldDirection isKindOfClass:NSNumber.class] && oldDirection.boolValue == sentByCurrentUser) return;
	if (old) [old removeFromSuperview];

	UIView *content = sciIvar(cell, "_messageContentContainerView") ?: view;

	UIView *badge = UIView.new;
	badge.tag = SCI_PRESERVED_TAG;
	badge.backgroundColor = [SCIUtils SCIColor_InstagramDestructive] ?: [SCIUtils SCIColor_InstagramPrimaryText];
	badge.layer.cornerRadius = 9.0;
	badge.layer.masksToBounds = YES;
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	badge.accessibilityLabel = @"Unsent";
	objc_setAssociatedObject(badge, &kSCIPreservedIndicatorOwnMessageKey, @(sentByCurrentUser), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	UIImageView *icon = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"xmark"
	                                                                               pointSize:9.0
	                                                                           renderingMode:UIImageRenderingModeAlwaysTemplate]];
	icon.tintColor = [SCIUtils SCIColor_InstagramBackground] ?: UIColor.whiteColor;
	icon.contentMode = UIViewContentModeScaleAspectFit;
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	[badge addSubview:icon];

	[view addSubview:badge];

	NSLayoutConstraint *horizontal = sentByCurrentUser
		? [badge.trailingAnchor constraintEqualToAnchor:content.leadingAnchor constant:-5.0]
		: [badge.leadingAnchor constraintEqualToAnchor:content.trailingAnchor constant:5.0];
	[NSLayoutConstraint activateConstraints:@[
		horizontal,
		[badge.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
		[badge.widthAnchor constraintEqualToConstant:18.0],
		[badge.heightAnchor constraintEqualToConstant:18.0],
		[icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:10.0],
		[icon.heightAnchor constraintEqualToConstant:10.0],
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
		if (pk.length) sciTrackSenderPk(sid, pk);
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

static void sciHook(Class cls, SEL sel, IMP imp, IMP *orig) {
	if (cls && class_getInstanceMethod(cls, sel)) MSHookMessageEx(cls, sel, imp, orig);
}

%ctor {
	Class cacheCls = NSClassFromString(@"IGDirectCacheUpdatesApplicator");
	sciHook(cacheCls, NSSelectorFromString(@"_applyThreadUpdates:completion:userAccess:"), (IMP)new_applyUpdates, (IMP *)&orig_applyUpdates);

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

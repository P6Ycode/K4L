#import "SCIDeletedMessagesStorage.h"
#import "../../../Shared/SCIStoragePaths.h"

NSNotificationName const SCIDeletedMessagesDidChangeNotification = @"SCIDeletedMessagesDidChangeNotification";

static NSString *const kSCIDMMediaDir   = @"media";
static NSString *const kSCIDMSenderFlagsFile = @"sender_flags.json";
static NSString *const kSCIDMPendingCandidatesDir = @"candidates";
static NSString *const kSCIDMPendingRemovalsDir = @"removals";

@implementation SCIDeletedMessagesStorage

#pragma mark - Plumbing

static dispatch_queue_t sciDMQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.scinsta.deletedmessages.io", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSString *sciSafePK(NSString *pk) {
    return pk.length ? pk : @"anon";
}

static NSString *sciStorageDir(void) {
    NSString *dir = [SCIStoragePaths deletedMessagesDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *sciMediaDirForOwner(NSString *pk) {
    NSString *dir = [[sciStorageDir() stringByAppendingPathComponent:kSCIDMMediaDir]
                     stringByAppendingPathComponent:sciSafePK(pk)];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *sciPendingStorageDir(void) {
    NSString *dir = [SCIStoragePaths deletedMessagesPendingDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *sciPendingSubdirectory(NSString *name) {
    NSString *dir = [sciPendingStorageDir() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *sciPendingJSONPath(NSString *directory, NSString *pk) {
    return [[sciPendingSubdirectory(directory) stringByAppendingPathComponent:sciSafePK(pk)]
            stringByAppendingPathExtension:@"json"];
}

static NSString *sciStagedMediaDirForOwner(NSString *pk) {
    NSString *dir = [[sciPendingStorageDir() stringByAppendingPathComponent:kSCIDMMediaDir]
                     stringByAppendingPathComponent:sciSafePK(pk)];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *sciJSONPathForOwner(NSString *pk) {
    return [sciStorageDir() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.json", sciSafePK(pk)]];
}

static NSString *sciFlagsPath(void) {
    return [sciStorageDir() stringByAppendingPathComponent:kSCIDMSenderFlagsFile];
}

static NSArray *sciReadArray(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @[];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSArray class]] ? obj : @[];
}

static BOOL sciWriteArray(NSString *path, NSArray *arr) {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:(arr ?: @[]) options:0 error:&err];
    if (!data) return NO;
    return [data writeToFile:path atomically:YES];
}

static NSMutableDictionary *sciReadDictionary(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return [NSMutableDictionary dictionary];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [obj isKindOfClass:[NSMutableDictionary class]] ? obj : [NSMutableDictionary dictionary];
}

static BOOL sciWriteDictionary(NSString *path, NSDictionary *dict) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:(dict ?: @{}) options:0 error:nil];
    return data ? [data writeToFile:path atomically:YES] : NO;
}

static unsigned long long sciDirectorySize(NSString *dir) {
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
    unsigned long long total = 0;
    for (NSString *rel in en) {
        NSDictionary *attrs = [en fileAttributes];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            total += [attrs[NSFileSize] unsignedLongLongValue];
        }
        (void)rel;
    }
    return total;
}

static NSMutableDictionary *sciReadFlags(void) {
    NSData *data = [NSData dataWithContentsOfFile:sciFlagsPath()];
    if (!data.length) return [NSMutableDictionary dictionary];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [obj isKindOfClass:[NSMutableDictionary class]] ? obj : [NSMutableDictionary dictionary];
}

static BOOL sciWriteFlags(NSDictionary *flags) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:(flags ?: @{}) options:0 error:nil];
    return data ? [data writeToFile:sciFlagsPath() atomically:YES] : NO;
}

static NSMutableDictionary *sciFlagsForOwner(NSMutableDictionary *flags, NSString *ownerPK, BOOL create) {
    NSString *owner = sciSafePK(ownerPK);
    id existing = flags[owner];
    if ([existing isKindOfClass:[NSMutableDictionary class]]) return existing;
    if ([existing isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *copy = [existing mutableCopy];
        flags[owner] = copy;
        return copy;
    }
    if (!create) return nil;
    NSMutableDictionary *ownerFlags = [NSMutableDictionary dictionary];
    flags[owner] = ownerFlags;
    return ownerFlags;
}

static NSDictionary *sciSenderFlags(NSString *senderPK, NSString *ownerPK) {
    if (!senderPK.length) return @{};
    __block NSDictionary *result = nil;
    dispatch_sync(sciDMQueue(), ^{
        NSMutableDictionary *flags = sciReadFlags();
        NSDictionary *ownerFlags = sciFlagsForOwner(flags, ownerPK, NO);
        id senderFlags = ownerFlags[senderPK];
        result = [senderFlags isKindOfClass:[NSDictionary class]] ? senderFlags : @{};
    });
    return result ?: @{};
}

static void sciPostChanged(NSString *ownerPK) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIDeletedMessagesDidChangeNotification
                                                            object:nil
                                                          userInfo:ownerPK.length ? @{@"owner_pk": ownerPK} : @{}];
    });
}

// Newest-first order. capturedAt is required; deletedAt is the truer key when present.
static NSDate *sciSortKey(SCIDeletedMessage *m) {
    return m.deletedAt ?: (m.capturedAt ?: m.sentAt);
}

static NSArray<SCIDeletedMessage *> *sciDecode(NSArray *raw) {
    NSMutableArray<SCIDeletedMessage *> *out = [NSMutableArray arrayWithCapacity:raw.count];
    for (id d in raw) {
        SCIDeletedMessage *m = [SCIDeletedMessage messageFromJSONDict:d];
        if (m) [out addObject:m];
    }
    return out;
}

static NSArray<NSDictionary *> *sciEncode(NSArray<SCIDeletedMessage *> *msgs) {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:msgs.count];
    for (SCIDeletedMessage *m in msgs) [out addObject:[m toJSONDict]];
    return out;
}

#pragma mark - Read

+ (NSArray<SCIDeletedMessage *> *)allMessagesForOwnerPK:(NSString *)ownerPK {
    __block NSArray<SCIDeletedMessage *> *result = nil;
    dispatch_sync(sciDMQueue(), ^{
        result = sciDecode(sciReadArray(sciJSONPathForOwner(ownerPK)));
    });
    return result ?: @[];
}

+ (NSArray<NSString *> *)allOwnerPKs {
    __block NSArray<NSString *> *owners = @[];
    dispatch_sync(sciDMQueue(), ^{
        NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:sciStorageDir() error:nil] ?: @[];
        NSMutableArray<NSString *> *result = [NSMutableArray array];
        for (NSString *file in files) {
            if (![file.pathExtension isEqualToString:@"json"]) continue;
            if ([file isEqualToString:kSCIDMSenderFlagsFile]) continue;
            NSString *owner = file.stringByDeletingPathExtension;
            if (owner.length) [result addObject:owner];
        }
        owners = [result copy];
    });
    return owners;
}

+ (NSArray<SCIDeletedMessage *> *)messagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (SCIDeletedMessage *m in [self allMessagesForOwnerPK:ownerPK]) {
        if ([m.senderPk isEqualToString:senderPK]) [out addObject:m];
    }
    return out;
}

+ (NSArray<SCIDeletedMessage *> *)messagesForThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK {
    if (!threadId.length) return @[];
    NSMutableArray<SCIDeletedMessage *> *out = [NSMutableArray array];
    for (SCIDeletedMessage *m in [self allMessagesForOwnerPK:ownerPK]) {
        if ([m.threadId isEqualToString:threadId]) [out addObject:m];
    }
    // Chronological by original send time (fall back to deletion time) so the
    // conversation reads top-to-bottom like a real chat.
    [out sortUsingComparator:^NSComparisonResult(SCIDeletedMessage *a, SCIDeletedMessage *b) {
        NSDate *da = a.sentAt ?: a.deletedAt ?: a.capturedAt ?: [NSDate distantPast];
        NSDate *db = b.sentAt ?: b.deletedAt ?: b.capturedAt ?: [NSDate distantPast];
        return [da compare:db];
    }];
    return out;
}

// Best display label for a sender, from any captured message by them. Prefer
// the full name (IG titles untitled groups with participant names, not handles).
static NSString *sciSenderLabel(SCIDeletedMessage *m) {
    if (m.senderFullName.length) return m.senderFullName;
    if (m.senderUsername.length) return [@"@" stringByAppendingString:m.senderUsername];
    return nil;
}

// Generated group title from the distinct non-owner sender labels — used when
// the real thread name wasn't captured (e.g. messages logged before the chat
// was opened with the tweak active).
static NSString *sciGeneratedGroupTitle(NSArray<SCIDeletedMessage *> *msgs, NSString *ownerPK) {
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (SCIDeletedMessage *m in msgs) {
        if (!m.senderPk.length || [m.senderPk isEqualToString:ownerPK]) continue;
        if ([seen containsObject:m.senderPk]) continue;
        [seen addObject:m.senderPk];
        NSString *label = sciSenderLabel(m);
        if (label.length) [labels addObject:label];
    }
    if (!labels.count) return @"Group chat";
    if (labels.count <= 3) return [labels componentsJoinedByString:@", "];
    NSArray *head = [labels subarrayWithRange:NSMakeRange(0, 3)];
    return [NSString stringWithFormat:@"%@ +%lu", [head componentsJoinedByString:@", "], (unsigned long)(labels.count - 3)];
}

+ (NSArray<SCIDeletedMessageGroup *> *)groupedForOwnerPK:(NSString *)ownerPK {
    NSArray<SCIDeletedMessage *> *all = [self allMessagesForOwnerPK:ownerPK];   // newest-first

    // First pass: per-thread aggregates that decide group-ness and title.
    NSMutableDictionary<NSString *, NSMutableArray<SCIDeletedMessage *> *> *byThread = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *nonOwnerSenders = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *flaggedGroupThreads = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSString *> *titleByThread = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *photoByThread = [NSMutableDictionary dictionary];
    for (SCIDeletedMessage *m in all) {
        NSString *tid = m.threadId;
        if (!tid.length) continue;
        NSMutableArray *list = byThread[tid];
        if (!list) { list = [NSMutableArray array]; byThread[tid] = list; }
        [list addObject:m];
        if (m.senderPk.length && ![m.senderPk isEqualToString:ownerPK]) {
            NSMutableSet *s = nonOwnerSenders[tid];
            if (!s) { s = [NSMutableSet set]; nonOwnerSenders[tid] = s; }
            [s addObject:m.senderPk];
        }
        if (m.isGroup) [flaggedGroupThreads addObject:tid];
        if (m.threadTitle.length && !titleByThread[tid]) titleByThread[tid] = m.threadTitle;
        if (m.threadPhotoURL.length && !photoByThread[tid]) photoByThread[tid] = m.threadPhotoURL;
    }

    NSMutableSet<NSString *> *groupThreads = [NSMutableSet set];
    for (NSString *tid in byThread) {
        if ([flaggedGroupThreads containsObject:tid] || nonOwnerSenders[tid].count >= 2) {
            [groupThreads addObject:tid];
        }
    }

    NSMutableArray<SCIDeletedMessageGroup *> *groups = [NSMutableArray array];

    // Group-thread entries — one per thread.
    for (NSString *tid in groupThreads) {
        NSArray<SCIDeletedMessage *> *msgs = byThread[tid];
        if (!msgs.count) continue;
        SCIDeletedMessageGroup *g = [SCIDeletedMessageGroup new];
        g.isGroup     = YES;
        g.threadId    = tid;
        g.threadTitle = titleByThread[tid].length ? titleByThread[tid] : sciGeneratedGroupTitle(msgs, ownerPK);
        g.threadPhotoURL = photoByThread[tid];
        g.messages    = msgs;
        NSDictionary *flags = sciSenderFlags(g.flagKey, ownerPK);
        g.isPinned    = [flags[@"pinned"] boolValue];
        g.isBlocked   = [flags[@"blocked"] boolValue];
        [groups addObject:g];
    }

    // 1:1 entries — bucket the rest by sender (legacy behaviour).
    NSMutableDictionary<NSString *, NSMutableArray<SCIDeletedMessage *> *> *byPk = [NSMutableDictionary dictionary];
    for (SCIDeletedMessage *m in all) {
        if (m.threadId.length && [groupThreads containsObject:m.threadId]) continue;
        if (!m.senderPk.length) continue;
        NSMutableArray *list = byPk[m.senderPk];
        if (!list) { list = [NSMutableArray array]; byPk[m.senderPk] = list; }
        [list addObject:m];
    }
    for (NSString *pk in byPk) {
        NSArray<SCIDeletedMessage *> *msgs = byPk[pk];
        SCIDeletedMessage *latest = msgs.firstObject;
        SCIDeletedMessageGroup *g = [SCIDeletedMessageGroup new];
        g.senderPk            = pk;
        g.senderUsername      = latest.senderUsername;
        g.senderFullName      = latest.senderFullName;
        g.senderProfilePicURL = latest.senderProfilePicURL;
        NSDictionary *flags   = sciSenderFlags(pk, ownerPK);
        g.isPinned            = [flags[@"pinned"] boolValue];
        g.isBlocked           = [flags[@"blocked"] boolValue];
        g.messages            = msgs;
        [groups addObject:g];
    }

    [groups sortUsingComparator:^NSComparisonResult(SCIDeletedMessageGroup *a, SCIDeletedMessageGroup *b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? NSOrderedAscending : NSOrderedDescending;
        NSDate *da = a.lastDeletedAt ?: [NSDate distantPast];
        NSDate *db = b.lastDeletedAt ?: [NSDate distantPast];
        return [db compare:da];
    }];
    return groups;
}

+ (NSArray<SCIDeletedMessageGroup *> *)groupedBySenderForOwnerPK:(NSString *)ownerPK {
    NSArray<SCIDeletedMessage *> *all = [self allMessagesForOwnerPK:ownerPK];
    NSMutableDictionary<NSString *, NSMutableArray<SCIDeletedMessage *> *> *byPk = [NSMutableDictionary dictionary];
    for (SCIDeletedMessage *m in all) {
        if (!m.senderPk.length) continue;
        NSMutableArray *list = byPk[m.senderPk];
        if (!list) { list = [NSMutableArray array]; byPk[m.senderPk] = list; }
        [list addObject:m];
    }

    NSMutableArray<SCIDeletedMessageGroup *> *groups = [NSMutableArray array];
    for (NSString *pk in byPk) {
        NSArray *msgs = byPk[pk];
        SCIDeletedMessage *latest = msgs.firstObject;   // already newest-first
        SCIDeletedMessageGroup *g = [SCIDeletedMessageGroup new];
        g.senderPk            = pk;
        g.senderUsername      = latest.senderUsername;
        g.senderFullName      = latest.senderFullName;
        g.senderProfilePicURL = latest.senderProfilePicURL;
        NSDictionary *flags   = sciSenderFlags(pk, ownerPK);
        g.isPinned            = [flags[@"pinned"] boolValue];
        g.isBlocked           = [flags[@"blocked"] boolValue];
        g.messages            = msgs;
        [groups addObject:g];
    }
    [groups sortUsingComparator:^NSComparisonResult(SCIDeletedMessageGroup *a, SCIDeletedMessageGroup *b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? NSOrderedAscending : NSOrderedDescending;
        NSDate *da = a.lastDeletedAt ?: [NSDate distantPast];
        NSDate *db = b.lastDeletedAt ?: [NSDate distantPast];
        return [db compare:da];
    }];
    return groups;
}

+ (SCIDeletedMessageGroup *)groupForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length) return nil;
    NSArray<SCIDeletedMessage *> *msgs = [self messagesForSenderPK:senderPK ownerPK:ownerPK];
    if (!msgs.count) return nil;
    SCIDeletedMessage *latest = msgs.firstObject;   // already newest-first
    SCIDeletedMessageGroup *g = [SCIDeletedMessageGroup new];
    g.senderPk            = senderPK;
    g.senderUsername      = latest.senderUsername;
    g.senderFullName      = latest.senderFullName;
    g.senderProfilePicURL = latest.senderProfilePicURL;
    NSDictionary *flags   = sciSenderFlags(senderPK, ownerPK);
    g.isPinned            = [flags[@"pinned"] boolValue];
    g.isBlocked           = [flags[@"blocked"] boolValue];
    g.messages            = msgs;
    return g;
}

+ (SCIDeletedMessageGroup *)groupForThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK {
    if (!threadId.length) return nil;
    NSArray<SCIDeletedMessage *> *all = [self allMessagesForOwnerPK:ownerPK];   // newest-first
    NSMutableArray<SCIDeletedMessage *> *msgs = [NSMutableArray array];
    NSMutableSet<NSString *> *nonOwner = [NSMutableSet set];
    BOOL flagged = NO;
    NSString *title = nil;
    NSString *photo = nil;
    NSString *fallbackSender = nil;
    for (SCIDeletedMessage *m in all) {
        if (![m.threadId isEqualToString:threadId]) continue;
        [msgs addObject:m];
        if (m.senderPk.length && ![m.senderPk isEqualToString:ownerPK]) [nonOwner addObject:m.senderPk];
        if (m.senderPk.length && !fallbackSender) fallbackSender = m.senderPk;
        if (m.isGroup) flagged = YES;
        if (m.threadTitle.length && !title) title = m.threadTitle;
        if (m.threadPhotoURL.length && !photo) photo = m.threadPhotoURL;
    }
    if (!msgs.count) return nil;

    if (flagged || nonOwner.count >= 2) {
        SCIDeletedMessageGroup *g = [SCIDeletedMessageGroup new];
        g.isGroup     = YES;
        g.threadId    = threadId;
        g.threadTitle = title.length ? title : sciGeneratedGroupTitle(msgs, ownerPK);
        g.threadPhotoURL = photo;
        g.messages    = msgs;
        NSDictionary *flags = sciSenderFlags(g.flagKey, ownerPK);
        g.isPinned    = [flags[@"pinned"] boolValue];
        g.isBlocked   = [flags[@"blocked"] boolValue];
        return g;
    }

    // 1:1 — prefer the non-owner sender, else whatever sender we have.
    NSString *senderPK = nonOwner.anyObject ?: fallbackSender;
    return senderPK.length ? [self groupForSenderPK:senderPK ownerPK:ownerPK] : nil;
}

#pragma mark - Write

+ (BOOL)saveMessage:(SCIDeletedMessage *)message forOwnerPK:(NSString *)ownerPK {
    if (!message.messageId.length) return NO;
    return [self saveMessages:@[message] forOwnerPK:ownerPK];
}

+ (BOOL)saveMessages:(NSArray<SCIDeletedMessage *> *)messages forOwnerPK:(NSString *)ownerPK {
    if (!messages.count) return NO;
    __block BOOL ok = NO;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciJSONPathForOwner(ownerPK);
        NSMutableArray<SCIDeletedMessage *> *cur = [sciDecode(sciReadArray(path)) mutableCopy];
        NSMutableSet<NSString *> *incomingIds = [NSMutableSet setWithCapacity:messages.count];
        NSMutableDictionary<NSString *, SCIDeletedMessage *> *existingById = [NSMutableDictionary dictionary];
        for (SCIDeletedMessage *m in cur) {
            if (m.messageId.length) existingById[m.messageId] = m;
        }
        for (SCIDeletedMessage *m in messages) {
            if (!m.messageId.length) continue;
            SCIDeletedMessage *existing = existingById[m.messageId];
            if (!m.mediaPath.length) m.mediaPath = existing.mediaPath;
            if (!m.thumbnailPath.length) m.thumbnailPath = existing.thumbnailPath;
            if (!m.mediaMimeType.length) m.mediaMimeType = existing.mediaMimeType;
            if (!m.stagedMediaPath.length) m.stagedMediaPath = existing.stagedMediaPath;
            if (!m.stagedThumbnailPath.length) m.stagedThumbnailPath = existing.stagedThumbnailPath;
            [incomingIds addObject:m.messageId];
        }
        // Drop any existing record for the incoming ids (replace semantics).
        NSMutableArray<SCIDeletedMessage *> *kept = [NSMutableArray arrayWithCapacity:cur.count];
        for (SCIDeletedMessage *m in cur) {
            if (![incomingIds containsObject:m.messageId]) [kept addObject:m];
        }
        [kept addObjectsFromArray:messages];
        [kept sortUsingComparator:^NSComparisonResult(SCIDeletedMessage *a, SCIDeletedMessage *b) {
            NSDate *da = sciSortKey(a) ?: [NSDate distantPast];
            NSDate *db = sciSortKey(b) ?: [NSDate distantPast];
            return [db compare:da];
        }];
        NSUInteger maxCount = 10000;
        if (kept.count > maxCount) {
            [kept removeObjectsInRange:NSMakeRange(maxCount, kept.count - maxCount)];
        }
        ok = sciWriteArray(path, sciEncode(kept));
    });
    if (ok) sciPostChanged(ownerPK);
    return ok;
}

+ (BOOL)applySenderInfo:(NSDictionary *)info
            forSenderPK:(NSString *)senderPK
                ownerPK:(NSString *)ownerPK {
    if (!senderPK.length || ![info isKindOfClass:[NSDictionary class]]) return NO;
    NSString *u  = [info[@"username"]        isKindOfClass:[NSString class]] ? info[@"username"]        : nil;
    NSString *fn = [info[@"full_name"]       isKindOfClass:[NSString class]] ? info[@"full_name"]       : nil;
    NSString *p  = [info[@"profile_pic_url"] isKindOfClass:[NSString class]] ? info[@"profile_pic_url"] : nil;
    if (!u.length && !fn.length && !p.length) return NO;

    __block BOOL touched = NO;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciJSONPathForOwner(ownerPK);
        NSMutableArray<SCIDeletedMessage *> *cur = [sciDecode(sciReadArray(path)) mutableCopy];
        for (SCIDeletedMessage *m in cur) {
            if (![m.senderPk isEqualToString:senderPK]) continue;
            if (u.length  && !m.senderUsername.length)        { m.senderUsername = u;        touched = YES; }
            if (fn.length && !m.senderFullName.length)        { m.senderFullName = fn;       touched = YES; }
            if (p.length  && !m.senderProfilePicURL.length)   { m.senderProfilePicURL = p;   touched = YES; }
        }
        if (touched) sciWriteArray(path, sciEncode(cur));
    });
    if (touched) sciPostChanged(ownerPK);
    return touched;
}

+ (BOOL)backfillThreadTitle:(NSString *)title
                    isGroup:(BOOL)isGroup
                   photoURL:(NSString *)photoURL
               forThreadId:(NSString *)threadId
                    ownerPK:(NSString *)ownerPK {
    if (!threadId.length) return NO;
    __block BOOL changed = NO;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciJSONPathForOwner(ownerPK);
        NSMutableArray<SCIDeletedMessage *> *cur = [sciDecode(sciReadArray(path)) mutableCopy];
        for (SCIDeletedMessage *m in cur) {
            if (![m.threadId isEqualToString:threadId]) continue;
            if (isGroup && !m.isGroup) { m.isGroup = YES; changed = YES; }
            if (title.length && ![m.threadTitle isEqualToString:title]) { m.threadTitle = title; changed = YES; }
            if (photoURL.length && ![m.threadPhotoURL isEqualToString:photoURL]) { m.threadPhotoURL = photoURL; changed = YES; }
        }
        if (changed) sciWriteArray(path, sciEncode(cur));
    });
    if (changed) sciPostChanged(ownerPK);
    return changed;
}

+ (BOOL)isSenderPinned:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    return [sciSenderFlags(senderPK, ownerPK)[@"pinned"] boolValue];
}

+ (BOOL)isSenderBlocked:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    return [sciSenderFlags(senderPK, ownerPK)[@"blocked"] boolValue];
}

+ (void)setSenderPinned:(BOOL)pinned senderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length) return;
    dispatch_sync(sciDMQueue(), ^{
        NSMutableDictionary *flags = sciReadFlags();
        NSMutableDictionary *ownerFlags = sciFlagsForOwner(flags, ownerPK, YES);
        NSMutableDictionary *senderFlags = [ownerFlags[senderPK] isKindOfClass:[NSMutableDictionary class]]
            ? ownerFlags[senderPK]
            : ([ownerFlags[senderPK] isKindOfClass:[NSDictionary class]] ? [ownerFlags[senderPK] mutableCopy] : [NSMutableDictionary dictionary]);
        senderFlags[@"pinned"] = @(pinned);
        ownerFlags[senderPK] = senderFlags;
        sciWriteFlags(flags);
    });
    sciPostChanged(ownerPK);
}

+ (void)setSenderBlocked:(BOOL)blocked senderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length) return;
    dispatch_sync(sciDMQueue(), ^{
        NSMutableDictionary *flags = sciReadFlags();
        NSMutableDictionary *ownerFlags = sciFlagsForOwner(flags, ownerPK, YES);
        NSMutableDictionary *senderFlags = [ownerFlags[senderPK] isKindOfClass:[NSMutableDictionary class]]
            ? ownerFlags[senderPK]
            : ([ownerFlags[senderPK] isKindOfClass:[NSDictionary class]] ? [ownerFlags[senderPK] mutableCopy] : [NSMutableDictionary dictionary]);
        senderFlags[@"blocked"] = @(blocked);
        ownerFlags[senderPK] = senderFlags;
        sciWriteFlags(flags);
    });
    sciPostChanged(ownerPK);
}

+ (void)deleteMessageId:(NSString *)messageId forOwnerPK:(NSString *)ownerPK {
    if (!messageId.length) return;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciJSONPathForOwner(ownerPK);
        NSMutableArray<SCIDeletedMessage *> *cur = [sciDecode(sciReadArray(path)) mutableCopy];
        NSMutableArray<SCIDeletedMessage *> *kept = [NSMutableArray arrayWithCapacity:cur.count];
        for (SCIDeletedMessage *m in cur) {
            if ([m.messageId isEqualToString:messageId]) {
                if (m.mediaPath.length) {
                    [[NSFileManager defaultManager] removeItemAtPath:
                        [sciMediaDirForOwner(ownerPK) stringByAppendingPathComponent:m.mediaPath.lastPathComponent]
                        error:nil];
                }
                if (m.thumbnailPath.length) {
                    [[NSFileManager defaultManager] removeItemAtPath:
                        [sciMediaDirForOwner(ownerPK) stringByAppendingPathComponent:m.thumbnailPath.lastPathComponent]
                        error:nil];
                }
                continue;
            }
            [kept addObject:m];
        }
        sciWriteArray(path, sciEncode(kept));
    });
    sciPostChanged(ownerPK);
}

+ (void)deleteMessagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length) return;
    NSArray *toDrop = [self messagesForSenderPK:senderPK ownerPK:ownerPK];
    for (SCIDeletedMessage *m in toDrop) {
        [self deleteMessageId:m.messageId forOwnerPK:ownerPK];
    }
}

+ (void)deleteMessagesForThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK {
    if (!threadId.length) return;
    NSArray *toDrop = [self messagesForThreadId:threadId ownerPK:ownerPK];
    for (SCIDeletedMessage *m in toDrop) {
        [self deleteMessageId:m.messageId forOwnerPK:ownerPK];
    }
}

+ (void)resetForOwnerPK:(NSString *)ownerPK {
    dispatch_sync(sciDMQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:sciJSONPathForOwner(ownerPK) error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:sciMediaDirForOwner(ownerPK) error:nil];
        NSMutableDictionary *flags = sciReadFlags();
        [flags removeObjectForKey:sciSafePK(ownerPK)];
        sciWriteFlags(flags);
    });
    sciPostChanged(ownerPK);
}

+ (void)resetAll {
    dispatch_sync(sciDMQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:sciStorageDir() error:nil];
    });
    sciPostChanged(nil);
}

#pragma mark - Media

+ (NSString *)absolutePathForRelativePath:(NSString *)relativePath ownerPK:(NSString *)ownerPK {
    if (!relativePath.length) return nil;
    return [sciMediaDirForOwner(ownerPK) stringByAppendingPathComponent:relativePath.lastPathComponent];
}

+ (NSString *)reserveRelativeMediaPathForMessageId:(NSString *)messageId
                                         extension:(NSString *)ext
                                           ownerPK:(NSString *)ownerPK {
    NSString *safeId = [messageId stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *cleanExt = ext.length ? ([ext hasPrefix:@"."] ? [ext substringFromIndex:1] : ext) : @"bin";
    NSString *fname = [NSString stringWithFormat:@"%@.%@", safeId, cleanExt];
    // Touch the dir so callers can write straight away.
    (void)sciMediaDirForOwner(ownerPK);
    return fname;
}

+ (unsigned long long)mediaSizeBytesForOwnerPK:(NSString *)ownerPK {
    return sciDirectorySize(sciMediaDirForOwner(ownerPK));
}

#pragma mark - Pending reconciliation and media recovery cache

+ (BOOL)savePendingCandidateSnapshot:(NSDictionary *)snapshot forOwnerPK:(NSString *)ownerPK {
    NSString *messageId = [snapshot[@"message_id"] isKindOfClass:[NSString class]] ? snapshot[@"message_id"] : nil;
    if (!messageId.length) return NO;
    __block BOOL ok = NO;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciPendingJSONPath(kSCIDMPendingCandidatesDir, ownerPK);
        NSMutableDictionary *all = sciReadDictionary(path);
        NSMutableDictionary *merged = [all[messageId] isKindOfClass:[NSDictionary class]]
            ? [all[messageId] mutableCopy] : [NSMutableDictionary dictionary];
        [merged addEntriesFromDictionary:snapshot];
        all[messageId] = merged;
        ok = sciWriteDictionary(path, all);
    });
    return ok;
}

+ (NSDictionary *)pendingCandidateSnapshotForMessageId:(NSString *)messageId ownerPK:(NSString *)ownerPK {
    if (!messageId.length) return nil;
    __block NSDictionary *result = nil;
    dispatch_sync(sciDMQueue(), ^{
        id candidate = sciReadDictionary(sciPendingJSONPath(kSCIDMPendingCandidatesDir, ownerPK))[messageId];
        if ([candidate isKindOfClass:[NSDictionary class]]) result = [candidate copy];
    });
    return result;
}

+ (BOOL)patchPendingCandidateForMessageId:(NSString *)messageId values:(NSDictionary *)values ownerPK:(NSString *)ownerPK {
    if (!messageId.length || !values.count) return NO;
    __block BOOL ok = NO;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciPendingJSONPath(kSCIDMPendingCandidatesDir, ownerPK);
        NSMutableDictionary *all = sciReadDictionary(path);
        NSMutableDictionary *candidate = [all[messageId] isKindOfClass:[NSDictionary class]]
            ? [all[messageId] mutableCopy] : nil;
        if (!candidate) return;
        BOOL stagesMedia = values[@"staged_media_path"] != nil || values[@"staged_thumbnail_path"] != nil;
        if (stagesMedia && [candidate[@"staging_disabled"] boolValue]) return;
        [candidate addEntriesFromDictionary:values];
        all[messageId] = candidate;
        ok = sciWriteDictionary(path, all);
    });
    return ok;
}

+ (void)removePendingCandidateForMessageId:(NSString *)messageId ownerPK:(NSString *)ownerPK {
    if (!messageId.length) return;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciPendingJSONPath(kSCIDMPendingCandidatesDir, ownerPK);
        NSMutableDictionary *all = sciReadDictionary(path);
        [all removeObjectForKey:messageId];
        sciWriteDictionary(path, all);
    });
}

+ (BOOL)savePendingRemovalForMessageId:(NSString *)messageId
                              threadId:(NSString *)threadId
                            mutationId:(NSString *)mutationId
                               ownerPK:(NSString *)ownerPK {
    if (!messageId.length) return NO;
    __block BOOL ok = NO;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciPendingJSONPath(kSCIDMPendingRemovalsDir, ownerPK);
        NSMutableDictionary *all = sciReadDictionary(path);
        NSMutableDictionary *entry = [all[messageId] isKindOfClass:[NSDictionary class]]
            ? [all[messageId] mutableCopy] : [NSMutableDictionary dictionary];
        entry[@"message_id"] = messageId;
        if (threadId.length) entry[@"thread_id"] = threadId;
        if (mutationId.length) entry[@"mutation_id"] = mutationId;
        if (!entry[@"created_at"]) entry[@"created_at"] = @([NSDate date].timeIntervalSince1970);
        all[messageId] = entry;
        ok = sciWriteDictionary(path, all);
    });
    return ok;
}

+ (NSArray<NSDictionary *> *)pendingRemovalsForOwnerPK:(NSString *)ownerPK {
    __block NSArray *result = nil;
    dispatch_sync(sciDMQueue(), ^{
        result = [sciReadDictionary(sciPendingJSONPath(kSCIDMPendingRemovalsDir, ownerPK)).allValues copy];
    });
    return result ?: @[];
}

+ (void)removePendingRemovalForMessageId:(NSString *)messageId ownerPK:(NSString *)ownerPK {
    if (!messageId.length) return;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciPendingJSONPath(kSCIDMPendingRemovalsDir, ownerPK);
        NSMutableDictionary *all = sciReadDictionary(path);
        [all removeObjectForKey:messageId];
        sciWriteDictionary(path, all);
    });
}

+ (NSString *)reserveRelativeStagedMediaPathForMessageId:(NSString *)messageId
                                                extension:(NSString *)ext
                                                   ownerPK:(NSString *)ownerPK
                                                 thumbnail:(BOOL)thumbnail {
    NSString *safeId = [messageId stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *cleanExt = ext.length ? ([ext hasPrefix:@"."] ? [ext substringFromIndex:1] : ext) : @"bin";
    (void)sciStagedMediaDirForOwner(ownerPK);
    return [NSString stringWithFormat:@"%@%@.%@", thumbnail ? @"thumb_" : @"", safeId, cleanExt];
}

+ (NSString *)absoluteStagedPathForRelativePath:(NSString *)relativePath ownerPK:(NSString *)ownerPK {
    if (!relativePath.length) return nil;
    return [sciStagedMediaDirForOwner(ownerPK) stringByAppendingPathComponent:relativePath.lastPathComponent];
}

+ (NSString *)promoteStagedRelativePath:(NSString *)relativePath
                               messageId:(NSString *)messageId
                                 ownerPK:(NSString *)ownerPK
                               thumbnail:(BOOL)thumbnail {
    if (!relativePath.length || !messageId.length) return nil;
    NSString *source = [self absoluteStagedPathForRelativePath:relativePath ownerPK:ownerPK];
    if (![[NSFileManager defaultManager] fileExistsAtPath:source]) return nil;
    NSString *baseId = thumbnail ? [@"thumb_" stringByAppendingString:messageId] : messageId;
    NSString *destinationRel = [self reserveRelativeMediaPathForMessageId:baseId extension:relativePath.pathExtension ownerPK:ownerPK];
    NSString *destination = [self absolutePathForRelativePath:destinationRel ownerPK:ownerPK];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:destination]) {
        if (![fm moveItemAtPath:source toPath:destination error:nil]) return nil;
    } else {
        [fm removeItemAtPath:source error:nil];
    }
    return destinationRel;
}

+ (unsigned long long)stagedMediaSizeBytesForOwnerPK:(NSString *)ownerPK {
    return sciDirectorySize(sciStagedMediaDirForOwner(ownerPK));
}

+ (void)clearStagedMediaForOwnerPK:(NSString *)ownerPK {
    dispatch_sync(sciDMQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:sciStagedMediaDirForOwner(ownerPK) error:nil];
        NSString *path = sciPendingJSONPath(kSCIDMPendingCandidatesDir, ownerPK);
        NSMutableDictionary *all = sciReadDictionary(path);
        for (NSString *key in all.allKeys) {
            NSMutableDictionary *candidate = [all[key] mutableCopy];
            [candidate removeObjectForKey:@"staged_media_path"];
            [candidate removeObjectForKey:@"staged_thumbnail_path"];
            candidate[@"staging_disabled"] = @YES;
            all[key] = candidate;
        }
        sciWriteDictionary(path, all);
    });
    sciPostChanged(ownerPK);
}

+ (NSString *)storageRootPath {
    return sciStorageDir();
}

+ (BOOL)replaceStorageWithDirectoryAtPath:(NSString *)sourcePath error:(NSError **)error {
    if (sourcePath.length == 0) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *destination = sciStorageDir();
    if ([fm fileExistsAtPath:destination] && ![fm removeItemAtPath:destination error:error]) {
        return NO;
    }
    NSString *parent = [destination stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL copied = [fm copyItemAtPath:sourcePath toPath:destination error:error];
    if (copied) sciPostChanged(nil);
    return copied;
}

@end

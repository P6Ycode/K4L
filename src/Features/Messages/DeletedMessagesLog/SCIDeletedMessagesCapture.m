#import "SCIDeletedMessagesCapture.h"
#import "SCIDeletedMessagesModels.h"
#import "SCIDeletedMessagesStorage.h"
#import "../../../Shared/Messages/SCIDirectUserResolver.h"
#import "../../../Shared/Messages/SCIDirectSeenContext.h"
#import "../../../Utils.h"
#import "../../../Shared/MediaDownload/SCIDashParser.h"
#import "../../../Shared/MediaDownload/SCIMediaFFmpeg.h"
#import "../../../Shared/MediaPreview/SCIImageFormat.h"
#import <objc/runtime.h>

#pragma mark - Lazy weak-ref cache

// Stash a weak ref at insert; on unsend, promote to strong and snapshot.
// Aged-out messages fall back to a `_messagesByServerId` read.

static NSMapTable *sciMessageRefs(void) {
    static NSMapTable *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory|NSPointerFunctionsObjectPersonality
                                  valueOptions:NSPointerFunctionsWeakMemory  |NSPointerFunctionsObjectPersonality];
    });
    return t;
}

static NSObject *sciMessageRefsLock(void) {
    static NSObject *o;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ o = [NSObject new]; });
    return o;
}

static dispatch_queue_t sciCaptureQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.scinsta.deletedmessages.capture", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static dispatch_queue_t sciDownloadQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.scinsta.deletedmessages.download", DISPATCH_QUEUE_CONCURRENT);
    });
    return q;
}

static NSURLSession *sciSharedSession(void) {
    static NSURLSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 30;
        cfg.timeoutIntervalForResource = 120;
        cfg.HTTPMaximumConnectionsPerHost = 4;
        s = [NSURLSession sessionWithConfiguration:cfg];
    });
    return s;
}

static BOOL sciCaptureEnabled(void) {
    return [SCIUtils getBoolPref:@"msgs_deleted_log"];
}

static SCIDashRepresentation *sciBestDashRepresentation(NSArray<SCIDashRepresentation *> *reps, BOOL video) {
    SCIDashRepresentation *best = nil;
    for (SCIDashRepresentation *rep in reps) {
        NSString *type = rep.contentType.lowercaseString ?: @"";
        BOOL isVideo = [type containsString:@"video"] || rep.width > 0 || rep.height > 0;
        BOOL isAudio = [type containsString:@"audio"] || (!isVideo && rep.url != nil);
        if (video ? !isVideo : !isAudio) continue;
        if (!best) {
            best = rep;
            continue;
        }
        NSInteger area = rep.width * rep.height;
        NSInteger bestArea = best.width * best.height;
        if (video) {
            if (area > bestArea || (area == bestArea && rep.bandwidth > best.bandwidth)) best = rep;
        } else if (rep.bandwidth > best.bandwidth) {
            best = rep;
        }
    }
    return best;
}

#pragma mark - Ivar / selector helpers

static NSString *sciStrIvar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Ivar iv = NULL;
    for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, name);
    if (!iv) return nil;
    @try {
        id v = object_getIvar(obj, iv);
        return [v isKindOfClass:[NSString class]] ? v : nil;
    } @catch (__unused id e) { return nil; }
}

static id sciAnyIvar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Ivar iv = NULL;
    for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, name);
    if (!iv) return nil;
    @try { return object_getIvar(obj, iv); } @catch (__unused id e) { return nil; }
}

static double sciDoubleSelector(id obj, NSString *selName) {
    if (!obj) return 0;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return 0;
    @try {
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        const char *rt = sig.methodReturnType;
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.target = obj; inv.selector = sel;
        [inv invoke];
        if (strcmp(rt, "d") == 0) { double r;     [inv getReturnValue:&r]; return r; }
        if (strcmp(rt, "f") == 0) { float  r;     [inv getReturnValue:&r]; return (double)r; }
        if (strcmp(rt, "q") == 0) { long long r;  [inv getReturnValue:&r]; return (double)r; }
        if (strcmp(rt, "i") == 0) { int    r;     [inv getReturnValue:&r]; return (double)r; }
    } @catch (__unused id e) {}
    return 0;
}

// Filter out NSObject's `<ClassName: 0xaddr>` description fallback.
static BOOL sciIsDescriptionFallback(NSString *s) {
    if (!s.length) return NO;
    return [s hasPrefix:@"<"] && [s containsString:@": 0x"] && [s hasSuffix:@">"];
}

static NSString *sciTryStringSelectors(id obj, NSArray<NSString *> *names) {
    if (!obj) return nil;
    for (NSString *n in names) {
        SEL s = NSSelectorFromString(n);
        if (![obj respondsToSelector:s]) continue;
        @try {
            id v = ((id(*)(id, SEL))objc_msgSend)(obj, s);
            NSString *str = nil;
            if ([v isKindOfClass:[NSString class]])           str = v;
            else if ([v isKindOfClass:[NSAttributedString class]]) str = [(NSAttributedString *)v string];
            if (!str.length || sciIsDescriptionFallback(str)) continue;
            return str;
        } @catch (__unused id e) {}
    }
    return nil;
}

static NSString *sciTryURLSelectors(id obj, NSArray<NSString *> *names) {
    if (!obj) return nil;
    for (NSString *n in names) {
        SEL s = NSSelectorFromString(n);
        if (![obj respondsToSelector:s]) continue;
        @try {
            id v = ((id(*)(id, SEL))objc_msgSend)(obj, s);
            if ([v isKindOfClass:[NSURL class]]) {
                NSString *str = [(NSURL *)v absoluteString];
                if (str.length) return str;
            }
            if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
        } @catch (__unused id e) {}
    }
    return nil;
}

static id sciTryObjectSelector(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    @try { return ((id(*)(id, SEL))objc_msgSend)(obj, sel); }
    @catch (__unused id e) { return nil; }
}

static BOOL sciBoolSelector(id obj, NSString *name, BOOL *found) {
    if (found) *found = NO;
    SEL sel = NSSelectorFromString(name);
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    @try {
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        if (!sig) return NO;
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.target = obj; inv.selector = sel;
        [inv invoke];
        BOOL value = NO;
        [inv getReturnValue:&value];
        if (found) *found = YES;
        return value;
    } @catch (__unused id e) { return NO; }
}

static BOOL sciBoolIvar(id obj, const char *name, BOOL *found) {
    if (found) *found = NO;
    if (!obj || !name) return NO;
    Ivar iv = NULL;
    for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, name);
    if (!iv) return NO;
    const char *type = ivar_getTypeEncoding(iv);
    if (!type || (type[0] != 'B' && type[0] != 'c')) return NO;
    @try {
        BOOL value = *(BOOL *)((uint8_t *)(__bridge void *)obj + ivar_getOffset(iv));
        if (found) *found = YES;
        return value;
    } @catch (__unused id e) { return NO; }
}

static BOOL sciSemanticIsSticker(id obj, BOOL *found) {
    BOOL value = sciBoolSelector(obj, @"isSticker", found);
    if (found && *found) return value;
    return sciBoolIvar(obj, "_isSticker", found);
}

static NSString *sciURLStringValue(id value) {
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value absoluteString];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value length] ? value : nil;
    return nil;
}

static id sciFindObjectWithClassNamesRecursive(id obj, NSSet<NSString *> *classNames, int depth,
                                               NSMutableSet<NSValue *> *visited) {
    if (!obj || depth < 0) return nil;
    if ([classNames containsObject:NSStringFromClass([obj class])]) return obj;
    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]
        || [obj isKindOfClass:[NSDate class]] || [obj isKindOfClass:[NSURL class]]) return nil;
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)obj) {
            id found = sciFindObjectWithClassNamesRecursive(value, classNames, depth - 1, visited);
            if (found) return found;
        }
        return nil;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id value in [(NSDictionary *)obj allValues]) {
            id found = sciFindObjectWithClassNamesRecursive(value, classNames, depth - 1, visited);
            if (found) return found;
        }
        return nil;
    }
    NSValue *box = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:box]) return nil;
    [visited addObject:box];
    for (Class c = [obj class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(c, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            id value = nil;
            @try { value = object_getIvar(obj, ivars[i]); } @catch (__unused id e) {}
            id found = sciFindObjectWithClassNamesRecursive(value, classNames, depth - 1, visited);
            if (found) { free(ivars); return found; }
        }
        if (ivars) free(ivars);
    }
    return nil;
}

static id sciFindObjectWithClassNames(id obj, NSArray<NSString *> *classNames, int depth) {
    return sciFindObjectWithClassNamesRecursive(obj, [NSSet setWithArray:classNames], depth, [NSMutableSet set]);
}

static NSString *sciGiphyMediaURL(id giphy) {
    id imageModels = sciTryObjectSelector(giphy, @"imageModels");
    if (![imageModels isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *configName in @[@"webpConfig", @"gifConfig", @"mp4Config"]) {
        for (id imageModel in [(NSDictionary *)imageModels allValues]) {
            id config = sciTryObjectSelector(imageModel, configName);
            NSString *url = sciURLStringValue(sciTryObjectSelector(config, @"url"));
            if (url.length) return url;
        }
    }
    return nil;
}

static NSString *sciStickerMediaURL(id sticker) {
    id store = sciAnyIvar(sticker, "_storeSticker");
    id facebook = sciAnyIvar(sticker, "_fbSticker");
    for (NSString *selector in @[@"animatedPreviewImageURL", @"imageURL", @"fallbackImageURL",
                                  @"staticPreviewImageURL", @"url"]) {
        NSString *url = sciURLStringValue(sciTryObjectSelector(store ?: facebook, selector));
        if (url.length) return url;
    }
    return nil;
}

static NSDate *sciDateFromSnapshotValue(id value) {
    if ([value isKindOfClass:[NSDate class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
    return nil;
}

static NSDictionary *sciJSONSafeSnapshot(NSDictionary *snapshot) {
    NSMutableDictionary *safe = [NSMutableDictionary dictionaryWithCapacity:snapshot.count];
    for (NSString *key in snapshot) {
        id value = snapshot[key];
        if ([value isKindOfClass:[NSDate class]]) value = @([(NSDate *)value timeIntervalSince1970]);
        if (value) safe[key] = value;
    }
    NSString *sid = safe[@"sid"];
    if (sid.length) safe[@"message_id"] = sid;
    return safe;
}

#pragma mark - URL scanner (recursive, scored)

static void sciScanForURLsRecursive(id obj, int depth,
                                     NSString **outMedia, int *mediaScore,
                                     NSString **outThumb, int *thumbScore,
                                     NSString *parentName) {
    if (!obj || depth < 0) return;
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)obj;
        BOOL urlShaped = NO;
        for (NSString *p in @[@"http://", @"https://", @"instagram://",
                              @"fb://", @"fbthreads://", @"intent://"]) {
            if ([s hasPrefix:p]) { urlShaped = YES; break; }
        }
        if (!urlShaped) return;

        NSString *n = parentName ?: @"";
        BOOL thumbHint = [n containsString:@"thumb"] || [n containsString:@"preview"]
                       || [n containsString:@"poster"] || [n containsString:@"cover"];
        BOOL mediaHint = [n containsString:@"playable"] || [n containsString:@"video"]
                       || [n containsString:@"audio"]   || [n containsString:@"voice"]
                       || [n containsString:@"asset"]   || [n containsString:@"download"]
                       || [n containsString:@"src"]     || [n containsString:@"url"];
        BOOL imageHint = [n containsString:@"image"] || [n containsString:@"photo"];

        int score = 1;
        if (mediaHint) score = 4;
        if (imageHint) score = thumbHint ? 2 : 3;
        if (thumbHint) {
            if (score > *thumbScore) { *thumbScore = score; *outThumb = s; }
        } else {
            if (score > *mediaScore) { *mediaScore = score; *outMedia = s; }
        }
        return;
    }
    if ([obj isKindOfClass:[NSURL class]]) {
        NSString *s = [(NSURL *)obj absoluteString];
        if (s.length) sciScanForURLsRecursive(s, depth, outMedia, mediaScore, outThumb, thumbScore, parentName);
        return;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) sciScanForURLsRecursive(e, depth - 1, outMedia, mediaScore, outThumb, thumbScore, parentName);
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        for (id k in d) {
            id v = d[k];
            NSString *kn = [k isKindOfClass:[NSString class]] ? (NSString *)k : parentName;
            sciScanForURLsRecursive(v, depth - 1, outMedia, mediaScore, outThumb, thumbScore, kn);
        }
        return;
    }
    Class cls = [obj class];
    NSString *cn = NSStringFromClass(cls);
    if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"]
        || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"]) return;
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Ivar *list = class_copyIvarList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            const char *type = ivar_getTypeEncoding(list[i]);
            if (!type || type[0] != '@') continue;
            const char *name = ivar_getName(list[i]);
            id v = nil;
            @try { v = object_getIvar(obj, list[i]); } @catch (__unused id e) {}
            if (!v) continue;
            NSString *nameStr = name ? @(name) : parentName;
            sciScanForURLsRecursive(v, depth - 1, outMedia, mediaScore, outThumb, thumbScore, nameStr);
        }
        if (list) free(list);
    }
}

#pragma mark - Token-based kind classifier

static void sciCollectIvarNames(id obj, int depth, NSMutableSet *visited, NSMutableSet<NSString *> *out) {
    if (!obj || depth < 0) return;
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) sciCollectIvarNames(e, depth - 1, visited, out);
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        for (id k in d) {
            if ([k isKindOfClass:[NSString class]]) [out addObject:[(NSString *)k lowercaseString]];
            sciCollectIvarNames(d[k], depth - 1, visited, out);
        }
        return;
    }
    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]
        || [obj isKindOfClass:[NSDate class]] || [obj isKindOfClass:[NSURL class]]) return;
    NSValue *box = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:box]) return;
    [visited addObject:box];
    Class cls = [obj class];
    NSString *cn = NSStringFromClass(cls);
    if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"]
        || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"]) return;
    [out addObject:cn.lowercaseString];
    // Only object-typed ivars holding values — IG declares every variant slot up-front, most nil.
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Ivar *list = class_copyIvarList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            const char *name = ivar_getName(list[i]);
            const char *type = ivar_getTypeEncoding(list[i]);
            if (!type || type[0] != '@') continue;
            id v = nil;
            @try { v = object_getIvar(obj, list[i]); } @catch (__unused id e) {}
            if (!v) continue;
            if (name) [out addObject:[@(name) lowercaseString]];
            sciCollectIvarNames(v, depth - 1, visited, out);
        }
        if (list) free(list);
    }
}

static BOOL sciSetContainsAny(NSSet<NSString *> *set, NSArray<NSString *> *needles) {
    for (NSString *n in needles) {
        for (NSString *tok in set) if ([tok containsString:n]) return YES;
    }
    return NO;
}

#pragma mark - Sender / metadata extraction

static NSString *sciSidFromMessage(id m) {
    id meta = sciAnyIvar(m, "_metadata");
    if (!meta) return nil;
    NSString *sid = sciStrIvar(meta, "_serverId") ?: sciStrIvar(meta, "_messageServerId");
    if (!sid.length) {
        id key = sciAnyIvar(meta, "_key");
        if (key) sid = sciStrIvar(key, "_serverId") ?: sciStrIvar(key, "_messageServerId");
    }
    return sid;
}

static NSString *sciSenderPkFromMessage(id m) {
    id meta = sciAnyIvar(m, "_metadata");
    return sciStrIvar(meta, "_senderPk");
}

static NSDate *sciSentAtFromMessage(id m) {
    id meta = sciAnyIvar(m, "_metadata");
    if (!meta) return nil;
    static const char *names[] = {"_serverTimestamp", "_clientTimestamp", "_timestamp"};
    for (int i = 0; i < 3; i++) {
        id v = sciAnyIvar(meta, names[i]);
        if ([v isKindOfClass:[NSDate class]]) return v;
        if ([v isKindOfClass:[NSNumber class]]) {
            double d = [(NSNumber *)v doubleValue];
            if (d > 1.0e12) d /= 1.0e9;
            else if (d > 1.0e10) d /= 1.0e3;
            if (d > 0) return [NSDate dateWithTimeIntervalSince1970:d];
        }
    }
    return nil;
}

// fieldCache (snake_case Pando dict) — KVC returns NSNull for many IGUser fields.
static void sciResolveSenderInfo(NSString *pk, NSString **outUser, NSString **outName, NSString **outPic) {
    if (!pk.length) return;
    NSString *u = sciDirectUserResolverUsernameForPK(pk);
    NSString *p = sciDirectUserResolverProfilePicURLStringForPK(pk);
    NSString *fn = nil;
    id user = sciDirectUserResolverUserForPK(pk);
    if (user) {
        Ivar fcIv = NULL;
        for (Class c = [user class]; c && !fcIv; c = class_getSuperclass(c))
            fcIv = class_getInstanceVariable(c, "_fieldCache");
        NSDictionary *fc = nil;
        if (fcIv) {
            id raw = object_getIvar(user, fcIv);
            if ([raw isKindOfClass:[NSDictionary class]]) fc = raw;
        }
        id (^fcStr)(NSString *) = ^id(NSString *k) {
            id v = fc[k];
            return [v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0 ? v : nil;
        };
        if (!u.length) u  = fcStr(@"username");
        if (!p.length) p  = fcStr(@"profile_pic_url");
        fn = fcStr(@"full_name");
        if (!fn.length) {
            @try {
                id kvc = [user valueForKey:@"fullName"];
                if ([kvc isKindOfClass:[NSString class]]) fn = kvc;
            } @catch (__unused id e) {}
        }
    }
    if (outUser) *outUser = u;
    if (outName) *outName = fn;
    if (outPic)  *outPic  = p;
}

#pragma mark - Share/link title fallback

// Walks string ivars by name (title/caption/headline/…). First non-empty wins; longer wins ties.
static NSString *sciExtractShareTitle(id obj) {
    if (!obj) return nil;
    NSMutableSet *visited = [NSMutableSet set];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:obj];
    NSString *best = nil;
    NSArray<NSString *> *keys = @[@"title", @"caption", @"text", @"name",
                                   @"description", @"summary", @"label",
                                   @"username", @"headline"];
    int hops = 0;
    while (stack.count && hops++ < 64) {
        id cur = stack.lastObject;
        [stack removeLastObject];
        if (!cur) continue;
        if ([cur isKindOfClass:[NSArray class]]) {
            for (id e in (NSArray *)cur) [stack addObject:e];
            continue;
        }
        if ([cur isKindOfClass:[NSString class]] || [cur isKindOfClass:[NSNumber class]]
            || [cur isKindOfClass:[NSDate class]] || [cur isKindOfClass:[NSURL class]]) continue;
        NSValue *box = [NSValue valueWithNonretainedObject:cur];
        if ([visited containsObject:box]) continue;
        [visited addObject:box];
        NSString *cn = NSStringFromClass([cur class]);
        if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"]
            || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"]) continue;
        for (Class c = [cur class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
            unsigned int n = 0;
            Ivar *list = class_copyIvarList(c, &n);
            for (unsigned int i = 0; i < n; i++) {
                const char *type = ivar_getTypeEncoding(list[i]);
                if (!type || type[0] != '@') continue;
                const char *name = ivar_getName(list[i]);
                id v = nil;
                @try { v = object_getIvar(cur, list[i]); } @catch (__unused id e) {}
                if (!v) continue;
                NSString *nameStr = name ? [@(name) lowercaseString] : @"";
                if ([v isKindOfClass:[NSString class]]) {
                    for (NSString *needle in keys) {
                        if (![nameStr containsString:needle]) continue;
                        NSString *s = v;
                        if (s.length && (!best || s.length > best.length)) best = s;
                    }
                } else {
                    [stack addObject:v];
                }
            }
            if (list) free(list);
        }
    }
    return best;
}

#pragma mark - Voice metadata sniffer

static void sciScanVoiceMetadata(id media, double *outDuration, NSArray **outWaveform) {
    NSMutableSet *visited = [NSMutableSet set];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:media];
    while (stack.count) {
        id cur = stack.lastObject;
        [stack removeLastObject];
        if (!cur) continue;
        if ([cur isKindOfClass:[NSArray class]]) {
            for (id e in cur) [stack addObject:e];
            continue;
        }
        if ([cur isKindOfClass:[NSString class]] || [cur isKindOfClass:[NSNumber class]]
            || [cur isKindOfClass:[NSDate class]] || [cur isKindOfClass:[NSURL class]]) continue;
        NSValue *box = [NSValue valueWithNonretainedObject:cur];
        if ([visited containsObject:box]) continue;
        [visited addObject:box];
        NSString *cn = NSStringFromClass([cur class]);
        if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"]
            || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"]) continue;

        if (!*outDuration) {
            double cand = sciDoubleSelector(cur, @"durationInSeconds");
            if (cand <= 0) cand = sciDoubleSelector(cur, @"duration");
            if (cand <= 0) {
                for (Class c = [cur class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
                    Ivar iv = class_getInstanceVariable(c, "_durationMs");
                    if (!iv) iv = class_getInstanceVariable(c, "_instamadillo_durationMs");
                    if (!iv) continue;
                    const char *t = ivar_getTypeEncoding(iv);
                    ptrdiff_t off = ivar_getOffset(iv);
                    if (t[0] == 'Q' || t[0] == 'q') {
                        long long ms = *(long long *)((char *)(__bridge void *)cur + off);
                        if (ms > 0) cand = (double)ms / 1000.0;
                    }
                    break;
                }
            }
            if (cand > 0) *outDuration = cand;
        }
        if (!*outWaveform) {
            id cand = sciAnyIvar(cur, "_averageVolume")
                   ?: sciAnyIvar(cur, "_waveformData")
                   ?: sciAnyIvar(cur, "_waveform")
                   ?: sciAnyIvar(cur, "_amplitudes");
            if ([cand isKindOfClass:[NSArray class]]) *outWaveform = cand;
        }
        for (Class c = [cur class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
            unsigned int n = 0;
            Ivar *list = class_copyIvarList(c, &n);
            for (unsigned int i = 0; i < n; i++) {
                const char *type = ivar_getTypeEncoding(list[i]);
                if (!type || type[0] != '@') continue;
                id v = nil;
                @try { v = object_getIvar(cur, list[i]); } @catch (__unused id e) {}
                if (v) [stack addObject:v];
            }
            if (list) free(list);
        }
    }
}

#pragma mark - Snapshot builder

// Returns nil for system / placeholder / non-user rows.
static NSDictionary *sciBuildSnapshot(id message, NSString *ownerHint) {
    NSString *sid = sciSidFromMessage(message);
    if (!sid.length) return nil;

    NSMutableDictionary *snap = [NSMutableDictionary dictionary];
    snap[@"sid"] = sid;
    if (ownerHint.length) snap[@"owner_pk"] = ownerHint;

    NSString *threadId = nil;
    @try { threadId = [message valueForKey:@"threadId"]; } @catch (__unused id e) {}
    if (![threadId isKindOfClass:[NSString class]] || !threadId.length) {
        id meta = sciAnyIvar(message, "_metadata");
        threadId = sciStrIvar(meta, "_threadId") ?: sciStrIvar(meta, "_threadID");
    }
    if (threadId.length) snap[@"thread_id"] = threadId;

    // Stamp group-ness + title from the open thread's metadata when this capture
    // happens while the chat is foregrounded (the common case). Read-time
    // grouping falls back to a multi-sender heuristic when this isn't available.
    if (threadId.length) {
        SCIDirectThreadContext *ctx = SCIDirectActiveThreadContext();
        if (ctx && [ctx.threadId isEqualToString:threadId]) {
            if (ctx.isGroup) snap[@"is_group"] = @YES;
            if (ctx.threadName.length) snap[@"thread_title"] = ctx.threadName;
        }
    }

    NSString *senderPk = sciSenderPkFromMessage(message);
    if (senderPk.length) {
        snap[@"sender_pk"] = senderPk;
        NSString *u = nil, *fn = nil, *pic = nil;
        sciResolveSenderInfo(senderPk, &u, &fn, &pic);
        if (u.length)  snap[@"sender_username"]        = u;
        if (fn.length) snap[@"sender_full_name"]       = fn;
        if (pic.length)snap[@"sender_profile_pic_url"] = pic;
    }
    NSDate *sentAt = sciSentAtFromMessage(message);
    if (sentAt) snap[@"sent_at"] = sentAt;

    // Reply id can sit on metadata, on the message, or as a Pando-resolved value-key.
    @try {
        id meta = sciAnyIvar(message, "_metadata");
        NSString *replyId = nil;
        for (NSString *k in @[@"_replyToMessageId", @"_replyMessageId",
                              @"_quotedMessageId", @"_repliedToMessageId",
                              @"_parentMessageId"]) {
            NSString *v = sciStrIvar(meta, k.UTF8String) ?: sciStrIvar(message, k.UTF8String);
            if (v.length) { replyId = v; break; }
        }
        if (!replyId.length) {
            for (NSString *k in @[@"replyToMessageId", @"replyMessageId",
                                  @"quotedMessageId", @"repliedToMessageId",
                                  @"reply_message_id"]) {
                @try {
                    id v = [message valueForKey:k];
                    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
                        replyId = v; break;
                    }
                } @catch (__unused id e) {}
            }
        }
        if (replyId.length) snap[@"reply_to_id"] = replyId;
    } @catch (__unused id e) {}

    id content = sciAnyIvar(message, "_content")
              ?: sciAnyIvar(message, "_messageContent")
              ?: sciAnyIvar(message, "_payload");
    if (!content) {
        @try { content = [message valueForKey:@"content"]; } @catch (__unused id e) {}
    }
    if (!content) {
        snap[@"kind"] = @(SCIDeletedMessageKindUnknown);
        return snap;
    }

    if (sciAnyIvar(content, "_threadActivity")
        || sciAnyIvar(content, "_messageTypeNotLocallyAvailable_placeholderTitle")
        || sciAnyIvar(content, "_messageTypeNotLocallyAvailable_placeholderMessage")
        || sciAnyIvar(content, "_expiredPlaceholder_messageContent")) {
        return nil;
    }

    SCIDeletedMessageKind kind = SCIDeletedMessageKindUnknown;
    NSString *text = nil, *mediaURL = nil, *thumbURL = nil;
    int mediaScore = 0, thumbScore = 0;

    NSString *txt = sciStrIvar(content, "_text_string");
    if (txt.length) {
        kind = SCIDeletedMessageKindText;
        text = txt;
    }

    // Media branch — photo / video / voice / gif / sticker.
    id media = sciAnyIvar(content, "_media");
    if (media) {
        id stickerPayload = sciAnyIvar(media, "_sticker") ?: sciTryObjectSelector(media, @"sticker");
        id instamadilloGif = sciTryObjectSelector(media, @"gif")
            ?: sciFindObjectWithClassNames(media, @[@"IGDirectInstamadilloGif"], 5);
        id giphy = sciAnyIvar(media, "_thirdPartyAnimatedMedia_gif")
            ?: sciFindObjectWithClassNames(media, @[@"IGGiphyGIFModel"], 5);
        BOOL hasSemanticSticker = NO;
        BOOL semanticSticker = sciSemanticIsSticker(instamadilloGif ?: giphy, &hasSemanticSticker);
        if (!hasSemanticSticker) semanticSticker = sciBoolIvar(media, "_animatedMedia_isSticker", &hasSemanticSticker);

        NSMutableSet *vis = [NSMutableSet set];
        NSMutableSet<NSString *> *tokens = [NSMutableSet set];
        sciCollectIvarNames(media, 5, vis, tokens);

        if (stickerPayload || (hasSemanticSticker && semanticSticker)) kind = SCIDeletedMessageKindSticker;
        else if (instamadilloGif || giphy)                         kind = SCIDeletedMessageKindGif;
        else if (sciSetContainsAny(tokens, @[@"voice", @"audio"])) kind = SCIDeletedMessageKindVoice;
        else if (sciSetContainsAny(tokens, @[@"sticker"]))         kind = SCIDeletedMessageKindSticker;
        else if (sciSetContainsAny(tokens, @[@"giphy", @"gif", @"animated"])) kind = SCIDeletedMessageKindGif;
        else if (sciSetContainsAny(tokens, @[@"video", @"dashmanifest", @"playableurl"])) kind = SCIDeletedMessageKindVideo;
        else                                                       kind = SCIDeletedMessageKindPhoto;

        if (kind == SCIDeletedMessageKindGif || kind == SCIDeletedMessageKindSticker) {
            NSString *explicitURL = sciURLStringValue(sciTryObjectSelector(instamadilloGif, @"gifURL"));
            if (!explicitURL.length) explicitURL = sciGiphyMediaURL(giphy);
            if (!explicitURL.length && stickerPayload) explicitURL = sciStickerMediaURL(stickerPayload);
            if (explicitURL.length) {
                mediaURL = explicitURL;
                mediaScore = 100;
            }
        }

        if (kind == SCIDeletedMessageKindVoice) {
            double dur = 0; NSArray *wf = nil;
            sciScanVoiceMetadata(media, &dur, &wf);
            if (dur > 0)  snap[@"duration"] = @(dur);
            if (wf.count) snap[@"waveform"] = wf;
        }

        // Visual media is an info wrapper. Its payload mirrors permanent media.
        id visualInfo = sciAnyIvar(media, "_visualMedia");
        id visualPayload = sciAnyIvar(visualInfo, "_media") ?: sciTryObjectSelector(visualInfo, @"media");
        if (visualInfo) {
            double viewMode = sciDoubleSelector(visualInfo, @"viewMode");
            snap[@"view_mode"] = @((NSInteger)viewMode);
            id stale = sciAnyIvar(visualInfo, "_mediaUrlGoesStaleDate") ?: sciTryObjectSelector(visualInfo, @"mediaUrlGoesStaleDate");
            if ([stale isKindOfClass:[NSDate class]]) snap[@"media_url_stale_at"] = stale;
        }

        if (kind == SCIDeletedMessageKindPhoto) {
            id permanent = sciAnyIvar(media, "_permanentMedia_permanentMedia");
            id photo = sciAnyIvar(permanent, "_photo_photo")
                    ?: sciAnyIvar(visualPayload, "_photo_photo");
            NSURL *photoURL = photo ? [SCIUtils getPhotoUrl:photo] : nil;
            if (photoURL.absoluteString.length) {
                mediaURL = photoURL.absoluteString;
                mediaScore = 100;
            }
        }

        // IGVideo sits under _permanentMedia_permanentMedia, not on media.
        if (kind == SCIDeletedMessageKindVideo) {
            id permanent = sciAnyIvar(media, "_permanentMedia_permanentMedia");
            id video = nil;
            id overlayPhoto = nil;
            if (permanent) {
                video = sciAnyIvar(permanent, "_video_video")
                     ?: sciAnyIvar(permanent, "_videoMemo_memoVideo");
                overlayPhoto = sciAnyIvar(permanent, "_video_overlayPhoto")
                            ?: sciAnyIvar(permanent, "_videoMemo_videoMemoPhoto");
            }
            // visualMedia fallback — view-once flows.
            if (!video) {
                if (visualPayload) {
                    video = sciAnyIvar(visualPayload, "_video_video")
                         ?: sciAnyIvar(visualPayload, "_video");
                    if (!overlayPhoto) overlayPhoto = sciAnyIvar(visualPayload, "_video_overlayPhoto")
                                                  ?: sciAnyIvar(visualPayload, "_overlayPhoto");
                }
            }

            if (video) {
                NSData *manifestData = sciAnyIvar(video, "_dashManifestData");
                if ([manifestData isKindOfClass:[NSData class]] && manifestData.length) {
                    NSString *xml = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
                    NSArray<SCIDashRepresentation *> *reps = [SCIDashParser parseManifest:xml];
                    SCIDashRepresentation *bestV = sciBestDashRepresentation(reps, YES);
                    SCIDashRepresentation *bestA = sciBestDashRepresentation(reps, NO);
                    if (bestV.url.absoluteString.length) {
                        mediaURL = bestV.url.absoluteString;
                        mediaScore = 100;
                    }
                    // DASH video + audio are separate reps; muxed via SCIMediaFFmpeg later.
                    if (bestA.url.absoluteString.length) snap[@"audio_url"] = bestA.url.absoluteString;
                }
                if (!mediaURL.length) {
                    for (NSString *ivName in @[@"_broadcastURL", @"_subtitleURL"]) {
                        id v = sciAnyIvar(video, ivName.UTF8String);
                        if ([v isKindOfClass:[NSURL class]]) {
                            mediaURL = [(NSURL *)v absoluteString];
                            mediaScore = 90;
                            break;
                        }
                    }
                }
            }
            if (overlayPhoto) {
                NSString *t = nil; int ts = 0;
                NSString *m = nil; int ms = 0;
                sciScanForURLsRecursive(overlayPhoto, 4, &m, &ms, &t, &ts, @"thumbnail");
                NSString *picked = t.length ? t : m;
                if (picked.length) { thumbURL = picked; thumbScore = MAX(ts, ms); }
            }
        }

        sciScanForURLsRecursive(media, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, @"media");
    }

    // Some XMA and outgoing layouts keep animated media outside `_media`.
    if (kind == SCIDeletedMessageKindUnknown) {
        id animated = sciFindObjectWithClassNames(content, @[@"IGDirectInstamadilloGif", @"IGGiphyGIFModel"], 5);
        if (animated) {
            BOOL foundSticker = NO;
            kind = sciSemanticIsSticker(animated, &foundSticker) && foundSticker
                ? SCIDeletedMessageKindSticker : SCIDeletedMessageKindGif;
            mediaURL = sciURLStringValue(sciTryObjectSelector(animated, @"gifURL"));
            if (!mediaURL.length) mediaURL = sciGiphyMediaURL(animated);
            if (mediaURL.length) mediaScore = 100;
            sciScanForURLsRecursive(animated, 4, &mediaURL, &mediaScore, &thumbURL, &thumbScore, @"animatedMedia");
        }
    }

    // Reshare branch.
    id reshare = sciAnyIvar(content, "_reshare_attachment");
    if (reshare && kind == SCIDeletedMessageKindUnknown) {
        kind = SCIDeletedMessageKindShare;
        sciScanForURLsRecursive(reshare, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, @"reshare");
        text = sciStrIvar(content, "_reshare_comment");
        if (!text.length) text = sciExtractShareTitle(reshare);
        if (!text.length) text = sciTryStringSelectors(reshare,
            @[@"caption", @"captionText", @"title", @"headline", @"summary",
              @"name", @"username", @"text"]);
        if (!mediaURL.length) {
            NSString *u = sciTryURLSelectors(reshare,
                @[@"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL", @"playableURL"]);
            if (u.length) mediaURL = u;
        }
    }

    // Link branch — IGDirectLinkContext has direct ivars.
    id link = sciAnyIvar(content, "_link_linkContext");
    if (link && kind == SCIDeletedMessageKindUnknown) {
        kind = SCIDeletedMessageKindLink;
        id u    = sciAnyIvar(link, "_url");
        id imgU = sciAnyIvar(link, "_imageURL");
        if ([u    isKindOfClass:[NSURL class]]) mediaURL = [(NSURL *)u    absoluteString];
        if ([imgU isKindOfClass:[NSURL class]]) thumbURL = [(NSURL *)imgU absoluteString];
        NSString *title   = sciStrIvar(link, "_title");
        NSString *summary = sciStrIvar(link, "_summary");
        NSString *comment = sciStrIvar(content, "_link_commentText");
        NSMutableArray *parts = [NSMutableArray array];
        if (comment.length) [parts addObject:comment];
        if (title.length)   [parts addObject:title];
        if (summary.length) [parts addObject:summary];
        if (!parts.count && mediaURL.length) [parts addObject:mediaURL];
        if (parts.count) text = [parts componentsJoinedByString:@"\n"];
    }

    // XMA — Pando-backed wrapper. IGDirectXMA has zero ivars; data comes
    // via valueForKey on names mirroring IGDirectXMABuilder / IGDirectXMAShareBuilder.
    if (kind == SCIDeletedMessageKindUnknown) {
        id xmaLike = sciAnyIvar(content, "_xma")
                  ?: sciAnyIvar(content, "_bloksXMA")
                  ?: sciAnyIvar(content, "_pollMessage")
                  ?: sciAnyIvar(content, "_progressiveImage");
        if (xmaLike) {
            NSString *xmaContentType = nil;
            @try {
                id v = [xmaLike valueForKey:@"contentType"];
                if ([v isKindOfClass:[NSString class]]) xmaContentType = [(NSString *)v lowercaseString];
            } @catch (__unused id e) {}

            // Audio share heuristic — generic_xma with playableAudioURL or /reels_audio_page targetURL.
            BOOL isAudio = NO;
            @try {
                id items = [xmaLike valueForKey:@"xmaItems"];
                id first = ([items isKindOfClass:[NSArray class]] && [items count] > 0) ? [items firstObject] : nil;
                if (first) {
                    id pa = [first valueForKey:@"playableAudioURL"];
                    if ([pa isKindOfClass:[NSURL class]] && [(NSURL *)pa absoluteString].length) isAudio = YES;
                    if (!isAudio) {
                        id tgt = [first valueForKey:@"targetURL"];
                        NSString *tgtStr = [tgt isKindOfClass:[NSURL class]] ? [(NSURL *)tgt absoluteString]
                                           : ([tgt isKindOfClass:[NSString class]] ? tgt : nil);
                        if ([tgtStr.lowercaseString containsString:@"reels_audio_page"]
                            || [tgtStr.lowercaseString containsString:@"audio_page"]) isAudio = YES;
                    }
                }
            } @catch (__unused id e) {}

            if (isAudio)                                           kind = SCIDeletedMessageKindAudioShare;
            else if ([xmaContentType isEqualToString:@"xma_link"]) kind = SCIDeletedMessageKindLink;
            else                                                   kind = SCIDeletedMessageKindShare;

            // Real share payload sits on xmaItems[0] (IGDirectXMAShare).
            NSMutableArray *probeTargets = [NSMutableArray arrayWithObject:xmaLike];
            @try {
                id items = [xmaLike valueForKey:@"xmaItems"];
                if ([items isKindOfClass:[NSArray class]]) {
                    for (id it in (NSArray *)items) if (it) [probeTargets addObject:it];
                }
            } @catch (__unused id e) {}
            @try {
                id meta = [xmaLike valueForKey:@"metadata"];
                if (meta && meta != [NSNull null]) [probeTargets addObject:meta];
            } @catch (__unused id e) {}

            NSString *(^pickStr)(id, NSArray<NSString *> *) = ^NSString *(id obj, NSArray<NSString *> *keys) {
                for (NSString *k in keys) {
                    @try {
                        id v = [obj valueForKey:k];
                        if (!v || v == [NSNull null]) continue;
                        if ([v isKindOfClass:[NSAttributedString class]]) v = [(NSAttributedString *)v string];
                        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0
                            && !sciIsDescriptionFallback(v)) return v;
                    } @catch (__unused id e) {}
                }
                return nil;
            };
            NSString *(^pickURL)(id, NSArray<NSString *> *) = ^NSString *(id obj, NSArray<NSString *> *keys) {
                for (NSString *k in keys) {
                    @try {
                        id v = [obj valueForKey:k];
                        if (!v || v == [NSNull null]) continue;
                        if ([v isKindOfClass:[NSURL class]]) {
                            NSString *s = [(NSURL *)v absoluteString];
                            if (s.length) return s;
                        }
                        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
                    } @catch (__unused id e) {}
                }
                return nil;
            };

            // IGDirectXMAShareBuilder mirror keys — priority order.
            NSArray<NSString *> *titleKeys = @[
                @"headerTitleText", @"titleText", @"headerSubtitleText",
                @"subtitleText", @"captionBodyText", @"footerBodyText",
                @"overlayTitle", @"overlayDescription", @"overlayText",
                @"quotedTitleText", @"quotedAttributionText", @"quotedCaptionBodyText",
                @"groupName", @"targetURLTitle",
                @"title", @"caption", @"text", @"summary", @"description"
            ];
            // Audio: prefer .mp4 (download/play); others: targetURL (in-app open).
            NSArray<NSString *> *mediaKeys = (kind == SCIDeletedMessageKindAudioShare)
                ? @[@"playableAudioURL", @"playableURL", @"accessoryPlayableURL",
                    @"fullSizeURL", @"targetURL",
                    @"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL"]
                : @[@"targetURL",
                    @"playableURL", @"playableAudioURL",
                    @"accessoryPlayableURL", @"fullSizeURL",
                    @"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL"];
            NSArray<NSString *> *thumbKeys = @[
                @"previewURL", @"accessoryPreviewURL", @"previewMaskURL",
                @"previewIgImageURL",
                @"thumbnailURL", @"posterURL", @"imageURL"
            ];

            NSMutableArray *titleParts = [NSMutableArray array];
            for (id obj in probeTargets) {
                NSString *t = pickStr(obj, titleKeys);
                if (t.length && ![titleParts containsObject:t]) [titleParts addObject:t];
                if (titleParts.count >= 3) break;
            }
            if (!text.length && titleParts.count) text = [titleParts componentsJoinedByString:@"\n"];

            for (id obj in probeTargets) {
                if (!mediaURL.length) {
                    NSString *u = pickURL(obj, mediaKeys);
                    if (u.length) { mediaURL = u; mediaScore = 70; }
                }
                if (!thumbURL.length) {
                    NSString *u = pickURL(obj, thumbKeys);
                    if (u.length) { thumbURL = u; thumbScore = 70; }
                }
                if (mediaURL.length && thumbURL.length) break;
            }

            sciScanForURLsRecursive(xmaLike, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, @"xma");

            // Unwrap IG/FB outbound redirector — `l.instagram.com/?u=<real>`.
            if (kind == SCIDeletedMessageKindLink && mediaURL.length) {
                NSURL *u = [NSURL URLWithString:mediaURL];
                NSString *host = u.host.lowercaseString;
                if ([host isEqualToString:@"l.instagram.com"]
                    || [host isEqualToString:@"l.facebook.com"]
                    || [host isEqualToString:@"lm.facebook.com"]) {
                    NSURLComponents *comps = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
                    for (NSURLQueryItem *q in comps.queryItems) {
                        if ([q.name isEqualToString:@"u"] && q.value.length) {
                            mediaURL = q.value;
                            break;
                        }
                    }
                }
            }
        }
    }

    if (kind == SCIDeletedMessageKindUnknown && text.length) kind = SCIDeletedMessageKindText;

    snap[@"kind"]  = @(kind);
    if (text.length)     snap[@"text"]      = text;
    if (mediaURL.length) snap[@"media_url"] = mediaURL;
    if (thumbURL.length) snap[@"thumb_url"] = thumbURL;
    return snap;
}

#pragma mark - Media download

// Tiny helper: download a URL into a temp file synchronously on the
// download queue. Used during video+audio mux. Completion is dispatched on
// the same queue that called us so we can chain steps.
static void sciDownloadToTempFile(NSURL *url, void (^done)(NSURL *file, NSError *err)) {
    if (!url) { done(nil, [NSError errorWithDomain:@"SCIDM" code:0 userInfo:nil]); return; }
    [[sciSharedSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data.length) { done(nil, err); return; }
        NSString *ext = url.pathExtension.length ? url.pathExtension : @"bin";
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"sci_dm_%@.%@", [NSUUID UUID].UUIDString, ext]];
        if (![data writeToFile:tmp atomically:YES]) {
            done(nil, [NSError errorWithDomain:@"SCIDM" code:1 userInfo:nil]);
            return;
        }
        done([NSURL fileURLWithPath:tmp], nil);
    }] resume];
}

static BOOL sciAttachStagedPathToFinalizedMessage(NSString *relativePath,
                                                   NSString *messageId,
                                                   NSString *ownerPk,
                                                   BOOL isThumbnail,
                                                   NSString *mimeType) {
    if (!relativePath.length || !messageId.length || !ownerPk.length) return NO;
    for (SCIDeletedMessage *m in [SCIDeletedMessagesStorage allMessagesForOwnerPK:ownerPk]) {
        if (![m.messageId isEqualToString:messageId]) continue;
        NSString *promoted = [SCIDeletedMessagesStorage promoteStagedRelativePath:relativePath
                                                                        messageId:messageId
                                                                          ownerPK:ownerPk
                                                                        thumbnail:isThumbnail];
        if (!promoted.length) return NO;
        if (isThumbnail) m.thumbnailPath = promoted;
        else {
            m.mediaPath = promoted;
            if (mimeType.length) m.mediaMimeType = mimeType;
        }
        return [SCIDeletedMessagesStorage saveMessage:m forOwnerPK:ownerPk];
    }
    return NO;
}

static BOOL sciPersistStagedPath(NSString *relativePath,
                                 NSString *messageId,
                                 NSString *ownerPk,
                                 BOOL isThumbnail,
                                 NSString *mimeType) {
    NSString *key = isThumbnail ? @"staged_thumbnail_path" : @"staged_media_path";
    NSMutableDictionary *values = [NSMutableDictionary dictionaryWithObject:relativePath forKey:key];
    if (!isThumbnail && mimeType.length) values[@"media_mime"] = mimeType;
    BOOL patched = [SCIDeletedMessagesStorage patchPendingCandidateForMessageId:messageId
                                                                         values:values
                                                                        ownerPK:ownerPk];
    BOOL attached = sciAttachStagedPathToFinalizedMessage(relativePath, messageId, ownerPk, isThumbnail, mimeType);
    return patched || attached;
}

// DASH video reps are silent — download video + audio reps and mux to mp4.
static void sciDownloadAndMuxVideo(NSString *videoURL, NSString *audioURL,
                                    NSString *messageId, NSString *ownerPk,
                                    BOOL staged) {
    if (!videoURL.length || !messageId.length) return;
    if (!audioURL.length || ![SCIMediaFFmpeg isAvailable]) return;
    NSURL *vURL = [NSURL URLWithString:videoURL];
    NSURL *aURL = [NSURL URLWithString:audioURL];
    if (!vURL || !aURL) return;
    NSString *fname = staged
        ? [SCIDeletedMessagesStorage reserveRelativeStagedMediaPathForMessageId:messageId extension:@"mp4" ownerPK:ownerPk thumbnail:NO]
        : [SCIDeletedMessagesStorage reserveRelativeMediaPathForMessageId:messageId extension:@"mp4" ownerPK:ownerPk];
    NSString *abs = staged
        ? [SCIDeletedMessagesStorage absoluteStagedPathForRelativePath:fname ownerPK:ownerPk]
        : [SCIDeletedMessagesStorage absolutePathForRelativePath:fname ownerPK:ownerPk];
    if (!abs.length) return;
    if ([[NSFileManager defaultManager] fileExistsAtPath:abs]) {
        if (!staged || sciPersistStagedPath(fname, messageId, ownerPk, NO, @"video/mp4")) return;
        [[NSFileManager defaultManager] removeItemAtPath:abs error:nil];
    }

    dispatch_async(sciDownloadQueue(), ^{
        __block NSURL *vFile = nil, *aFile = nil;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        sciDownloadToTempFile(vURL, ^(NSURL *f, NSError *e) { if (!e) vFile = f; dispatch_semaphore_signal(sema); });
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        sciDownloadToTempFile(aURL, ^(NSURL *f, NSError *e) { if (!e) aFile = f; dispatch_semaphore_signal(sema); });
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        if (!vFile || !aFile) {
            if (vFile) [[NSFileManager defaultManager] removeItemAtURL:vFile error:nil];
            if (aFile) [[NSFileManager defaultManager] removeItemAtURL:aFile error:nil];
            return;
        }
        [SCIMediaFFmpeg mergeVideoFileURL:vFile
                             audioFileURL:aFile
                        preferredBasename:messageId
                         estimatedDuration:0
                                     width:0
                                    height:0
                             sourceBitrate:0
                                  progress:nil
                                completion:^(NSURL *outURL, NSError *err) {
            [[NSFileManager defaultManager] removeItemAtURL:vFile error:nil];
            [[NSFileManager defaultManager] removeItemAtURL:aFile error:nil];
            if (err || !outURL) return;
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:abs]) {
                [fm removeItemAtURL:outURL error:nil];
            } else if (![fm moveItemAtURL:outURL toURL:[NSURL fileURLWithPath:abs] error:nil]) {
                return;
            }
            if (staged) {
                if (!sciPersistStagedPath(fname, messageId, ownerPk, NO, @"video/mp4")) {
                    [fm removeItemAtPath:abs error:nil];
                }
                return;
            }
            for (SCIDeletedMessage *m in [SCIDeletedMessagesStorage allMessagesForOwnerPK:ownerPk]) {
                if (![m.messageId isEqualToString:messageId]) continue;
                m.mediaPath = fname;
                [SCIDeletedMessagesStorage saveMessage:m forOwnerPK:ownerPk];
                break;
            }
        } cancelOut:nil];
    });
}

static void sciDownloadMedia(NSString *urlString, NSString *messageId,
                             NSString *ownerPk, BOOL isThumbnail,
                             SCIDeletedMessageKind kind, BOOL staged) {
    if (!urlString.length || !messageId.length) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    NSString *ext = url.pathExtension.length
        ? url.pathExtension
        : ((isThumbnail || kind == SCIDeletedMessageKindPhoto) ? @"jpg" : @"bin");
    // Voice notes are served with a video container extension (.mp4) even though
    // they are audio-only. Force an audio extension so the file is typed as audio
    // everywhere downstream (preview player, share, save).
    if (!isThumbnail && kind == SCIDeletedMessageKindVoice) {
        ext = @"m4a";
    }
    NSString *fname = staged
        ? [SCIDeletedMessagesStorage reserveRelativeStagedMediaPathForMessageId:messageId extension:ext ownerPK:ownerPk thumbnail:isThumbnail]
        : (isThumbnail
            ? [NSString stringWithFormat:@"thumb_%@.%@", messageId, ext]
            : [SCIDeletedMessagesStorage reserveRelativeMediaPathForMessageId:messageId extension:ext ownerPK:ownerPk]);
    NSString *abs = staged
        ? [SCIDeletedMessagesStorage absoluteStagedPathForRelativePath:fname ownerPK:ownerPk]
        : [SCIDeletedMessagesStorage absolutePathForRelativePath:fname ownerPK:ownerPk];
    if (!abs.length) return;
    if ([[NSFileManager defaultManager] fileExistsAtPath:abs]) {
        if (!staged || sciPersistStagedPath(fname, messageId, ownerPk, isThumbnail, nil)) return;
        [[NSFileManager defaultManager] removeItemAtPath:abs error:nil];
    }

    dispatch_async(sciDownloadQueue(), ^{
        NSURLSessionDataTask *task = [sciSharedSession() dataTaskWithURL:url
                                                       completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err || !data.length) return;
            NSString *detectedExt = SCIFileExtensionForMediaResponse(data, resp, url);
            if (!detectedExt.length) detectedExt = ext;
            if (!isThumbnail && kind == SCIDeletedMessageKindVoice) detectedExt = @"m4a";
            NSString *writeName = fname;
            NSString *writePath = abs;
            if (![detectedExt.lowercaseString isEqualToString:ext.lowercaseString]) {
                writeName = staged
                    ? [SCIDeletedMessagesStorage reserveRelativeStagedMediaPathForMessageId:messageId extension:detectedExt ownerPK:ownerPk thumbnail:isThumbnail]
                    : (isThumbnail
                        ? [NSString stringWithFormat:@"thumb_%@.%@", messageId, detectedExt]
                        : [SCIDeletedMessagesStorage reserveRelativeMediaPathForMessageId:messageId extension:detectedExt ownerPK:ownerPk]);
                writePath = staged
                    ? [SCIDeletedMessagesStorage absoluteStagedPathForRelativePath:writeName ownerPK:ownerPk]
                    : [SCIDeletedMessagesStorage absolutePathForRelativePath:writeName ownerPK:ownerPk];
            }
            if (![data writeToFile:writePath atomically:YES]) return;
            NSString *mimeType = SCIMIMETypeForImageFormat(SCIImageFormatForData(data)) ?: resp.MIMEType;
            if (staged) {
                if (!sciPersistStagedPath(writeName, messageId, ownerPk, isThumbnail, mimeType)) {
                    [[NSFileManager defaultManager] removeItemAtPath:writePath error:nil];
                }
                return;
            }
            for (SCIDeletedMessage *m in [SCIDeletedMessagesStorage allMessagesForOwnerPK:ownerPk]) {
                if (![m.messageId isEqualToString:messageId]) continue;
                if (isThumbnail) m.thumbnailPath = writeName;
                else {
                    m.mediaPath = writeName;
                    m.mediaMimeType = mimeType;
                }
                [SCIDeletedMessagesStorage saveMessage:m forOwnerPK:ownerPk];
                break;
            }
        }];
        [task resume];
    });
}

static void sciStageRecoverySnapshot(NSDictionary *snapshot, NSString *ownerPk) {
    NSString *messageId = snapshot[@"sid"];
    if (!messageId.length || !ownerPk.length) return;
    SCIDeletedMessageKind kind = (SCIDeletedMessageKind)[snapshot[@"kind"] integerValue];
    BOOL disappearing = [snapshot[@"view_mode"] isKindOfClass:[NSNumber class]];
    if (!disappearing && kind != SCIDeletedMessageKindGif && kind != SCIDeletedMessageKindSticker) return;
    NSString *mediaURL = snapshot[@"media_url"];
    NSString *audioURL = snapshot[@"audio_url"];
    if (kind == SCIDeletedMessageKindVideo && mediaURL.length && audioURL.length) {
        sciDownloadAndMuxVideo(mediaURL, audioURL, messageId, ownerPk, YES);
    } else if (mediaURL.length) {
        sciDownloadMedia(mediaURL, messageId, ownerPk, NO, kind, YES);
    }
    NSString *thumbnailURL = snapshot[@"thumb_url"];
    if (thumbnailURL.length) sciDownloadMedia(thumbnailURL, messageId, ownerPk, YES, kind, YES);
}

#pragma mark - Per-thread fallback (covers foreground threads in IG's _cache)

static id sciDirectCacheFromApplicator(id applicator) {
    if (!applicator) return nil;
    @try {
        Ivar iv = class_getInstanceVariable([applicator class], "_cache");
        return iv ? object_getIvar(applicator, iv) : nil;
    } @catch (__unused id e) { return nil; }
}

// `applicator._cache.threadClientStateForThreadId:tid` returns an
// IGDirectThreadClientState whose `_messagesByServerId` ivar is a dict
// keyed by sid → IGDirectMessage. Direct ivar read skips method dispatch.
static id sciFallbackLookupMessage(id applicator, NSString *sid, NSString *threadId) {
    if (!applicator || !sid.length || !threadId.length) return nil;
    @try {
        id cache = sciDirectCacheFromApplicator(applicator);
        if (!cache) return nil;
        id state = nil;
        SEL sel = NSSelectorFromString(@"threadClientStateForThreadId:");
        if ([cache respondsToSelector:sel]) {
            state = ((id(*)(id, SEL, id))objc_msgSend)(cache, sel, threadId);
        } else {
            id states = sciAnyIvar(cache, "_threadClientStateByThreadIds");
            if ([states isKindOfClass:[NSDictionary class]]) state = states[threadId];
        }
        if (!state) return nil;
        for (Class c = [state class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
            Ivar di = class_getInstanceVariable(c, "_messagesByServerId");
            if (!di) continue;
            id dict = object_getIvar(state, di);
            if ([dict isKindOfClass:[NSDictionary class]]) return ((NSDictionary *)dict)[sid];
            break;
        }
    } @catch (__unused id e) {}
    return nil;
}

static id sciFindMessageInFetchedThread(id value, NSString *sid, NSInteger depth, NSMutableSet *visited) {
    if (!value || !sid.length || depth < 0) return nil;
    NSValue *identity = [NSValue valueWithNonretainedObject:value];
    if ([visited containsObject:identity]) return nil;
    [visited addObject:identity];
    if ([sciSidFromMessage(value) isEqualToString:sid]) return value;
    if ([value isKindOfClass:[NSDictionary class]]) {
        id direct = value[sid];
        if (direct) return direct;
        for (id child in [value allValues]) {
            id found = sciFindMessageInFetchedThread(child, sid, depth - 1, visited);
            if (found) return found;
        }
        return nil;
    }
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]] || [value isKindOfClass:[NSOrderedSet class]]) {
        for (id child in value) {
            id found = sciFindMessageInFetchedThread(child, sid, depth - 1, visited);
            if (found) return found;
        }
        return nil;
    }
    for (NSString *name in @[@"_messagesByServerId", @"_messages", @"_publishedMessages", @"_messageList"]) {
        id child = sciAnyIvar(value, name.UTF8String);
        id found = sciFindMessageInFetchedThread(child, sid, depth - 1, visited);
        if (found) return found;
    }
    return nil;
}

#pragma mark - Public hooks

void sciDMCaptureNoteInsert(id message, NSString *ownerPk, NSString *threadId, BOOL persistCandidate) {
    if (!message) return;
    @try {
        NSString *sid = sciSidFromMessage(message);
        if (!sid.length) return;
        @synchronized (sciMessageRefsLock()) {
            [sciMessageRefs() setObject:message forKey:sid];
        }
        if (persistCandidate && ownerPk.length) {
            NSMutableDictionary *snapshot = [sciBuildSnapshot(message, ownerPk) mutableCopy];
            if (!snapshot[@"thread_id"] && threadId.length) snapshot[@"thread_id"] = threadId;
            if (snapshot.count) {
                [SCIDeletedMessagesStorage savePendingCandidateSnapshot:sciJSONSafeSnapshot(snapshot) forOwnerPK:ownerPk];
                sciStageRecoverySnapshot(snapshot, ownerPk);
            }
        }
    } @catch (__unused id e) {}
}

static NSString *sciExtractKeySid(id key) {
    if (!key) return nil;
    @try {
        for (Class c = [key class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
            Ivar iv = class_getInstanceVariable(c, "_serverId");
            if (!iv) iv = class_getInstanceVariable(c, "_messageServerId");
            if (!iv) continue;
            id v = object_getIvar(key, iv);
            if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
            break;
        }
    } @catch (__unused id e) {}
    return nil;
}

static NSString *sciExtractKeyMutationId(id key) {
    if (!key) return nil;
    for (NSString *name in @[@"_mutationId", @"_mutationID", @"_clientMutationId"]) {
        NSString *value = sciStrIvar(key, name.UTF8String);
        if (value.length) return value;
    }
    return nil;
}

static NSMutableDictionary<NSString *, id> *sciStrongRefsForKeys(NSArray *keys, id applicator, NSString *thread) {
    NSMutableDictionary<NSString *, id> *strongRefs = [NSMutableDictionary dictionary];

    @synchronized (sciMessageRefsLock()) {
        NSMapTable *t = sciMessageRefs();
        for (id key in keys) {
            NSString *sid = sciExtractKeySid(key);
            if (!sid.length) continue;
            id m = [t objectForKey:sid];
            if (m) strongRefs[sid] = m;
        }
    }

    for (id key in keys) {
        NSString *sid = sciExtractKeySid(key);
        if (!sid.length || strongRefs[sid]) continue;
        id m = sciFallbackLookupMessage(applicator, sid, thread);
        if (m) strongRefs[sid] = m;
    }

    return strongRefs;
}

NSArray<NSDictionary *> *sciDMCapturePreviewMetadataForKeys(NSArray *keys,
                                                            id applicator,
                                                            NSString *ownerPk,
                                                            NSString *threadId) {
    if (!keys.count) return @[];
    NSString *owner = ownerPk.length ? [ownerPk copy] : @"";
    NSString *thread = threadId.length ? [threadId copy] : nil;
    NSDictionary<NSString *, id> *strongRefs = sciStrongRefsForKeys(keys, applicator, thread);
    NSMutableArray<NSDictionary *> *previews = [NSMutableArray arrayWithCapacity:keys.count];
    for (id key in keys) {
        NSString *sid = sciExtractKeySid(key);
        NSDictionary *snap = [SCIDeletedMessagesStorage pendingCandidateSnapshotForMessageId:sid ownerPK:owner]
                          ?: sciBuildSnapshot(strongRefs[sid], owner);
        if (!snap) continue;
        NSString *senderPk = snap[@"sender_pk"];
        if (senderPk.length && [SCIDeletedMessagesStorage isSenderBlocked:senderPk ownerPK:owner]) continue;

        NSMutableDictionary *preview = [NSMutableDictionary dictionary];
        preview[@"messageId"] = sid;
        preview[@"threadId"] = snap[@"thread_id"] ?: thread ?: @"";
        if (senderPk.length) preview[@"senderPk"] = senderPk;
        if ([snap[@"sender_username"] isKindOfClass:[NSString class]]) preview[@"senderUsername"] = snap[@"sender_username"];
        if ([snap[@"sender_full_name"] isKindOfClass:[NSString class]]) preview[@"senderFullName"] = snap[@"sender_full_name"];
        if ([snap[@"kind"] isKindOfClass:[NSNumber class]]) preview[@"kind"] = snap[@"kind"];
        if ([snap[@"text"] isKindOfClass:[NSString class]]) {
            preview[@"text"] = snap[@"text"];
            preview[@"previewText"] = snap[@"text"];
        }
        [previews addObject:preview];
    }
    return previews;
}

static BOOL sciFinalizeSnapshot(NSDictionary *snap, NSString *sid, NSString *thread, NSString *owner) {
    if (!snap || !sid.length) return NO;
    NSString *senderPk = snap[@"sender_pk"];
    if (!senderPk.length) return NO;
    if (senderPk.length && [SCIDeletedMessagesStorage isSenderBlocked:senderPk ownerPK:owner]) {
        [SCIDeletedMessagesStorage removePendingCandidateForMessageId:sid ownerPK:owner];
        [SCIDeletedMessagesStorage removePendingRemovalForMessageId:sid ownerPK:owner];
        return YES;
    }

    SCIDeletedMessageKind kind = (SCIDeletedMessageKind)[snap[@"kind"] integerValue];
    NSString *txt = snap[@"text"];
    NSString *mu  = snap[@"media_url"];
    NSString *tu  = snap[@"thumb_url"];
    if ((kind == SCIDeletedMessageKindUnknown || kind == SCIDeletedMessageKindOther)
        && !txt.length && !mu.length && !tu.length) return NO;

    NSDate *now = [NSDate date];
    SCIDeletedMessage *m = [SCIDeletedMessage new];
    m.messageId           = sid;
    m.threadId            = snap[@"thread_id"] ?: thread ?: @"";
    m.threadTitle         = snap[@"thread_title"];
    m.isGroup             = [snap[@"is_group"] boolValue];
    m.senderPk            = senderPk ?: @"";
    m.senderUsername      = snap[@"sender_username"];
    m.senderFullName      = snap[@"sender_full_name"];
    m.senderProfilePicURL = snap[@"sender_profile_pic_url"];
    m.sentAt              = sciDateFromSnapshotValue(snap[@"sent_at"]);
    m.capturedAt          = now;
    m.deletedAt           = now;
    m.kind                = kind;
    m.text                = txt;
    m.previewText         = txt;
    m.mediaURL            = mu;
    m.thumbnailURL        = tu;
    m.mediaMimeType       = snap[@"media_mime"];
    m.durationSeconds     = [snap[@"duration"] doubleValue];
    m.viewMode            = [snap[@"view_mode"] isKindOfClass:[NSNumber class]] ? [snap[@"view_mode"] integerValue] : -1;
    m.mediaURLStaleAt     = sciDateFromSnapshotValue(snap[@"media_url_stale_at"]);
    id wf = snap[@"waveform"];
    if ([wf isKindOfClass:[NSArray class]]) m.waveform = wf;
    m.replyToMessageId = snap[@"reply_to_id"];

    if (![SCIDeletedMessagesStorage saveMessage:m forOwnerPK:owner]) return NO;

    // Save the log entry before promoting media so an in-flight staged download
    // can attach itself even if it finishes while this unsend is being finalized.
    NSDictionary *latestCandidate = [SCIDeletedMessagesStorage pendingCandidateSnapshotForMessageId:sid ownerPK:owner] ?: snap;
    m.mediaMimeType = latestCandidate[@"media_mime"] ?: m.mediaMimeType;
    m.mediaPath = [SCIDeletedMessagesStorage promoteStagedRelativePath:latestCandidate[@"staged_media_path"]
                                                            messageId:sid ownerPK:owner thumbnail:NO];
    m.thumbnailPath = [SCIDeletedMessagesStorage promoteStagedRelativePath:latestCandidate[@"staged_thumbnail_path"]
                                                                messageId:sid ownerPK:owner thumbnail:YES];
    if (m.mediaPath.length || m.thumbnailPath.length) {
        [SCIDeletedMessagesStorage saveMessage:m forOwnerPK:owner];
    }
    [SCIDeletedMessagesStorage removePendingCandidateForMessageId:sid ownerPK:owner];
    [SCIDeletedMessagesStorage removePendingRemovalForMessageId:sid ownerPK:owner];

    NSString *audioURL = snap[@"audio_url"];
    BOOL isDeeplinkOnly = (m.kind == SCIDeletedMessageKindShare || m.kind == SCIDeletedMessageKindLink);
    if (!m.mediaPath.length && m.kind == SCIDeletedMessageKindVideo && audioURL.length && m.mediaURL.length) {
        sciDownloadAndMuxVideo(m.mediaURL, audioURL, sid, owner, NO);
    } else if (!m.mediaPath.length && !isDeeplinkOnly && m.mediaURL.length) {
        sciDownloadMedia(m.mediaURL, sid, owner, NO, m.kind, NO);
    }
    if (!m.thumbnailPath.length && m.thumbnailURL.length) sciDownloadMedia(m.thumbnailURL, sid, owner, YES, m.kind, NO);
    return YES;
}

static NSMutableSet<NSString *> *sciPendingFetches(void) {
    static NSMutableSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSMutableSet set]; });
    return set;
}

static void sciFetchThreadForPendingRemoval(id applicator, NSString *sid, NSString *thread, NSString *owner) {
    id cache = sciDirectCacheFromApplicator(applicator);
    if (!cache || !sid.length || !thread.length || !owner.length) return;
    NSString *fetchKey = [NSString stringWithFormat:@"%@:%@:%@", owner, thread, sid];
    @synchronized (sciPendingFetches()) {
        if ([sciPendingFetches() containsObject:fetchKey]) return;
        [sciPendingFetches() addObject:fetchKey];
    }

    void (^completion)(id) = ^(id fetchedThread) {
        @synchronized (sciPendingFetches()) { [sciPendingFetches() removeObject:fetchKey]; }
        id message = sciFindMessageInFetchedThread(fetchedThread, sid, 4, [NSMutableSet set])
                  ?: sciFallbackLookupMessage(applicator, sid, thread);
        if (!message) return;
        NSDictionary *snap = sciBuildSnapshot(message, owner);
        if (!snap) return;
        dispatch_async(sciCaptureQueue(), ^{ sciFinalizeSnapshot(snap, sid, thread, owner); });
    };

    SEL publicFetch = NSSelectorFromString(@"fetchThreadWithThreadId:completion:");
    SEL legacyFetch = NSSelectorFromString(@"_fetchThreadFromCacheWithThreadId:completion:");
    @try {
        if ([cache respondsToSelector:publicFetch]) {
            ((void(*)(id, SEL, id, id))objc_msgSend)(cache, publicFetch, thread, completion);
        } else if ([cache respondsToSelector:legacyFetch]) {
            ((void(*)(id, SEL, id, id))objc_msgSend)(cache, legacyFetch, thread, completion);
        } else {
            @synchronized (sciPendingFetches()) { [sciPendingFetches() removeObject:fetchKey]; }
        }
    } @catch (__unused id e) {
        @synchronized (sciPendingFetches()) { [sciPendingFetches() removeObject:fetchKey]; }
    }
}

void sciDMCaptureNoteRemoveKeys(NSArray *keys, id applicator,
                                 NSString *ownerPk, NSString *threadId) {
    if (!sciCaptureEnabled() || !keys.count) return;
    NSString *owner  = ownerPk.length  ? [ownerPk copy]  : @"";
    NSString *thread = threadId.length ? [threadId copy] : nil;

    // Resolve the real group name from IG's cache (deduped per thread).
    if (thread.length && owner.length) sciDMCaptureResolveThreadMeta(applicator, thread, owner);

    for (id key in keys) {
        NSString *sid = sciExtractKeySid(key);
        if (sid.length) {
            [SCIDeletedMessagesStorage savePendingRemovalForMessageId:sid
                                                              threadId:thread
                                                            mutationId:sciExtractKeyMutationId(key)
                                                               ownerPK:owner];
        }
    }
    NSMutableDictionary<NSString *, id> *strongRefs = sciStrongRefsForKeys(keys, applicator, thread);
    @synchronized (sciMessageRefsLock()) {
        NSMapTable *t = sciMessageRefs();
        for (id key in keys) {
            NSString *sid = sciExtractKeySid(key);
            if (sid.length) [t removeObjectForKey:sid];
        }
    }

    dispatch_async(sciCaptureQueue(), ^{
        for (id key in keys) {
            NSString *sid = sciExtractKeySid(key);
            NSDictionary *snap = [SCIDeletedMessagesStorage pendingCandidateSnapshotForMessageId:sid ownerPK:owner];
            if (!snap && strongRefs[sid]) snap = sciBuildSnapshot(strongRefs[sid], owner);
            if (snap) sciFinalizeSnapshot(snap, sid, thread, owner);
        }
    });
}

void sciDMCaptureRetryPendingRemovals(id applicator, NSString *ownerPk) {
    if (!sciCaptureEnabled() || !ownerPk.length) return;
    NSString *owner = [ownerPk copy];
    NSArray<NSDictionary *> *pending = [SCIDeletedMessagesStorage pendingRemovalsForOwnerPK:owner];
    if (!pending.count) return;
    dispatch_async(sciCaptureQueue(), ^{
        for (NSDictionary *entry in pending) {
            NSString *sid = entry[@"message_id"];
            NSString *thread = entry[@"thread_id"];
            NSDictionary *snap = [SCIDeletedMessagesStorage pendingCandidateSnapshotForMessageId:sid ownerPK:owner];
            if (!snap) {
                id message = sciFallbackLookupMessage(applicator, sid, thread);
                if (message) snap = sciBuildSnapshot(message, owner);
            }
            if (snap) sciFinalizeSnapshot(snap, sid, thread, owner);
            else sciFetchThreadForPendingRemoval(applicator, sid, thread, owner);
        }
    });
}

#pragma mark - Group thread title resolution

static NSString *sciJoinThreadNames(NSArray<NSString *> *names) {
    if (!names.count) return nil;
    if (names.count <= 3) return [names componentsJoinedByString:@", "];
    NSArray *head = [names subarrayWithRange:NSMakeRange(0, 3)];
    return [NSString stringWithFormat:@"%@ +%lu", [head componentsJoinedByString:@", "], (unsigned long)(names.count - 3)];
}

static NSString *sciGroupCustomName(id metadata) {
    id groupMeta = sciTryObjectSelector(metadata, @"groupMetadata") ?: sciAnyIvar(metadata, "_groupMetadata");
    if (!groupMeta) return nil;
    NSString *name = sciTryStringSelectors(groupMeta, @[@"customName"]);
    if (!name.length) name = sciStrIvar(groupMeta, "_customName");
    return name.length ? name : nil;
}

// metadata.groupMetadata.groupPhotoIdentifier.groupImageSpecifier.remoteImageURL.url
// Only set for groups with an explicit custom photo.
static NSString *sciGroupPhotoURL(id metadata) {
    id groupMeta = sciTryObjectSelector(metadata, @"groupMetadata") ?: sciAnyIvar(metadata, "_groupMetadata");
    if (!groupMeta) return nil;
    id identifier = sciTryObjectSelector(groupMeta, @"groupPhotoIdentifier") ?: sciAnyIvar(groupMeta, "_groupPhotoIdentifier");
    if (!identifier) return nil;
    id specifier = sciTryObjectSelector(identifier, @"groupImageSpecifier") ?: sciAnyIvar(identifier, "_groupImageSpecifier");
    if (!specifier) return nil;
    id imageURL = sciTryObjectSelector(specifier, @"remoteImageURL") ?: sciAnyIvar(specifier, "_remoteImageURL");
    if (!imageURL) return nil;
    NSString *s = sciTryURLSelectors(imageURL, @[@"url", @"fallbackURL"]);
    return s.length ? s : nil;
}

static NSArray<NSString *> *sciThreadUserNames(id metadata) {
    id users = sciTryObjectSelector(metadata, @"users") ?: sciAnyIvar(metadata, "_users");
    if (![users isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id u in (NSArray *)users) {
        NSString *n = sciTryStringSelectors(u, @[@"fullName"]);
        if (!n.length) {
            id fc = sciAnyIvar(u, "_fieldCache");
            if ([fc isKindOfClass:[NSDictionary class]]) {
                id v = ((NSDictionary *)fc)[@"full_name"] ?: ((NSDictionary *)fc)[@"username"];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) n = v;
            }
        }
        if (!n.length) n = sciTryStringSelectors(u, @[@"username"]);
        if (n.length) [names addObject:n];
    }
    return names.count ? names : nil;
}

static id sciThreadMetadataFromObject(id threadObj) {
    if (!threadObj) return nil;
    Class metaCls = NSClassFromString(@"IGDirectThreadMetadata");
    id meta = sciTryObjectSelector(threadObj, @"threadMetadata") ?: sciAnyIvar(threadObj, "_threadMetadata");
    if (metaCls && [meta isKindOfClass:metaCls]) return meta;
    id provider = sciTryObjectSelector(threadObj, @"threadInfoProvider") ?: sciAnyIvar(threadObj, "_threadInfoProvider");
    if (provider) {
        id pmeta = sciTryObjectSelector(provider, @"threadMetadata") ?: sciAnyIvar(provider, "_threadMetadata");
        if (metaCls && [pmeta isKindOfClass:metaCls]) return pmeta;
        if (!meta) meta = pmeta;
    }
    if (metaCls) {
        id found = sciFindObjectWithClassNames(threadObj, @[@"IGDirectThreadMetadata"], 6);
        if (found) return found;
    }
    return meta;
}

// YES when metadata was read (group-ness known), even for a 1:1. *outTitle is
// set only for groups: the custom name, else IG-style joined participant names.
static BOOL sciExtractThreadMeta(id threadObj, BOOL *outIsGroup, NSString **outTitle, NSString **outPhotoURL) {
    id meta = sciThreadMetadataFromObject(threadObj);
    if (!meta) return NO;
    BOOL found = NO;
    BOOL isGroup = sciBoolSelector(meta, @"isGroup", &found);
    if (!found) isGroup = sciBoolIvar(meta, "_isGroup", &found);
    if (!found) return NO;
    NSString *title = nil;
    NSString *photo = nil;
    if (isGroup) {
        title = sciGroupCustomName(meta);
        if (!title.length) title = sciJoinThreadNames(sciThreadUserNames(meta));
        photo = sciGroupPhotoURL(meta);
    }
    if (outIsGroup) *outIsGroup = isGroup;
    if (outTitle) *outTitle = title;
    if (outPhotoURL) *outPhotoURL = photo;
    return YES;
}

static NSMutableSet<NSString *> *sciResolvedThreadMetaKeys(void) {
    static NSMutableSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSMutableSet set]; });
    return set;
}

void sciDMCaptureResolveThreadMeta(id applicator, NSString *threadId, NSString *ownerPk) {
    if (!sciCaptureEnabled() || !threadId.length || !ownerPk.length) return;
    NSString *key = [NSString stringWithFormat:@"%@:%@", ownerPk, threadId];
    @synchronized (sciResolvedThreadMetaKeys()) {
        if ([sciResolvedThreadMetaKeys() containsObject:key]) return;
        [sciResolvedThreadMetaKeys() addObject:key];
    }
    NSString *owner = [ownerPk copy];
    NSString *tid = [threadId copy];

    void (^clearKey)(void) = ^{
        @synchronized (sciResolvedThreadMetaKeys()) { [sciResolvedThreadMetaKeys() removeObject:key]; }
    };
    // Returns YES once metadata was read (group or confirmed 1:1) so we stop
    // re-resolving; NO means try again on the next unsend in this thread.
    BOOL (^apply)(id) = ^BOOL(id threadObj) {
        BOOL isGroup = NO; NSString *title = nil; NSString *photo = nil;
        if (!sciExtractThreadMeta(threadObj, &isGroup, &title, &photo)) return NO;
        if (isGroup) [SCIDeletedMessagesStorage backfillThreadTitle:title isGroup:YES photoURL:photo forThreadId:tid ownerPK:owner];
        return YES;
    };

    id cache = sciDirectCacheFromApplicator(applicator);
    if (!cache) { clearKey(); return; }

    // Synchronous attempt via the in-memory client state.
    @try {
        SEL sel = NSSelectorFromString(@"threadClientStateForThreadId:");
        if ([cache respondsToSelector:sel]) {
            id state = ((id(*)(id, SEL, id))objc_msgSend)(cache, sel, tid);
            if (state && apply(state)) return;
        }
    } @catch (__unused id e) {}

    // Async cache fetch — the thread object carries IGDirectThreadMetadata.
    SEL publicFetch = NSSelectorFromString(@"fetchThreadWithThreadId:completion:");
    @try {
        if ([cache respondsToSelector:publicFetch]) {
            ((void(*)(id, SEL, id, id))objc_msgSend)(cache, publicFetch, tid, ^(id fetchedThread) {
                if (!apply(fetchedThread)) clearKey();
            });
            return;
        }
    } @catch (__unused id e) {}
    clearKey();
}

#pragma mark - Reaction unsend capture

static BOOL sciReactionCaptureEnabled(void) {
    return [SCIUtils getBoolPref:@"msgs_deleted_log_reactions"];
}

// Best-effort one-line preview of the message a reaction was attached to.
static NSString *sciReactionTargetPreview(id targetMessage) {
    if (!targetMessage) return nil;
    @try {
        NSDictionary *snap = sciBuildSnapshot(targetMessage, nil);
        NSString *txt = snap[@"text"];
        if ([txt isKindOfClass:[NSString class]] && txt.length) {
            NSString *oneLine = [txt stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            if (oneLine.length > 80) oneLine = [[oneLine substringToIndex:77] stringByAppendingString:@"..."];
            return oneLine;
        }
        NSNumber *kindNum = snap[@"kind"];
        if ([kindNum isKindOfClass:[NSNumber class]]) {
            SCIDeletedMessageKind k = (SCIDeletedMessageKind)kindNum.integerValue;
            if (k != SCIDeletedMessageKindUnknown && k != SCIDeletedMessageKindText) {
                return [SCIDeletedMessageKindLocalizedName(k) lowercaseString];
            }
        }
    } @catch (__unused id e) {}
    return nil;
}

NSDictionary *sciDMCaptureNoteReactionUnsend(id reaction,
                                             NSString *reactorPk,
                                             id targetMessage,
                                             NSString *targetMessageId,
                                             id applicator,
                                             NSString *ownerPk,
                                             NSString *threadId) {
    if (!sciReactionCaptureEnabled() || !reaction) return nil;

    NSString *owner = ownerPk.length ? [ownerPk copy] : @"";

    // Emoji + reactor + timestamp from IGDirectMessageReaction.
    NSString *emoji = sciStrIvar(reaction, "_userBasedReaction_emojiUnicode");
    NSString *pk = reactorPk.length ? reactorPk : sciStrIvar(reaction, "_userBasedReaction_userId");
    if (!pk.length) return nil;

    NSDate *reactedAt = nil;
    id ts = sciAnyIvar(reaction, "_userBasedReaction_serverTimestamp");
    if ([ts isKindOfClass:[NSDate class]]) reactedAt = ts;

    // The "message id" of a reaction record is synthetic but stable so repeated
    // deltas dedupe: target message id + reactor + emoji.
    NSString *recordId = [NSString stringWithFormat:@"reaction:%@:%@:%@",
                          targetMessageId.length ? targetMessageId : @"?",
                          pk,
                          emoji.length ? emoji : @"?"];

    NSString *targetPreview = sciReactionTargetPreview(targetMessage);

    NSString *u = nil, *fn = nil, *pic = nil;
    sciResolveSenderInfo(pk, &u, &fn, &pic);

    BOOL threadIsGroup = NO;
    NSString *threadTitle = nil;
    if (threadId.length) {
        SCIDirectThreadContext *ctx = SCIDirectActiveThreadContext();
        if (ctx && [ctx.threadId isEqualToString:threadId]) {
            threadIsGroup = ctx.isGroup;
            threadTitle = ctx.threadName.length ? ctx.threadName : nil;
        }
    }

    NSDate *now = [NSDate date];
    dispatch_async(sciCaptureQueue(), ^{
        if (pk.length && [SCIDeletedMessagesStorage isSenderBlocked:pk ownerPK:owner]) return;

        SCIDeletedMessage *m = [SCIDeletedMessage new];
        m.messageId            = recordId;
        m.threadId             = threadId ?: @"";
        m.threadTitle          = threadTitle;
        m.isGroup              = threadIsGroup;
        m.senderPk             = pk;
        m.senderUsername       = u;
        m.senderFullName       = fn;
        m.senderProfilePicURL  = pic;
        m.sentAt               = reactedAt ?: now;
        m.capturedAt           = now;
        m.deletedAt            = now;
        m.kind                 = SCIDeletedMessageKindReaction;
        m.reactionEmoji        = emoji;
        m.reactionTargetPreview = targetPreview;
        // Human-readable body used by previews / search.
        if (emoji.length && targetPreview.length) {
            m.text = [NSString stringWithFormat:@"Removed %@ from \"%@\"", emoji, targetPreview];
        } else if (emoji.length) {
            m.text = [NSString stringWithFormat:@"Removed reaction %@", emoji];
        } else {
            m.text = @"Removed a reaction";
        }
        m.previewText = m.text;
        m.replyToMessageId = targetMessageId;

        [SCIDeletedMessagesStorage saveMessage:m forOwnerPK:owner];
    });

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (pk.length) info[@"senderPk"] = pk;
    if (u.length) info[@"senderUsername"] = u;
    if (fn.length) info[@"senderFullName"] = fn;
    if (emoji.length) info[@"emoji"] = emoji;
    if (targetPreview.length) info[@"targetPreview"] = targetPreview;
    return info.copy;
}

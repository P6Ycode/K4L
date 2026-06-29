#import "SPKDirectSeenContext.h"

#import <objc/message.h>

#import "../../Networking/SPKInstagramAPI.h"
#import "../../Settings/SPKSetting.h"
#import "../../Settings/SPKSettingsViewController.h"
#import "../../Settings/SPKTopicSettingsSupport.h"
#import "../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../Shared/UI/SPKMediaChrome.h"
#import "../../Shared/UI/SPKNotificationCenter.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "SPKDirectUserResolver.h"

@implementation SPKDirectThreadContext
- (instancetype)init {
    if ((self = [super init])) {
        _users = @[];
    }
    return self;
}
@end

static SPKDirectThreadContext *SPKDirectActiveContext;
static NSArray<NSDictionary *> *SPKDirectManualSeenThreadsCache;
static NSSet<NSString *> *SPKDirectManualSeenThreadIdsCache;
// Effective defaults key the caches were built from; when the current mode or
// account produces a different key, the caches are rebuilt.
static NSString *SPKDirectManualSeenCachedKey;
BOOL SPKDirectSeenDebugPrintEnabled = NO;

static id SPKDirectKVCObject(id target, NSString *key) {
    if (!target || key.length == 0) return nil;
    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SPKDirectObjectForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;

    NSMethodSignature *sig = [target methodSignatureForSelector:selector];
    if (!sig) return nil;

    const char *returnType = [sig methodReturnType];
    if (returnType == NULL) return nil;

    if (strcmp(returnType, "@") == 0) {
        return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    }

    if (strcmp(returnType, "c") == 0 || strcmp(returnType, "B") == 0) {
        BOOL val = ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }
    if (strcmp(returnType, "i") == 0 || strcmp(returnType, "I") == 0 ||
        strcmp(returnType, "s") == 0 || strcmp(returnType, "S") == 0) {
        int val = ((int (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }
    if (strcmp(returnType, "l") == 0 || strcmp(returnType, "L") == 0 ||
        strcmp(returnType, "q") == 0 || strcmp(returnType, "Q") == 0) {
        long long val = ((long long (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }
    if (strcmp(returnType, "f") == 0) {
        float val = ((float (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }
    if (strcmp(returnType, "d") == 0) {
        double val = ((double (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }

    return nil;
}

static NSString *SPKDirectStringFromValue(id value) {
    if (!value || value == (id)kCFNull) return nil;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *string = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return string.length > 0 ? string : nil;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *string = [[value stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return string.length > 0 ? string : nil;
    }
    NSString *description = [[value description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return description.length > 0 ? description : nil;
}

static NSString *SPKDirectFirstStringForSelectors(id target, NSArray<NSString *> *selectors) {
    for (NSString *selectorName in selectors) {
        NSString *value = SPKDirectStringFromValue(SPKDirectObjectForSelector(target, selectorName));
        if (value.length == 0) value = SPKDirectStringFromValue(SPKDirectKVCObject(target, selectorName));
        if (value.length > 0) return value;
    }
    return nil;
}

static NSString *SPKDirectThreadIdDirectlyFromObject(id object) {
    if (!object) return nil;
    NSString *threadId = SPKDirectFirstStringForSelectors(object, @[@"threadId", @"threadID", @"thread_id"]);
    if (threadId.length == 0 && [object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        threadId = SPKDirectStringFromValue(dict[@"threadId"] ?: dict[@"thread_id"]);
    }
    return threadId;
}

static NSNumber *SPKDirectFirstNumberForSelectors(id target, NSArray<NSString *> *selectors) {
    for (NSString *selectorName in selectors) {
        id value = SPKDirectObjectForSelector(target, selectorName);
        if (!value) value = SPKDirectKVCObject(target, selectorName);
        if ([value respondsToSelector:@selector(boolValue)]) return @([value boolValue]);
    }
    return nil;
}

static NSArray *SPKDirectArrayFromCollection(id collection) {
    if (!collection ||
        [collection isKindOfClass:[NSString class]] ||
        [collection isKindOfClass:[NSDictionary class]] ||
        [collection isKindOfClass:[NSURL class]]) {
        return nil;
    }
    if ([collection isKindOfClass:[NSArray class]]) return collection;
    if ([collection isKindOfClass:[NSOrderedSet class]]) return [(NSOrderedSet *)collection array];
    if ([collection isKindOfClass:[NSSet class]]) return [(NSSet *)collection allObjects];
    if ([collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id item in collection) [array addObject:item];
        return array;
    }
    return nil;
}

static NSArray<NSDictionary *> *SPKDirectUsersFromObject(id object) {
    NSMutableArray<NSDictionary *> *users = [NSMutableArray array];
    NSArray<NSString *> *selectors = @[
        @"users",
        @"threadUsers",
        @"recentlyActiveUsers",
        @"participants",
        @"recipientUsers"
    ];

    for (NSString *selectorName in selectors) {
        id collection = SPKDirectObjectForSelector(object, selectorName);
        if (!collection) collection = SPKDirectKVCObject(object, selectorName);
        NSArray *rawUsers = SPKDirectArrayFromCollection(collection);
        if (rawUsers.count == 0) continue;

        for (id user in rawUsers) {
            NSString *pk = SPKDirectFirstStringForSelectors(user, @[@"pk", @"userId", @"userID", @"id"]);
            NSString *username = SPKDirectFirstStringForSelectors(user, @[@"username", @"userName"]);
            NSString *fullName = SPKDirectFirstStringForSelectors(user, @[@"fullName", @"full_name", @"name"]);
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            if (pk.length > 0) entry[@"pk"] = pk;
            if (username.length > 0) entry[@"username"] = username;
            if (fullName.length > 0) entry[@"fullName"] = fullName;
            NSString *profilePicUrl = spkDirectUserResolverProfilePicURLStringFromUser(user);
            if (profilePicUrl.length > 0) entry[@"profilePicUrl"] = profilePicUrl;
            if (entry.count > 0) [users addObject:entry];
        }

        if (users.count > 0) break;
    }

    return users.copy;
}

static NSString *SPKDirectNameFromUsers(NSArray<NSDictionary *> *users) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSDictionary *user in users) {
        NSString *username = [user[@"username"] isKindOfClass:[NSString class]] ? user[@"username"] : nil;
        NSString *fullName = [user[@"fullName"] isKindOfClass:[NSString class]] ? user[@"fullName"] : nil;
        NSString *name = fullName.length > 0 ? fullName : (username.length > 0 ? [@"@" stringByAppendingString:username] : nil);
        if (name.length > 0) [names addObject:name];
    }
    return names.count > 0 ? [names componentsJoinedByString:@", "] : nil;
}

static NSString *SPKDirectNormalizeUsername(NSString *username) {
    NSString *trimmed = [[username ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([trimmed hasPrefix:@"@"]) trimmed = [trimmed substringFromIndex:1];
    return trimmed;
}

static NSString *SPKDirectCleanFullName(NSString *fullName, NSString *username) {
    NSString *cleanName = [SPKDirectStringFromValue(fullName) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *normalizedUsername = SPKDirectNormalizeUsername(username);
    if (cleanName.length == 0) return nil;
    if ([SPKDirectNormalizeUsername(cleanName) isEqualToString:normalizedUsername]) return nil;
    return cleanName;
}

static SPKDirectThreadContext *SPKDirectThreadContextFromSourceInternal(id source, NSMutableSet<NSValue *> *visited, BOOL allowActiveFallback);

static SPKDirectThreadContext *SPKDirectContextDirectlyFromObject(id object) {
    if (!object) return nil;

    id target = object;

    // Resolve threadInfoProvider (e.g. from IGDirectThreadViewController, or via _threadSession)
    id provider = [SPKUtils getIvarForObj:object name:"_threadInfoProvider"];
    if (!provider) {
        provider = SPKDirectObjectForSelector(object, @"threadInfoProvider");
    }
    if (!provider) {
        id threadSession = [SPKUtils getIvarForObj:object name:"_threadSession"];
        if (threadSession) {
            provider = [SPKUtils getIvarForObj:threadSession name:"_threadInfoProvider"];
            if (!provider) provider = SPKDirectObjectForSelector(threadSession, @"threadInfoProvider");
        }
    }
    if (!provider) {
        id vcCtx = [SPKUtils getIvarForObj:object name:"_threadViewControllerContext"];
        if (!vcCtx) vcCtx = SPKDirectObjectForSelector(object, @"threadViewControllerContext");
        if (vcCtx) {
            provider = SPKDirectObjectForSelector(vcCtx, @"threadInfoProvider");
        }
    }
    if (provider) {
        target = provider;
    }

    id metadata = nil;
    if ([target respondsToSelector:NSSelectorFromString(@"threadMetadata")]) {
        id meta = SPKDirectObjectForSelector(target, @"threadMetadata");
        if (meta) {
            metadata = meta;
            target = meta;
        }
    }

    NSString *threadId = SPKDirectThreadIdDirectlyFromObject(target);
    if (threadId.length == 0 && target != object) {
        threadId = SPKDirectThreadIdDirectlyFromObject(object);
    }
    if (threadId.length == 0 && [object respondsToSelector:NSSelectorFromString(@"threadKey")]) {
        id key = SPKDirectObjectForSelector(object, @"threadKey");
        threadId = SPKDirectThreadIdDirectlyFromObject(key);
    }
    if (threadId.length == 0) return nil;

    NSArray<NSDictionary *> *users = SPKDirectUsersFromObject(target);
    if (users.count == 0 && target != object) {
        users = SPKDirectUsersFromObject(object);
    }

    NSString *threadName = SPKDirectFirstStringForSelectors(target, @[@"threadName", @"threadTitle", @"title", @"name"]);
    if (threadName.length == 0 && [object isKindOfClass:[UIViewController class]]) {
        threadName = ((UIViewController *)object).navigationItem.title;
    }
    if (threadName.length == 0 && [object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        threadName = SPKDirectStringFromValue(dict[@"threadName"] ?: dict[@"thread_title"] ?: dict[@"title"]);
    }
    if (threadName.length == 0 && target != object) {
        threadName = SPKDirectFirstStringForSelectors(object, @[@"threadName", @"threadTitle", @"title", @"name"]);
    }
    if (threadName.length == 0) threadName = SPKDirectNameFromUsers(users);

    NSNumber *isGroupValue = SPKDirectFirstNumberForSelectors(target, @[@"isGroup", @"isGroupThread", @"groupThread"]);
    if (!isGroupValue && [object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        id raw = dict[@"isGroup"] ?: dict[@"is_group"] ?: dict[@"is_group_thread"];
        if ([raw respondsToSelector:@selector(boolValue)]) isGroupValue = @([raw boolValue]);
    }
    if (!isGroupValue && target != object) {
        isGroupValue = SPKDirectFirstNumberForSelectors(object, @[@"isGroup", @"isGroupThread", @"groupThread"]);
    }

    if (SPKDirectSeenDebugPrintEnabled) {
        SPKLog(@"Messages", @"SPKDirectContextDirectlyFromObject: object=%@ provider=%@ metadata=%@ target=%@ threadId=%@ name=%@ usersCount=%lu users=%@",
               NSStringFromClass([object class]),
               provider ? NSStringFromClass([provider class]) : @"nil",
               metadata ? NSStringFromClass([metadata class]) : @"nil",
               NSStringFromClass([target class]),
               threadId,
               threadName,
               (unsigned long)users.count,
               users);
    }

    SPKDirectThreadContext *context = [SPKDirectThreadContext new];
    context.threadId = threadId;
    context.threadName = threadName ?: @"";
    context.isGroup = [isGroupValue boolValue];
    context.users = users ?: @[];

    if (context.isGroup && target) {
        @try {
            id groupMeta = SPKDirectObjectForSelector(target, @"groupMetadata");
            id photoId   = groupMeta  ? SPKDirectObjectForSelector(groupMeta, @"groupPhotoIdentifier")   : nil;
            id specifier = photoId    ? SPKDirectObjectForSelector(photoId,   @"groupImageSpecifier")    : nil;
            id remoteUrl = specifier  ? SPKDirectObjectForSelector(specifier, @"remoteImageURL")         : nil;
            id url       = remoteUrl  ? SPKDirectObjectForSelector(remoteUrl, @"url")                    : nil;
            if ([url isKindOfClass:[NSURL class]])   context.groupPhotoUrl = ((NSURL *)url).absoluteString;
            else if ([url isKindOfClass:[NSString class]] && [(NSString *)url length]) context.groupPhotoUrl = url;
        } @catch (__unused id e) {}
    }

    return context;
}

static SPKDirectThreadContext *SPKDirectThreadContextFromSourceInternal(id source, NSMutableSet<NSValue *> *visited, BOOL allowActiveFallback) {
    if (!source) return allowActiveFallback ? SPKDirectActiveContext : nil;

    NSValue *pointerValue = [NSValue valueWithNonretainedObject:source];
    if ([visited containsObject:pointerValue]) return nil;
    [visited addObject:pointerValue];

    SPKDirectThreadContext *context = SPKDirectContextDirectlyFromObject(source);
    if (context.threadId.length > 0) return context;

    if ([source isKindOfClass:[UIView class]]) {
        context = SPKDirectThreadContextFromSourceInternal([SPKUtils nearestViewControllerForView:(UIView *)source], visited, NO);
        if (context.threadId.length > 0) return context;
    }

    if ([source isKindOfClass:[UIViewController class]]) {
        UIViewController *viewController = (UIViewController *)source;
        context = SPKDirectThreadContextFromSourceInternal(viewController.parentViewController, visited, NO);
        if (context.threadId.length > 0) return context;
        context = SPKDirectThreadContextFromSourceInternal(viewController.navigationController, visited, NO);
        if (context.threadId.length > 0) return context;
        for (UIViewController *child in viewController.childViewControllers) {
            context = SPKDirectThreadContextFromSourceInternal(child, visited, NO);
            if (context.threadId.length > 0) return context;
        }
    }

    for (NSString *key in @[
        @"_thread",
        @"thread",
        @"_directThread",
        @"directThread",
        @"_threadInfoProvider",
        @"threadInfoProvider",
        @"_threadViewController",
        @"threadViewController",
        @"_messageListViewController",
        @"messageListViewController",
        @"_directMessageListViewController",
        @"directMessageListViewController",
        @"_messageListDataSource",
        @"messageListDataSource",
        @"_dataSource",
        @"dataSource",
        @"_stateProvider",
        @"stateProvider",
        @"_delegate",
        @"delegate",
        @"_viewModel",
        @"viewModel",
        @"_item",
        @"item"
    ]) {
        id candidate = [key hasPrefix:@"_"] ? [SPKUtils getIvarForObj:source name:key.UTF8String] : SPKDirectKVCObject(source, key);
        context = SPKDirectThreadContextFromSourceInternal(candidate, visited, NO);
        if (context.threadId.length > 0) return context;
    }

    return allowActiveFallback ? SPKDirectActiveContext : nil;
}

SPKDirectThreadContext *SPKDirectThreadContextFromSource(id source) {
    return SPKDirectThreadContextFromSourceInternal(source, [NSMutableSet set], YES);
}

static id SPKDirectInboxValueForKeys(id candidate, NSArray<NSString *> *keys) {
    if (!candidate) return nil;
    for (NSString *key in keys) {
        id value = nil;
        if ([candidate isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)candidate;
            value = dict[key];
            if (!value && [key containsString:@"_"]) {
                NSString *camelKey = [key stringByReplacingOccurrencesOfString:@"_" withString:@""];
                value = dict[camelKey];
            }
        } else {
            value = SPKDirectKVCObject(candidate, key);
            if (!value) {
                NSString *ivarKey = [@"_" stringByAppendingString:key];
                value = [SPKUtils getIvarForObj:candidate name:ivarKey.UTF8String];
            }
        }
        if (value && value != (id)kCFNull) return value;
    }
    return nil;
}

static SPKDirectThreadContext *SPKDirectContextFromShallowInboxObject(id object) {
    if (!object) return nil;

    id target = object;
    
    id provider = [SPKUtils getIvarForObj:object name:"_threadInfoProvider"];
    if (!provider) provider = SPKDirectObjectForSelector(object, @"threadInfoProvider");
    if (!provider) {
        id threadSession = [SPKUtils getIvarForObj:object name:"_threadSession"];
        if (threadSession) {
            provider = [SPKUtils getIvarForObj:threadSession name:"_threadInfoProvider"];
            if (!provider) provider = SPKDirectObjectForSelector(threadSession, @"threadInfoProvider");
        }
    }
    if (!provider) {
        id vcCtx = [SPKUtils getIvarForObj:object name:"_threadViewControllerContext"];
        if (!vcCtx) vcCtx = SPKDirectObjectForSelector(object, @"threadViewControllerContext");
        if (vcCtx) {
            provider = SPKDirectObjectForSelector(vcCtx, @"threadInfoProvider");
        }
    }
    if (provider) {
        target = provider;
    }

    if ([target respondsToSelector:NSSelectorFromString(@"threadMetadata")]) {
        id meta = SPKDirectObjectForSelector(target, @"threadMetadata");
        if (meta) target = meta;
    }

    NSString *threadId = SPKDirectStringFromValue(SPKDirectInboxValueForKeys(target, @[@"threadId", @"threadID", @"thread_id"]));
    if (threadId.length == 0 && target != object) {
        threadId = SPKDirectStringFromValue(SPKDirectInboxValueForKeys(object, @[@"threadId", @"threadID", @"thread_id"]));
    }
    if (threadId.length == 0) return nil;

    NSString *threadName = SPKDirectStringFromValue(SPKDirectInboxValueForKeys(target, @[@"threadName", @"threadTitle", @"thread_title", @"title", @"name"]));
    if (threadName.length == 0 && target != object) {
        threadName = SPKDirectStringFromValue(SPKDirectInboxValueForKeys(object, @[@"threadName", @"threadTitle", @"thread_title", @"title", @"name"]));
    }

    id isGroupValue = SPKDirectInboxValueForKeys(target, @[@"isGroup", @"isGroupThread", @"groupThread", @"is_group", @"is_group_thread"]);
    if (!isGroupValue && target != object) {
        isGroupValue = SPKDirectInboxValueForKeys(object, @[@"isGroup", @"isGroupThread", @"groupThread", @"is_group", @"is_group_thread"]);
    }

    NSArray<NSDictionary *> *users = SPKDirectUsersFromObject(target);
    if (users.count == 0 && target != object) {
        users = SPKDirectUsersFromObject(object);
    }
    if (threadName.length == 0) {
        threadName = SPKDirectNameFromUsers(users);
    }

    SPKDirectThreadContext *context = [SPKDirectThreadContext new];
    context.threadId = threadId;
    context.threadName = threadName ?: @"";
    context.isGroup = [isGroupValue respondsToSelector:@selector(boolValue)] ? [isGroupValue boolValue] : NO;
    context.users = users ?: @[];
    return context;
}

static SPKDirectThreadContext *SPKDirectContextFromShallowInboxCandidate(id candidate) {
    if (!candidate) return nil;

    SPKDirectThreadContext *context = SPKDirectContextFromShallowInboxObject(candidate);
    if (context.threadId.length > 0) return context;

    NSArray<NSString *> *keys = @[
        @"_thread",
        @"thread",
        @"_directThread",
        @"directThread",
        @"_threadInfo",
        @"threadInfo",
        @"_threadSummary",
        @"threadSummary",
        @"_threadMetadata",
        @"threadMetadata",
        @"_threadViewModel",
        @"threadViewModel",
        @"_inboxItem",
        @"inboxItem",
        @"_item",
        @"item"
    ];

    for (NSString *key in keys) {
        id nested = nil;
        if ([candidate isKindOfClass:[NSDictionary class]]) {
            nested = ((NSDictionary *)candidate)[key];
        }
        if (!nested) {
            nested = [key hasPrefix:@"_"] ? [SPKUtils getIvarForObj:candidate name:key.UTF8String] : SPKDirectKVCObject(candidate, key);
        }
        context = SPKDirectContextFromShallowInboxObject(nested);
        if (context.threadId.length > 0) return context;
    }

    return nil;
}

SPKDirectThreadContext *SPKDirectThreadContextFromInboxViewModel(id viewModel) {
    return SPKDirectContextFromShallowInboxCandidate(viewModel);
}

NSDictionary *SPKDirectThreadEntryFromContext(SPKDirectThreadContext *context) {
    NSString *threadId = SPKDirectStringFromValue(context.threadId);
    if (threadId.length == 0) return nil;
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"threadId"] = threadId;
    entry[@"threadName"] = context.threadName ?: @"";
    entry[@"isGroup"] = @(context.isGroup);
    entry[@"users"] = context.users ?: @[];
    if (context.groupPhotoUrl.length) entry[@"groupPhotoUrl"] = context.groupPhotoUrl;
    return entry.copy;
}

void SPKDirectSetActiveThreadContext(SPKDirectThreadContext *context) {
    NSString *oldThreadId = SPKDirectActiveContext.threadId ?: @"";
    NSString *newThreadId = context.threadId ?: @"";
    SPKDirectActiveContext = context;
    if (newThreadId.length > 0 && ![oldThreadId isEqualToString:newThreadId]) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Active thread context set threadId=%@ threadName=%@ isGroup=%d",
               newThreadId,
               context.threadName ?: @"",
               context.isGroup);
    } else if (newThreadId.length == 0 && oldThreadId.length > 0) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Active thread context cleared threadId=%@", oldThreadId);
    }
}

SPKDirectThreadContext *SPKDirectActiveThreadContext(void) {
    return SPKDirectActiveContext;
}

static NSArray<NSDictionary *> *SPKDirectManualSeenThreadListFromRawValue(id rawStored) {
    NSArray *stored = [rawStored isKindOfClass:[NSArray class]] ? rawStored : nil;
    NSMutableArray<NSDictionary *> *threads = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (id value in stored ?: @[]) {
        NSDictionary *dict = [value isKindOfClass:[NSDictionary class]] ? value : nil;
        NSString *threadId = SPKDirectStringFromValue(dict[@"threadId"]);
        if (threadId.length == 0 || [seen containsObject:threadId]) continue;
        [seen addObject:threadId];

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"threadId"] = threadId;
        entry[@"threadName"] = SPKDirectStringFromValue(dict[@"threadName"]) ?: @"";
        entry[@"isGroup"] = @([dict[@"isGroup"] respondsToSelector:@selector(boolValue)] ? [dict[@"isGroup"] boolValue] : NO);
        entry[@"users"] = [dict[@"users"] isKindOfClass:[NSArray class]] ? dict[@"users"] : @[];
        if (dict[@"addedAt"]) entry[@"addedAt"] = dict[@"addedAt"];
        NSString *groupPhotoUrl = SPKDirectStringFromValue(dict[@"groupPhotoUrl"]);
        if (groupPhotoUrl.length) entry[@"groupPhotoUrl"] = groupPhotoUrl;
        [threads addObject:entry.copy];
    }

    return threads.copy;
}

static void SPKDirectUpdateManualSeenThreadCaches(NSArray<NSDictionary *> *threads) {
    SPKDirectManualSeenThreadsCache = [threads copy] ?: @[];
    NSMutableSet<NSString *> *threadIds = [NSMutableSet set];
    for (NSDictionary *entry in SPKDirectManualSeenThreadsCache) {
        NSString *threadId = SPKDirectStringFromValue(entry[@"threadId"]);
        if (threadId.length > 0) [threadIds addObject:threadId];
    }
    SPKDirectManualSeenThreadIdsCache = threadIds.copy;
}

static NSString *SPKDirectManualSeenThreadsKeyForMode(BOOL manualSeenEnabled) {
    // Separate lists per mode: ON → Excluded (chats using default seen),
    // OFF → Included (chats requiring manual seen).
    return manualSeenEnabled ? @"msgs_manual_seen_excluded" : @"msgs_manual_seen_included";
}

NSArray<NSDictionary *> *SPKDirectManualSeenThreadList(BOOL manualSeenEnabled) {
    NSString *baseKey = SPKDirectManualSeenThreadsKeyForMode(manualSeenEnabled);
    NSString *effectiveKey = SPKEffectivePreferenceKey(baseKey);
    // Rebuild when the mode or account changes (effective key differs).
    if (!SPKDirectManualSeenThreadsCache || ![effectiveKey isEqualToString:SPKDirectManualSeenCachedKey]) {
        SPKDirectManualSeenCachedKey = effectiveKey;
        SPKDirectUpdateManualSeenThreadCaches(SPKDirectManualSeenThreadListFromRawValue(SPKPreferenceObjectForKey(baseKey)));
    }
    return SPKDirectManualSeenThreadsCache;
}

void SPKDirectSetManualSeenThreadList(NSArray<NSDictionary *> *threads, BOOL manualSeenEnabled) {
    NSString *baseKey = SPKDirectManualSeenThreadsKeyForMode(manualSeenEnabled);
    NSArray *normalized = SPKDirectManualSeenThreadListFromRawValue(threads);
    SPKPreferenceSetObject(normalized, baseKey);
    SPKDirectManualSeenCachedKey = SPKEffectivePreferenceKey(baseKey);
    SPKDirectUpdateManualSeenThreadCaches(normalized);
}

BOOL SPKDirectManualSeenListContainsThreadId(NSString *threadId, BOOL manualSeenEnabled) {
    NSString *normalizedThreadId = SPKDirectStringFromValue(threadId);
    if (normalizedThreadId.length == 0) return NO;
    // Always go through the list (cheap when cached) so the membership set
    // matches the current mode/account, not a stale one.
    (void)SPKDirectManualSeenThreadList(manualSeenEnabled);
    return [SPKDirectManualSeenThreadIdsCache containsObject:normalizedThreadId];
}

void SPKDirectAddOrUpdateManualSeenThreadEntry(NSDictionary *entry, BOOL manualSeenEnabled) {
    NSString *threadId = SPKDirectStringFromValue(entry[@"threadId"]);
    if (threadId.length == 0) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Ignored add/update for manual seen list: missing threadId entry=%@", entry);
        return;
    }

    NSMutableArray<NSDictionary *> *threads = [SPKDirectManualSeenThreadList(manualSeenEnabled) mutableCopy];
    NSInteger existingIndex = -1;
    for (NSInteger idx = 0; idx < (NSInteger)threads.count; idx++) {
        if ([threads[idx][@"threadId"] isEqualToString:threadId]) {
            existingIndex = idx;
            break;
        }
    }

    NSMutableDictionary *merged = [entry mutableCopy];
    merged[@"threadId"] = threadId;
    NSDictionary *existing = existingIndex >= 0 ? threads[existingIndex] : nil;
    if (!merged[@"threadName"] && existing[@"threadName"]) merged[@"threadName"] = existing[@"threadName"];
    if (!merged[@"threadName"]) merged[@"threadName"] = @"";
    if (!merged[@"isGroup"] && existing[@"isGroup"]) merged[@"isGroup"] = existing[@"isGroup"];
    if (!merged[@"isGroup"]) merged[@"isGroup"] = @(NO);
    if (![merged[@"users"] isKindOfClass:[NSArray class]] || [(NSArray *)merged[@"users"] count] == 0) {
        merged[@"users"] = [existing[@"users"] isKindOfClass:[NSArray class]] ? existing[@"users"] : @[];
    }
    if (existing[@"addedAt"]) {
        merged[@"addedAt"] = existing[@"addedAt"];
    }
    if (!merged[@"addedAt"]) merged[@"addedAt"] = @([[NSDate date] timeIntervalSince1970]);
    if (!merged[@"groupPhotoUrl"] && existing[@"groupPhotoUrl"]) merged[@"groupPhotoUrl"] = existing[@"groupPhotoUrl"];

    if (existingIndex >= 0) {
        threads[existingIndex] = merged.copy;
    } else {
        [threads addObject:merged.copy];
    }
    SPKDirectSetManualSeenThreadList(threads, manualSeenEnabled);
    SPKLog(@"Messages", @"[Sparkle MessagesSeen] %@ manual seen list entry threadId=%@ threadName=%@ list=%@ count=%lu",
           existingIndex >= 0 ? @"Updated" : @"Added",
           threadId,
           merged[@"threadName"] ?: @"",
           SPKDirectManualSeenListTitle(manualSeenEnabled),
           (unsigned long)threads.count);
}

void SPKDirectRemoveManualSeenThreadId(NSString *threadId, BOOL manualSeenEnabled) {
    NSString *normalizedThreadId = SPKDirectStringFromValue(threadId);
    if (normalizedThreadId.length == 0) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Ignored remove for manual seen list: missing threadId");
        return;
    }
    NSMutableArray<NSDictionary *> *threads = [SPKDirectManualSeenThreadList(manualSeenEnabled) mutableCopy];
    NSUInteger beforeCount = threads.count;
    [threads filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        (void)bindings;
        return ![entry[@"threadId"] isEqualToString:normalizedThreadId];
    }]];
    SPKDirectSetManualSeenThreadList(threads, manualSeenEnabled);
    SPKLog(@"Messages", @"[Sparkle MessagesSeen] Removed manual seen list entry threadId=%@ list=%@ before=%lu after=%lu",
           normalizedThreadId,
           SPKDirectManualSeenListTitle(manualSeenEnabled),
           (unsigned long)beforeCount,
           (unsigned long)threads.count);
}

static void SPKDirectEnrichManualSeenThreadEntryIfNeeded(NSDictionary *entry, BOOL manualSeenEnabled) {
    if ([entry[@"isGroup"] boolValue]) return;
    NSString *threadId = SPKDirectStringFromValue(entry[@"threadId"]);
    NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
    
    NSString *currentPk = [SPKUtils currentUserPK];
    NSDictionary *user = nil;
    for (NSDictionary *u in users) {
        if (![u isKindOfClass:[NSDictionary class]]) continue;
        NSString *pk = u[@"pk"];
        if (currentPk.length > 0 && [pk isEqualToString:currentPk]) continue;
        user = u;
        break;
    }
    if (!user && users.count > 0) {
        user = users.firstObject;
    }

    NSString *username = SPKDirectStringFromValue(user[@"username"]);
    NSString *pk = SPKDirectStringFromValue(user[@"pk"]);
    NSString *profilePicUrl = SPKDirectStringFromValue(user[@"profilePicUrl"]);
    if (threadId.length == 0 || username.length == 0) return;
    if (pk.length > 0 && profilePicUrl.length > 0) return; // already fully enriched!

    NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    if (encodedUsername.length == 0) return;

    [SPKInstagramAPI sendRequestWithMethod:@"GET"
                                       path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", encodedUsername]
                                       body:nil
                                 completion:^(NSDictionary *response, NSError *error) {
        NSDictionary *resolvedUser = response[@"data"][@"user"];
        if (![resolvedUser isKindOfClass:[NSDictionary class]]) resolvedUser = response[@"user"];
        if (![resolvedUser isKindOfClass:[NSDictionary class]] || error) {
            SPKLog(@"Messages", @"[Sparkle MessagesSeen] Thread metadata enrichment failed threadId=%@ username=%@ error=%@",
                   threadId,
                   username,
                   error);
            return;
        }

        NSString *resolvedUsername = SPKDirectStringFromValue(resolvedUser[@"username"]) ?: username;
        NSString *resolvedPk = SPKDirectStringFromValue(resolvedUser[@"id"] ?: resolvedUser[@"pk"]) ?: pk ?: @"";
        NSString *fullName = SPKDirectCleanFullName(SPKDirectStringFromValue(resolvedUser[@"full_name"] ?: resolvedUser[@"fullName"]), resolvedUsername) ?: SPKDirectStringFromValue(user[@"fullName"]) ?: @"";
        NSString *profilePic = SPKDirectStringFromValue(resolvedUser[@"profile_pic_url"] ?: resolvedUser[@"profile_pic_url_hd"]);

        NSMutableDictionary *updatedEntry = [entry mutableCopy];
        NSString *threadName = SPKDirectStringFromValue(updatedEntry[@"threadName"]);
        NSString *normalizedThreadName = SPKDirectNormalizeUsername(threadName);
        NSString *normalizedUsername = SPKDirectNormalizeUsername(resolvedUsername);
        if (threadName.length == 0 ||
            [normalizedThreadName isEqualToString:normalizedUsername] ||
            [[threadName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"@"]] caseInsensitiveCompare:resolvedUsername] == NSOrderedSame) {
            updatedEntry[@"threadName"] = fullName.length > 0 ? fullName : resolvedUsername;
        }
        
        NSMutableDictionary *mutUser = [NSMutableDictionary dictionary];
        mutUser[@"pk"] = resolvedPk;
        mutUser[@"username"] = resolvedUsername;
        mutUser[@"fullName"] = fullName;
        if (profilePic.length > 0) mutUser[@"profilePicUrl"] = profilePic;
        
        updatedEntry[@"users"] = @[mutUser.copy];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            SPKDirectAddOrUpdateManualSeenThreadEntry(updatedEntry, manualSeenEnabled);
        });
    }];
}

NSString *SPKDirectManualSeenListTitle(BOOL manualSeenEnabled) {
    return manualSeenEnabled ? @"Excluded Chats" : @"Included Chats";
}

NSUInteger SPKDirectManualSeenThreadCount(BOOL manualSeenEnabled) {
    return SPKDirectManualSeenThreadList(manualSeenEnabled).count;
}

NSDictionary *SPKDirectManualSeenThreadEntryForUserPK(NSString *pk, BOOL manualSeenEnabled) {
    if (pk.length == 0) return nil;
    NSArray<NSDictionary *> *threads = SPKDirectManualSeenThreadList(manualSeenEnabled);
    for (NSDictionary *entry in threads) {
        if ([entry[@"isGroup"] boolValue]) continue;
        NSArray *users = entry[@"users"];
        for (NSDictionary *user in users) {
            if ([user[@"pk"] isEqualToString:pk]) {
                return entry;
            }
        }
    }
    return nil;
}

static BOOL SPKDirectManualSeenListContainsThreadIdInList(NSString *threadId, NSArray<NSDictionary *> *threads) {
    if (threads == SPKDirectManualSeenThreadsCache) {
        return SPKDirectManualSeenListContainsThreadId(threadId, [SPKUtils getBoolPref:@"msgs_manual_seen"]);
    }

    NSString *normalizedThreadId = SPKDirectStringFromValue(threadId);
    if (normalizedThreadId.length == 0) return NO;
    for (NSDictionary *entry in threads) {
        if ([entry[@"threadId"] isEqualToString:normalizedThreadId]) return YES;
    }
    return NO;
}

static NSString *SPKDirectFastThreadIdForSource(id source) {
    NSString *threadId = SPKDirectThreadIdDirectlyFromObject(source);
    if (threadId.length > 0) return threadId;

    if ([source isKindOfClass:[UIView class]]) {
        UIViewController *viewController = [SPKUtils nearestViewControllerForView:(UIView *)source];
        threadId = SPKDirectThreadIdDirectlyFromObject(viewController);
        if (threadId.length > 0) return threadId;
    }

    threadId = SPKDirectActiveContext.threadId;
    return threadId.length > 0 ? threadId : nil;
}

static NSString *SPKDirectManualSeenListModeTitle(BOOL manualSeenEnabled) {
    return manualSeenEnabled ? @"Excluded" : @"Included";
}

static NSString *SPKDirectManualSeenListHelpText(BOOL manualSeenEnabled) {
    return manualSeenEnabled
        ? @"When Manually Mark Seen is enabled, chats in this list use Instagram's normal seen behavior and do not need the eye button. Add group chats from the open chat or inbox long-press menu."
        : @"When Manually Mark Seen is disabled, only chats in this list require the eye button or auto seen triggers to mark seen. Add group chats from the open chat or inbox long-press menu.";
}

BOOL SPKDirectManualSeenAppliesToSource(id source) {
    BOOL manualSeenEnabled = [SPKUtils getBoolPref:@"msgs_manual_seen"];
    NSArray<NSDictionary *> *threads = SPKDirectManualSeenThreadList(manualSeenEnabled);
    if (threads.count == 0) return manualSeenEnabled;

    NSString *threadId = SPKDirectFastThreadIdForSource(source);
    if (threadId.length == 0) return manualSeenEnabled;

    BOOL listed = SPKDirectManualSeenListContainsThreadIdInList(threadId, threads);
    return manualSeenEnabled ? !listed : listed;
}

BOOL SPKDirectShouldShowSeenButtonForSource(id source) {
    return SPKDirectManualSeenAppliesToSource(source);
}

static BOOL SPKDirectCurrentThreadRuleState(SPKDirectThreadContext *context, NSString **outThreadId, NSString **outThreadName, NSString **outListTitle, BOOL *outListed, BOOL *outManualSeenEnabled) {
    NSString *threadId = SPKDirectStringFromValue(context.threadId);
    if (threadId.length == 0) return NO;

    BOOL manualSeenEnabled = [SPKUtils getBoolPref:@"msgs_manual_seen"];
    BOOL listed = SPKDirectManualSeenListContainsThreadId(threadId, manualSeenEnabled);
    NSString *listTitle = SPKDirectManualSeenListTitle(manualSeenEnabled);
    NSString *threadName = context.threadName.length > 0 ? context.threadName : @"This chat";

    if (outThreadId) *outThreadId = threadId;
    if (outThreadName) *outThreadName = threadName;
    if (outListTitle) *outListTitle = listTitle;
    if (outListed) *outListed = listed;
    if (outManualSeenEnabled) *outManualSeenEnabled = manualSeenEnabled;
    return YES;
}

NSString *SPKDirectCurrentThreadRuleActionTitle(SPKDirectThreadContext *context) {
    if (!context) return nil;
    BOOL applies = SPKDirectManualSeenAppliesToSource(context);
    return applies ? @"Start Marking as Seen" : @"Stop Marking as Seen";
}

NSString *SPKDirectCurrentThreadRuleConfirmationTitle(SPKDirectThreadContext *context) {
    if (!context) return nil;
    BOOL applies = SPKDirectManualSeenAppliesToSource(context);
    return applies ? @"Confirm Start Marking as Seen" : @"Confirm Stop Marking as Seen";
}

NSString *SPKDirectCurrentThreadRuleConfirmationMessage(SPKDirectThreadContext *context) {
    NSString *threadName = nil;
    if (!SPKDirectCurrentThreadRuleState(context, NULL, &threadName, NULL, NULL, NULL)) return nil;
    BOOL applies = SPKDirectManualSeenAppliesToSource(context);
    return applies
        ? [NSString stringWithFormat:@"Do you want to start marking %@ as seen?", threadName]
        : [NSString stringWithFormat:@"Do you want to stop marking %@ as seen?", threadName];
}

BOOL SPKDirectToggleCurrentThreadRule(SPKDirectThreadContext *context, NSString **notificationTitle, NSString **notificationSubtitle) {
    NSString *threadId = nil;
    NSString *threadName = nil;
    NSString *listTitle = nil;
    BOOL listed = NO;
    BOOL manualSeenEnabled = NO;
    if (!SPKDirectCurrentThreadRuleState(context, &threadId, &threadName, &listTitle, &listed, &manualSeenEnabled)) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Toggle thread rule failed: missing current thread context=%@", context);
        return NO;
    }

    BOOL applies = SPKDirectManualSeenAppliesToSource(context);

    if (listed) {
        SPKDirectRemoveManualSeenThreadId(threadId, manualSeenEnabled);
    } else {
        NSDictionary *entry = SPKDirectThreadEntryFromContext(context);
        if (!entry) return NO;
        SPKDirectAddOrUpdateManualSeenThreadEntry(entry, manualSeenEnabled);
        SPKDirectEnrichManualSeenThreadEntryIfNeeded(entry, manualSeenEnabled);
    }
    SPKLog(@"Messages", @"[Sparkle MessagesSeen] %@ %@ threadId=%@ threadName=%@ manualSeenEnabled=%d",
           listed ? @"Removed from" : @"Added to",
           listTitle,
           threadId,
           threadName,
           manualSeenEnabled);

    if (notificationTitle) {
        *notificationTitle = applies
            ? [NSString stringWithFormat:@"Messages seen on for %@", threadName]
            : [NSString stringWithFormat:@"Messages seen off for %@", threadName];
    }
    if (notificationSubtitle) *notificationSubtitle = listTitle;
    return YES;
}

// Circular 45pt avatar with a 24pt group glyph centered inside — matches the
// profile-picture style used for 1:1 entries but keeps the glyph at native size.
static UIImage *SPKDirectGroupAvatarPlaceholderImage(void) {
    static CGFloat const kSize = 45.0;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kSize, kSize) format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        (void)ctx;
        [[SPKUtils SPKColor_InstagramTertiaryBackground] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, kSize, kSize)] fill];

        UIImage *glyph = nil;
        for (NSString *name in @[@"group", @"people", @"members"]) {
            glyph = [SPKAssetUtils instagramIconNamed:name pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
            if (glyph) break;
        }
        if (!glyph) glyph = [SPKAssetUtils instagramIconNamed:@"user_circle" pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        if (!glyph) return;
        UIImage *tinted = [glyph imageWithTintColor:[SPKUtils SPKColor_InstagramSecondaryText]];
        CGFloat g = 24.0;
        [tinted drawInRect:CGRectMake((kSize - g) / 2.0, (kSize - g) / 2.0, g, g)];
    }];
}

@interface SPKDirectManualSeenThreadsViewController : SPKSettingsViewController
@property (nonatomic, assign) BOOL manualSeenEnabled;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *threads;
@end

@implementation SPKDirectManualSeenThreadsViewController

- (instancetype)init {
    BOOL manualSeen = [SPKUtils getBoolPref:@"msgs_manual_seen"];
    if ((self = [super initWithTitle:SPKDirectManualSeenListTitle(manualSeen) sections:@[] reduceMargin:NO])) {
        _manualSeenEnabled = manualSeen;
        _threads = [SPKDirectManualSeenThreadList(_manualSeenEnabled) mutableCopy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIBarButtonItem *addItem = SPKMediaChromeTopBarButtonItemWithTint(@"plus", self, @selector(addChat), [SPKUtils SPKColor_InstagramPrimaryText], @"Add chat");
    UIBarButtonItem *infoItem = SPKMediaChromeTopBarButtonItemWithTint(@"info", self, @selector(showHowItWorks), [SPKUtils SPKColor_InstagramPrimaryText], @"How it works");
    SPKMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ infoItem, addItem ]);
}

- (void)reloadThreads {
    self.threads = [[SPKDirectManualSeenThreadList(self.manualSeenEnabled) sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSNumber *aAdded = [a[@"addedAt"] respondsToSelector:@selector(compare:)] ? a[@"addedAt"] : @0;
        NSNumber *bAdded = [b[@"addedAt"] respondsToSelector:@selector(compare:)] ? b[@"addedAt"] : @0;
        return [bAdded compare:aAdded];
    }] mutableCopy];
}

- (NSString *)displayNameForEntry:(NSDictionary *)entry {
    NSString *name = [entry[@"threadName"] isKindOfClass:[NSString class]] ? entry[@"threadName"] : nil;
    if (name.length > 0) return name;
    NSString *fromUsers = SPKDirectNameFromUsers([entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[]);
    return fromUsers.length > 0 ? fromUsers : @"Unknown Chat";
}

- (NSString *)subtitleForEntry:(NSDictionary *)entry {
    NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
    if ([entry[@"isGroup"] boolValue]) {
        return [NSString stringWithFormat:@"%lu participant%@", (unsigned long)users.count, users.count == 1 ? @"" : @"s"];
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSDictionary *user in users) {
        NSString *username = [user[@"username"] isKindOfClass:[NSString class]] ? user[@"username"] : nil;
        if (username.length > 0) [parts addObject:[@"@" stringByAppendingString:username]];
    }
    return [parts componentsJoinedByString:@", "];
}

- (void)rebuildSections {
    [self reloadThreads];
    NSMutableArray<SPKSetting *> *rows = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSUInteger idx = 0; idx < self.threads.count; idx++) {
        NSDictionary *entry = self.threads[idx];
        NSString *title = [self displayNameForEntry:entry];
        BOOL isGroup = [entry[@"isGroup"] boolValue];
        SPKSetting *row = [SPKSetting buttonCellWithTitle:title
                                                 subtitle:[self subtitleForEntry:entry]
                                                     icon:nil
                                                   action:^{
            [weakSelf showChatActionsForIndex:idx];
        }];

        if (isGroup) {
            NSString *groupPhotoUrl = [entry[@"groupPhotoUrl"] isKindOfClass:[NSString class]] ? entry[@"groupPhotoUrl"] : nil;
            if (groupPhotoUrl.length) {
                row.imageUrl = [NSURL URLWithString:groupPhotoUrl];
            } else {
                row.iconProvider = ^UIImage *{ return SPKDirectGroupAvatarPlaceholderImage(); };
                row.userInfo = @{@"avatarIcon": @YES};
            }
        } else {
            NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
            NSString *profilePicUrl = nil;
            for (NSDictionary *user in users) {
                if ([user[@"profilePicUrl"] isKindOfClass:[NSString class]]) {
                    profilePicUrl = user[@"profilePicUrl"];
                    break;
                }
                if ([user[@"pk"] isKindOfClass:[NSString class]]) {
                    profilePicUrl = spkDirectUserResolverProfilePicURLStringForPK(user[@"pk"]);
                    if (profilePicUrl) break;
                }
            }
            if (profilePicUrl.length > 0) {
                row.imageUrl = [NSURL URLWithString:profilePicUrl];
            } else {
                row.icon = SPKSettingsIcon(@"user");
            }
        }

        [rows addObject:row];
    }

    [self replaceSections:@[ SPKTopicSection(@"", rows, nil) ]];
    self.title = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.threads.count, SPKDirectManualSeenListModeTitle(self.manualSeenEnabled)];
}

- (void)showHowItWorks {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"How It Works"
                                                message:SPKDirectManualSeenListHelpText(self.manualSeenEnabled)
                                                actions:@[
        [SPKIGAlertAction actionWithTitle:@"OK" style:SPKIGAlertActionStyleCancel handler:nil]
    ]];
}

- (void)showChatActionsForIndex:(NSUInteger)index {
    if (index >= self.threads.count) return;
    NSDictionary *entry = self.threads[index];
    NSMutableArray<SPKIGAlertAction *> *actions = [NSMutableArray array];
    NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
    
    BOOL isGroup = [entry[@"isGroup"] boolValue];
    
    SPKIGAlertAction *openProfileAction = nil;
    if (!isGroup && users.count == 1) {
        NSString *username = [users.firstObject[@"username"] isKindOfClass:[NSString class]] ? users.firstObject[@"username"] : nil;
        if (username.length > 0) {
            openProfileAction = [SPKIGAlertAction actionWithTitle:@"Open Profile" style:SPKIGAlertActionStyleDefault handler:^{
                [SPKUtils openInstagramProfileForUsername:username];
            }];
        }
    }
    
    __weak typeof(self) weakSelf = self;
    SPKIGAlertAction *removeAction = [SPKIGAlertAction actionWithTitle:@"Remove" style:SPKIGAlertActionStyleDestructive handler:^{
        NSString *threadId = [entry[@"threadId"] isKindOfClass:[NSString class]] ? entry[@"threadId"] : nil;
        if (threadId.length > 0) {
            NSString *threadName = [weakSelf displayNameForEntry:entry];
            SPKDirectRemoveManualSeenThreadId(threadId, weakSelf.manualSeenEnabled);
            SPKNotify(kSPKNotificationDirectThreadSeenRule,
                      [NSString stringWithFormat:@"Removed %@", threadName],
                      SPKDirectManualSeenListTitle(weakSelf.manualSeenEnabled),
                      @"circle_check_filled",
                      SPKNotificationToneSuccess);
            [weakSelf rebuildSections];
        }
    }];
    
    SPKIGAlertAction *cancelAction = [SPKIGAlertAction actionWithTitle:@"Cancel" style:SPKIGAlertActionStyleCancel handler:nil];
    
    if (openProfileAction) {
        [actions addObject:openProfileAction];
        [actions addObject:removeAction];
        [actions addObject:cancelAction];
    } else {
        // Only 2 actions: Cancel (safe) on left, Remove (destructive) on right
        [actions addObject:cancelAction];
        [actions addObject:removeAction];
    }
    
    NSString *message = nil;
    if (isGroup) {
        NSMutableArray<NSString *> *userLines = [NSMutableArray array];
        for (NSDictionary *user in users) {
            NSString *username = [user[@"username"] isKindOfClass:[NSString class]] ? user[@"username"] : nil;
            NSString *fullName = [user[@"fullName"] isKindOfClass:[NSString class]] ? user[@"fullName"] : nil;
            if (username.length > 0) {
                if (fullName.length > 0) {
                    [userLines addObject:[NSString stringWithFormat:@"@%@ (%@)", username, fullName]];
                } else {
                    [userLines addObject:[NSString stringWithFormat:@"@%@", username]];
                }
            } else if (fullName.length > 0) {
                [userLines addObject:fullName];
            }
        }
        if (userLines.count > 0) {
            message = [userLines componentsJoinedByString:@"\n"];
        }
    }
    
    [SPKIGAlertPresenter presentAlertFromViewController:self title:[self displayNameForEntry:entry] message:message actions:actions];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:nil
                                                                             handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || indexPath.row >= strongSelf.threads.count) {
            completionHandler(NO);
            return;
        }
        NSString *threadId = strongSelf.threads[indexPath.row][@"threadId"];
        if (threadId.length == 0) {
            completionHandler(NO);
            return;
        }
        NSString *threadName = [strongSelf displayNameForEntry:strongSelf.threads[indexPath.row]];
        SPKDirectRemoveManualSeenThreadId(threadId, strongSelf.manualSeenEnabled);
        SPKNotify(kSPKNotificationDirectThreadSeenRule,
                  [NSString stringWithFormat:@"Removed %@", threadName],
                  SPKDirectManualSeenListTitle(strongSelf.manualSeenEnabled),
                  @"circle_check_filled",
                  SPKNotificationToneSuccess);
        [strongSelf rebuildSections];
        completionHandler(YES);
    }];
    deleteAction.image = SPKSettingsIcon(@"trash");
    deleteAction.backgroundColor = [SPKUtils SPKColor_InstagramDestructive];
    deleteAction.accessibilityLabel = @"Remove";
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.row >= self.threads.count) return;
    NSString *threadId = self.threads[indexPath.row][@"threadId"];
    if (threadId.length > 0) {
        NSString *threadName = [self displayNameForEntry:self.threads[indexPath.row]];
        SPKDirectRemoveManualSeenThreadId(threadId, self.manualSeenEnabled);
        SPKNotify(kSPKNotificationDirectThreadSeenRule,
                  [NSString stringWithFormat:@"Removed %@", threadName],
                  SPKDirectManualSeenListTitle(self.manualSeenEnabled),
                  @"circle_check_filled",
                  SPKNotificationToneSuccess);
        [self rebuildSections];
    }
}

- (void)presentError:(NSString *)message {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Unable to Add Chat"
                                                message:message
                                                actions:@[[SPKIGAlertAction actionWithTitle:@"OK" style:SPKIGAlertActionStyleCancel handler:nil]]];
}

- (void)addChat {
    __weak typeof(self) weakSelf = self;
    [SPKIGAlertPresenter presentTextInputAlertFromViewController:self
                                                           title:@"Add Chat"
                                                         message:@"Enter the Instagram username for a 1:1 DM thread."
                                                     placeholder:@"username"
                                                     initialText:nil
                                                 autocapitalized:NO
                                                    confirmTitle:@"Search"
                                                     cancelTitle:@"Cancel"
                                                    confirmStyle:SPKIGAlertActionStyleDefault
                                                    confirmBlock:^(NSString *text) {
        [weakSelf lookupUsername:text];
    } cancelBlock:nil];
}

- (void)lookupUsername:(NSString *)rawUsername {
    NSString *username = [[[rawUsername ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"@"]];
    if (username.length == 0) return;
    NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    if (encodedUsername.length == 0) return;

    SPKLog(@"Messages", @"[Sparkle MessagesSeen] Settings add chat lookup started username=%@ list=%@",
           username,
           SPKDirectManualSeenListTitle(self.manualSeenEnabled));

    __weak typeof(self) weakSelf = self;
    [SPKInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", encodedUsername]
                                      body:nil
                                completion:^(NSDictionary *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary *user = response[@"data"][@"user"];
        if (![user isKindOfClass:[NSDictionary class]]) user = response[@"user"];
        if (![user isKindOfClass:[NSDictionary class]] || error) {
            SPKLog(@"Messages", @"[Sparkle MessagesSeen] Settings add chat user lookup failed username=%@ error=%@", username, error);
            [strongSelf presentError:[NSString stringWithFormat:@"User '%@' was not found.", username]];
            return;
        }
        NSString *pk = SPKDirectStringFromValue(user[@"id"] ?: user[@"pk"]);
        NSString *resolvedUsername = SPKDirectStringFromValue(user[@"username"]) ?: username;
        NSString *fullName = SPKDirectStringFromValue(user[@"full_name"] ?: user[@"fullName"]) ?: @"";
        NSString *profilePicUrl = SPKDirectStringFromValue(user[@"profile_pic_url"] ?: user[@"profile_pic_url_hd"]);
        if (pk.length == 0) {
            SPKLog(@"Messages", @"[Sparkle MessagesSeen] Settings add chat user lookup missing pk username=%@ response=%@", username, user);
            [strongSelf presentError:@"Could not resolve this user's Instagram id."];
            return;
        }

        NSString *encodedRecipients = [[NSString stringWithFormat:@"[%@]", pk] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        [SPKInstagramAPI sendRequestWithMethod:@"GET"
                                          path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=%@", encodedRecipients]
                                          body:nil
                                    completion:^(NSDictionary *threadResponse, NSError *threadError) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (!innerSelf) return;
            NSDictionary *thread = threadResponse[@"thread"];
            if (![thread isKindOfClass:[NSDictionary class]] || threadError) {
                SPKLog(@"Messages", @"[Sparkle MessagesSeen] Settings add chat thread lookup failed username=%@ pk=%@ error=%@", resolvedUsername, pk, threadError);
                [innerSelf presentError:[NSString stringWithFormat:@"No 1:1 DM thread was found with @%@.", resolvedUsername]];
                return;
            }

            NSString *threadId = SPKDirectStringFromValue(thread[@"thread_id"] ?: thread[@"threadId"]);
            if (threadId.length == 0) {
                SPKLog(@"Messages", @"[Sparkle MessagesSeen] Settings add chat thread lookup missing threadId username=%@ pk=%@ response=%@", resolvedUsername, pk, thread);
                [innerSelf presentError:[NSString stringWithFormat:@"No 1:1 DM thread was found with @%@.", resolvedUsername]];
                return;
            }

            NSString *threadName = SPKDirectStringFromValue(thread[@"thread_title"] ?: thread[@"threadName"]) ?: resolvedUsername;
            SPKLog(@"Messages", @"[Sparkle MessagesSeen] Settings add chat resolved username=%@ pk=%@ threadId=%@ threadName=%@",
                   resolvedUsername,
                   pk,
                   threadId,
                   threadName);
            NSString *message = fullName.length > 0
                ? [NSString stringWithFormat:@"@%@ (%@)", resolvedUsername, fullName]
                : [@"@" stringByAppendingString:resolvedUsername];
            [SPKIGAlertPresenter presentAlertFromViewController:innerSelf
                                                           title:@"Add to List?"
                                                         message:message
                                                         actions:@[
                [SPKIGAlertAction actionWithTitle:@"Cancel" style:SPKIGAlertActionStyleCancel handler:nil],
                [SPKIGAlertAction actionWithTitle:@"Add" style:SPKIGAlertActionStyleDefault handler:^{
                    NSMutableDictionary *usersEntry = [@{
                        @"pk": pk,
                        @"username": resolvedUsername,
                        @"fullName": fullName,
                    } mutableCopy];
                    if (profilePicUrl.length > 0) usersEntry[@"profilePicUrl"] = profilePicUrl;
                    SPKDirectAddOrUpdateManualSeenThreadEntry(@{
                        @"threadId": threadId,
                        @"threadName": threadName,
                        @"isGroup": @(NO),
                        @"users": @[usersEntry.copy],
                    }, innerSelf.manualSeenEnabled);
                    SPKNotify(kSPKNotificationDirectThreadSeenRule,
                              [NSString stringWithFormat:@"Added %@", threadName],
                              SPKDirectManualSeenListTitle(innerSelf.manualSeenEnabled),
                              @"circle_check_filled",
                              SPKNotificationToneSuccess);
                    [innerSelf rebuildSections];
                }],
            ]];
        }];
    }];
}

@end

UIViewController *SPKDirectManualSeenListViewController(void) {
    return [[SPKDirectManualSeenThreadsViewController alloc] init];
}

#import "SCIDirectSeenContext.h"

#import <objc/message.h>

#import "../../Networking/SCIInstagramAPI.h"
#import "../../Settings/SCISetting.h"
#import "../../Settings/SCISettingsViewController.h"
#import "../../Settings/SCITopicSettingsSupport.h"
#import "../../Shared/UI/SCIIGAlertPresenter.h"
#import "../../Shared/UI/SCIMediaChrome.h"
#import "../../Shared/UI/SCINotificationCenter.h"
#import "../../Utils.h"
#import "SCIDirectUserResolver.h"

static NSString * const kSCIDirectManualSeenThreadsKey = @"msgs_manual_seen_threads";

@implementation SCIDirectThreadContext
- (instancetype)init {
    if ((self = [super init])) {
        _users = @[];
    }
    return self;
}
@end

static SCIDirectThreadContext *SCIDirectActiveContext;
static NSArray<NSDictionary *> *SCIDirectManualSeenThreadsCache;
static NSSet<NSString *> *SCIDirectManualSeenThreadIdsCache;
BOOL SCIDirectSeenDebugPrintEnabled = NO;

static id SCIDirectKVCObject(id target, NSString *key) {
    if (!target || key.length == 0) return nil;
    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SCIDirectObjectForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static NSString *SCIDirectStringFromValue(id value) {
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

static NSString *SCIDirectFirstStringForSelectors(id target, NSArray<NSString *> *selectors) {
    for (NSString *selectorName in selectors) {
        NSString *value = SCIDirectStringFromValue(SCIDirectObjectForSelector(target, selectorName));
        if (value.length == 0) value = SCIDirectStringFromValue(SCIDirectKVCObject(target, selectorName));
        if (value.length > 0) return value;
    }
    return nil;
}

static NSString *SCIDirectThreadIdDirectlyFromObject(id object) {
    if (!object) return nil;
    NSString *threadId = SCIDirectFirstStringForSelectors(object, @[@"threadId", @"threadID", @"thread_id"]);
    if (threadId.length == 0 && [object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        threadId = SCIDirectStringFromValue(dict[@"threadId"] ?: dict[@"thread_id"]);
    }
    return threadId;
}

static NSNumber *SCIDirectFirstNumberForSelectors(id target, NSArray<NSString *> *selectors) {
    for (NSString *selectorName in selectors) {
        id value = SCIDirectObjectForSelector(target, selectorName);
        if (!value) value = SCIDirectKVCObject(target, selectorName);
        if ([value respondsToSelector:@selector(boolValue)]) return @([value boolValue]);
    }
    return nil;
}

static NSArray *SCIDirectArrayFromCollection(id collection) {
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

static NSArray<NSDictionary *> *SCIDirectUsersFromObject(id object) {
    NSMutableArray<NSDictionary *> *users = [NSMutableArray array];
    NSArray<NSString *> *selectors = @[
        @"users",
        @"threadUsers",
        @"recentlyActiveUsers",
        @"participants",
        @"recipientUsers"
    ];

    for (NSString *selectorName in selectors) {
        id collection = SCIDirectObjectForSelector(object, selectorName);
        if (!collection) collection = SCIDirectKVCObject(object, selectorName);
        NSArray *rawUsers = SCIDirectArrayFromCollection(collection);
        if (rawUsers.count == 0) continue;

        for (id user in rawUsers) {
            NSString *pk = SCIDirectFirstStringForSelectors(user, @[@"pk", @"userId", @"userID", @"id"]);
            NSString *username = SCIDirectFirstStringForSelectors(user, @[@"username", @"userName"]);
            NSString *fullName = SCIDirectFirstStringForSelectors(user, @[@"fullName", @"full_name", @"name"]);
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            if (pk.length > 0) entry[@"pk"] = pk;
            if (username.length > 0) entry[@"username"] = username;
            if (fullName.length > 0) entry[@"fullName"] = fullName;
            NSString *profilePicUrl = sciDirectUserResolverProfilePicURLStringFromUser(user);
            if (profilePicUrl.length > 0) entry[@"profilePicUrl"] = profilePicUrl;
            if (entry.count > 0) [users addObject:entry];
        }

        if (users.count > 0) break;
    }

    return users.copy;
}

static NSString *SCIDirectNameFromUsers(NSArray<NSDictionary *> *users) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSDictionary *user in users) {
        NSString *username = [user[@"username"] isKindOfClass:[NSString class]] ? user[@"username"] : nil;
        NSString *fullName = [user[@"fullName"] isKindOfClass:[NSString class]] ? user[@"fullName"] : nil;
        NSString *name = fullName.length > 0 ? fullName : (username.length > 0 ? [@"@" stringByAppendingString:username] : nil);
        if (name.length > 0) [names addObject:name];
    }
    return names.count > 0 ? [names componentsJoinedByString:@", "] : nil;
}

static NSString *SCIDirectNormalizeUsername(NSString *username) {
    NSString *trimmed = [[username ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([trimmed hasPrefix:@"@"]) trimmed = [trimmed substringFromIndex:1];
    return trimmed;
}

static NSString *SCIDirectCleanFullName(NSString *fullName, NSString *username) {
    NSString *cleanName = [SCIDirectStringFromValue(fullName) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *normalizedUsername = SCIDirectNormalizeUsername(username);
    if (cleanName.length == 0) return nil;
    if ([SCIDirectNormalizeUsername(cleanName) isEqualToString:normalizedUsername]) return nil;
    return cleanName;
}

static SCIDirectThreadContext *SCIDirectThreadContextFromSourceInternal(id source, NSMutableSet<NSValue *> *visited, BOOL allowActiveFallback);

static SCIDirectThreadContext *SCIDirectContextDirectlyFromObject(id object) {
    if (!object) return nil;

    id target = object;

    // Resolve threadInfoProvider (e.g. from IGDirectThreadViewController, or via _threadSession)
    id provider = [SCIUtils getIvarForObj:object name:"_threadInfoProvider"];
    if (!provider) {
        provider = SCIDirectObjectForSelector(object, @"threadInfoProvider");
    }
    if (!provider) {
        id threadSession = [SCIUtils getIvarForObj:object name:"_threadSession"];
        if (threadSession) {
            provider = [SCIUtils getIvarForObj:threadSession name:"_threadInfoProvider"];
            if (!provider) provider = SCIDirectObjectForSelector(threadSession, @"threadInfoProvider");
        }
    }
    if (!provider) {
        id vcCtx = [SCIUtils getIvarForObj:object name:"_threadViewControllerContext"];
        if (!vcCtx) vcCtx = SCIDirectObjectForSelector(object, @"threadViewControllerContext");
        if (vcCtx) {
            provider = SCIDirectObjectForSelector(vcCtx, @"threadInfoProvider");
        }
    }
    if (provider) {
        target = provider;
    }

    id metadata = nil;
    if ([target respondsToSelector:NSSelectorFromString(@"threadMetadata")]) {
        id meta = SCIDirectObjectForSelector(target, @"threadMetadata");
        if (meta) {
            metadata = meta;
            target = meta;
        }
    }

    NSString *threadId = SCIDirectThreadIdDirectlyFromObject(target);
    if (threadId.length == 0 && target != object) {
        threadId = SCIDirectThreadIdDirectlyFromObject(object);
    }
    if (threadId.length == 0 && [object respondsToSelector:NSSelectorFromString(@"threadKey")]) {
        id key = SCIDirectObjectForSelector(object, @"threadKey");
        threadId = SCIDirectThreadIdDirectlyFromObject(key);
    }
    if (threadId.length == 0) return nil;

    NSArray<NSDictionary *> *users = SCIDirectUsersFromObject(target);
    if (users.count == 0 && target != object) {
        users = SCIDirectUsersFromObject(object);
    }

    NSString *threadName = SCIDirectFirstStringForSelectors(target, @[@"threadName", @"threadTitle", @"title", @"name"]);
    if (threadName.length == 0 && [object isKindOfClass:[UIViewController class]]) {
        threadName = ((UIViewController *)object).navigationItem.title;
    }
    if (threadName.length == 0 && [object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        threadName = SCIDirectStringFromValue(dict[@"threadName"] ?: dict[@"thread_title"] ?: dict[@"title"]);
    }
    if (threadName.length == 0 && target != object) {
        threadName = SCIDirectFirstStringForSelectors(object, @[@"threadName", @"threadTitle", @"title", @"name"]);
    }
    if (threadName.length == 0) threadName = SCIDirectNameFromUsers(users);

    NSNumber *isGroupValue = SCIDirectFirstNumberForSelectors(target, @[@"isGroup", @"isGroupThread", @"groupThread"]);
    if (!isGroupValue && [object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        id raw = dict[@"isGroup"] ?: dict[@"is_group"] ?: dict[@"is_group_thread"];
        if ([raw respondsToSelector:@selector(boolValue)]) isGroupValue = @([raw boolValue]);
    }
    if (!isGroupValue && target != object) {
        isGroupValue = SCIDirectFirstNumberForSelectors(object, @[@"isGroup", @"isGroupThread", @"groupThread"]);
    }

    if (SCIDirectSeenDebugPrintEnabled) {
        SCILog(@"Messages", @"SCIDirectContextDirectlyFromObject: object=%@ provider=%@ metadata=%@ target=%@ threadId=%@ name=%@ usersCount=%lu users=%@",
               NSStringFromClass([object class]),
               provider ? NSStringFromClass([provider class]) : @"nil",
               metadata ? NSStringFromClass([metadata class]) : @"nil",
               NSStringFromClass([target class]),
               threadId,
               threadName,
               (unsigned long)users.count,
               users);
    }

    SCIDirectThreadContext *context = [SCIDirectThreadContext new];
    context.threadId = threadId;
    context.threadName = threadName ?: @"";
    context.isGroup = [isGroupValue boolValue];
    context.users = users ?: @[];
    return context;
}

static SCIDirectThreadContext *SCIDirectThreadContextFromSourceInternal(id source, NSMutableSet<NSValue *> *visited, BOOL allowActiveFallback) {
    if (!source) return allowActiveFallback ? SCIDirectActiveContext : nil;

    NSValue *pointerValue = [NSValue valueWithNonretainedObject:source];
    if ([visited containsObject:pointerValue]) return nil;
    [visited addObject:pointerValue];

    SCIDirectThreadContext *context = SCIDirectContextDirectlyFromObject(source);
    if (context.threadId.length > 0) return context;

    if ([source isKindOfClass:[UIView class]]) {
        context = SCIDirectThreadContextFromSourceInternal([SCIUtils nearestViewControllerForView:(UIView *)source], visited, NO);
        if (context.threadId.length > 0) return context;
    }

    if ([source isKindOfClass:[UIViewController class]]) {
        UIViewController *viewController = (UIViewController *)source;
        context = SCIDirectThreadContextFromSourceInternal(viewController.parentViewController, visited, NO);
        if (context.threadId.length > 0) return context;
        context = SCIDirectThreadContextFromSourceInternal(viewController.navigationController, visited, NO);
        if (context.threadId.length > 0) return context;
        for (UIViewController *child in viewController.childViewControllers) {
            context = SCIDirectThreadContextFromSourceInternal(child, visited, NO);
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
        id candidate = [key hasPrefix:@"_"] ? [SCIUtils getIvarForObj:source name:key.UTF8String] : SCIDirectKVCObject(source, key);
        context = SCIDirectThreadContextFromSourceInternal(candidate, visited, NO);
        if (context.threadId.length > 0) return context;
    }

    return allowActiveFallback ? SCIDirectActiveContext : nil;
}

SCIDirectThreadContext *SCIDirectThreadContextFromSource(id source) {
    return SCIDirectThreadContextFromSourceInternal(source, [NSMutableSet set], YES);
}

static id SCIDirectInboxValueForKeys(id candidate, NSArray<NSString *> *keys) {
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
            value = SCIDirectKVCObject(candidate, key);
            if (!value) {
                NSString *ivarKey = [@"_" stringByAppendingString:key];
                value = [SCIUtils getIvarForObj:candidate name:ivarKey.UTF8String];
            }
        }
        if (value && value != (id)kCFNull) return value;
    }
    return nil;
}

static SCIDirectThreadContext *SCIDirectContextFromShallowInboxObject(id object) {
    if (!object) return nil;

    id target = object;
    
    id provider = [SCIUtils getIvarForObj:object name:"_threadInfoProvider"];
    if (!provider) provider = SCIDirectObjectForSelector(object, @"threadInfoProvider");
    if (!provider) {
        id threadSession = [SCIUtils getIvarForObj:object name:"_threadSession"];
        if (threadSession) {
            provider = [SCIUtils getIvarForObj:threadSession name:"_threadInfoProvider"];
            if (!provider) provider = SCIDirectObjectForSelector(threadSession, @"threadInfoProvider");
        }
    }
    if (!provider) {
        id vcCtx = [SCIUtils getIvarForObj:object name:"_threadViewControllerContext"];
        if (!vcCtx) vcCtx = SCIDirectObjectForSelector(object, @"threadViewControllerContext");
        if (vcCtx) {
            provider = SCIDirectObjectForSelector(vcCtx, @"threadInfoProvider");
        }
    }
    if (provider) {
        target = provider;
    }

    if ([target respondsToSelector:NSSelectorFromString(@"threadMetadata")]) {
        id meta = SCIDirectObjectForSelector(target, @"threadMetadata");
        if (meta) target = meta;
    }

    NSString *threadId = SCIDirectStringFromValue(SCIDirectInboxValueForKeys(target, @[@"threadId", @"threadID", @"thread_id"]));
    if (threadId.length == 0 && target != object) {
        threadId = SCIDirectStringFromValue(SCIDirectInboxValueForKeys(object, @[@"threadId", @"threadID", @"thread_id"]));
    }
    if (threadId.length == 0) return nil;

    NSString *threadName = SCIDirectStringFromValue(SCIDirectInboxValueForKeys(target, @[@"threadName", @"threadTitle", @"thread_title", @"title", @"name"]));
    if (threadName.length == 0 && target != object) {
        threadName = SCIDirectStringFromValue(SCIDirectInboxValueForKeys(object, @[@"threadName", @"threadTitle", @"thread_title", @"title", @"name"]));
    }

    id isGroupValue = SCIDirectInboxValueForKeys(target, @[@"isGroup", @"isGroupThread", @"groupThread", @"is_group", @"is_group_thread"]);
    if (!isGroupValue && target != object) {
        isGroupValue = SCIDirectInboxValueForKeys(object, @[@"isGroup", @"isGroupThread", @"groupThread", @"is_group", @"is_group_thread"]);
    }

    NSArray<NSDictionary *> *users = SCIDirectUsersFromObject(target);
    if (users.count == 0 && target != object) {
        users = SCIDirectUsersFromObject(object);
    }
    if (threadName.length == 0) {
        threadName = SCIDirectNameFromUsers(users);
    }

    SCIDirectThreadContext *context = [SCIDirectThreadContext new];
    context.threadId = threadId;
    context.threadName = threadName ?: @"";
    context.isGroup = [isGroupValue respondsToSelector:@selector(boolValue)] ? [isGroupValue boolValue] : NO;
    context.users = users ?: @[];
    return context;
}

static SCIDirectThreadContext *SCIDirectContextFromShallowInboxCandidate(id candidate) {
    if (!candidate) return nil;

    SCIDirectThreadContext *context = SCIDirectContextFromShallowInboxObject(candidate);
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
            nested = [key hasPrefix:@"_"] ? [SCIUtils getIvarForObj:candidate name:key.UTF8String] : SCIDirectKVCObject(candidate, key);
        }
        context = SCIDirectContextFromShallowInboxObject(nested);
        if (context.threadId.length > 0) return context;
    }

    return nil;
}

SCIDirectThreadContext *SCIDirectThreadContextFromInboxViewModel(id viewModel) {
    return SCIDirectContextFromShallowInboxCandidate(viewModel);
}

NSDictionary *SCIDirectThreadEntryFromContext(SCIDirectThreadContext *context) {
    NSString *threadId = SCIDirectStringFromValue(context.threadId);
    if (threadId.length == 0) return nil;
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"threadId"] = threadId;
    entry[@"threadName"] = context.threadName ?: @"";
    entry[@"isGroup"] = @(context.isGroup);
    entry[@"users"] = context.users ?: @[];
    return entry.copy;
}

void SCIDirectSetActiveThreadContext(SCIDirectThreadContext *context) {
    NSString *oldThreadId = SCIDirectActiveContext.threadId ?: @"";
    NSString *newThreadId = context.threadId ?: @"";
    SCIDirectActiveContext = context;
    if (newThreadId.length > 0 && ![oldThreadId isEqualToString:newThreadId]) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Active thread context set threadId=%@ threadName=%@ isGroup=%d",
               newThreadId,
               context.threadName ?: @"",
               context.isGroup);
    } else if (newThreadId.length == 0 && oldThreadId.length > 0) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Active thread context cleared threadId=%@", oldThreadId);
    }
}

SCIDirectThreadContext *SCIDirectActiveThreadContext(void) {
    return SCIDirectActiveContext;
}

static NSArray<NSDictionary *> *SCIDirectManualSeenThreadListFromRawValue(id rawStored) {
    NSArray *stored = [rawStored isKindOfClass:[NSArray class]] ? rawStored : nil;
    NSMutableArray<NSDictionary *> *threads = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (id value in stored ?: @[]) {
        NSDictionary *dict = [value isKindOfClass:[NSDictionary class]] ? value : nil;
        NSString *threadId = SCIDirectStringFromValue(dict[@"threadId"]);
        if (threadId.length == 0 || [seen containsObject:threadId]) continue;
        [seen addObject:threadId];

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"threadId"] = threadId;
        entry[@"threadName"] = SCIDirectStringFromValue(dict[@"threadName"]) ?: @"";
        entry[@"isGroup"] = @([dict[@"isGroup"] respondsToSelector:@selector(boolValue)] ? [dict[@"isGroup"] boolValue] : NO);
        entry[@"users"] = [dict[@"users"] isKindOfClass:[NSArray class]] ? dict[@"users"] : @[];
        if (dict[@"addedAt"]) entry[@"addedAt"] = dict[@"addedAt"];
        [threads addObject:entry.copy];
    }

    return threads.copy;
}

static void SCIDirectUpdateManualSeenThreadCaches(NSArray<NSDictionary *> *threads) {
    SCIDirectManualSeenThreadsCache = [threads copy] ?: @[];
    NSMutableSet<NSString *> *threadIds = [NSMutableSet set];
    for (NSDictionary *entry in SCIDirectManualSeenThreadsCache) {
        NSString *threadId = SCIDirectStringFromValue(entry[@"threadId"]);
        if (threadId.length > 0) [threadIds addObject:threadId];
    }
    SCIDirectManualSeenThreadIdsCache = threadIds.copy;
}

NSArray<NSDictionary *> *SCIDirectManualSeenThreadList(BOOL manualSeenEnabled) {
    (void)manualSeenEnabled;
    if (!SCIDirectManualSeenThreadsCache) {
        SCIDirectUpdateManualSeenThreadCaches(SCIDirectManualSeenThreadListFromRawValue([[NSUserDefaults standardUserDefaults] objectForKey:kSCIDirectManualSeenThreadsKey]));
    }
    return SCIDirectManualSeenThreadsCache;
}

void SCIDirectSetManualSeenThreadList(NSArray<NSDictionary *> *threads, BOOL manualSeenEnabled) {
    (void)manualSeenEnabled;
    NSArray *normalized = SCIDirectManualSeenThreadListFromRawValue(threads);
    [[NSUserDefaults standardUserDefaults] setObject:normalized forKey:kSCIDirectManualSeenThreadsKey];
    SCIDirectUpdateManualSeenThreadCaches(normalized);
}

BOOL SCIDirectManualSeenListContainsThreadId(NSString *threadId, BOOL manualSeenEnabled) {
    (void)manualSeenEnabled;
    NSString *normalizedThreadId = SCIDirectStringFromValue(threadId);
    if (normalizedThreadId.length == 0) return NO;
    if (!SCIDirectManualSeenThreadIdsCache) (void)SCIDirectManualSeenThreadList(manualSeenEnabled);
    return [SCIDirectManualSeenThreadIdsCache containsObject:normalizedThreadId];
}

void SCIDirectAddOrUpdateManualSeenThreadEntry(NSDictionary *entry, BOOL manualSeenEnabled) {
    NSString *threadId = SCIDirectStringFromValue(entry[@"threadId"]);
    if (threadId.length == 0) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Ignored add/update for manual seen list: missing threadId entry=%@", entry);
        return;
    }

    NSMutableArray<NSDictionary *> *threads = [SCIDirectManualSeenThreadList(manualSeenEnabled) mutableCopy];
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

    if (existingIndex >= 0) {
        threads[existingIndex] = merged.copy;
    } else {
        [threads addObject:merged.copy];
    }
    SCIDirectSetManualSeenThreadList(threads, manualSeenEnabled);
    SCILog(@"Messages", @"[SCInsta MessagesSeen] %@ manual seen list entry threadId=%@ threadName=%@ list=%@ count=%lu",
           existingIndex >= 0 ? @"Updated" : @"Added",
           threadId,
           merged[@"threadName"] ?: @"",
           SCIDirectManualSeenListTitle(manualSeenEnabled),
           (unsigned long)threads.count);
}

void SCIDirectRemoveManualSeenThreadId(NSString *threadId, BOOL manualSeenEnabled) {
    NSString *normalizedThreadId = SCIDirectStringFromValue(threadId);
    if (normalizedThreadId.length == 0) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Ignored remove for manual seen list: missing threadId");
        return;
    }
    NSMutableArray<NSDictionary *> *threads = [SCIDirectManualSeenThreadList(manualSeenEnabled) mutableCopy];
    NSUInteger beforeCount = threads.count;
    [threads filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        (void)bindings;
        return ![entry[@"threadId"] isEqualToString:normalizedThreadId];
    }]];
    SCIDirectSetManualSeenThreadList(threads, manualSeenEnabled);
    SCILog(@"Messages", @"[SCInsta MessagesSeen] Removed manual seen list entry threadId=%@ list=%@ before=%lu after=%lu",
           normalizedThreadId,
           SCIDirectManualSeenListTitle(manualSeenEnabled),
           (unsigned long)beforeCount,
           (unsigned long)threads.count);
}

static void SCIDirectEnrichManualSeenThreadEntryIfNeeded(NSDictionary *entry, BOOL manualSeenEnabled) {
    if ([entry[@"isGroup"] boolValue]) return;
    NSString *threadId = SCIDirectStringFromValue(entry[@"threadId"]);
    NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
    
    NSString *currentPk = [SCIUtils currentUserPK];
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

    NSString *username = SCIDirectStringFromValue(user[@"username"]);
    NSString *pk = SCIDirectStringFromValue(user[@"pk"]);
    NSString *profilePicUrl = SCIDirectStringFromValue(user[@"profilePicUrl"]);
    if (threadId.length == 0 || username.length == 0) return;
    if (pk.length > 0 && profilePicUrl.length > 0) return; // already fully enriched!

    NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    if (encodedUsername.length == 0) return;

    [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                       path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", encodedUsername]
                                       body:nil
                                 completion:^(NSDictionary *response, NSError *error) {
        NSDictionary *resolvedUser = response[@"data"][@"user"];
        if (![resolvedUser isKindOfClass:[NSDictionary class]]) resolvedUser = response[@"user"];
        if (![resolvedUser isKindOfClass:[NSDictionary class]] || error) {
            SCILog(@"Messages", @"[SCInsta MessagesSeen] Thread metadata enrichment failed threadId=%@ username=%@ error=%@",
                   threadId,
                   username,
                   error);
            return;
        }

        NSString *resolvedUsername = SCIDirectStringFromValue(resolvedUser[@"username"]) ?: username;
        NSString *resolvedPk = SCIDirectStringFromValue(resolvedUser[@"id"] ?: resolvedUser[@"pk"]) ?: pk ?: @"";
        NSString *fullName = SCIDirectCleanFullName(SCIDirectStringFromValue(resolvedUser[@"full_name"] ?: resolvedUser[@"fullName"]), resolvedUsername) ?: SCIDirectStringFromValue(user[@"fullName"]) ?: @"";
        NSString *profilePic = SCIDirectStringFromValue(resolvedUser[@"profile_pic_url"] ?: resolvedUser[@"profile_pic_url_hd"]);

        NSMutableDictionary *updatedEntry = [entry mutableCopy];
        NSString *threadName = SCIDirectStringFromValue(updatedEntry[@"threadName"]);
        NSString *normalizedThreadName = SCIDirectNormalizeUsername(threadName);
        NSString *normalizedUsername = SCIDirectNormalizeUsername(resolvedUsername);
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
            SCIDirectAddOrUpdateManualSeenThreadEntry(updatedEntry, manualSeenEnabled);
        });
    }];
}

NSString *SCIDirectManualSeenListTitle(BOOL manualSeenEnabled) {
    return manualSeenEnabled ? @"Excluded Chats" : @"Included Chats";
}

NSUInteger SCIDirectManualSeenThreadCount(BOOL manualSeenEnabled) {
    return SCIDirectManualSeenThreadList(manualSeenEnabled).count;
}

static BOOL SCIDirectManualSeenListContainsThreadIdInList(NSString *threadId, NSArray<NSDictionary *> *threads) {
    if (threads == SCIDirectManualSeenThreadsCache) {
        return SCIDirectManualSeenListContainsThreadId(threadId, [SCIUtils getBoolPref:@"msgs_manual_seen"]);
    }

    NSString *normalizedThreadId = SCIDirectStringFromValue(threadId);
    if (normalizedThreadId.length == 0) return NO;
    for (NSDictionary *entry in threads) {
        if ([entry[@"threadId"] isEqualToString:normalizedThreadId]) return YES;
    }
    return NO;
}

static NSString *SCIDirectFastThreadIdForSource(id source) {
    NSString *threadId = SCIDirectThreadIdDirectlyFromObject(source);
    if (threadId.length > 0) return threadId;

    if ([source isKindOfClass:[UIView class]]) {
        UIViewController *viewController = [SCIUtils nearestViewControllerForView:(UIView *)source];
        threadId = SCIDirectThreadIdDirectlyFromObject(viewController);
        if (threadId.length > 0) return threadId;
    }

    threadId = SCIDirectActiveContext.threadId;
    return threadId.length > 0 ? threadId : nil;
}

static NSString *SCIDirectManualSeenListModeTitle(BOOL manualSeenEnabled) {
    return manualSeenEnabled ? @"Excluded" : @"Included";
}

static NSString *SCIDirectManualSeenListHelpText(BOOL manualSeenEnabled) {
    return manualSeenEnabled
        ? @"When Manually Mark Seen is enabled, chats in this list use Instagram's normal seen behavior and do not need the eye button. Add group chats from the open chat or inbox long-press menu."
        : @"When Manually Mark Seen is disabled, only chats in this list require the eye button or auto seen triggers to mark seen. Add group chats from the open chat or inbox long-press menu.";
}

BOOL SCIDirectManualSeenAppliesToSource(id source) {
    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"msgs_manual_seen"];
    NSArray<NSDictionary *> *threads = SCIDirectManualSeenThreadList(manualSeenEnabled);
    if (threads.count == 0) return manualSeenEnabled;

    NSString *threadId = SCIDirectFastThreadIdForSource(source);
    if (threadId.length == 0) return manualSeenEnabled;

    BOOL listed = SCIDirectManualSeenListContainsThreadIdInList(threadId, threads);
    return manualSeenEnabled ? !listed : listed;
}

BOOL SCIDirectShouldShowSeenButtonForSource(id source) {
    return SCIDirectManualSeenAppliesToSource(source);
}

static BOOL SCIDirectCurrentThreadRuleState(SCIDirectThreadContext *context, NSString **outThreadId, NSString **outThreadName, NSString **outListTitle, BOOL *outListed, BOOL *outManualSeenEnabled) {
    NSString *threadId = SCIDirectStringFromValue(context.threadId);
    if (threadId.length == 0) return NO;

    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"msgs_manual_seen"];
    BOOL listed = SCIDirectManualSeenListContainsThreadId(threadId, manualSeenEnabled);
    NSString *listTitle = SCIDirectManualSeenListTitle(manualSeenEnabled);
    NSString *threadName = context.threadName.length > 0 ? context.threadName : @"This chat";

    if (outThreadId) *outThreadId = threadId;
    if (outThreadName) *outThreadName = threadName;
    if (outListTitle) *outListTitle = listTitle;
    if (outListed) *outListed = listed;
    if (outManualSeenEnabled) *outManualSeenEnabled = manualSeenEnabled;
    return YES;
}

NSString *SCIDirectCurrentThreadRuleActionTitle(SCIDirectThreadContext *context) {
    NSString *listTitle = nil;
    BOOL listed = NO;
    if (!SCIDirectCurrentThreadRuleState(context, NULL, NULL, &listTitle, &listed, NULL)) return nil;
    return listed
        ? [NSString stringWithFormat:@"Remove from %@", listTitle]
        : [NSString stringWithFormat:@"Add to %@", listTitle];
}

NSString *SCIDirectCurrentThreadRuleConfirmationTitle(SCIDirectThreadContext *context) {
    NSString *listTitle = nil;
    BOOL listed = NO;
    if (!SCIDirectCurrentThreadRuleState(context, NULL, NULL, &listTitle, &listed, NULL)) return nil;
    return listed
        ? [NSString stringWithFormat:@"Confirm Removal from %@", listTitle]
        : [NSString stringWithFormat:@"Confirm Addition to %@", listTitle];
}

NSString *SCIDirectCurrentThreadRuleConfirmationMessage(SCIDirectThreadContext *context) {
    NSString *threadName = nil;
    NSString *listTitle = nil;
    BOOL listed = NO;
    if (!SCIDirectCurrentThreadRuleState(context, NULL, &threadName, &listTitle, &listed, NULL)) return nil;
    return listed
        ? [NSString stringWithFormat:@"Do you want to remove %@ from %@?", threadName, listTitle]
        : [NSString stringWithFormat:@"Do you want to add %@ to %@?", threadName, listTitle];
}

BOOL SCIDirectToggleCurrentThreadRule(SCIDirectThreadContext *context, NSString **notificationTitle, NSString **notificationSubtitle) {
    NSString *threadId = nil;
    NSString *threadName = nil;
    NSString *listTitle = nil;
    BOOL listed = NO;
    BOOL manualSeenEnabled = NO;
    if (!SCIDirectCurrentThreadRuleState(context, &threadId, &threadName, &listTitle, &listed, &manualSeenEnabled)) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Toggle thread rule failed: missing current thread context=%@", context);
        return NO;
    }

    if (listed) {
        SCIDirectRemoveManualSeenThreadId(threadId, manualSeenEnabled);
    } else {
        NSDictionary *entry = SCIDirectThreadEntryFromContext(context);
        if (!entry) return NO;
        SCIDirectAddOrUpdateManualSeenThreadEntry(entry, manualSeenEnabled);
        SCIDirectEnrichManualSeenThreadEntryIfNeeded(entry, manualSeenEnabled);
    }
    SCILog(@"Messages", @"[SCInsta MessagesSeen] %@ %@ threadId=%@ threadName=%@ manualSeenEnabled=%d",
           listed ? @"Removed from" : @"Added to",
           listTitle,
           threadId,
           threadName,
           manualSeenEnabled);

    if (notificationTitle) {
        *notificationTitle = [NSString stringWithFormat:@"%@ %@", listed ? @"Removed" : @"Added", threadName];
    }
    if (notificationSubtitle) *notificationSubtitle = listTitle;
    return YES;
}

@interface SCIDirectManualSeenThreadsViewController : SCISettingsViewController
@property (nonatomic, assign) BOOL manualSeenEnabled;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *threads;
@end

@implementation SCIDirectManualSeenThreadsViewController

- (instancetype)init {
    BOOL manualSeen = [SCIUtils getBoolPref:@"msgs_manual_seen"];
    if ((self = [super initWithTitle:SCIDirectManualSeenListTitle(manualSeen) sections:@[] reduceMargin:NO])) {
        _manualSeenEnabled = manualSeen;
        _threads = [SCIDirectManualSeenThreadList(_manualSeenEnabled) mutableCopy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIBarButtonItem *addItem = SCIMediaChromeTopBarButtonItemWithTint(@"plus", self, @selector(addChat), [SCIUtils SCIColor_InstagramPrimaryText], @"Add chat");
    UIBarButtonItem *infoItem = SCIMediaChromeTopBarButtonItemWithTint(@"info", self, @selector(showHowItWorks), [SCIUtils SCIColor_InstagramPrimaryText], @"How it works");
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ infoItem, addItem ]);
}

- (void)reloadThreads {
    self.threads = [[SCIDirectManualSeenThreadList(self.manualSeenEnabled) sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSNumber *aAdded = [a[@"addedAt"] respondsToSelector:@selector(compare:)] ? a[@"addedAt"] : @0;
        NSNumber *bAdded = [b[@"addedAt"] respondsToSelector:@selector(compare:)] ? b[@"addedAt"] : @0;
        return [bAdded compare:aAdded];
    }] mutableCopy];
}

- (NSString *)displayNameForEntry:(NSDictionary *)entry {
    NSString *name = [entry[@"threadName"] isKindOfClass:[NSString class]] ? entry[@"threadName"] : nil;
    if (name.length > 0) return name;
    NSString *fromUsers = SCIDirectNameFromUsers([entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[]);
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
    NSMutableArray<SCISetting *> *rows = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSUInteger idx = 0; idx < self.threads.count; idx++) {
        NSDictionary *entry = self.threads[idx];
        NSString *title = [self displayNameForEntry:entry];
        BOOL isGroup = [entry[@"isGroup"] boolValue];
        SCISetting *row = [SCISetting buttonCellWithTitle:title
                                                 subtitle:[self subtitleForEntry:entry]
                                                     icon:SCISettingsIcon(isGroup ? @"group" : @"user")
                                                   action:^{
            [weakSelf showChatActionsForIndex:idx];
        }];
        
        if (!isGroup) {
            NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
            NSString *profilePicUrl = nil;
            for (NSDictionary *user in users) {
                if ([user[@"profilePicUrl"] isKindOfClass:[NSString class]]) {
                    profilePicUrl = user[@"profilePicUrl"];
                    break;
                }
                if ([user[@"pk"] isKindOfClass:[NSString class]]) {
                    profilePicUrl = sciDirectUserResolverProfilePicURLStringForPK(user[@"pk"]);
                    if (profilePicUrl) break;
                }
            }
            if (profilePicUrl.length > 0) {
                row.imageUrl = [NSURL URLWithString:profilePicUrl];
            }
        }
        
        [rows addObject:row];
    }

    [self replaceSections:@[ SCITopicSection(@"", rows, nil) ]];
    self.title = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.threads.count, SCIDirectManualSeenListModeTitle(self.manualSeenEnabled)];
}

- (void)showHowItWorks {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"How It Works"
                                                message:SCIDirectManualSeenListHelpText(self.manualSeenEnabled)
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"OK" style:SCIIGAlertActionStyleCancel handler:nil]
    ]];
}

- (void)showChatActionsForIndex:(NSUInteger)index {
    if (index >= self.threads.count) return;
    NSDictionary *entry = self.threads[index];
    NSMutableArray<SCIIGAlertAction *> *actions = [NSMutableArray array];
    NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
    
    BOOL isGroup = [entry[@"isGroup"] boolValue];
    
    SCIIGAlertAction *openProfileAction = nil;
    if (!isGroup && users.count == 1) {
        NSString *username = [users.firstObject[@"username"] isKindOfClass:[NSString class]] ? users.firstObject[@"username"] : nil;
        if (username.length > 0) {
            openProfileAction = [SCIIGAlertAction actionWithTitle:@"Open Profile" style:SCIIGAlertActionStyleDefault handler:^{
                [SCIUtils openInstagramProfileForUsername:username];
            }];
        }
    }
    
    __weak typeof(self) weakSelf = self;
    SCIIGAlertAction *removeAction = [SCIIGAlertAction actionWithTitle:@"Remove" style:SCIIGAlertActionStyleDestructive handler:^{
        NSString *threadId = [entry[@"threadId"] isKindOfClass:[NSString class]] ? entry[@"threadId"] : nil;
        if (threadId.length > 0) {
            NSString *threadName = [weakSelf displayNameForEntry:entry];
            SCIDirectRemoveManualSeenThreadId(threadId, weakSelf.manualSeenEnabled);
            SCINotify(kSCINotificationDirectThreadSeenRule,
                      [NSString stringWithFormat:@"Removed %@", threadName],
                      SCIDirectManualSeenListTitle(weakSelf.manualSeenEnabled),
                      @"circle_check_filled",
                      SCINotificationToneSuccess);
            [weakSelf rebuildSections];
        }
    }];
    
    SCIIGAlertAction *cancelAction = [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil];
    
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
    
    [SCIIGAlertPresenter presentAlertFromViewController:self title:[self displayNameForEntry:entry] message:message actions:actions];
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
        SCIDirectRemoveManualSeenThreadId(threadId, strongSelf.manualSeenEnabled);
        SCINotify(kSCINotificationDirectThreadSeenRule,
                  [NSString stringWithFormat:@"Removed %@", threadName],
                  SCIDirectManualSeenListTitle(strongSelf.manualSeenEnabled),
                  @"circle_check_filled",
                  SCINotificationToneSuccess);
        [strongSelf rebuildSections];
        completionHandler(YES);
    }];
    deleteAction.image = SCISettingsIcon(@"trash");
    deleteAction.backgroundColor = [SCIUtils SCIColor_InstagramDestructive];
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
        SCIDirectRemoveManualSeenThreadId(threadId, self.manualSeenEnabled);
        SCINotify(kSCINotificationDirectThreadSeenRule,
                  [NSString stringWithFormat:@"Removed %@", threadName],
                  SCIDirectManualSeenListTitle(self.manualSeenEnabled),
                  @"circle_check_filled",
                  SCINotificationToneSuccess);
        [self rebuildSections];
    }
}

- (void)presentError:(NSString *)message {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Unable to Add Chat"
                                                message:message
                                                actions:@[[SCIIGAlertAction actionWithTitle:@"OK" style:SCIIGAlertActionStyleCancel handler:nil]]];
}

- (void)addChat {
    __weak typeof(self) weakSelf = self;
    [SCIIGAlertPresenter presentTextInputAlertFromViewController:self
                                                           title:@"Add Chat"
                                                         message:@"Enter the Instagram username for a 1:1 DM thread."
                                                     placeholder:@"username"
                                                     initialText:nil
                                                 autocapitalized:NO
                                                    confirmTitle:@"Search"
                                                     cancelTitle:@"Cancel"
                                                    confirmStyle:SCIIGAlertActionStyleDefault
                                                    confirmBlock:^(NSString *text) {
        [weakSelf lookupUsername:text];
    } cancelBlock:nil];
}

- (void)lookupUsername:(NSString *)rawUsername {
    NSString *username = [[[rawUsername ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"@"]];
    if (username.length == 0) return;
    NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    if (encodedUsername.length == 0) return;

    SCILog(@"Messages", @"[SCInsta MessagesSeen] Settings add chat lookup started username=%@ list=%@",
           username,
           SCIDirectManualSeenListTitle(self.manualSeenEnabled));

    __weak typeof(self) weakSelf = self;
    [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", encodedUsername]
                                      body:nil
                                completion:^(NSDictionary *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary *user = response[@"data"][@"user"];
        if (![user isKindOfClass:[NSDictionary class]]) user = response[@"user"];
        if (![user isKindOfClass:[NSDictionary class]] || error) {
            SCILog(@"Messages", @"[SCInsta MessagesSeen] Settings add chat user lookup failed username=%@ error=%@", username, error);
            [strongSelf presentError:[NSString stringWithFormat:@"User '%@' was not found.", username]];
            return;
        }
        NSString *pk = SCIDirectStringFromValue(user[@"id"] ?: user[@"pk"]);
        NSString *resolvedUsername = SCIDirectStringFromValue(user[@"username"]) ?: username;
        NSString *fullName = SCIDirectStringFromValue(user[@"full_name"] ?: user[@"fullName"]) ?: @"";
        NSString *profilePicUrl = SCIDirectStringFromValue(user[@"profile_pic_url"] ?: user[@"profile_pic_url_hd"]);
        if (pk.length == 0) {
            SCILog(@"Messages", @"[SCInsta MessagesSeen] Settings add chat user lookup missing pk username=%@ response=%@", username, user);
            [strongSelf presentError:@"Could not resolve this user's Instagram id."];
            return;
        }

        NSString *encodedRecipients = [[NSString stringWithFormat:@"[%@]", pk] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                          path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=%@", encodedRecipients]
                                          body:nil
                                    completion:^(NSDictionary *threadResponse, NSError *threadError) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (!innerSelf) return;
            NSDictionary *thread = threadResponse[@"thread"];
            if (![thread isKindOfClass:[NSDictionary class]] || threadError) {
                SCILog(@"Messages", @"[SCInsta MessagesSeen] Settings add chat thread lookup failed username=%@ pk=%@ error=%@", resolvedUsername, pk, threadError);
                [innerSelf presentError:[NSString stringWithFormat:@"No 1:1 DM thread was found with @%@.", resolvedUsername]];
                return;
            }

            NSString *threadId = SCIDirectStringFromValue(thread[@"thread_id"] ?: thread[@"threadId"]);
            if (threadId.length == 0) {
                SCILog(@"Messages", @"[SCInsta MessagesSeen] Settings add chat thread lookup missing threadId username=%@ pk=%@ response=%@", resolvedUsername, pk, thread);
                [innerSelf presentError:[NSString stringWithFormat:@"No 1:1 DM thread was found with @%@.", resolvedUsername]];
                return;
            }

            NSString *threadName = SCIDirectStringFromValue(thread[@"thread_title"] ?: thread[@"threadName"]) ?: resolvedUsername;
            SCILog(@"Messages", @"[SCInsta MessagesSeen] Settings add chat resolved username=%@ pk=%@ threadId=%@ threadName=%@",
                   resolvedUsername,
                   pk,
                   threadId,
                   threadName);
            NSString *message = fullName.length > 0
                ? [NSString stringWithFormat:@"@%@ (%@)", resolvedUsername, fullName]
                : [@"@" stringByAppendingString:resolvedUsername];
            [SCIIGAlertPresenter presentAlertFromViewController:innerSelf
                                                           title:@"Add to List?"
                                                         message:message
                                                         actions:@[
                [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
                [SCIIGAlertAction actionWithTitle:@"Add" style:SCIIGAlertActionStyleDefault handler:^{
                    NSMutableDictionary *usersEntry = [@{
                        @"pk": pk,
                        @"username": resolvedUsername,
                        @"fullName": fullName,
                    } mutableCopy];
                    if (profilePicUrl.length > 0) usersEntry[@"profilePicUrl"] = profilePicUrl;
                    SCIDirectAddOrUpdateManualSeenThreadEntry(@{
                        @"threadId": threadId,
                        @"threadName": threadName,
                        @"isGroup": @(NO),
                        @"users": @[usersEntry.copy],
                    }, innerSelf.manualSeenEnabled);
                    SCINotify(kSCINotificationDirectThreadSeenRule,
                              [NSString stringWithFormat:@"Added %@", threadName],
                              SCIDirectManualSeenListTitle(innerSelf.manualSeenEnabled),
                              @"circle_check_filled",
                              SCINotificationToneSuccess);
                    [innerSelf rebuildSections];
                }],
            ]];
        }];
    }];
}

@end

UIViewController *SCIDirectManualSeenListViewController(void) {
    return [[SCIDirectManualSeenThreadsViewController alloc] init];
}

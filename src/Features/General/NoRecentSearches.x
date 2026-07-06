#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../InstagramHeaders.h"
#import "../../Utils.h"

// Disable logging of searches.
//
// The relevant classes were migrated Obj-C -> Swift around IG 434, so the
// plain class names (IGRecentSearchStore, IGSearchEntityRouter) no longer
// exist at runtime on newer builds — they're registered under their mangled
// Swift names instead, which made the old static hook on IGRecentSearchStore
// silently bind to nothing. We resolve each class by trying the legacy Obj-C name
// and the Swift-mangled name, and hook selectors that are stable across
// versions (addItem:, _processRecentlySelectedRecipients:, and the
// shouldAddToRecents init) via MSHookMessageEx.

static BOOL SPKNoRecentSearchesEnabled(void) {
    return [SPKUtils getBoolPref:@"general_no_recent_searches"];
}

#pragma mark - IGSearchEntityRouter (gate recents at the source)

static id (*orig_searchRouterInit3)(id, SEL, id, id, BOOL) = NULL;
static id replaced_searchRouterInit3(id self, SEL _cmd, id session, id module, BOOL shouldAddToRecents) {
    if (SPKNoRecentSearchesEnabled()) {
        shouldAddToRecents = NO;
    }
    return orig_searchRouterInit3(self, _cmd, session, module, shouldAddToRecents);
}

static id (*orig_searchRouterInit4)(id, SEL, id, id, BOOL, long long) = NULL;
static id replaced_searchRouterInit4(id self, SEL _cmd, id session, id module, BOOL shouldAddToRecents, long long mode) {
    if (SPKNoRecentSearchesEnabled()) {
        shouldAddToRecents = NO;
    }
    return orig_searchRouterInit4(self, _cmd, session, module, shouldAddToRecents, mode);
}

#pragma mark - IGRecentSearchStore (most in-app search bars)

static BOOL (*orig_recentStoreAddItem)(id, SEL, id) = NULL;
static BOOL replaced_recentStoreAddItem(id self, SEL _cmd, id item) {
    if (SPKNoRecentSearchesEnabled()) {
        return NO;
    }
    return orig_recentStoreAddItem(self, _cmd, item);
}

// Hide already-saved recents (loaded from disk) without deleting them, so the
// list also disappears for users who enabled the toggle after searches were
// stored. These are the readonly getters the search UI reads; returning empty
// is reversible the moment the pref is turned back off.
static id (*orig_recentStoreRecentItems)(id, SEL) = NULL;
static id replaced_recentStoreRecentItems(id self, SEL _cmd) {
    if (SPKNoRecentSearchesEnabled()) {
        return @[];
    }
    return orig_recentStoreRecentItems(self, _cmd);
}

static id (*orig_recentStoreAllItems)(id, SEL) = NULL;
static id replaced_recentStoreAllItems(id self, SEL _cmd) {
    if (SPKNoRecentSearchesEnabled()) {
        return @[];
    }
    return orig_recentStoreAllItems(self, _cmd);
}

#pragma mark - IGDirectRecipientRecentSearchStorage (DM recipient search bar)

static void (*orig_directProcessRecents)(id, SEL, id) = NULL;
static void replaced_directProcessRecents(id self, SEL _cmd, id recipients) {
    if (SPKNoRecentSearchesEnabled()) {
        return;
    }
    orig_directProcessRecents(self, _cmd, recipients);
}

// Report the recipient store as empty so the recent-recipients section is also
// hidden for previously-saved entries.
static BOOL (*orig_directIsEmpty)(id, SEL) = NULL;
static BOOL replaced_directIsEmpty(id self, SEL _cmd) {
    if (SPKNoRecentSearchesEnabled()) {
        return YES;
    }
    return orig_directIsEmpty(self, _cmd);
}

#pragma mark - Installation

static Class SPKResolveClass(NSArray<NSString *> *candidateNames) {
    for (NSString *name in candidateNames) {
        Class cls = NSClassFromString(name);
        if (cls)
            return cls;
    }
    return Nil;
}

static void SPKHookIfPresent(Class cls, NSString *selectorName, IMP replacement, void *origStore) {
    if (!cls)
        return;
    SEL selector = NSSelectorFromString(selectorName);
    if (!class_getInstanceMethod(cls, selector))
        return;
    MSHookMessageEx(cls, selector, replacement, (IMP *)origStore);
}

void SPKInstallNoRecentSearchesHooksIfEnabled(void) {
    if (!SPKNoRecentSearchesEnabled())
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // IGSearchEntityRouter — force shouldAddToRecents off in every init variant.
        Class routerClass = SPKResolveClass(@[
            @"IGSearchEntityRouter",
            @"_TtC20IGSearchEntityRouter20IGSearchEntityRouter",
        ]);
        SPKHookIfPresent(routerClass,
                         @"initWithUserSession:analyticsModule:shouldAddToRecents:",
                         (IMP)replaced_searchRouterInit3, &orig_searchRouterInit3);
        SPKHookIfPresent(routerClass,
                         @"initWithUserSession:analyticsModule:shouldAddToRecents:mode:",
                         (IMP)replaced_searchRouterInit4, &orig_searchRouterInit4);

        // IGRecentSearchStore — block new entries from being recorded.
        Class recentStoreClass = SPKResolveClass(@[
            @"IGRecentSearchStore",
            @"_TtC19IGRecentSearchStore19IGRecentSearchStore",
        ]);
        SPKHookIfPresent(recentStoreClass, @"addItem:",
                         (IMP)replaced_recentStoreAddItem, &orig_recentStoreAddItem);
        SPKHookIfPresent(recentStoreClass, @"recentItems",
                         (IMP)replaced_recentStoreRecentItems, &orig_recentStoreRecentItems);
        SPKHookIfPresent(recentStoreClass, @"allItems",
                         (IMP)replaced_recentStoreAllItems, &orig_recentStoreAllItems);

        // IGDirectRecipientRecentSearchStorage — block recent DM recipients.
        // (Still a plain Obj-C class on both 410 and 435.)
        Class directStorageClass = SPKResolveClass(@[
            @"IGDirectRecipientRecentSearchStorage",
        ]);
        SPKHookIfPresent(directStorageClass, @"_processRecentlySelectedRecipients:",
                         (IMP)replaced_directProcessRecents, &orig_directProcessRecents);
        SPKHookIfPresent(directStorageClass, @"isEmpty",
                         (IMP)replaced_directIsEmpty, &orig_directIsEmpty);
    });
}

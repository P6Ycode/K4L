#import "SPKInstagramIconCatalog.h"

#import <dlfcn.h>

#import "../AssetUtils.h"

static NSBundle *SPKInstagramIconCatalogFrameworkBundle(void) {
    static NSBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework"];
        bundle = [NSBundle bundleWithPath:path];
    });
    return bundle;
}

static void SPKInstagramIconCatalogLoadCoreUI(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_LAZY);
    });
}

static NSArray<NSString *> *SPKInstagramIconCatalogFilterNames(id names) {
    if (![names isKindOfClass:[NSArray class]] && ![names isKindOfClass:[NSSet class]]) {
        return @[];
    }

    NSMutableOrderedSet<NSString *> *filtered = [NSMutableOrderedSet orderedSet];
    for (id value in names) {
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *name = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([name hasPrefix:@"ig_icon_"] && [name hasSuffix:@"_24"]) {
            [filtered addObject:name];
        }
    }
    return [filtered.array sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

static NSArray<NSString *> *SPKInstagramIconCatalogNamesFromSelector(id catalog, SEL selector) {
    if (!catalog || ![catalog respondsToSelector:selector]) {
        return @[];
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id result = [catalog performSelector:selector];
#pragma clang diagnostic pop

    return SPKInstagramIconCatalogFilterNames(result);
}

static id SPKInstagramIconCatalogCreateCatalog(NSURL *assetsURL, NSBundle *bundle) {
    SPKInstagramIconCatalogLoadCoreUI();

    Class catalogClass = NSClassFromString(@"CUICatalog");
    if (!catalogClass) {
        return nil;
    }

    id catalog = nil;
    SEL initWithURLError = NSSelectorFromString(@"initWithURL:error:");
    if (assetsURL && [catalogClass instancesRespondToSelector:initWithURLError]) {
        NSMethodSignature *signature = [catalogClass instanceMethodSignatureForSelector:initWithURLError];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        NSError *error = nil;
        id allocated = [catalogClass alloc];
        [invocation setTarget:allocated];
        [invocation setSelector:initWithURLError];
        [invocation setArgument:&assetsURL atIndex:2];
        [invocation setArgument:&error atIndex:3];
        [invocation invoke];
        __unsafe_unretained id returnedCatalog = nil;
        [invocation getReturnValue:&returnedCatalog];
        catalog = returnedCatalog;
    }

    SEL initWithNameFromBundle = NSSelectorFromString(@"initWithName:fromBundle:");
    if (!catalog && bundle && [catalogClass instancesRespondToSelector:initWithNameFromBundle]) {
        NSMethodSignature *signature = [catalogClass instanceMethodSignatureForSelector:initWithNameFromBundle];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        NSString *name = @"Assets";
        id allocated = [catalogClass alloc];
        [invocation setTarget:allocated];
        [invocation setSelector:initWithNameFromBundle];
        [invocation setArgument:&name atIndex:2];
        [invocation setArgument:&bundle atIndex:3];
        [invocation invoke];
        __unsafe_unretained id returnedCatalog = nil;
        [invocation getReturnValue:&returnedCatalog];
        catalog = returnedCatalog;
    }

    return catalog;
}

static NSArray<NSString *> *SPKInstagramIconCatalogRuntimeNames(void) {
    NSBundle *bundle = SPKInstagramIconCatalogFrameworkBundle();
    NSURL *assetsURL = [bundle URLForResource:@"Assets" withExtension:@"car"];
    id catalog = SPKInstagramIconCatalogCreateCatalog(assetsURL, bundle);
    if (!catalog) {
        return @[];
    }

    for (NSString *selectorName in @[ @"allImageNames", @"_allImageNames", @"imageNames", @"allAssetNames", @"allRenditionNames", @"renditionNames" ]) {
        NSArray<NSString *> *names = SPKInstagramIconCatalogNamesFromSelector(catalog, NSSelectorFromString(selectorName));
        if (names.count > 0) {
            return names;
        }
    }

    return @[];
}

@implementation SPKInstagramIconCatalog

+ (NSArray<NSString *> *)availableInstagramIconNames {
    static NSArray<NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = SPKInstagramIconCatalogRuntimeNames();
    });
    return names ?: @[];
}

+ (NSString *)displayNameForIconName:(NSString *)iconName {
    NSString *name = [iconName copy] ?: @"";
    if ([name hasPrefix:@"ig_icon_"]) {
        name = [name substringFromIndex:@"ig_icon_".length];
    }
    if ([name hasSuffix:@"_24"]) {
        name = [name substringToIndex:name.length - @"_24".length];
    }
    return name;
}

+ (NSString *)searchTextForIconName:(NSString *)iconName {
    NSString *displayName = [self displayNameForIconName:iconName];
    NSString *normalized = [[[displayName stringByReplacingOccurrencesOfString:@"_" withString:@" "] stringByReplacingOccurrencesOfString:@"-" withString:@" "] lowercaseString];
    return [NSString stringWithFormat:@"%@ %@", [displayName lowercaseString], normalized];
}

+ (BOOL)isInstagramBundleIconName:(NSString *)iconName {
    return [iconName hasPrefix:@"ig_icon_"];
}

@end

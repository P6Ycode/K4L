#import "Utils.h"
#import "AssetUtils.h"
#import "App/SCICore.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "Shared/MediaPreview/SCIMediaCacheManager.h"
#import "Shared/Gallery/SCIGalleryPaths.h"
#import "Shared/UI/SCIIGAlertPresenter.h"
#import "Settings/SCIPreferenceAvailability.h"
#import "Settings/SCIPreferences.h"
#import "App/SCIStabilityGuard.h"

static NSString *SCITrimmedLogBody(NSString *body) {
    return [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *SCINormalizedLogBody(NSString *category, NSString *body, NSString **outCategory) {
    NSString *resolvedCategory = category.length ? category : @"General";
    NSString *resolvedBody = body ?: @"";
    NSArray<NSDictionary<NSString *, NSString *> *> *legacyPrefixes = @[
        @{@"prefix": @"[SCInsta][startup]", @"category": @"Startup"},
        @{@"prefix": @"[SCInsta Gallery]", @"category": @"Gallery"},
        @{@"prefix": @"[SCInsta BulkDownload]", @"category": @"BulkDownload"},
        @{@"prefix": @"[SCInsta]", @"category": resolvedCategory},
    ];

    for (NSDictionary<NSString *, NSString *> *entry in legacyPrefixes) {
        NSString *prefix = entry[@"prefix"];
        if ([resolvedBody hasPrefix:prefix]) {
            resolvedCategory = entry[@"category"] ?: resolvedCategory;
            resolvedBody = SCITrimmedLogBody([resolvedBody substringFromIndex:prefix.length]);
            break;
        }
    }

    if (outCategory) {
        *outCategory = resolvedCategory;
    }
    return resolvedBody;
}

void SCILogMessage(NSString *category, os_log_type_t type, NSString *format, ...) {
    NSString *body = @"";
    if (format.length > 0) {
        va_list args;
        va_start(args, format);
        body = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
    }

    NSString *resolvedCategory = nil;
    NSString *resolvedBody = SCINormalizedLogBody(category, body ?: @"", &resolvedCategory);
    NSString *line = [NSString stringWithFormat:@"[SCInsta %@]: %@", resolvedCategory ?: @"General", resolvedBody ?: @""];
    os_log_with_type(OS_LOG_DEFAULT, type, "%{public}s", line.UTF8String);
}

static NSNumber *SCINumericValueForSelector(id target, NSString *selectorName) {
    if (!target || !selectorName.length) return nil;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;

    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    const char *returnType = signature.methodReturnType;
    if (!returnType || !returnType[0]) return nil;

    switch (returnType[0]) {
        case '@': {
            id value = ((id (*)(id, SEL))objc_msgSend)(target, selector);
            if ([value respondsToSelector:@selector(doubleValue)]) {
                return @([value doubleValue]);
            }
            return nil;
        }
        case 'd':
            return @(((double (*)(id, SEL))objc_msgSend)(target, selector));
        case 'f':
            return @((double)((float (*)(id, SEL))objc_msgSend)(target, selector));
        case 'q':
            return @((double)((long long (*)(id, SEL))objc_msgSend)(target, selector));
        case 'Q':
            return @((double)((unsigned long long (*)(id, SEL))objc_msgSend)(target, selector));
        case 'i':
            return @((double)((int (*)(id, SEL))objc_msgSend)(target, selector));
        case 'I':
            return @((double)((unsigned int (*)(id, SEL))objc_msgSend)(target, selector));
        case 'l':
            return @((double)((long (*)(id, SEL))objc_msgSend)(target, selector));
        case 'L':
            return @((double)((unsigned long (*)(id, SEL))objc_msgSend)(target, selector));
        case 's':
            return @((double)((short (*)(id, SEL))objc_msgSend)(target, selector));
        case 'S':
            return @((double)((unsigned short (*)(id, SEL))objc_msgSend)(target, selector));
        case 'c':
            return @((double)((char (*)(id, SEL))objc_msgSend)(target, selector));
        case 'C':
            return @((double)((unsigned char (*)(id, SEL))objc_msgSend)(target, selector));
        case 'B':
            return @((double)((BOOL (*)(id, SEL))objc_msgSend)(target, selector));
        default:
            return nil;
    }
}

static id SCIObjectForSelector(id target, NSString *selectorName) {
    if (!target || !selectorName.length) return nil;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;

    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static id SCIKVCObject(id target, NSString *key) {
    if (!target || !key.length) return nil;

    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSURL *SCIURLFromStringOrURL(id value) {
    if (!value) return nil;

    if ([value isKindOfClass:[NSURL class]]) {
        return value;
    }

    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return [NSURL URLWithString:(NSString *)value];
    }

    return nil;
}

static double SCIDoubleValue(id value) {
    if (!value) return 0.0;

    if ([value respondsToSelector:@selector(doubleValue)]) {
        return [value doubleValue];
    }

    return 0.0;
}

static NSInteger SCIIntegerValue(id value) {
    if (!value) return 0;

    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }

    return 0;
}

static NSArray *SCIArrayFromCollection(id collection) {
    if (!collection ||
        [collection isKindOfClass:[NSDictionary class]] ||
        [collection isKindOfClass:[NSString class]] ||
        [collection isKindOfClass:[NSURL class]]) {
        return nil;
    }

    if ([collection isKindOfClass:[NSArray class]]) {
        return collection;
    }

    if ([collection isKindOfClass:[NSOrderedSet class]]) {
        return [(NSOrderedSet *)collection array];
    }

    if ([collection isKindOfClass:[NSSet class]]) {
        return [(NSSet *)collection allObjects];
    }

    if ([collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
        NSMutableArray *items = [NSMutableArray array];
        for (id item in collection) {
            [items addObject:item];
        }
        return items;
    }

    return nil;
}

static NSString * const kSCICacheAutoClearModeKey = @"general_cache_auto_clear";
static NSString * const kSCICacheLastClearedAtKey = @"general_cache_last_cleared_at";

static UIColor *SCIDynamicInstagramColor(CGFloat lightRed,
                                         CGFloat lightGreen,
                                         CGFloat lightBlue,
                                         CGFloat darkRed,
                                         CGFloat darkGreen,
                                         CGFloat darkBlue) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
        BOOL dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        CGFloat red = dark ? darkRed : lightRed;
        CGFloat green = dark ? darkGreen : lightGreen;
        CGFloat blue = dark ? darkBlue : lightBlue;
        return [UIColor colorWithRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1.0];
    }];
}

static UIColor *SCIInstagramColorFromClassSelector(NSString *className, SEL selector) {
    Class colorClass = NSClassFromString(className);
    if (!colorClass || ![colorClass respondsToSelector:selector]) return nil;

    id color = ((id (*)(id, SEL))objc_msgSend)(colorClass, selector);
    return [color isKindOfClass:[UIColor class]] ? color : nil;
}

static UIColor *SCIInstagramDestructiveColor(void) {
    UIColor *color = SCIInstagramColorFromClassSelector(@"HMDSColor", @selector(dangerText));
    if (color) return color;

    color = SCIInstagramColorFromClassSelector(@"HMDSColor", @selector(danger));
    if (color) return color;

    color = SCIInstagramColorFromClassSelector(@"TWDSColor", @selector(negative));
    if (color) return color;

    return [UIColor colorWithDynamicProvider:^UIColor *(__unused UITraitCollection *traits) {
        return [UIColor colorWithRed:1.0 green:0.396 blue:0.490 alpha:1.0];
    }];
}

static NSArray *SCIImageVersionsFromPhoto(IGPhoto *photo) {
    if (!photo) return nil;

    NSArray *versions = SCIArrayFromCollection(SCIObjectForSelector(photo, @"imageVersions"));
    if (versions.count > 0) return versions;

    versions = SCIArrayFromCollection([SCIUtils getIvarForObj:photo name:"_originalImageVersions"]);
    if (versions.count > 0) return versions;

    versions = SCIArrayFromCollection(SCIObjectForSelector(photo, @"imageVersionDictionaries"));
    if (versions.count > 0) return versions;

    versions = SCIArrayFromCollection([SCIUtils getIvarForObj:photo name:"_imageVersions"]);
    if (versions.count > 0) return versions;

    versions = SCIArrayFromCollection([SCIUtils getIvarForObj:photo name:"_imageVersionDictionaries"]);
    return versions.count > 0 ? versions : nil;
}

static NSArray *SCIVideoVersionsFromVideo(IGVideo *video) {
    if (!video) return nil;

    NSArray *versions = SCIArrayFromCollection(SCIObjectForSelector(video, @"videoVersions"));
    if (versions.count > 0) return versions;

    versions = SCIArrayFromCollection(SCIObjectForSelector(video, @"videoVersionDictionaries"));
    if (versions.count > 0) return versions;

    versions = SCIArrayFromCollection([SCIUtils getIvarForObj:video name:"_videoVersions"]);
    if (versions.count > 0) return versions;

    versions = SCIArrayFromCollection([SCIUtils getIvarForObj:video name:"_videoVersionDictionaries"]);
    return versions.count > 0 ? versions : nil;
}

static NSArray<NSDictionary *> *SCISortedMediaVariantsFromVersions(NSArray *versions) {
    if (![versions isKindOfClass:[NSArray class]] || versions.count == 0) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *variants = [NSMutableArray array];
    NSMutableSet<NSString *> *seenURLs = [NSMutableSet set];

    for (id version in versions) {
        id rawURL = nil;
        id widthValue = nil;
        id heightValue = nil;
        id bandwidthValue = nil;

        if ([version isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)version;
            rawURL = dict[@"url"] ?: dict[@"urlString"];
            widthValue = dict[@"width"];
            heightValue = dict[@"height"];
            bandwidthValue = dict[@"bandwidth"];
        } else {
            rawURL = SCIObjectForSelector(version, @"url");
            if (!rawURL) {
                rawURL = SCIObjectForSelector(version, @"urlString");
            }
            widthValue = SCINumericValueForSelector(version, @"width");
            heightValue = SCINumericValueForSelector(version, @"height");
            bandwidthValue = SCINumericValueForSelector(version, @"bandwidth");
        }

        NSURL *url = SCIURLFromStringOrURL(rawURL);
        if (!url) continue;

        NSString *absolute = url.absoluteString;
        if (absolute.length == 0 || [seenURLs containsObject:absolute]) {
            continue;
        }
        [seenURLs addObject:absolute];

        [variants addObject:@{
            @"url": url,
            @"width": @(SCIDoubleValue(widthValue)),
            @"height": @(SCIDoubleValue(heightValue)),
            @"bandwidth": @(SCIIntegerValue(bandwidthValue))
        }];
    }

    [variants sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        double lhsArea = [lhs[@"width"] doubleValue] * [lhs[@"height"] doubleValue];
        double rhsArea = [rhs[@"width"] doubleValue] * [rhs[@"height"] doubleValue];

        if (lhsArea > rhsArea) return NSOrderedAscending;
        if (lhsArea < rhsArea) return NSOrderedDescending;

        NSInteger lhsBandwidth = [lhs[@"bandwidth"] integerValue];
        NSInteger rhsBandwidth = [rhs[@"bandwidth"] integerValue];
        if (lhsBandwidth > rhsBandwidth) return NSOrderedAscending;
        if (lhsBandwidth < rhsBandwidth) return NSOrderedDescending;

        return NSOrderedSame;
    }];

    return variants;
}

static NSURL *SCIHighestQualityURLFromVersions(NSArray *versions) {
    NSArray<NSDictionary *> *variants = SCISortedMediaVariantsFromVersions(versions);
    if (variants.count == 0) return nil;

    id value = variants.firstObject[@"url"];
    return [value isKindOfClass:[NSURL class]] ? value : nil;
}

static NSURL *SCIURLFromVideoURLCollection(id collection) {
    if (!collection) return nil;

    NSArray *items = SCIArrayFromCollection(collection);

    if (!items) {
        return SCIURLFromStringOrURL(collection);
    }

    for (id item in items) {
        NSURL *url = nil;

        if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)item;
            url = SCIURLFromStringOrURL(dict[@"url"] ?: dict[@"urlString"]);
        } else {
            url = SCIURLFromStringOrURL(item);
        }

        if (url) return url;
    }

    return nil;
}

static NSURL *SCIProfilePictureURLFromInfo(id info) {
    if (!info) return nil;

    NSURL *url = SCIURLFromStringOrURL(SCIObjectForSelector(info, @"url"));
    if (url) return url;

    url = SCIURLFromStringOrURL(SCIObjectForSelector(info, @"urlString"));
    if (url) return url;

    if ([info isKindOfClass:[NSDictionary class]]) {
        NSDictionary *infoDictionary = (NSDictionary *)info;
        url = SCIURLFromStringOrURL(infoDictionary[@"url"] ?: infoDictionary[@"urlString"]);
        if (url) return url;
    }

    return nil;
}

static NSURL *SCIHDProfilePicURL(id user) {
    if (!user) return nil;

    NSURL *url = SCIProfilePictureURLFromInfo(SCIObjectForSelector(user, @"hdProfilePicUrlInfo"));
    if (url) return url;

    url = SCIURLFromStringOrURL(SCIObjectForSelector(user, @"HDProfilePicURL"));
    if (url) return url;

    url = SCIProfilePictureURLFromInfo(SCIObjectForSelector(user, @"_private_hdProfilePicUrlInfo"));
    if (url) return url;

    url = SCIProfilePictureURLFromInfo(SCIObjectForSelector(user, @"HDProfilePicURLInfo"));
    if (url) return url;

    url = SCIURLFromStringOrURL(SCIObjectForSelector(user, @"profile_pic_url_hd"));
    if (url) return url;

    return SCIURLFromStringOrURL(SCIKVCObject(user, @"profile_pic_url_hd"));
}

static NSURL *SCIThumbProfilePicURL(id user) {
    if (!user) return nil;

    NSURL *url = SCIURLFromStringOrURL(SCIObjectForSelector(user, @"derivedProfilePicURL"));
    if (url) return url;

    url = SCIURLFromStringOrURL(SCIObjectForSelector(user, @"profilePicURLString"));
    if (url) return url;

    url = SCIURLFromStringOrURL(SCIObjectForSelector(user, @"profilePicURL"));
    if (url) return url;

    url = SCIURLFromStringOrURL(SCIObjectForSelector(user, @"_private_profilePicURLString"));
    if (url) return url;

    url = SCIURLFromStringOrURL(SCIObjectForSelector(user, @"_private_profilePicUrl"));
    if (url) return url;

    url = SCIURLFromStringOrURL(SCIObjectForSelector(user, @"profile_pic_url"));
    if (url) return url;

    return SCIURLFromStringOrURL(SCIKVCObject(user, @"profile_pic_url"));
}

static BOOL SCIInstagramHostMatchesCanonical(NSString *host) {
    if (host.length == 0) return NO;
    NSString *lower = host.lowercaseString;
    return [lower isEqualToString:@"instagram.com"]
        || [lower isEqualToString:@"www.instagram.com"]
        || [lower isEqualToString:@"instagr.am"]
        || [lower hasSuffix:@".instagram.com"];
}

static BOOL SCIInstagramPathUsesSharePrefix(NSArray<NSString *> *segments) {
    if (segments.count < 2) return NO;
    NSString *candidate = segments[1].lowercaseString;
    return [candidate isEqualToString:@"p"]
        || [candidate isEqualToString:@"reel"]
        || [candidate isEqualToString:@"reels"]
        || [candidate isEqualToString:@"tv"];
}

static NSArray<NSString *> *SCISanitizedInstagramPathSegments(NSArray<NSString *> *segments) {
    if (segments.count >= 3 && SCIInstagramPathUsesSharePrefix(segments)) {
        return [segments subarrayWithRange:NSMakeRange(1, segments.count - 1)];
    }
    return segments;
}

static NSArray<NSURLQueryItem *> *SCISanitizedInstagramQueryItems(NSArray<NSURLQueryItem *> *items) {
    if (items.count == 0) return nil;

    static NSSet<NSString *> *blockedKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedKeys = [NSSet setWithArray:@[
            @"igsh", @"igshid", @"ig_rid", @"ig_mid",
            @"utm_source", @"utm_medium", @"utm_campaign", @"utm_term", @"utm_content",
            @"fbclid"
        ]];
    });

    NSMutableArray<NSURLQueryItem *> *kept = [NSMutableArray array];
    for (NSURLQueryItem *item in items) {
        if (![blockedKeys containsObject:item.name.lowercaseString]) {
            [kept addObject:item];
        }
    }
    return kept.count > 0 ? kept : nil;
}

@implementation SCIUtils

// Master kill switch overlay: when "Disable All Settings" is on, runtime
// reads of feature prefs return the registered default instead of the user's
// stored value. The toggles themselves still display the saved state because
// the settings UI reads NSUserDefaults directly (boolForKey:), not these
// accessors.
//
// A handful of keys must bypass the overlay so the kill switch and the
// settings shortcut keep working. They're enumerated here.
static NSSet<NSString *> *SCIMasterDisableBypassKeys(void) {
    static NSSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"tools_disable_all",
            @"tools_settings_shortcut",
            @"gallery_quick_access_tab",
            @"tools_open_settings_on_launch",
            @"app_first_run",
        ]];
    });
    return keys;
}

static BOOL SCIMasterDisableActive(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"tools_disable_all"];
}

static id SCIPrefValueWithMasterOverlay(NSString *key) {
    if (key.length == 0) return nil;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (SCIMasterDisableActive() && ![SCIMasterDisableBypassKeys() containsObject:key]) {
        return SCICoreRegisteredDefaults()[key];
    }
    return [defaults objectForKey:key];
}

+ (BOOL)getBoolPref:(NSString *)key {
    if (![key length]) return NO;
    if (!SCIPrefIsAvailable(key)) return NO;
    id value = SCIPrefValueWithMasterOverlay(key);
    if ([value respondsToSelector:@selector(boolValue)]) return [value boolValue];
    return NO;
}
+ (double)getDoublePref:(NSString *)key {
    if (![key length]) return 0;
    id value = SCIPrefValueWithMasterOverlay(key);
    if ([value respondsToSelector:@selector(doubleValue)]) return [value doubleValue];
    return 0;
}
+ (NSString *)getStringPref:(NSString *)key {
    if (![key length]) return @"";
    id value = SCIPrefValueWithMasterOverlay(key);
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

// MARK: Misc
+ (BOOL)tabOrderSetTo:(NSString *)ordering {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"interface_nav_order"] isEqualToString:ordering];
};

+ (NSString *)IGVersionString {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
};
+ (BOOL)isNotch {
    return [[[UIApplication sharedApplication] keyWindow] safeAreaInsets].bottom > 0;
};

+ (BOOL)existingLongPressGestureRecognizerForView:(UIView *)view {
    NSArray *allRecognizers = view.gestureRecognizers;

    for (UIGestureRecognizer *recognizer in allRecognizers) {
        if ([[recognizer class] isSubclassOfClass:[UILongPressGestureRecognizer class]]) {
            return YES;
        }
    }

    return NO;
}

+ (_Bool)sci_liquidGlassLauncherPrefKey:(NSString *)key orig:(_Bool)fallback {
    return [SCIUtils sci_isLiquidGlassEffectivelyEnabled] ? YES : fallback;
}

+ (BOOL)sci_isLiquidGlassEffectivelyEnabled {
    return [SCIUtils getBoolPref:kSCIPrefInterfaceLiquidGlass] &&
        !SCIStabilityGuardIsSafeStartupMode();
}

// MARK: Session / user
+ (id)activeUserSession {
    @try {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                id session = nil;
                @try {
                    if ([window respondsToSelector:@selector(userSession)]) {
                        session = [window valueForKey:@"userSession"];
                    }
                } @catch (__unused NSException *e) {}
                if (session) return session;
            }
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

+ (NSString *)pkFromIGUser:(id)user {
    if (!user) return nil;
    Ivar pkIvar = NULL;
    for (Class cls = [user class]; cls && !pkIvar; cls = class_getSuperclass(cls)) {
        pkIvar = class_getInstanceVariable(cls, "_pk");
    }
    if (!pkIvar) return nil;
    @try {
        id pk = object_getIvar(user, pkIvar);
        if ([pk isKindOfClass:[NSString class]] && [(NSString *)pk length]) return pk;
        if (pk) return [pk description];
    } @catch (__unused NSException *e) {}
    return nil;
}

+ (NSString *)currentUserPK {
    id session = [self activeUserSession];
    if (!session) return nil;
    @try {
        id user = [session valueForKey:@"user"];
        return [self pkFromIGUser:user];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

+ (void)cleanCache {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSError *> *deletionErrors = [NSMutableArray array];

    // Temp folder
    // * disabled bc app crashed trying to delete certain files inside it
    // todo: remove the above disclaimer if this new code doesn't cause crashing
    NSArray *tempFolderContents = [fileManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:NSTemporaryDirectory()] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];

    for (NSURL *fileURL in tempFolderContents) {
        NSError *cacheItemDeletionError;
        [fileManager removeItemAtURL:fileURL error:&cacheItemDeletionError];

        if (cacheItemDeletionError) [deletionErrors addObject:cacheItemDeletionError];
    }

    // Analytics folder
    NSString *analyticsFolder = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Application Support/com.burbn.instagram/analytics"];
    NSArray *analyticsFolderContents = [fileManager contentsOfDirectoryAtURL:[[NSURL alloc] initFileURLWithPath:analyticsFolder] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];

    for (NSURL *fileURL in analyticsFolderContents) {
        NSError *cacheItemDeletionError;
        [fileManager removeItemAtURL:fileURL error:&cacheItemDeletionError];

        if (cacheItemDeletionError) [deletionErrors addObject:cacheItemDeletionError];
    }
    
    // Caches folder
    NSString *cachesFolder = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Caches"];
    NSArray *cachesFolderContents = [fileManager contentsOfDirectoryAtURL:[[NSURL alloc] initFileURLWithPath:cachesFolder] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    
    for (NSURL *fileURL in cachesFolderContents) {
        NSError *cacheItemDeletionError;
        [fileManager removeItemAtURL:fileURL error:&cacheItemDeletionError];

        if (cacheItemDeletionError) [deletionErrors addObject:cacheItemDeletionError];
    }

    NSURL *previewCacheURL = [[[SCIMediaCacheManager sharedManager] valueForKey:@"cacheRootURL"] copy];
    if (previewCacheURL) {
        NSError *previewCacheDeletionError = nil;
        [fileManager removeItemAtURL:previewCacheURL error:&previewCacheDeletionError];
        if (previewCacheDeletionError) [deletionErrors addObject:previewCacheDeletionError];
    }

    // Log errors
    if (deletionErrors.count > 1) {

        for (NSError *error in deletionErrors) {
            SCILog(@"General", @"[SCInsta] File Deletion Error: %@", error);
        }

    }

    [SCIUtils markCacheClearedNow];
}

+ (unsigned long long)cacheSizeBytes {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *libraryFolder = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSArray<NSURL *> *folders = @[
        [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES],
        [NSURL fileURLWithPath:[libraryFolder stringByAppendingPathComponent:@"Application Support/com.burbn.instagram/analytics"] isDirectory:YES],
        [NSURL fileURLWithPath:[libraryFolder stringByAppendingPathComponent:@"Caches"] isDirectory:YES]
    ];
    NSArray<NSURLResourceKey> *resourceKeys = @[NSURLIsRegularFileKey, NSURLFileSizeKey];
    unsigned long long totalBytes = 0;

    for (NSURL *folderURL in folders) {
        NSArray<NSURL *> *folderContents = [fileManager contentsOfDirectoryAtURL:folderURL
                                                      includingPropertiesForKeys:resourceKeys
                                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                           error:nil];
        for (NSURL *itemURL in folderContents) {
            NSDictionary<NSURLResourceKey, id> *values = [itemURL resourceValuesForKeys:resourceKeys error:nil];
            if ([values[NSURLIsRegularFileKey] boolValue]) {
                totalBytes += [values[NSURLFileSizeKey] unsignedLongLongValue];
            }

            NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:itemURL
                                                           includingPropertiesForKeys:resourceKeys
                                                                              options:0
                                                                         errorHandler:nil];
            for (NSURL *fileURL in enumerator) {
                values = [fileURL resourceValuesForKeys:resourceKeys error:nil];
                if ([values[NSURLIsRegularFileKey] boolValue]) {
                    totalBytes += [values[NSURLFileSizeKey] unsignedLongLongValue];
                }
            }
        }
    }

    return totalBytes;
}

+ (NSString *)formattedCacheSize {
    return [NSByteCountFormatter stringFromByteCount:(long long)[self cacheSizeBytes]
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

+ (NSString *)cacheAutoClearMode {
    NSString *mode = [SCIUtils getStringPref:kSCICacheAutoClearModeKey];
    return mode.length > 0 ? mode : @"never";
}

+ (BOOL)shouldAutomaticallyClearCacheNow {
    NSString *mode = [self cacheAutoClearMode];
    if ([mode isEqualToString:@"never"]) return NO;
    if ([mode isEqualToString:@"always"]) return YES;

    NSDate *lastClearedAt = [[NSUserDefaults standardUserDefaults] objectForKey:kSCICacheLastClearedAtKey];
    if (![lastClearedAt isKindOfClass:[NSDate class]]) return YES;

    NSTimeInterval interval = 0.0;
    if ([mode isEqualToString:@"daily"]) interval = 24.0 * 60.0 * 60.0;
    else if ([mode isEqualToString:@"weekly"]) interval = 7.0 * 24.0 * 60.0 * 60.0;
    else if ([mode isEqualToString:@"monthly"]) interval = 30.0 * 24.0 * 60.0 * 60.0;
    else return NO;

    return [[NSDate date] timeIntervalSinceDate:lastClearedAt] >= interval;
}

+ (void)markCacheClearedNow {
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kSCICacheLastClearedAtKey];
}

+ (void)evaluateAutomaticCacheClearIfNeeded {
    if (![self shouldAutomaticallyClearCacheNow]) return;
    SCILog(@"General", @"[SCInsta] Automatically clearing cache...");
    [self cleanCache];
}

// MARK: Display View Controllers
+ (void)showMediaPreview:(NSURL *)fileURL {
    [SCIFullScreenMediaPlayer showFileURL:fileURL];
}
+ (void)showShareVC:(id)item {
    UIActivityViewController *acVC = [[UIActivityViewController alloc] initWithActivityItems:@[item] applicationActivities:nil];
    if (is_iPad()) {
        acVC.popoverPresentationController.sourceView = topMostController().view;
        acVC.popoverPresentationController.sourceRect = CGRectMake(topMostController().view.bounds.size.width / 2.0, topMostController().view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    [topMostController() presentViewController:acVC animated:true completion:nil];
}
+ (void)showSettingsVC:(UIWindow *)window {
    UIViewController *rootController = [window rootViewController];
    SCISettingsViewController *settingsViewController = [SCISettingsViewController new];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:settingsViewController];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    
    [rootController presentViewController:navigationController animated:YES completion:nil];
}

+ (void)showSettingsForTopicTitle:(NSString *)title {
    NSArray *rootSections = [SCITweakSettings sections];
    SCISetting *matchedRow = nil;
    for (NSDictionary *section in rootSections) {
        NSArray *rows = section[@"rows"];
        for (SCISetting *row in rows) {
            if (![row isKindOfClass:[SCISetting class]]) continue;
            if ([row.title isEqualToString:title]) {
                matchedRow = row;
                break;
            }
        }
        if (matchedRow) break;
    }

    UIViewController *settingsViewController = nil;
    if (matchedRow) {
        if (matchedRow.navViewController) {
            settingsViewController = matchedRow.navViewController;
        } else if (matchedRow.navSections.count > 0) {
            settingsViewController = [[SCISettingsViewController alloc] initWithTitle:title sections:matchedRow.navSections reduceMargin:NO];
            settingsViewController.title = title;
        }
    }

    if (!settingsViewController) {
        settingsViewController = [SCISettingsViewController new];
    }


    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:settingsViewController];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    UIViewController *presenter = topMostController();
    UIUserInterfaceStyle interfaceStyle = presenter.view.window.traitCollection.userInterfaceStyle;
    if (interfaceStyle == UIUserInterfaceStyleUnspecified) {
        interfaceStyle = presenter.traitCollection.userInterfaceStyle;
    }
    if (interfaceStyle != UIUserInterfaceStyleUnspecified) {
        navigationController.overrideUserInterfaceStyle = interfaceStyle;
        settingsViewController.overrideUserInterfaceStyle = interfaceStyle;
    }
    UISheetPresentationController *sheet = navigationController.sheetPresentationController;
    sheet.detents = @[
        [UISheetPresentationControllerDetent mediumDetent],
        [UISheetPresentationControllerDetent largeDetent]
    ];
    sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;

    [presenter presentViewController:navigationController animated:YES completion:nil];
}

// MARK: Colours
+ (UIColor *)SCIColor_Primary {
    return [UIColor colorWithRed:0/255.0 green:149/255.0 blue:246/255.0 alpha:1.0];
}

+ (UIColor *)SCIColor_InstagramBackground {
    return SCIDynamicInstagramColor(255.0, 255.0, 255.0, 11.0, 16.0, 20.0);
}

+ (UIColor *)SCIColor_InstagramSecondaryBackground {
    return SCIDynamicInstagramColor(240.0, 241.0, 245.0, 42.0, 48.0, 55.0);
}

+ (UIColor *)SCIColor_InstagramTertiaryBackground {
    return SCIDynamicInstagramColor(232.0, 234.0, 238.0, 58.0, 64.0, 72.0);
}

+ (UIColor *)SCIColor_InstagramGroupedBackground {
    return [self SCIColor_InstagramBackground];
}

+ (UIColor *)SCIColor_InstagramPrimaryText {
    return SCIDynamicInstagramColor(15.0, 20.0, 25.0, 244.0, 247.0, 251.0);
}

+ (UIColor *)SCIColor_InstagramSecondaryText {
    return SCIDynamicInstagramColor(99.0, 108.0, 118.0, 177.0, 185.0, 194.0);
}

+ (UIColor *)SCIColor_InstagramTertiaryText {
    return SCIDynamicInstagramColor(130.0, 138.0, 147.0, 130.0, 138.0, 147.0);
}

+ (UIColor *)SCIColor_InstagramSeparator {
    return SCIDynamicInstagramColor(220.0, 223.0, 228.0, 52.0, 59.0, 67.0);
}

+ (UIColor *)SCIColor_InstagramFavorite {
    return [UIColor colorWithRed:255.0 / 255.0 green:48.0 / 255.0 blue:64.0 / 255.0 alpha:1.0];
}

+ (UIColor *)SCIColor_InstagramDestructive {
    return SCIInstagramDestructiveColor();
}

+ (UIColor *)SCIColor_InstagramPressedBackground {
    return SCIDynamicInstagramColor(232.0, 233.0, 238.0, 51.0, 60.0, 69.0);
}

+ (UIColor *)SCIColor_SettingsSwitchOnTint {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
        return traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? UIColor.whiteColor : UIColor.blackColor;
    }];
}

+ (UIColor *)SCIColor_SettingsSwitchThumbTint {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
        return traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? UIColor.blackColor : UIColor.whiteColor;
    }];
}

+ (UIColor *)SCIColor_SettingsSwitchOnTintForTraitCollection:(UITraitCollection *)traitCollection {
    BOOL isDark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return isDark ? UIColor.whiteColor : UIColor.blackColor;
}

+ (UIColor *)SCIColor_SettingsSwitchThumbTintForTraitCollection:(UITraitCollection *)traitCollection {
    BOOL isDark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return isDark ? UIColor.blackColor : UIColor.whiteColor;
}

// MARK: Errors
+ (NSError *)errorWithDescription:(NSString *)errorDesc {
    return [self errorWithDescription:errorDesc code:1];
}
+ (NSError *)errorWithDescription:(NSString *)errorDesc code:(NSInteger)errorCode {
    NSError *error = [ NSError errorWithDomain:@"com.socuul.scinsta" code:errorCode userInfo:@{ NSLocalizedDescriptionKey: errorDesc } ];
    return error;
}
+ (BOOL)openURL:(NSURL *)url {
    if (!url) return NO;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    return YES;
}

+ (BOOL)openURLThroughApplicationDelegate:(NSURL *)url {
    if (!url) return NO;
    UIApplication *application = [UIApplication sharedApplication];
    id<UIApplicationDelegate> delegate = application.delegate;
    if ([delegate respondsToSelector:@selector(application:openURL:options:)]) {
        [delegate application:application openURL:url options:@{}];
        return YES;
    }
    return NO;
}

+ (BOOL)openInstagramProfileForUsername:(NSString *)username {
    NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if (encodedUsername.length == 0) return NO;

    NSURL *appURL = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", encodedUsername]];
    if (appURL && [[UIApplication sharedApplication] canOpenURL:appURL]) {
        if ([self openURLThroughApplicationDelegate:appURL]) return YES;
        return [self openURL:appURL];
    }

    NSURL *webURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/", encodedUsername]];
    return [self openInstagramMediaURL:webURL];
}

+ (BOOL)openInstagramMediaURL:(NSURL *)url {
    if (!url) return NO;
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    UIApplication *application = [UIApplication sharedApplication];
    id<UIApplicationDelegate> delegate = application.delegate;

    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
        activity.webpageURL = url;
        SEL continueSelector = @selector(application:continueUserActivity:restorationHandler:);
        if ([delegate respondsToSelector:continueSelector]) {
            BOOL handled = [delegate application:application
                            continueUserActivity:activity
                              restorationHandler:^(__unused NSArray<id<UIUserActivityRestoring>> *restorableObjects) {}];
            if (handled) return YES;
        }
        if ([self openURLThroughApplicationDelegate:url]) return YES;
    } else if ([scheme isEqualToString:@"instagram"]) {
        if ([self openURLThroughApplicationDelegate:url]) return YES;
    }

    return [self openURL:url];
}

+ (NSURL *)sanitizedInstagramShareURL:(NSURL *)url {
    if (!url) return nil;
    if (![url isKindOfClass:[NSURL class]]) return nil;

    if (![url.scheme.lowercaseString isEqualToString:@"http"] && ![url.scheme.lowercaseString isEqualToString:@"https"]) {
        return url;
    }
    if (!SCIInstagramHostMatchesCanonical(url.host)) {
        return url;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) {
        return url;
    }

    NSArray<NSString *> *rawSegments = [components.path componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *segments = [NSMutableArray array];
    for (NSString *segment in rawSegments) {
        if (segment.length > 0) {
            [segments addObject:segment];
        }
    }

    NSArray<NSString *> *sanitizedSegments = SCISanitizedInstagramPathSegments(segments);
    NSString *path = sanitizedSegments.count > 0 ? [@"/" stringByAppendingString:[sanitizedSegments componentsJoinedByString:@"/"]] : @"/";
    if (![path hasSuffix:@"/"]) {
        path = [path stringByAppendingString:@"/"];
    }

    components.scheme = @"https";
    components.host = @"www.instagram.com";
    components.path = path;
    components.queryItems = SCISanitizedInstagramQueryItems(components.queryItems);
    components.fragment = nil;

    return components.URL ?: url;
}

+ (NSString *)instagramShortcodeForMediaPK:(NSString *)mediaPK {
    if (mediaPK.length == 0) return nil;

    // Media pk may arrive as "<pk>" or "<pk>_<userpk>"; only the leading id matters.
    NSString *identifier = [mediaPK componentsSeparatedByString:@"_"].firstObject ?: mediaPK;
    if (identifier.length == 0) return nil;
    if ([identifier rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) return nil;

    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:identifier];
    if (![scanner scanUnsignedLongLong:&value] || !scanner.isAtEnd || value == 0) return nil;

    static NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    NSMutableString *shortcode = [NSMutableString string];
    while (value > 0) {
        NSUInteger index = (NSUInteger)(value % 64);
        unichar character = [alphabet characterAtIndex:index];
        [shortcode insertString:[NSString stringWithCharacters:&character length:1] atIndex:0];
        value /= 64;
    }
    return shortcode.length > 0 ? shortcode : nil;
}

+ (BOOL)openPhotosApp {
    NSURL *url = [NSURL URLWithString:@"photos-redirect://"];
    if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
        return [self openURL:url];
    }
    return NO;
}

// MARK: Media
+ (NSURL *)getPhotoUrl:(IGPhoto *)photo {
    if (!photo) return nil;

    NSURL *photoUrl = SCIHighestQualityURLFromVersions(SCIImageVersionsFromPhoto(photo));
    if (photoUrl) return photoUrl;

    if ([photo respondsToSelector:@selector(imageURLForWidth:)]) {
        photoUrl = [photo imageURLForWidth:100000.00];
        if (photoUrl) return photoUrl;
    }

    photoUrl = SCIURLFromStringOrURL(SCIObjectForSelector(photo, @"thumbnailURL"));

    return photoUrl;
}
+ (NSURL *)getPhotoUrlForMedia:(IGMedia *)media {
    if (!media) return nil;

    IGPhoto *photo = SCIObjectForSelector(media, @"photo");
    if (!photo) return nil;

    return [SCIUtils getPhotoUrl:photo];
}
+ (NSURL *)getBestProfilePictureURLForUser:(id)user {
    return SCIHDProfilePicURL(user) ?: SCIThumbProfilePicURL(user);
}
+ (NSURL *)getVideoUrl:(IGVideo *)video {
    if (!video) return nil;

    NSURL *videoURL = SCIHighestQualityURLFromVersions(SCIVideoVersionsFromVideo(video));
    if (videoURL) return videoURL;

    // The past (pre v398)
    if ([video respondsToSelector:@selector(sortedVideoURLsBySize)]) {
        id sorted = [video sortedVideoURLsBySize];
        videoURL = SCIURLFromVideoURLCollection(sorted);
        if (videoURL) return videoURL;
    }

    // The present (post v398)
    if ([video respondsToSelector:@selector(allVideoURLs)]) {
        videoURL = SCIURLFromVideoURLCollection([video allVideoURLs]);
        if (videoURL) return videoURL;
    }

    return nil;
}
+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media {
    if (!media) return nil;

    IGVideo *video = SCIObjectForSelector(media, @"video");
    if (!video) return nil;

    return [SCIUtils getVideoUrl:video];
}

// MARK: View Controller Helpers
+ (UIViewController *)viewControllerForView:(UIView *)view {
    NSString *viewDelegate = @"viewDelegate";
    if ([view respondsToSelector:NSSelectorFromString(viewDelegate)]) {
        return [view valueForKey:viewDelegate];
    }

    return nil;
}

+ (UIViewController *)viewControllerForAncestralView:(UIView *)view {
    NSString *_viewControllerForAncestor = @"_viewControllerForAncestor";
    if ([view respondsToSelector:NSSelectorFromString(_viewControllerForAncestor)]) {
        return [view valueForKey:_viewControllerForAncestor];
    }

    return nil;
}

+ (UIViewController *)nearestViewControllerForView:(UIView *)view {
    return [self viewControllerForView:view] ?: [self viewControllerForAncestralView:view];
}

// Functions


// MARK: Alerts
+ (BOOL)showConfirmation:(void(^)(void))okHandler title:(NSString *)title {
    return [self showConfirmation:okHandler cancelHandler:nil title:title message:nil];
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler title:(NSString *)title message:(NSString *)message {
    return [self showConfirmation:okHandler cancelHandler:nil title:title message:message];
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler title:(NSString *)title {
    return [self showConfirmation:okHandler cancelHandler:cancelHandler title:title message:nil];
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler title:(NSString *)title message:(NSString *)message {
    [SCIIGAlertPresenter presentAlertFromViewController:topMostController()
                                                  title:title ?: @"Confirm Action"
                                                message:message ?: @"Are you sure you want to continue?"
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:^{
            if (cancelHandler) cancelHandler();
        }],
        [SCIIGAlertAction actionWithTitle:@"Confirm" style:SCIIGAlertActionStyleDefault handler:^{
            if (okHandler) okHandler();
        }],
    ]];
    return YES;
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler {
    return [self showConfirmation:okHandler title:nil];
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler {
    return [self showConfirmation:okHandler cancelHandler:cancelHandler title:nil];
}
+ (void)showRestartConfirmation {
    [SCIIGAlertPresenter presentAlertFromViewController:topMostController()
                                                  title:@"Restart required"
                                                message:@"You must restart the app to apply this change"
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Later" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Restart" style:SCIIGAlertActionStyleDefault handler:^{
            exit(0);
        }],
    ]];
};

// MARK: Math
+ (NSUInteger)decimalPlacesInDouble:(double)value {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setMaximumFractionDigits:15]; // Allow enough digits for double precision
    [formatter setMinimumFractionDigits:0];
    [formatter setDecimalSeparator:@"."]; // Force dot for internal logic, then respect locale for final display if needed

    NSString *stringValue = [formatter stringFromNumber:@(value)];

    // Find decimal separator
    NSRange decimalRange = [stringValue rangeOfString:formatter.decimalSeparator];

    if (decimalRange.location == NSNotFound) {
        return 0;
    } else {
        return stringValue.length - (decimalRange.location + decimalRange.length);
    }
}

+ (UIImage *)sci_scaleImage:(UIImage *)image maxPointDimension:(CGFloat)maxPt {
    if (!image || maxPt <= 0) {
        return image;
    }
    CGFloat w = image.size.width;
    CGFloat h = image.size.height;
    CGFloat maxdim = MAX(w, h);
    if (maxdim <= maxPt + 0.01) {
        return image;
    }
    CGFloat ratio = maxPt / maxdim;
    CGSize newSize = CGSizeMake(round(w * ratio), round(h * ratio));
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = image.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize format:fmt];
    UIImage *out = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    }];
    UIImageRenderingMode mode = image.renderingMode;
    if (mode != UIImageRenderingModeAutomatic) {
        out = [out imageWithRenderingMode:mode];
    }
    return out;
}

// Ivars
+ (NSNumber *)numericValueForObj:(id)obj selectorName:(NSString *)selectorName {
    return SCINumericValueForSelector(obj, selectorName);
}

+ (id)getIvarForObj:(id)obj name:(const char *)name {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) return nil;

    return object_getIvar(obj, ivar);
}
+ (void)setIvarForObj:(id)obj name:(const char *)name value:(id)value {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) return;
    
    object_setIvarWithStrongDefault(obj, ivar, value);
}


@end

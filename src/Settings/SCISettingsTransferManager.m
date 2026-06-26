#import "SCISettingsTransferManager.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <compression.h>

#import "TweakSettings.h"
#import "SCIPreferenceAvailability.h"
#import "SCIAppIconCatalog.h"
#import "../Utils.h"
#import "../App/SCICore.h"
#import "../Shared/Account/SCIAccountManager.h"
#import "../Shared/UI/SCIIGAlertPresenter.h"
#import "../Shared/Gallery/SCIGalleryCoreDataStack.h"
#import "../Shared/Gallery/SCIGalleryManager.h"
#import "../Shared/Gallery/SCIGalleryPaths.h"
#import "../Shared/Settings/SCISettingsLockManager.h"
#import "../Features/Messages/DeletedMessagesLog/SCIDeletedMessagesStorage.h"
#import "../Features/Profile/ProfileAnalyzer/SCIProfileAnalyzerStorage.h"

typedef NS_ENUM(NSInteger, SCITransferAccountScope) {
    SCITransferAccountScopeAllAccounts = 0,     // global + every account's overrides
    SCITransferAccountScopeCurrentAccount = 1,  // global + the active account's overrides
};

@interface SCISettingsTransferManager () <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *presentingController;
@property (nonatomic, strong) UIDocumentPickerViewController *activeDocumentPicker;
@property (nonatomic, assign) BOOL pendingImportSettings;
@property (nonatomic, assign) BOOL pendingImportGallery;
@property (nonatomic, assign) BOOL pendingImportDeletedMessages;
@property (nonatomic, assign) BOOL pendingImportProfileAnalyzer;
@property (nonatomic, assign) BOOL isImportMode;
- (void)exportFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery includeDeletedMessages:(BOOL)includeDeletedMessages includeProfileAnalyzer:(BOOL)includeProfileAnalyzer settingsScope:(SCITransferAccountScope)settingsScope;
@end

static NSString *SCITemporaryTransferRoot(NSString *suffix) {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"scinsta-transfer-%@-%@", suffix, NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    return root;
}

static NSArray<SCISetting *> *SCIFlattenSettingsRowsFromSections(NSArray *sections) {
    NSMutableArray<SCISetting *> *rows = [NSMutableArray array];
    for (NSDictionary *section in sections) {
        NSArray *sectionRows = [section[@"rows"] isKindOfClass:[NSArray class]] ? section[@"rows"] : @[];
        for (SCISetting *row in sectionRows) {
            if (![row isKindOfClass:[SCISetting class]]) continue;
            [rows addObject:row];
            if (row.navSections.count > 0) {
                [rows addObjectsFromArray:SCIFlattenSettingsRowsFromSections(row.navSections)];
            }
        }
    }
    return rows;
}

static void SCIAddPreferenceKeysFromMenu(UIMenu *menu, NSMutableSet<NSString *> *keys) {
    for (UIMenuElement *element in menu.children ?: @[]) {
        if ([element isKindOfClass:[UIMenu class]]) {
            SCIAddPreferenceKeysFromMenu((UIMenu *)element, keys);
            continue;
        }

        if (![element isKindOfClass:[UICommand class]]) continue;
        NSDictionary *propertyList = ((UICommand *)element).propertyList;
        NSString *defaultsKey = [propertyList[@"defaultsKey"] isKindOfClass:[NSString class]] ? propertyList[@"defaultsKey"] : nil;
        if (defaultsKey.length > 0) {
            [keys addObject:defaultsKey];
        }
    }
}

static BOOL SCIIsSCIPreferenceKey(NSString *key) {
    if (key.length == 0) return NO;

    static NSSet<NSString *> *exactKeys;
    static NSArray<NSString *> *prefixes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        exactKeys = [NSSet setWithArray:@[
            @"app_first_run"
        ]];
        // Every SCInsta surface prefix. Keep this complete — a missing prefix means
        // user-set keys of that group that aren't registered defaults / settings rows
        // silently fall out of export (and per-account variants too). SCInsta-specific
        // prefixes only; avoid generic ones (app_, dm_, enable_) that IG might also use.
        prefixes = @[
            @"feed_",
            @"general_",
            @"gallery_",
            @"interface_",
            @"msgs_",
            @"notifs_",
            @"profile_",
            @"reels_",
            @"stories_",
            @"tools_",
            @"downloads_",
            @"instants_",
            @"trim_",
            @"main_"
        ];
    });

    if ([exactKeys containsObject:key]) return YES;
    for (NSString *prefix in prefixes) {
        if ([key hasPrefix:prefix]) return YES;
    }
    return NO;
}

// Per-account override keys are "u_<pk>_<baseKey>" (see SCIEffectivePreferenceKey in
// Utils.m); pk is the numeric IG user PK. Parses one out, rejecting anything else.
static BOOL SCIParsePerAccountKey(NSString *key, NSString * _Nullable * _Nullable pkOut, NSString * _Nullable * _Nullable baseOut) {
    if (![key hasPrefix:@"u_"] || key.length < 4) return NO;
    NSString *rest = [key substringFromIndex:2];
    NSRange sep = [rest rangeOfString:@"_"];
    if (sep.location == NSNotFound || sep.location == 0) return NO;
    NSString *pk = [rest substringToIndex:sep.location];
    // pk must be all digits so we never mistake an unrelated "u_*" key for ours.
    if ([pk rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) return NO;
    NSString *base = [rest substringFromIndex:sep.location + 1];
    if (base.length == 0) return NO;
    if (pkOut) *pkOut = pk;
    if (baseOut) *baseOut = base;
    return YES;
}

// Transient / device-local state that must never travel between installs:
// crash-recovery safe mode and the startup profiling flag. Exporting these
// could, e.g., drop a fresh install straight into safe mode.
static NSSet<NSString *> *SCITransferExcludedKeys(void) {
    static NSSet<NSString *> *excluded;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        excluded = [NSSet setWithArray:@[
            @"app_safe_startup",
            @"app_startup_profiling"
        ]];
    });
    return excluded;
}

static NSSet<NSString *> *SCIExportedPreferenceKeys(void) {
    NSMutableSet<NSString *> *keys = [NSMutableSet set];

    // Every key registered as an SCInsta default is, by construction, one of
    // ours — include them all rather than prefix-filtering. The old prefix
    // allowlist silently dropped whole feature groups whose keys don't start
    // with a "surface" prefix (downloads_, instants_, trim_, main_feed_mode, …),
    // which is why those settings were lost across export/import.
    for (NSString *key in SCICoreRegisteredDefaults()) {
        [keys addObject:key];
    }

    for (SCISetting *row in SCIFlattenSettingsRowsFromSections([SCITweakSettings sections])) {
        if (row.defaultsKey.length > 0) [keys addObject:row.defaultsKey];
        if (row.mutuallyExclusiveDefaultsKey.length > 0) [keys addObject:row.mutuallyExclusiveDefaultsKey];
        if (row.baseMenu) SCIAddPreferenceKeysFromMenu(row.baseMenu, keys);
    }

    [keys addObjectsFromArray:@[
        @"app_first_run",
        @"gallery_folders",
        @"gallery_sort_mode",
        @"gallery_view_mode",
        @"general_cache_auto_clear",
        @"general_cache_last_cleared_at",
        // Runtime-only prefs whose keys use a non-surface prefix, so they are
        // neither registered as defaults nor caught by the prefix scan below.
        @"enable_hidden_texteffectsstyles",
        @"dm_log_date_format"
    ]];

    NSDictionary *allPrefs = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *key in allPrefs) {
        if (SCIIsSCIPreferenceKey(key)) {
            [keys addObject:key];
        }
    }

    [keys minusSet:SCITransferExcludedKeys()];
    return keys;
}

// Every per-account override key ("u_<pk>_<base>") currently in defaults whose base is
// one of ours, filtered to the requested scope. The base allowlist (SCIExportedPreferenceKeys
// ∪ SCIIsSCIPreferenceKey) is why the SCIIsSCIPreferenceKey prefix list must stay complete.
static NSSet<NSString *> *SCIPerAccountOverrideKeys(SCITransferAccountScope scope, NSString *currentPK) {
    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    NSSet<NSString *> *base = SCIExportedPreferenceKeys();
    NSSet<NSString *> *excluded = SCITransferExcludedKeys();
    NSDictionary *allPrefs = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *key in allPrefs) {
        NSString *pk = nil, *baseKey = nil;
        if (!SCIParsePerAccountKey(key, &pk, &baseKey)) continue;
        if (![base containsObject:baseKey] && !SCIIsSCIPreferenceKey(baseKey)) continue;
        if ([excluded containsObject:baseKey]) continue;
        if (scope == SCITransferAccountScopeCurrentAccount && ![pk isEqualToString:(currentPK ?: @"")]) continue;
        [keys addObject:key];
    }
    return keys;
}

// Global/base keys + the in-scope per-account overrides.
static NSSet<NSString *> *SCIExportedPreferenceKeysForScope(SCITransferAccountScope scope, NSString *currentPK) {
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithSet:SCIExportedPreferenceKeys()];
    [keys unionSet:SCIPerAccountOverrideKeys(scope, currentPK)];
    return keys;
}

static NSDictionary *SCIPreferencesSnapshotForScope(SCITransferAccountScope scope, NSString *currentPK) {
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];

    if (scope == SCITransferAccountScopeCurrentAccount) {
        // "This account" = FLATTEN: capture the active account's *effective* values
        // (per-account override → global → default) for every per-account-capable key,
        // stored under base keys. Device-global keys are excluded — they aren't this
        // account's settings. On import these are re-homed into the importing account's
        // namespace, so other accounts are never touched.
        for (NSString *key in SCIExportedPreferenceKeys()) {
            if (SCIPreferenceKeyIsGlobal(key)) continue;
            id value = SCIPreferenceObjectForKey(key);
            if (value) snapshot[key] = value;
        }
        return snapshot;
    }

    // "All accounts" = verbatim: base/global keys + every account's overrides as stored.
    NSDictionary *allPrefs = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *key in SCIExportedPreferenceKeysForScope(scope, currentPK)) {
        id value = allPrefs[key];
        if (value) snapshot[key] = value;
    }
    return snapshot;
}

static UIViewController *SCIDocumentPickerPresenter(UIViewController *preferredController) {
    UIViewController *presenter = preferredController;
    if (!presenter || !presenter.view.window) {
        presenter = topMostController();
    }
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    if ([presenter isKindOfClass:[UINavigationController class]]) {
        UIViewController *visible = ((UINavigationController *)presenter).visibleViewController;
        if (visible) presenter = visible;
    }
    return presenter ?: topMostController();
}

static BOOL SCIIsValidSettingsTransferBundleRoot(NSString *bundleRoot);
static NSString *SCIResolvedSettingsTransferBundleRoot(NSURL *pickedURL);

static void SCIAppendUInt16LE(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2] = { (uint8_t)(value & 0xff), (uint8_t)((value >> 8) & 0xff) };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void SCIAppendUInt32LE(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = {
        (uint8_t)(value & 0xff),
        (uint8_t)((value >> 8) & 0xff),
        (uint8_t)((value >> 16) & 0xff),
        (uint8_t)((value >> 24) & 0xff)
    };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static uint16_t SCIReadUInt16LE(const uint8_t *bytes, NSUInteger offset) {
    return (uint16_t)bytes[offset] | ((uint16_t)bytes[offset + 1] << 8);
}

static uint32_t SCIReadUInt32LE(const uint8_t *bytes, NSUInteger offset) {
    return (uint32_t)bytes[offset] |
           ((uint32_t)bytes[offset + 1] << 8) |
           ((uint32_t)bytes[offset + 2] << 16) |
           ((uint32_t)bytes[offset + 3] << 24);
}

static uint32_t SCIZipCRC32ForBytes(uint32_t crc, const uint8_t *bytes, NSUInteger length) {
    static uint32_t table[256];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int j = 0; j < 8; j++) {
                c = (c & 1) ? (0xedb88320U ^ (c >> 1)) : (c >> 1);
            }
            table[i] = c;
        }
    });

    crc = crc ^ 0xffffffffU;
    for (NSUInteger i = 0; i < length; i++) {
        crc = table[(crc ^ bytes[i]) & 0xff] ^ (crc >> 8);
    }
    return crc ^ 0xffffffffU;
}

static void SCIZipCurrentDOSTimeDate(uint16_t *timeOut, uint16_t *dateOut) {
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:[NSDate date]];
    NSInteger year = MAX(1980, MIN(2107, components.year));
    if (timeOut) *timeOut = (uint16_t)((components.hour << 11) | (components.minute << 5) | (components.second / 2));
    if (dateOut) *dateOut = (uint16_t)(((year - 1980) << 9) | (components.month << 5) | components.day);
}

@interface SCIZipEntry : NSObject
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic, copy) NSString *sourcePath;
@property (nonatomic, assign) uint32_t crc32;
@property (nonatomic, assign) uint32_t size;
@property (nonatomic, assign) uint32_t localHeaderOffset;
@property (nonatomic, assign) uint16_t dosTime;
@property (nonatomic, assign) uint16_t dosDate;
@end

@implementation SCIZipEntry
@end

static NSArray<SCIZipEntry *> *SCIZipEntriesForDirectory(NSString *root, NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSString *> *enumerator = [fm enumeratorAtPath:root];
    NSMutableArray<SCIZipEntry *> *entries = [NSMutableArray array];

    for (NSString *relativePath in enumerator) {
        NSString *sourcePath = [root stringByAppendingPathComponent:relativePath];
        NSNumber *isDirectory = nil;
        NSURL *sourceURL = [NSURL fileURLWithPath:sourcePath];
        [sourceURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (isDirectory.boolValue) continue;

        NSDictionary *attrs = [fm attributesOfItemAtPath:sourcePath error:error];
        if (!attrs) return nil;
        unsigned long long fileSize = [attrs[NSFileSize] unsignedLongLongValue];
        if (fileSize > UINT32_MAX) {
            if (error) {
                *error = [NSError errorWithDomain:@"SCInstaSettingsTransfer"
                                             code:2001
                                         userInfo:@{NSLocalizedDescriptionKey: @"Export contains a file larger than 4 GB, which is not supported yet."}];
            }
            return nil;
        }

        SCIZipEntry *entry = [SCIZipEntry new];
        entry.relativePath = [relativePath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        entry.sourcePath = sourcePath;
        entry.size = (uint32_t)fileSize;
        if ([entry.relativePath dataUsingEncoding:NSUTF8StringEncoding].length > UINT16_MAX) {
            if (error) {
                *error = [NSError errorWithDomain:@"SCInstaSettingsTransfer"
                                             code:2003
                                         userInfo:@{NSLocalizedDescriptionKey: @"Export contains a path that is too long for zip."}];
            }
            return nil;
        }
        [entries addObject:entry];
    }

    [entries sortUsingComparator:^NSComparisonResult(SCIZipEntry *a, SCIZipEntry *b) {
        return [a.relativePath compare:b.relativePath];
    }];
    if (entries.count > UINT16_MAX) {
        if (error) {
            *error = [NSError errorWithDomain:@"SCInstaSettingsTransfer"
                                         code:2004
                                     userInfo:@{NSLocalizedDescriptionKey: @"Export contains too many files for this zip writer."}];
        }
        return nil;
    }
    return entries;
}

static BOOL SCIWriteStoredZipFromDirectory(NSString *root, NSString *zipPath, NSError **error) {
    NSArray<SCIZipEntry *> *entries = SCIZipEntriesForDirectory(root, error);
    if (!entries) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *parent = [zipPath stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createFileAtPath:zipPath contents:nil attributes:nil];
    NSFileHandle *zip = [NSFileHandle fileHandleForWritingAtPath:zipPath];
    if (!zip) return NO;

    uint16_t dosTime = 0;
    uint16_t dosDate = 0;
    SCIZipCurrentDOSTimeDate(&dosTime, &dosDate);

    for (SCIZipEntry *entry in entries) {
        entry.dosTime = dosTime;
        entry.dosDate = dosDate;
        if ([zip offsetInFile] > UINT32_MAX) {
            if (error) {
                *error = [NSError errorWithDomain:@"SCInstaSettingsTransfer"
                                             code:2005
                                         userInfo:@{NSLocalizedDescriptionKey: @"Export is too large for this zip writer."}];
            }
            [zip closeFile];
            return NO;
        }
        entry.localHeaderOffset = (uint32_t)[zip offsetInFile];
        NSData *nameData = [entry.relativePath dataUsingEncoding:NSUTF8StringEncoding];

        NSMutableData *local = [NSMutableData data];
        SCIAppendUInt32LE(local, 0x04034b50);
        SCIAppendUInt16LE(local, 20);
        SCIAppendUInt16LE(local, 0);
        SCIAppendUInt16LE(local, 0);
        SCIAppendUInt16LE(local, entry.dosTime);
        SCIAppendUInt16LE(local, entry.dosDate);
        SCIAppendUInt32LE(local, 0);
        SCIAppendUInt32LE(local, entry.size);
        SCIAppendUInt32LE(local, entry.size);
        SCIAppendUInt16LE(local, (uint16_t)nameData.length);
        SCIAppendUInt16LE(local, 0);
        [local appendData:nameData];
        [zip writeData:local];

        NSFileHandle *input = [NSFileHandle fileHandleForReadingAtPath:entry.sourcePath];
        if (!input) {
            if (error) {
                *error = [NSError errorWithDomain:@"SCInstaSettingsTransfer"
                                             code:2006
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not read %@.", entry.relativePath]}];
            }
            [zip closeFile];
            return NO;
        }
        uint32_t crc = 0;
        @autoreleasepool {
            while (true) {
                NSData *chunk = [input readDataOfLength:1024 * 1024];
                if (chunk.length == 0) break;
                crc = SCIZipCRC32ForBytes(crc, chunk.bytes, chunk.length);
                [zip writeData:chunk];
            }
        }
        [input closeFile];
        entry.crc32 = crc;

        unsigned long long returnOffset = [zip offsetInFile];
        [zip seekToFileOffset:entry.localHeaderOffset + 14];
        NSMutableData *sizes = [NSMutableData data];
        SCIAppendUInt32LE(sizes, entry.crc32);
        SCIAppendUInt32LE(sizes, entry.size);
        SCIAppendUInt32LE(sizes, entry.size);
        [zip writeData:sizes];
        [zip seekToFileOffset:returnOffset];
    }

    if ([zip offsetInFile] > UINT32_MAX) {
        if (error) {
            *error = [NSError errorWithDomain:@"SCInstaSettingsTransfer"
                                         code:2005
                                     userInfo:@{NSLocalizedDescriptionKey: @"Export is too large for this zip writer."}];
        }
        [zip closeFile];
        return NO;
    }
    uint32_t centralOffset = (uint32_t)[zip offsetInFile];
    NSMutableData *central = [NSMutableData data];
    for (SCIZipEntry *entry in entries) {
        NSData *nameData = [entry.relativePath dataUsingEncoding:NSUTF8StringEncoding];
        SCIAppendUInt32LE(central, 0x02014b50);
        SCIAppendUInt16LE(central, 20);
        SCIAppendUInt16LE(central, 20);
        SCIAppendUInt16LE(central, 0);
        SCIAppendUInt16LE(central, 0);
        SCIAppendUInt16LE(central, entry.dosTime);
        SCIAppendUInt16LE(central, entry.dosDate);
        SCIAppendUInt32LE(central, entry.crc32);
        SCIAppendUInt32LE(central, entry.size);
        SCIAppendUInt32LE(central, entry.size);
        SCIAppendUInt16LE(central, (uint16_t)nameData.length);
        SCIAppendUInt16LE(central, 0);
        SCIAppendUInt16LE(central, 0);
        SCIAppendUInt16LE(central, 0);
        SCIAppendUInt16LE(central, 0);
        SCIAppendUInt32LE(central, 0);
        SCIAppendUInt32LE(central, entry.localHeaderOffset);
        [central appendData:nameData];
    }
    [zip writeData:central];

    uint32_t centralSize = (uint32_t)central.length;
    NSMutableData *eocd = [NSMutableData data];
    SCIAppendUInt32LE(eocd, 0x06054b50);
    SCIAppendUInt16LE(eocd, 0);
    SCIAppendUInt16LE(eocd, 0);
    SCIAppendUInt16LE(eocd, (uint16_t)entries.count);
    SCIAppendUInt16LE(eocd, (uint16_t)entries.count);
    SCIAppendUInt32LE(eocd, centralSize);
    SCIAppendUInt32LE(eocd, centralOffset);
    SCIAppendUInt16LE(eocd, 0);
    [zip writeData:eocd];
    [zip closeFile];
    return YES;
}

static BOOL SCIIsSafeZipEntryName(NSString *name) {
    if (name.length == 0 || [name hasPrefix:@"/"] || [name containsString:@"\\"]) return NO;
    for (NSString *part in [name componentsSeparatedByString:@"/"]) {
        if ([part isEqualToString:@".."]) return NO;
    }
    return YES;
}

// Inflates a raw DEFLATE blob (`src`, srcLen bytes) into `outputPath`, expecting
// `expectedOut` bytes. Uses libcompression's zlib (raw) decoder. Returns NO on
// failure or a length mismatch.
static BOOL SCIInflateRawDeflateToFile(const uint8_t *src, size_t srcLen, size_t expectedOut, NSString *outputPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createFileAtPath:outputPath contents:nil attributes:nil];
    NSFileHandle *out = [NSFileHandle fileHandleForWritingAtPath:outputPath];
    if (!out) return NO;

    compression_stream stream;
    if (compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_OK) {
        [out closeFile];
        return NO;
    }
    stream.src_ptr = src;
    stream.src_size = srcLen;

    const size_t dstCap = 256 * 1024;
    uint8_t *dst = malloc(dstCap);
    if (!dst) {
        compression_stream_destroy(&stream);
        [out closeFile];
        return NO;
    }

    BOOL ok = YES;
    size_t totalOut = 0;
    while (YES) {
        stream.dst_ptr = dst;
        stream.dst_size = dstCap;
        compression_status status = compression_stream_process(&stream, COMPRESSION_STREAM_FINALIZE);
        size_t produced = dstCap - stream.dst_size;
        if (produced > 0) {
            @autoreleasepool {
                [out writeData:[NSData dataWithBytesNoCopy:dst length:produced freeWhenDone:NO]];
            }
            totalOut += produced;
        }
        if (status == COMPRESSION_STATUS_END) break;
        if (status != COMPRESSION_STATUS_OK) { ok = NO; break; }
    }

    free(dst);
    compression_stream_destroy(&stream);
    [out closeFile];
    if (ok && expectedOut > 0 && totalOut != expectedOut) ok = NO;
    return ok;
}

// Expands a zip created by our own exporter (stored, method 0) as well as zips
// re-compressed by Files / iCloud / desktop tools (DEFLATE, method 8).
static NSString *SCIExpandStoredZipSettingsTransferArchive(NSURL *archiveURL, NSError **error) {
    NSData *zipData = [NSData dataWithContentsOfURL:archiveURL options:NSDataReadingMappedIfSafe error:error];
    if (zipData.length < 22) return nil;

    const uint8_t *bytes = zipData.bytes;
    NSInteger eocdOffset = -1;
    for (NSInteger i = (NSInteger)zipData.length - 22; i >= 0 && i >= (NSInteger)zipData.length - 65557; i--) {
        if (SCIReadUInt32LE(bytes, (NSUInteger)i) == 0x06054b50) {
            eocdOffset = i;
            break;
        }
    }
    if (eocdOffset < 0) return nil;

    uint16_t entryCount = SCIReadUInt16LE(bytes, (NSUInteger)eocdOffset + 10);
    uint32_t centralSize = SCIReadUInt32LE(bytes, (NSUInteger)eocdOffset + 12);
    uint32_t centralOffset = SCIReadUInt32LE(bytes, (NSUInteger)eocdOffset + 16);
    if ((NSUInteger)centralOffset + centralSize > zipData.length) return nil;

    NSString *tempRoot = SCITemporaryTransferRoot(@"import");
    NSString *expandedRoot = [tempRoot stringByAppendingPathComponent:@"Expanded"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:expandedRoot withIntermediateDirectories:YES attributes:nil error:nil];

    NSFileHandle *archiveHandle = [NSFileHandle fileHandleForReadingFromURL:archiveURL error:error];
    if (!archiveHandle) return nil;

    NSUInteger cursor = centralOffset;
    for (uint16_t i = 0; i < entryCount; i++) {
        if (cursor + 46 > zipData.length || SCIReadUInt32LE(bytes, cursor) != 0x02014b50) {
            [archiveHandle closeFile];
            return nil;
        }

        uint16_t method = SCIReadUInt16LE(bytes, cursor + 10);
        uint32_t compressedSize = SCIReadUInt32LE(bytes, cursor + 20);
        uint32_t uncompressedSize = SCIReadUInt32LE(bytes, cursor + 24);
        uint16_t nameLen = SCIReadUInt16LE(bytes, cursor + 28);
        uint16_t extraLen = SCIReadUInt16LE(bytes, cursor + 30);
        uint16_t commentLen = SCIReadUInt16LE(bytes, cursor + 32);
        uint32_t localOffset = SCIReadUInt32LE(bytes, cursor + 42);
        if (cursor + 46 + nameLen + extraLen + commentLen > zipData.length) {
            [archiveHandle closeFile];
            return nil;
        }

        NSData *nameData = [zipData subdataWithRange:NSMakeRange(cursor + 46, nameLen)];
        NSString *entryName = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
        cursor += 46 + nameLen + extraLen + commentLen;
        if (!SCIIsSafeZipEntryName(entryName)) {
            [archiveHandle closeFile];
            return nil;
        }
        if ([entryName hasSuffix:@"/"]) {
            [fm createDirectoryAtPath:[expandedRoot stringByAppendingPathComponent:entryName] withIntermediateDirectories:YES attributes:nil error:nil];
            continue;
        }
        if (method != 0 && method != 8) {
            if (error) {
                *error = [NSError errorWithDomain:@"SCInstaSettingsTransfer"
                                             code:2002
                                         userInfo:@{NSLocalizedDescriptionKey: @"This zip uses an unsupported compression method."}];
            }
            [archiveHandle closeFile];
            return nil;
        }
        if ((NSUInteger)localOffset + 30 > zipData.length || SCIReadUInt32LE(bytes, localOffset) != 0x04034b50) {
            [archiveHandle closeFile];
            return nil;
        }
        uint16_t localNameLen = SCIReadUInt16LE(bytes, localOffset + 26);
        uint16_t localExtraLen = SCIReadUInt16LE(bytes, localOffset + 28);
        unsigned long long dataOffset = (unsigned long long)localOffset + 30ULL + localNameLen + localExtraLen;
        if (dataOffset + compressedSize > zipData.length) {
            [archiveHandle closeFile];
            return nil;
        }

        NSString *destPath = [expandedRoot stringByAppendingPathComponent:entryName];
        [fm createDirectoryAtPath:[destPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];

        if (method == 8) {
            // DEFLATE — inflate the compressed payload (mapped, no extra copy).
            if (!SCIInflateRawDeflateToFile(bytes + dataOffset, compressedSize, uncompressedSize, destPath)) {
                if (error) {
                    *error = [NSError errorWithDomain:@"SCInstaSettingsTransfer"
                                                 code:2007
                                             userInfo:@{NSLocalizedDescriptionKey: @"Could not decompress the backup archive."}];
                }
                [archiveHandle closeFile];
                return nil;
            }
            continue;
        }

        // Stored (method 0) — copy the raw bytes straight through.
        [fm createFileAtPath:destPath contents:nil attributes:nil];
        NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:destPath];
        [archiveHandle seekToFileOffset:dataOffset];
        uint32_t remaining = compressedSize;
        while (remaining > 0) {
            NSUInteger chunkSize = MIN((NSUInteger)remaining, (NSUInteger)(1024 * 1024));
            NSData *chunk = [archiveHandle readDataOfLength:chunkSize];
            if (chunk.length == 0) break;
            [output writeData:chunk];
            remaining -= (uint32_t)chunk.length;
        }
        [output closeFile];
        if (remaining > 0) {
            [archiveHandle closeFile];
            return nil;
        }
    }

    [archiveHandle closeFile];
    return SCIIsValidSettingsTransferBundleRoot(expandedRoot) ? expandedRoot : SCIResolvedSettingsTransferBundleRoot([NSURL fileURLWithPath:expandedRoot isDirectory:YES]);
}

static BOOL SCIIsValidSettingsTransferBundleRoot(NSString *bundleRoot) {
    if (bundleRoot.length == 0) return NO;
    NSString *prefsPath = [bundleRoot stringByAppendingPathComponent:@"Preferences/settings.plist"];
    NSString *galleryPath = [bundleRoot stringByAppendingPathComponent:@"Gallery"];
    NSString *deletedMessagesPath = [bundleRoot stringByAppendingPathComponent:@"DeletedMessages"];
    NSString *profileAnalyzerPath = [bundleRoot stringByAppendingPathComponent:@"ProfileAnalyzer"];
    return [[NSFileManager defaultManager] fileExistsAtPath:prefsPath] ||
           [[NSFileManager defaultManager] fileExistsAtPath:galleryPath] ||
           [[NSFileManager defaultManager] fileExistsAtPath:deletedMessagesPath] ||
           [[NSFileManager defaultManager] fileExistsAtPath:profileAnalyzerPath];
}

static NSString *SCIResolvedSettingsTransferBundleRoot(NSURL *pickedURL) {
    if (!pickedURL.path.length) return nil;

    NSString *candidate = pickedURL.path;
    for (NSInteger i = 0; i < 5 && candidate.length > 1; i++) {
        if (SCIIsValidSettingsTransferBundleRoot(candidate)) {
            return candidate;
        }
        candidate = [candidate stringByDeletingLastPathComponent];
    }
    return nil;
}

static NSString *SCIExpandSerializedSettingsTransferArchive(NSURL *archiveURL, NSError **error) {
    NSData *archiveData = [NSData dataWithContentsOfURL:archiveURL options:NSDataReadingMappedIfSafe error:error];
    if (archiveData.length == 0) return nil;

    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithSerializedRepresentation:archiveData];
    if (!wrapper.isDirectory) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"SCInstaSettingsTransfer"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Archive contents were invalid."}];
        }
        return nil;
    }

    NSString *tempRoot = SCITemporaryTransferRoot(@"import");
    NSString *expandedRoot = [tempRoot stringByAppendingPathComponent:@"Expanded"];
    NSURL *expandedURL = [NSURL fileURLWithPath:expandedRoot isDirectory:YES];
    if (![wrapper writeToURL:expandedURL options:NSFileWrapperWritingAtomic originalContentsURL:nil error:error]) {
        return nil;
    }

    return SCIIsValidSettingsTransferBundleRoot(expandedRoot) ? expandedRoot : SCIResolvedSettingsTransferBundleRoot(expandedURL);
}

static NSString *SCIResolvedImportBundleRootForPickedURL(NSURL *pickedURL, NSError **error) {
    NSString *bundleRoot = SCIResolvedSettingsTransferBundleRoot(pickedURL);
    if (bundleRoot.length > 0) return bundleRoot;

    NSNumber *isDirectory = nil;
    [pickedURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    if (isDirectory.boolValue) return nil;

    NSString *zipBundleRoot = SCIExpandStoredZipSettingsTransferArchive(pickedURL, error);
    if (zipBundleRoot.length > 0) return zipBundleRoot;

    return SCIExpandSerializedSettingsTransferArchive(pickedURL, error);
}

static NSString *SCITransferScopeString(SCITransferAccountScope scope) {
    return scope == SCITransferAccountScopeCurrentAccount ? @"current" : @"all";
}

static NSDictionary *SCITransferManifest(BOOL includeSettings, BOOL includeGallery, BOOL includeDeletedMessages, BOOL includeProfileAnalyzer, SCITransferAccountScope scope, NSString *sourcePK, NSArray<NSString *> *includedKeys) {
    NSMutableDictionary *manifest = [@{
        @"format_version": @4,
        @"created_at": [NSDate date],
        @"includes_settings": @(includeSettings),
        @"includes_gallery": @(includeGallery),
        @"includes_deleted_messages": @(includeDeletedMessages),
        @"includes_profile_analyzer": @(includeProfileAnalyzer),
        // The account scope of the whole export (settings + gallery). "current" exports
        // are re-homed onto the importing device's active account. `account_scope`
        // replaces the legacy `settings_scope` (still read on import for old archives).
        @"account_scope": SCITransferScopeString(scope),
        @"source_account_pk": sourcePK ?: @"",
        @"included_keys": (includeSettings && includedKeys) ? [includedKeys sortedArrayUsingSelector:@selector(compare:)] : @[]
    } mutableCopy];
    return manifest;
}

// Sanitize a username/PK so it is safe inside a file name.
static NSString *SCISanitizeFilenameComponent(NSString *component) {
    if (component.length == 0) return @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < component.length; i++) {
        unichar c = [component characterAtIndex:i];
        [out appendString:[allowed characterIsMember:c] ? [NSString stringWithCharacters:&c length:1] : @"-"];
    }
    return out;
}

// Descriptive, sortable, collision-free export file name, e.g.
// "SCInsta-Settings-AllAccounts-2026-06-26.zip" or "SCInsta-Settings-jane.doe-2026-06-26.zip".
static NSString *SCITransferArchiveFilename(BOOL includeSettings, BOOL includeGallery, BOOL includeDeletedMessages, BOOL includeProfileAnalyzer, SCITransferAccountScope scope, NSString *currentUsername, NSString *currentPK) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (includeSettings) [parts addObject:@"Settings"];
    if (includeGallery) [parts addObject:@"Gallery"];
    if (includeDeletedMessages) [parts addObject:@"Messages"];
    if (includeProfileAnalyzer) [parts addObject:@"Analyzer"];
    NSString *content = parts.count == 0 ? @"Backup" : (parts.count > 2 ? @"Backup" : [parts componentsJoinedByString:@"+"]);

    NSMutableString *name = [NSMutableString stringWithFormat:@"SCInsta-%@", content];
    // Tag the filename by the scope that was chosen: a "this account" export always
    // carries the account's username; an all-accounts export is labelled only when it
    // actually included per-account-scopable content (settings or gallery).
    if (scope == SCITransferAccountScopeCurrentAccount) {
        NSString *who = currentUsername;
        if (who.length == 0) who = [SCIAccountManager usernameForPK:currentPK];
        if (who.length == 0) who = currentPK.length ? currentPK : @"account";
        [name appendFormat:@"-%@", SCISanitizeFilenameComponent(who)];
    } else if (includeSettings || includeGallery) {
        [name appendString:@"-AllAccounts"];
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    [name appendFormat:@"-%@.zip", [formatter stringFromDate:[NSDate date]]];
    return name;
}

@implementation SCISettingsTransferManager

+ (instancetype)sharedManager {
    static SCISettingsTransferManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[SCISettingsTransferManager alloc] init];
    });
    return manager;
}

- (void)exportSettingsAndGalleryFromController:(UIViewController *)controller {
    [self exportFromController:controller includeSettings:YES includeGallery:YES];
}

- (void)importSettingsAndGalleryFromController:(UIViewController *)controller {
    [self importFromController:controller includeSettings:YES includeGallery:YES];
}

- (void)presentExportOptionsFromController:(UIViewController *)controller {
    __weak typeof(self) weakSelf = self;
    [SCIIGAlertPresenter presentActionSheetFromViewController:controller
                                                        title:@"Export Backup"
                                                      message:@"Choose what to include in the export."
                                                      actions:@[
        [SCIIGAlertAction actionWithTitle:@"Export Settings Only" style:SCIIGAlertActionStyleDefault handler:^{
        [weakSelf exportFromController:controller includeSettings:YES includeGallery:NO];
    }],
        [SCIIGAlertAction actionWithTitle:@"Export Gallery Only" style:SCIIGAlertActionStyleDefault handler:^{
        [weakSelf exportFromController:controller includeSettings:NO includeGallery:YES];
    }],
        [SCIIGAlertAction actionWithTitle:@"Export Settings + Gallery" style:SCIIGAlertActionStyleDefault handler:^{
        [weakSelf exportFromController:controller includeSettings:YES includeGallery:YES];
    }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
    ]];
}

- (void)presentImportOptionsFromController:(UIViewController *)controller {
    __weak typeof(self) weakSelf = self;
    [SCIIGAlertPresenter presentActionSheetFromViewController:controller
                                                        title:@"Import Backup"
                                                      message:@"Choose what to restore from the backup."
                                                      actions:@[
        [SCIIGAlertAction actionWithTitle:@"Import Settings Only" style:SCIIGAlertActionStyleDefault handler:^{
        [weakSelf importFromController:controller includeSettings:YES includeGallery:NO];
    }],
        [SCIIGAlertAction actionWithTitle:@"Import Gallery Only" style:SCIIGAlertActionStyleDefault handler:^{
        [weakSelf importFromController:controller includeSettings:NO includeGallery:YES];
    }],
        [SCIIGAlertAction actionWithTitle:@"Import Settings + Gallery" style:SCIIGAlertActionStyleDefault handler:^{
        [weakSelf importFromController:controller includeSettings:YES includeGallery:YES];
    }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
    ]];
}

- (void)exportFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery {
    [self exportFromController:controller includeSettings:includeSettings includeGallery:includeGallery includeDeletedMessages:NO];
}

- (void)exportFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery includeDeletedMessages:(BOOL)includeDeletedMessages {
    [self exportFromController:controller includeSettings:includeSettings includeGallery:includeGallery includeDeletedMessages:includeDeletedMessages includeProfileAnalyzer:NO];
}

- (void)exportFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery includeDeletedMessages:(BOOL)includeDeletedMessages includeProfileAnalyzer:(BOOL)includeProfileAnalyzer {
    // When per-account settings is on, let the user choose whether to back up every
    // account or just the active one — this scopes both preferences and the Gallery.
    BOOL perAccountOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"general_per_account_settings"];
    NSString *currentPK = [SCIAccountManager currentAccountPK];
    BOOL settingsScopable = includeSettings && SCIPerAccountOverrideKeys(SCITransferAccountScopeAllAccounts, nil).count > 0;
    BOOL offerScope = perAccountOn && currentPK.length > 0 && (settingsScopable || includeGallery);

    if (!offerScope) {
        [self exportFromController:controller includeSettings:includeSettings includeGallery:includeGallery includeDeletedMessages:includeDeletedMessages includeProfileAnalyzer:includeProfileAnalyzer settingsScope:SCITransferAccountScopeAllAccounts];
        return;
    }

    NSString *username = [SCIAccountManager currentAccountUsername];
    NSString *thisTitle = username.length ? [NSString stringWithFormat:@"This Account Only (%@)", username] : @"This Account Only";
    NSString *scopeMessage = includeGallery
        ? @"Per-account settings are on. Back up every account's settings and Gallery, or only the active account's."
        : @"Per-account settings are on. Back up every account's settings, or only the active account's.";
    __weak typeof(self) weakSelf = self;
    [SCIIGAlertPresenter presentActionSheetFromViewController:controller
                                                        title:@"Which accounts?"
                                                      message:scopeMessage
                                                      actions:@[
        [SCIIGAlertAction actionWithTitle:@"All Accounts" style:SCIIGAlertActionStyleDefault handler:^{
            [weakSelf exportFromController:controller includeSettings:includeSettings includeGallery:includeGallery includeDeletedMessages:includeDeletedMessages includeProfileAnalyzer:includeProfileAnalyzer settingsScope:SCITransferAccountScopeAllAccounts];
        }],
        [SCIIGAlertAction actionWithTitle:thisTitle style:SCIIGAlertActionStyleDefault handler:^{
            [weakSelf exportFromController:controller includeSettings:includeSettings includeGallery:includeGallery includeDeletedMessages:includeDeletedMessages includeProfileAnalyzer:includeProfileAnalyzer settingsScope:SCITransferAccountScopeCurrentAccount];
        }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
    ]];
}

- (void)exportFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery includeDeletedMessages:(BOOL)includeDeletedMessages includeProfileAnalyzer:(BOOL)includeProfileAnalyzer settingsScope:(SCITransferAccountScope)settingsScope {
    if (!includeSettings && !includeGallery && !includeDeletedMessages && !includeProfileAnalyzer) return;
    self.presentingController = controller;
    self.isImportMode = NO;

    NSString *currentPK = [SCIAccountManager currentAccountPK];
    // Only current-account exports record a source PK (so import can re-map it).
    NSString *sourcePK = (settingsScope == SCITransferAccountScopeCurrentAccount) ? currentPK : nil;

    NSString *root = SCITemporaryTransferRoot(@"export");
    NSString *bundleRoot = [root stringByAppendingPathComponent:@"SCInstaExportBundle"];
    NSString *prefsPath = [bundleRoot stringByAppendingPathComponent:@"Preferences/settings.plist"];
    NSString *galleryDestination = [bundleRoot stringByAppendingPathComponent:@"Gallery"];
    NSString *deletedMessagesDestination = [bundleRoot stringByAppendingPathComponent:@"DeletedMessages"];
    NSString *profileAnalyzerDestination = [bundleRoot stringByAppendingPathComponent:@"ProfileAnalyzer"];
    NSString *manifestPath = [bundleRoot stringByAppendingPathComponent:@"manifest.plist"];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:bundleRoot withIntermediateDirectories:YES attributes:nil error:nil];

    NSArray<NSString *> *includedKeys = nil;
    if (includeSettings) {
        [fm createDirectoryAtPath:[prefsPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *prefs = SCIPreferencesSnapshotForScope(settingsScope, currentPK);
        includedKeys = prefs.allKeys;
        [prefs writeToFile:prefsPath atomically:YES];
    }

    if (includeGallery) {
        // One safe path for both scopes: a fresh store built via Core Data (current ⇒
        // only this account's files, all ⇒ every file). Avoids copying the live, possibly
        // WAL-dirty gallery.sqlite.
        NSString *ownerScope = (settingsScope == SCITransferAccountScopeCurrentAccount && currentPK.length > 0) ? currentPK : nil;
        NSError *galleryError = nil;
        if (![[SCIGalleryCoreDataStack shared] exportGalleryFilesToBundleDirectory:galleryDestination ownerAccountPK:ownerScope error:&galleryError]) {
            SCINotify(kSCINotificationSettingsExport, @"Export failed", galleryError.localizedDescription ?: @"Gallery export failed.", @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
            return;
        }
    }

    if (includeDeletedMessages) {
        NSError *copyError = nil;
        NSString *source = [SCIDeletedMessagesStorage storageRootPath];
        if ([fm fileExistsAtPath:source]) {
            if (![fm copyItemAtPath:source toPath:deletedMessagesDestination error:&copyError]) {
                SCINotify(kSCINotificationSettingsExport, @"Export failed", copyError.localizedDescription, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
                return;
            }
        } else if (![fm createDirectoryAtPath:deletedMessagesDestination withIntermediateDirectories:YES attributes:nil error:&copyError]) {
            SCINotify(kSCINotificationSettingsExport, @"Export failed", copyError.localizedDescription, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
            return;
        }
        NSString *keepalivePath = [deletedMessagesDestination stringByAppendingPathComponent:@".scinsta_keep"];
        if (![fm fileExistsAtPath:keepalivePath]) {
            [fm createFileAtPath:keepalivePath contents:[NSData data] attributes:nil];
        }
    }

    if (includeProfileAnalyzer) {
        NSError *copyError = nil;
        NSString *source = [SCIProfileAnalyzerStorage storageRootPath];
        if ([fm fileExistsAtPath:source]) {
            if (![fm copyItemAtPath:source toPath:profileAnalyzerDestination error:&copyError]) {
                SCINotify(kSCINotificationSettingsExport, @"Export failed", copyError.localizedDescription, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
                return;
            }
        } else if (![fm createDirectoryAtPath:profileAnalyzerDestination withIntermediateDirectories:YES attributes:nil error:&copyError]) {
            SCINotify(kSCINotificationSettingsExport, @"Export failed", copyError.localizedDescription, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
            return;
        }
        NSString *keepalivePath = [profileAnalyzerDestination stringByAppendingPathComponent:@".scinsta_keep"];
        if (![fm fileExistsAtPath:keepalivePath]) {
            [fm createFileAtPath:keepalivePath contents:[NSData data] attributes:nil];
        }
    }

    [SCITransferManifest(includeSettings, includeGallery, includeDeletedMessages, includeProfileAnalyzer, settingsScope, sourcePK, includedKeys) writeToFile:manifestPath atomically:YES];

    NSError *archiveError = nil;
    NSString *archiveName = SCITransferArchiveFilename(includeSettings, includeGallery, includeDeletedMessages, includeProfileAnalyzer, settingsScope, [SCIAccountManager currentAccountUsername], currentPK);
    NSString *archivePath = [root stringByAppendingPathComponent:archiveName];
    if (!SCIWriteStoredZipFromDirectory(bundleRoot, archivePath, &archiveError)) {
        NSString *message = archiveError.localizedDescription ?: @"The export zip could not be created.";
        SCINotify(kSCINotificationSettingsExport, @"Export failed", message, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
        return;
    }

    NSURL *archiveURL = [NSURL fileURLWithPath:archivePath isDirectory:NO];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[archiveURL] asCopy:YES];
    picker.delegate = self;
    self.activeDocumentPicker = picker;
    SCILog(@"Transfer", @"Presenting export document picker settings=%@ gallery=%@ deletedMessages=%@ profileAnalyzer=%@", includeSettings ? @"yes" : @"no", includeGallery ? @"yes" : @"no", includeDeletedMessages ? @"yes" : @"no", includeProfileAnalyzer ? @"yes" : @"no");
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = SCIDocumentPickerPresenter(controller);
        if (!presenter || !presenter.view.window) {
            SCINotify(kSCINotificationSettingsExport, @"Export ready", @"Unable to open Files; opening share sheet instead.", @"arrow_up", SCINotificationToneForIconResource(@"arrow_up"));
            [SCIUtils showShareVC:archiveURL];
            return;
        }
        [presenter presentViewController:picker animated:YES completion:^{
            SCINotify(kSCINotificationSettingsExport, @"Opened export sheet", nil, @"arrow_up", SCINotificationToneForIconResource(@"arrow_up"));
        }];
    });
}

- (void)importFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery {
    [self importFromController:controller includeSettings:includeSettings includeGallery:includeGallery includeDeletedMessages:NO];
}

- (void)importFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery includeDeletedMessages:(BOOL)includeDeletedMessages {
    [self importFromController:controller includeSettings:includeSettings includeGallery:includeGallery includeDeletedMessages:includeDeletedMessages includeProfileAnalyzer:NO];
}

- (void)importFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery includeDeletedMessages:(BOOL)includeDeletedMessages includeProfileAnalyzer:(BOOL)includeProfileAnalyzer {
    if (!includeSettings && !includeGallery && !includeDeletedMessages && !includeProfileAnalyzer) return;
    self.presentingController = controller;
    self.pendingImportSettings = includeSettings;
    self.pendingImportGallery = includeGallery;
    self.pendingImportDeletedMessages = includeDeletedMessages;
    self.pendingImportProfileAnalyzer = includeProfileAnalyzer;
    self.isImportMode = YES;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];
    picker.delegate = self;
    self.activeDocumentPicker = picker;
    SCILog(@"Transfer", @"Presenting import document picker settings=%@ gallery=%@ deletedMessages=%@ profileAnalyzer=%@", includeSettings ? @"yes" : @"no", includeGallery ? @"yes" : @"no", includeDeletedMessages ? @"yes" : @"no", includeProfileAnalyzer ? @"yes" : @"no");
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = SCIDocumentPickerPresenter(controller);
        if (!presenter || !presenter.view.window) {
            SCINotify(kSCINotificationSettingsImport, @"Import failed", @"Unable to open Files picker.", @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
            self.activeDocumentPicker = nil;
            return;
        }
        [presenter presentViewController:picker animated:YES completion:^{
            SCINotify(kSCINotificationSettingsImport, @"Choose an export bundle", nil, @"arrow_down", SCINotificationToneForIconResource(@"arrow_down"));
        }];
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.pendingImportSettings = NO;
    self.pendingImportGallery = NO;
    self.pendingImportDeletedMessages = NO;
    self.pendingImportProfileAnalyzer = NO;
    self.presentingController = nil;
    self.activeDocumentPicker = nil;
    self.isImportMode = NO;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    self.presentingController = nil;
    self.activeDocumentPicker = nil;
    if (!url) return;
    
    if (!self.isImportMode) {
        SCINotify(kSCINotificationSettingsExport, @"Export complete", @"SCInsta backup saved successfully.", @"circle_check_filled", SCINotificationToneForIconResource(@"circle_check_filled"));
        return;
    }

    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSError *archiveError = nil;
    NSString *bundleRoot = SCIResolvedImportBundleRootForPickedURL(url, &archiveError);
    NSString *prefsPath = [bundleRoot stringByAppendingPathComponent:@"Preferences/settings.plist"];
    NSString *galleryPath = [bundleRoot stringByAppendingPathComponent:@"Gallery"];
    NSString *deletedMessagesPath = [bundleRoot stringByAppendingPathComponent:@"DeletedMessages"];
    NSString *profileAnalyzerPath = [bundleRoot stringByAppendingPathComponent:@"ProfileAnalyzer"];
    NSString *manifestPath = [bundleRoot stringByAppendingPathComponent:@"manifest.plist"];
    NSDictionary *manifest = bundleRoot.length > 0 ? [NSDictionary dictionaryWithContentsOfFile:manifestPath] : nil;
    NSDictionary *prefs = [[NSFileManager defaultManager] fileExistsAtPath:prefsPath] ? [NSDictionary dictionaryWithContentsOfFile:prefsPath] : nil;
    BOOL archiveHasSettings = [prefs isKindOfClass:[NSDictionary class]];
    BOOL archiveHasGallery = [[NSFileManager defaultManager] fileExistsAtPath:galleryPath];
    BOOL archiveHasDeletedMessages = [[NSFileManager defaultManager] fileExistsAtPath:deletedMessagesPath];
    BOOL archiveHasProfileAnalyzer = [[NSFileManager defaultManager] fileExistsAtPath:profileAnalyzerPath];
    BOOL importSettings = self.pendingImportSettings;
    BOOL importGallery = self.pendingImportGallery;
    BOOL importDeletedMessages = self.pendingImportDeletedMessages;
    BOOL importProfileAnalyzer = self.pendingImportProfileAnalyzer;
    self.pendingImportSettings = NO;
    self.pendingImportGallery = NO;
    self.pendingImportDeletedMessages = NO;
    self.pendingImportProfileAnalyzer = NO;

    if (manifest && [manifest isKindOfClass:[NSDictionary class]]) {
        NSNumber *manifestSettings = manifest[@"includes_settings"];
        NSNumber *manifestGallery = manifest[@"includes_gallery"];
        NSNumber *manifestDeletedMessages = manifest[@"includes_deleted_messages"];
        NSNumber *manifestProfileAnalyzer = manifest[@"includes_profile_analyzer"];
        if ([manifestSettings respondsToSelector:@selector(boolValue)]) archiveHasSettings = manifestSettings.boolValue && archiveHasSettings;
        if ([manifestGallery respondsToSelector:@selector(boolValue)]) archiveHasGallery = manifestGallery.boolValue && archiveHasGallery;
        if ([manifestDeletedMessages respondsToSelector:@selector(boolValue)]) archiveHasDeletedMessages = manifestDeletedMessages.boolValue && archiveHasDeletedMessages;
        if ([manifestProfileAnalyzer respondsToSelector:@selector(boolValue)]) archiveHasProfileAnalyzer = manifestProfileAnalyzer.boolValue && archiveHasProfileAnalyzer;
    }

    if ((importSettings && !archiveHasSettings) || (importGallery && !archiveHasGallery) || (importDeletedMessages && !archiveHasDeletedMessages) || (importProfileAnalyzer && !archiveHasProfileAnalyzer) || (!archiveHasSettings && !archiveHasGallery && !archiveHasDeletedMessages && !archiveHasProfileAnalyzer)) {
        if (scoped) [url stopAccessingSecurityScopedResource];
        NSString *message = archiveError.localizedDescription ?: @"Archive contents were invalid.";
        SCINotify(kSCINotificationSettingsImport, @"Import failed", message, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
        return;
    }

    // Backup scope (applies to both preferences and Gallery). A "current" backup is
    // flattened onto this device's active account on import. Read the new `account_scope`
    // field, falling back to the legacy `settings_scope` for older archives.
    NSDictionary *scopeManifest = [manifest isKindOfClass:[NSDictionary class]] ? manifest : nil;
    NSString *scopeString = scopeManifest[@"account_scope"] ?: scopeManifest[@"settings_scope"];
    BOOL currentScope = [scopeString isEqualToString:@"current"];
    NSString *currentPK = [SCIAccountManager currentAccountPK];
    NSString *currentUsername = [SCIAccountManager currentAccountUsername];

    if (importSettings) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        if (currentScope) {
            // FLATTEN: re-home the backup's (base-key, effective-value) settings into the
            // importing account's namespace — or global if per-account mode is off — and
            // touch nothing else, so other accounts are unaffected.
            NSString *targetPK = SCIPerAccountModeActive() ? currentPK : nil;
            if (targetPK.length > 0) {
                for (NSString *key in SCIPerAccountOverrideKeys(SCITransferAccountScopeCurrentAccount, targetPK)) {
                    [defaults removeObjectForKey:key];
                }
            } else {
                for (NSString *key in SCIExportedPreferenceKeys()) {
                    [defaults removeObjectForKey:key];
                }
            }
            [prefs enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
                if (SCIPreferenceKeyIsGlobal(key) || !SCIPrefIsAvailable(key)) return;  // flatten archives carry only per-account-capable base keys
                NSString *applyKey = targetPK.length > 0 ? [NSString stringWithFormat:@"u_%@_%@", targetPK, key] : key;
                [defaults setObject:value forKey:applyKey];
            }];
        } else {
            // ALL ACCOUNTS: verbatim restore — clear every scope key, apply as stored.
            for (NSString *key in SCIExportedPreferenceKeysForScope(SCITransferAccountScopeAllAccounts, nil)) {
                [defaults removeObjectForKey:key];
            }
            [prefs enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
                NSString *pk = nil, *baseKey = nil;
                BOOL isPerAccount = SCIParsePerAccountKey(key, &pk, &baseKey);
                NSString *availabilityKey = isPerAccount ? baseKey : key;  // availability keyed by base pref
                if (!SCIPrefIsAvailable(availabilityKey)) return;
                [defaults setObject:value forKey:key];
            }];
        }
        // The app icon is a pref but also live UIApplication state — apply the
        // imported selection so it changes immediately instead of requiring the
        // user to re-pick it.
        [SCIAppIconCatalog applyStoredIconIfNeeded];
    }

    // The non-gallery remainder (messages, profile analyzer, finalize) runs after the
    // gallery merge — which may be deferred behind a conflict prompt — so it lives in a
    // block invoked from every path.
    void (^finishImport)(NSInteger) = ^(NSInteger galleryAddedCount) {
        if (importDeletedMessages) {
            NSError *deletedMessagesError = nil;
            if (![SCIDeletedMessagesStorage replaceStorageWithDirectoryAtPath:deletedMessagesPath error:&deletedMessagesError]) {
                if (scoped) [url stopAccessingSecurityScopedResource];
                SCINotify(kSCINotificationSettingsImport, @"Import failed", deletedMessagesError.localizedDescription, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
                return;
            }
        }

        if (importProfileAnalyzer) {
            NSError *profileAnalyzerError = nil;
            if (![SCIProfileAnalyzerStorage replaceStorageWithDirectoryAtPath:profileAnalyzerPath error:&profileAnalyzerError]) {
                if (scoped) [url stopAccessingSecurityScopedResource];
                SCINotify(kSCINotificationSettingsImport, @"Import failed", profileAnalyzerError.localizedDescription, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
                return;
            }
        }

        if (scoped) [url stopAccessingSecurityScopedResource];

        NSMutableArray<NSString *> *restored = [NSMutableArray array];
        if (importSettings) [restored addObject:@"preferences"];
        if (importGallery) [restored addObject:[NSString stringWithFormat:@"Gallery (%ld added)", (long)galleryAddedCount]];
        if (importDeletedMessages) [restored addObject:@"unsent messages"];
        if (importProfileAnalyzer) [restored addObject:@"Profile Analyzer"];
        NSString *subtitle = [NSString stringWithFormat:@"Restored: %@.", [restored componentsJoinedByString:@", "]];
        SCINotify(kSCINotificationSettingsImport, @"Import complete", subtitle, @"circle_check_filled", SCINotificationToneForIconResource(@"circle_check_filled"));

        // Only prompt to restart when something needs a relaunch to take effect.
        // Preferences are read at launch / hook-install time; the deleted-messages and
        // profile-analyzer stores are swapped on disk under live references. The Gallery
        // merge writes to the live context, so a gallery-only import needs no restart.
        if (importSettings || importDeletedMessages || importProfileAnalyzer) {
            [SCIUtils showRestartConfirmation];
        }
    };

    // A "this account" import re-assigns gallery files to the active account.
    NSString *remapPK = currentScope ? currentPK : nil;
    NSString *remapUsername = currentScope ? currentUsername : nil;

    void (^mergeGalleryThenFinish)(SCIGalleryImportConflictStrategy) = ^(SCIGalleryImportConflictStrategy strategy) {
        NSInteger galleryAddedCount = 0;
        if (importGallery) {
            NSError *galleryMergeError = nil;
            galleryAddedCount = [[SCIGalleryCoreDataStack shared] mergeGalleryFilesFromBundleDirectory:galleryPath
                                                                                  remapOwnerAccountPK:remapPK
                                                                                        ownerUsername:remapUsername
                                                                                     conflictStrategy:strategy
                                                                                                error:&galleryMergeError];
            if (galleryAddedCount < 0) {
                if (scoped) [url stopAccessingSecurityScopedResource];
                SCINotify(kSCINotificationSettingsImport, @"Import failed", galleryMergeError.localizedDescription ?: @"Gallery import failed.", @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
                return;
            }
        }
        finishImport(galleryAddedCount);
    };

    // If a "this account" gallery import collides with items already owned by another
    // account on this device, ask once how to resolve them all, then proceed.
    NSInteger conflicts = (importGallery && remapPK.length > 0)
        ? [[SCIGalleryCoreDataStack shared] galleryImportConflictCountForBundleDirectory:galleryPath ownerAccountPK:remapPK]
        : 0;
    if (conflicts > 0) {
        NSString *message = [NSString stringWithFormat:@"%ld imported file%@ already exist%@ on this device under a different account. What should happen to %@?",
                             (long)conflicts, conflicts == 1 ? @"" : @"s", conflicts == 1 ? @"s" : @"", conflicts == 1 ? @"it" : @"them"];
        [SCIIGAlertPresenter presentAlertFromViewController:topMostController()
                                                      title:@"Files from Another Account"
                                                    message:message
                                                    actions:@[
            [SCIIGAlertAction actionWithTitle:@"Claim for This Account" style:SCIIGAlertActionStyleDefault handler:^{
                mergeGalleryThenFinish(SCIGalleryImportConflictStrategyClaim);
            }],
            [SCIIGAlertAction actionWithTitle:@"Keep a Separate Copy" style:SCIIGAlertActionStyleDefault handler:^{
                mergeGalleryThenFinish(SCIGalleryImportConflictStrategyDuplicate);
            }],
            [SCIIGAlertAction actionWithTitle:[NSString stringWithFormat:@"Skip %@", conflicts == 1 ? @"It" : @"Them"]
                                        style:SCIIGAlertActionStyleCancel
                                      handler:^{
                mergeGalleryThenFinish(SCIGalleryImportConflictStrategySkip);
            }],
        ]];
        return;  // resolution continues in the chosen handler
    }

    mergeGalleryThenFinish(SCIGalleryImportConflictStrategySkip);
}

- (void)resetAllSettingsFromController:(UIViewController *)controller {
    [SCIIGAlertPresenter presentAlertFromViewController:controller
                                                  title:@"Reset all settings?"
                                                message:@"This restores every SCInsta preference to its default value. Gallery media is left untouched. This cannot be undone."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Reset" style:SCIIGAlertActionStyleDestructive handler:^{
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            // Clear global keys AND every account's per-account overrides.
            for (NSString *key in SCIExportedPreferenceKeysForScope(SCITransferAccountScopeAllAccounts, nil)) {
                [defaults removeObjectForKey:key];
            }
            [[SCISettingsLockManager sharedManager] removePasscode];
            SCINotify(kSCINotificationSettingsImport,
                      @"Settings reset",
                      @"All SCInsta preferences were restored to defaults.",
                      @"circle_check_filled",
                      SCINotificationToneForIconResource(@"circle_check_filled"));
            [SCIUtils showRestartConfirmation];
        }],
    ]];
}

@end

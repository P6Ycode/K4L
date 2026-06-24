#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <ctype.h>
#import <math.h>

#import "SCIGalleryFile.h"
#import "SCIGalleryPaths.h"
#import "SCIGalleryCoreDataStack.h"
#import "SCIGalleryOriginController.h"
#import "../Account/SCIAccountManager.h"
#import "../../Utils.h"
#import "../../AssetUtils.h"

static CGFloat const kThumbnailSize = 300.0;

static NSCache<NSString *, UIImage *> *SCIGalleryThumbnailCache(void) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 200;
    });
    return cache;
}

static dispatch_queue_t SCIGalleryThumbnailStateQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.scinsta.gallery.thumbnail-state", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSMutableDictionary<NSString *, NSMutableArray<void(^)(BOOL success)> *> *SCIGalleryThumbnailCompletions(void) {
    static NSMutableDictionary<NSString *, NSMutableArray<void(^)(BOOL success)> *> *completions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        completions = [NSMutableDictionary dictionary];
    });
    return completions;
}

static NSString *SCIGalleryNormalizedExtension(NSString * _Nullable origExt, SCIGalleryMediaType mediaType) {
    NSString *e = origExt.length ? origExt.lowercaseString : @"";
    static NSSet<NSString *> *imageExts;
    static NSSet<NSString *> *videoExts;
    static NSSet<NSString *> *audioExts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageExts = [NSSet setWithArray:@[ @"jpg", @"jpeg", @"png", @"heic", @"webp", @"gif" ]];
        videoExts = [NSSet setWithArray:@[ @"mp4", @"mov", @"m4v", @"webm" ]];
        audioExts = [NSSet setWithArray:@[ @"m4a", @"aac", @"mp3", @"wav", @"caf", @"aiff", @"flac", @"opus", @"ogg" ]];
    });
    // Only keep the original extension when it belongs to the SAME category as the
    // requested media type. Otherwise we'd e.g. keep a ".mp4" extension for audio
    // (audio extracted from a video container), which makes the file look like a
    // video to every downstream extension-based check and breaks duplicate detection.
    if (e.length > 0 && e.length <= 5) {
        if (mediaType == SCIGalleryMediaTypeAudio && [audioExts containsObject:e]) return e;
        if (mediaType == SCIGalleryMediaTypeVideo && [videoExts containsObject:e]) return e;
        if (mediaType == SCIGalleryMediaTypeImage && [imageExts containsObject:e]) {
            return [e isEqualToString:@"jpeg"] ? @"jpg" : e;
        }
    }
    if (mediaType == SCIGalleryMediaTypeAudio) return @"m4a";
    return (mediaType == SCIGalleryMediaTypeVideo) ? @"mp4" : @"jpg";
}

static NSString *SCIGallerySourceSlug(SCIGallerySource source) {
    switch (source) {
        case SCIGallerySourceFeed:    return @"feed";
        case SCIGallerySourceStories: return @"story";
        case SCIGallerySourceReels:   return @"reel";
        case SCIGallerySourceProfile: return @"profile-photo";
        case SCIGallerySourceDMs:     return @"dms";
        case SCIGallerySourceThumbnail: return @"thumbnail";
        case SCIGallerySourceInstants: return @"instants";
        case SCIGallerySourceAudioPage: return @"audio-page";
        case SCIGallerySourceComments: return @"comments";
        case SCIGallerySourceOther:
        default:                    return @"other";
    }
}

/// Path component for a canonical web post/reel link (`/p/` or `/reel/`). Stories are intentionally excluded — they use `/stories/<user>/<pk>/` instead, built separately. Returns nil for sources that have no shareable post link.
static NSString *SCIGalleryPostPathComponentForSource(SCIGallerySource source) {
    switch (source) {
        case SCIGallerySourceReels:
            return @"reel";
        case SCIGallerySourceFeed:
        case SCIGallerySourceProfile:
        case SCIGallerySourceOther:
            return @"p";
        default:
            return nil;
    }
}

static long long SCIEpochMillisecondsForDate(NSDate *date) {
    NSTimeInterval interval = [date timeIntervalSince1970];
    if (interval <= 0.0) {
        interval = [[NSDate date] timeIntervalSince1970];
    }
    return (long long)llround(interval * 1000.0);
}

/// Safe single path segment: ASCII-ish, no path separators.
static NSString *SCISanitizedGalleryUsername(NSString *raw) {
    if (!raw.length) {
        return @"";
    }
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN((NSUInteger)48, raw.length)];
    NSUInteger maxLen = 48;
    [raw enumerateSubstringsInRange:NSMakeRange(0, raw.length)
                            options:NSStringEnumerationByComposedCharacterSequences
                         usingBlock:^(NSString * _Nullable substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if (out.length >= maxLen) {
            *stop = YES;
            return;
        }
        if (substring.length != 1) {
            [out appendString:@"_"];
            return;
        }
        unichar c = [substring characterAtIndex:0];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.') {
            [out appendString:substring];
        } else if (c == ' ') {
            [out appendString:@"_"];
        } else {
            [out appendString:@"_"];
        }
    }];
    NSString *collapsed = [out stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
    while ([collapsed containsString:@"__"]) {
        collapsed = [collapsed stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
    }
    collapsed = [collapsed stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"._-"]];
    return collapsed.length ? collapsed : @"user";
}

static BOOL SCIDigitsOnlyString(NSString *s) {
    if (s.length == 0) {
        return NO;
    }
    for (NSUInteger i = 0; i < s.length; i++) {
        if (!isdigit((unsigned char)[s characterAtIndex:i])) {
            return NO;
        }
    }
    return YES;
}

static NSDate * _Nullable SCIParseCompactDigitDateFromString(NSString *s) {
    if (!SCIDigitsOnlyString(s)) {
        return nil;
    }
    NSUInteger n = s.length;
    if (n != 8 && n != 12 && n != 14) {
        return nil;
    }
    static NSDateFormatter *fmt8;
    static NSDateFormatter *fmt12;
    static NSDateFormatter *fmt14;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt8 = [[NSDateFormatter alloc] init];
        fmt8.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt8.timeZone = [NSTimeZone localTimeZone];
        fmt8.dateFormat = @"yyyyMMdd";

        fmt12 = [[NSDateFormatter alloc] init];
        fmt12.locale = fmt8.locale;
        fmt12.timeZone = fmt8.timeZone;
        fmt12.dateFormat = @"yyyyMMddHHmm";

        fmt14 = [[NSDateFormatter alloc] init];
        fmt14.locale = fmt8.locale;
        fmt14.timeZone = fmt8.timeZone;
        fmt14.dateFormat = @"yyyyMMddHHmmss";
    });
    if (n == 14) {
        return [fmt14 dateFromString:s];
    }
    if (n == 12) {
        return [fmt12 dateFromString:s];
    }
    return [fmt8 dateFromString:s];
}

/// Parses unix epoch seconds/milliseconds, with sanity bounds to avoid confusing user ids for timestamps.
static NSDate * _Nullable SCIParseEpochDateFromString(NSString *s) {
    if (!SCIDigitsOnlyString(s)) {
        return nil;
    }
    if (s.length < 10 || s.length > 13) {
        return nil;
    }
    unsigned long long raw = strtoull(s.UTF8String, NULL, 10);
    if (raw == 0ULL) {
        return nil;
    }
    NSTimeInterval seconds = (s.length >= 13) ? ((NSTimeInterval)raw / 1000.0) : (NSTimeInterval)raw;
    // Keep plausible Instagram-era timestamps and avoid treating pk values as epochs.
    if (seconds < 946684800.0 || seconds > 4102444800.0) { // 2000-01-01 ... 2100-01-01
        return nil;
    }
    return [NSDate dateWithTimeIntervalSince1970:seconds];
}

/// Recognizes slug segments matching `SCIGallerySourceSlug` output (feed, story, reel, …).
static BOOL SCISourceFromBasenameSlug(NSString *low, SCIGallerySource *out) {
    if ([low isEqualToString:@"feed"]) {
        *out = SCIGallerySourceFeed;
        return YES;
    }
    if ([low isEqualToString:@"story"] || [low isEqualToString:@"stories"]) {
        *out = SCIGallerySourceStories;
        return YES;
    }
    if ([low isEqualToString:@"reel"] || [low isEqualToString:@"reels"]) {
        *out = SCIGallerySourceReels;
        return YES;
    }
    if ([low isEqualToString:@"profile"] || [low isEqualToString:@"profile-photo"] || [low isEqualToString:@"profilephoto"]) {
        *out = SCIGallerySourceProfile;
        return YES;
    }
    if ([low isEqualToString:@"dm"] || [low isEqualToString:@"dms"]) {
        *out = SCIGallerySourceDMs;
        return YES;
    }
    if ([low isEqualToString:@"thumbnail"] || [low isEqualToString:@"thumb"]) {
        *out = SCIGallerySourceThumbnail;
        return YES;
    }
    if ([low isEqualToString:@"instant"] || [low isEqualToString:@"instants"]) {
        *out = SCIGallerySourceInstants;
        return YES;
    }
    if ([low isEqualToString:@"audio"] || [low isEqualToString:@"audio-page"] || [low isEqualToString:@"audiopage"]) {
        *out = SCIGallerySourceAudioPage;
        return YES;
    }
    if ([low isEqualToString:@"comment"] || [low isEqualToString:@"comments"]) {
        *out = SCIGallerySourceComments;
        return YES;
    }
    if ([low isEqualToString:@"other"]) {
        *out = SCIGallerySourceOther;
        return YES;
    }
    return NO;
}

void SCIGalleryApplyImportHeuristicsFromFilename(NSString *fileName, SCIGallerySaveMetadata *m) {
    if (!fileName.length || !m) {
        return;
    }
    NSString *stem = [fileName lastPathComponent].stringByDeletingPathExtension;
    if (stem.length == 0) {
        return;
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *p in [stem componentsSeparatedByString:@"_"]) {
        NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length > 0) {
            [parts addObject:t];
        }
    }
    if (parts.count == 0) {
        return;
    }

    NSDate *leadEpochDate = SCIParseEpochDateFromString(parts.firstObject);
    if (leadEpochDate) {
        if (!m.importCapturedDate) {
            m.importCapturedDate = leadEpochDate;
        }
        [parts removeObjectAtIndex:0];
    }
    if (parts.count == 0) {
        return;
    }

    NSDate *trailDate = SCIParseCompactDigitDateFromString(parts.lastObject);
    if (trailDate) {
        if (!m.importPostedDate) {
            m.importPostedDate = trailDate;
        }
        // Backward-compatible fallback: if no epoch/save-time token exists, use trailing date.
        if (!m.importCapturedDate) {
            m.importCapturedDate = trailDate;
        }
        [parts removeLastObject];
    }
    if (parts.count == 0) {
        return;
    }

    NSString *slugLow = parts.lastObject.lowercaseString;
    SCIGallerySource slugSource = SCIGallerySourceOther;
    if (SCISourceFromBasenameSlug(slugLow, &slugSource)) {
        if (m.source == (int16_t)SCIGallerySourceOther) {
            m.source = (int16_t)slugSource;
        }
        [parts removeLastObject];
    }
    if (parts.count == 0) {
        return;
    }

    if (parts.count >= 2) {
        NSString *a = parts[0];
        NSString *b = parts[1];
        if (SCIDigitsOnlyString(a) && !SCIDigitsOnlyString(b)) {
            if (!m.sourceUserPK.length) {
                m.sourceUserPK = a;
            }
            if (!m.sourceUsername.length) {
                m.sourceUsername = b;
                [SCIGalleryOriginController populateProfileMetadata:m username:b user:nil];
            }
        } else if (!SCIDigitsOnlyString(a) && SCIDigitsOnlyString(b)) {
            if (!m.sourceUsername.length) {
                m.sourceUsername = a;
                [SCIGalleryOriginController populateProfileMetadata:m username:a user:nil];
            }
            if (!m.sourceUserPK.length) {
                m.sourceUserPK = b;
            }
        } else if (!SCIDigitsOnlyString(a) && !SCIDigitsOnlyString(b)) {
            if (!m.sourceUsername.length) {
                m.sourceUsername = a;
                [SCIGalleryOriginController populateProfileMetadata:m username:a user:nil];
            }
        }
        return;
    }

    NSString *only = parts[0];
    if (SCIDigitsOnlyString(only)) {
        if (!m.sourceUserPK.length) {
            m.sourceUserPK = only;
        }
    } else {
        if (!m.sourceUsername.length) {
            m.sourceUsername = only;
            [SCIGalleryOriginController populateProfileMetadata:m username:only user:nil];
        }
    }
}

NSString *SCIFileNameForMedia(NSURL *fileURL,
                              SCIGalleryMediaType mediaType,
                              SCIGallerySaveMetadata * _Nullable metadata) {
    NSString *orig = fileURL.lastPathComponent ?: @"";
    NSString *origExt = orig.pathExtension;
    NSString *ext = SCIGalleryNormalizedExtension(origExt, mediaType);

    static NSDateFormatter *compactDateFmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        compactDateFmt = [[NSDateFormatter alloc] init];
        compactDateFmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        compactDateFmt.timeZone = [NSTimeZone localTimeZone];
        compactDateFmt.dateFormat = @"yyyyMMddHHmmss";
    });
    NSDate *saveDate = metadata.importCapturedDate ?: [NSDate date];
    if (metadata && !metadata.importCapturedDate) {
        metadata.importCapturedDate = saveDate;
    }
    NSDate *postedDate = metadata.importPostedDate ?: saveDate;
    if (metadata && !metadata.importPostedDate) {
        metadata.importPostedDate = postedDate;
    }
    NSString *dateCompact = [compactDateFmt stringFromDate:postedDate];
    NSString *epoch = [NSString stringWithFormat:@"%lld", SCIEpochMillisecondsForDate(saveDate)];

    SCIGallerySource src = metadata ? (SCIGallerySource)metadata.source : SCIGallerySourceOther;
    NSString *slug = SCIGallerySourceSlug(src);
    NSString *user = @"media";

    if (metadata.importFileNameStem.length > 0) {
        NSString *sanitizedStem = SCISanitizedGalleryUsername(metadata.importFileNameStem);
        if (sanitizedStem.length > 0) {
            user = sanitizedStem;
        }
    } else if (metadata.sourceUsername.length > 0) {
        NSString *sanitizedUser = SCISanitizedGalleryUsername(metadata.sourceUsername);
        if (sanitizedUser.length > 0) {
            user = sanitizedUser;
        }
    }

    return [NSString stringWithFormat:@"%@_%@_%@_%@.%@", epoch, user, slug, dateCompact, ext];
}

@implementation SCIGalleryFile

@dynamic identifier;
@dynamic relativePath;
@dynamic mediaType;
@dynamic source;
@dynamic dateAdded;
@dynamic fileSize;
@dynamic isFavorite;
@dynamic folderPath;
@dynamic customName;
@dynamic sourceUsername;
@dynamic sourceUserPK;
@dynamic sourceProfileURLString;
@dynamic sourceMediaPK;
@dynamic sourceMediaCode;
@dynamic sourceMediaURLString;
@dynamic pixelWidth;
@dynamic pixelHeight;
@dynamic durationSeconds;
@dynamic ownerAccountPK;
@dynamic ownerUsername;

#pragma mark - Save to Gallery

+ (SCIGalleryFile *)saveFileToGallery:(NSURL *)fileURL
                           source:(SCIGallerySource)source
                        mediaType:(SCIGalleryMediaType)mediaType
                            error:(NSError **)error {
    return [self saveFileToGallery:fileURL source:source mediaType:mediaType folderPath:nil metadata:nil error:error];
}

+ (SCIGalleryFile *)saveFileToGallery:(NSURL *)fileURL
                           source:(SCIGallerySource)source
                        mediaType:(SCIGalleryMediaType)mediaType
                       folderPath:(NSString *)folderPath
                            error:(NSError **)error {
    return [self saveFileToGallery:fileURL source:source mediaType:mediaType folderPath:folderPath metadata:nil error:error];
}

+ (void)applyMetadata:(nullable SCIGallerySaveMetadata *)metadata toFile:(SCIGalleryFile *)file fallbackSource:(SCIGallerySource)fallbackSource {
    if (metadata) {
        file.source = metadata.source;
        file.sourceUsername = metadata.sourceUsername.length ? metadata.sourceUsername : nil;
        file.sourceUserPK = metadata.sourceUserPK.length ? metadata.sourceUserPK : nil;
        file.sourceProfileURLString = metadata.sourceProfileURLString.length ? metadata.sourceProfileURLString : nil;
        file.sourceMediaPK = metadata.sourceMediaPK.length ? metadata.sourceMediaPK : nil;
        file.sourceMediaCode = metadata.sourceMediaCode.length ? metadata.sourceMediaCode : nil;
        file.sourceMediaURLString = metadata.sourceMediaURLString.length ? metadata.sourceMediaURLString : nil;
        file.pixelWidth = metadata.pixelWidth;
        file.pixelHeight = metadata.pixelHeight;
        file.durationSeconds = metadata.durationSeconds;
        file.customName = metadata.customName.length ? metadata.customName : nil;
    } else {
        file.source = fallbackSource;
        file.sourceUsername = nil;
        file.sourceUserPK = nil;
        file.sourceProfileURLString = nil;
        file.sourceMediaPK = nil;
        file.sourceMediaCode = nil;
        file.sourceMediaURLString = nil;
        file.pixelWidth = 0;
        file.pixelHeight = 0;
        file.durationSeconds = 0;
        file.customName = nil;
    }
}

+ (NSFetchRequest *)unassignedFetchRequest {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"SCIGalleryFile"];
    request.predicate = [NSPredicate predicateWithFormat:@"ownerAccountPK == nil OR ownerAccountPK == ''"];
    return request;
}

+ (NSUInteger)unassignedFileCount {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSUInteger count = [ctx countForFetchRequest:[self unassignedFetchRequest] error:nil];
    return count == NSNotFound ? 0 : count;
}

+ (NSUInteger)claimUnassignedFilesForAccountPK:(NSString *)pk username:(NSString *)username {
    if (pk.length == 0) return 0;
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSArray<SCIGalleryFile *> *files = [ctx executeFetchRequest:[self unassignedFetchRequest] error:nil];
    for (SCIGalleryFile *file in files) {
        file.ownerAccountPK = pk;
        file.ownerUsername = username.length > 0 ? username : nil;
    }
    if (files.count > 0) [[SCIGalleryCoreDataStack shared] saveContext];
    return files.count;
}

+ (SCIGalleryMediaType)inferMediaTypeFromFileURL:(NSURL *)fileURL {
    NSString *e = fileURL.pathExtension.lowercaseString;
    static NSSet<NSString *> *videoExts;
    static NSSet<NSString *> *audioExts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        videoExts = [NSSet setWithArray:@[ @"mp4", @"mov", @"m4v", @"webm" ]];
        audioExts = [NSSet setWithArray:@[ @"m4a", @"aac", @"mp3", @"wav", @"caf", @"aiff", @"flac", @"opus", @"ogg" ]];
    });
    if ([audioExts containsObject:e]) {
        return SCIGalleryMediaTypeAudio;
    }
    if ([videoExts containsObject:e]) {
        return SCIGalleryMediaTypeVideo;
    }
    return SCIGalleryMediaTypeImage;
}

+ (void)probeMediaAtPath:(NSString *)path mediaType:(SCIGalleryMediaType)mediaType file:(SCIGalleryFile *)file {
    if (mediaType == SCIGalleryMediaTypeImage) {
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
        if (!src) {
            return;
        }
        CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
        CFRelease(src);
        if (!props) {
            return;
        }
        NSNumber *w = CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
        NSNumber *h = CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
        if (file.pixelWidth <= 0 && [w respondsToSelector:@selector(intValue)]) {
            file.pixelWidth = (int32_t)w.intValue;
        }
        if (file.pixelHeight <= 0 && [h respondsToSelector:@selector(intValue)]) {
            file.pixelHeight = (int32_t)h.intValue;
        }
        CFRelease(props);
        return;
    }

    NSURL *url = [NSURL fileURLWithPath:path];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    CMTime dur = asset.duration;
    if (file.durationSeconds <= 0.05 && CMTIME_IS_NUMERIC(dur)) {
        double sec = CMTimeGetSeconds(dur);
        if (sec > 0.05 && !isnan(sec)) {
            file.durationSeconds = sec;
        }
    }
    if (mediaType == SCIGalleryMediaTypeAudio) {
        return;
    }

    NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (tracks.count == 0) {
        return;
    }
    AVAssetTrack *track = tracks.firstObject;
    CGSize natural = track.naturalSize;
    CGAffineTransform tx = track.preferredTransform;
    CGSize rendered = CGSizeApplyAffineTransform(natural, tx);
    int32_t w = (int32_t)lround(fabs(rendered.width));
    int32_t h = (int32_t)lround(fabs(rendered.height));
    if (file.pixelWidth <= 0) {
        file.pixelWidth = w;
    }
    if (file.pixelHeight <= 0) {
        file.pixelHeight = h;
    }
}

+ (SCIGalleryFile *)saveFileToGallery:(NSURL *)fileURL
                           source:(SCIGallerySource)source
                        mediaType:(SCIGalleryMediaType)mediaType
                       folderPath:(NSString *)folderPath
                         metadata:(SCIGallerySaveMetadata *)metadata
                            error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:fileURL.path]) {
        if (error) {
            *error = [NSError errorWithDomain:@"SCIGallery" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Source file does not exist"}];
        }
        return nil;
    }

    NSString *fileName = SCIFileNameForMedia(fileURL, mediaType, metadata);
    NSString *destPath = [[SCIGalleryPaths galleryMediaDirectory] stringByAppendingPathComponent:fileName];

    if ([fm fileExistsAtPath:destPath]) {
        NSString *stem = [fileName stringByDeletingPathExtension];
        NSString *ext = fileName.pathExtension;
        for (int n = 1; n < 100; n++) {
            NSString *candidate = [NSString stringWithFormat:@"%@-%d.%@", stem, n, ext];
            NSString *candidatePath = [[SCIGalleryPaths galleryMediaDirectory] stringByAppendingPathComponent:candidate];
            if (![fm fileExistsAtPath:candidatePath]) {
                fileName = candidate;
                destPath = candidatePath;
                break;
            }
        }
    }

    NSError *copyError;
    if (![fm copyItemAtPath:fileURL.path toPath:destPath error:&copyError]) {
        SCILog(@"General", @"[SCInsta Gallery] Failed to copy file: %@", copyError);
        if (error) *error = copyError;
        return nil;
    }

    NSDictionary *attrs = [fm attributesOfItemAtPath:destPath error:nil];
    int64_t size = [attrs[NSFileSize] longLongValue];

    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    SCIGalleryFile *file = [NSEntityDescription insertNewObjectForEntityForName:@"SCIGalleryFile"
                                                       inManagedObjectContext:ctx];
    file.identifier = [NSUUID UUID].UUIDString;
    file.relativePath = fileName;
    file.mediaType = mediaType;
    file.dateAdded = metadata.importCapturedDate ?: metadata.importPostedDate ?: [NSDate date];
    file.fileSize = size;
    file.isFavorite = NO;
    file.folderPath = folderPath;

    [self applyMetadata:metadata toFile:file fallbackSource:source];
    // Tag with the saving account so the per-account gallery filter can scope it.
    // Editable afterwards via the file's edit-details sheet.
    NSString *ownerPK = [SCIAccountManager currentAccountPK];
    if (ownerPK.length > 0) {
        file.ownerAccountPK = ownerPK;
        file.ownerUsername = [SCIAccountManager currentAccountUsername];
    }
    [self probeMediaAtPath:destPath mediaType:mediaType file:file];

    NSError *saveError;
    if (![ctx save:&saveError]) {
        SCILog(@"General", @"[SCInsta Gallery] Failed to save entity: %@", saveError);
        [fm removeItemAtPath:destPath error:nil];
        if (error) *error = saveError;
        return nil;
    }

    [self generateThumbnailForFile:file completion:nil];

    return file;
}

#pragma mark - Remove

- (BOOL)removeWithError:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *mediaPath = [self filePath];
    if ([fm fileExistsAtPath:mediaPath]) {
        [fm removeItemAtPath:mediaPath error:nil];
    }

    NSString *thumbPath = [self thumbnailPath];
    if ([fm fileExistsAtPath:thumbPath]) {
        [fm removeItemAtPath:thumbPath error:nil];
    }

    NSManagedObjectContext *ctx = self.managedObjectContext;
    [ctx deleteObject:self];

    NSError *saveError;
    if (![ctx save:&saveError]) {
        SCILog(@"General", @"[SCInsta Gallery] Failed to delete entity: %@", saveError);
        if (error) *error = saveError;
        return NO;
    }

    return YES;
}

- (BOOL)replaceMediaWithFileURL:(NSURL *)newURL
                      mediaType:(SCIGalleryMediaType)mediaType
                          error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!newURL || ![fm fileExistsAtPath:newURL.path]) {
        if (error) {
            *error = [NSError errorWithDomain:@"SCIGallery" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Replacement file does not exist"}];
        }
        return NO;
    }

    NSString *dir = [SCIGalleryPaths galleryMediaDirectory];
    NSString *oldMediaPath = [self filePath];
    NSString *thumbPath = [self thumbnailPath];

    NSString *stem = [self.relativePath stringByDeletingPathExtension];
    if (stem.length == 0) {
        stem = [NSUUID UUID].UUIDString;
    }
    NSString *newExt = SCIGalleryNormalizedExtension(newURL.pathExtension, mediaType);
    NSString *newName = [stem stringByAppendingPathExtension:newExt];
    NSString *newPath = [dir stringByAppendingPathComponent:newName];

    // Land on a path distinct from the existing media file so the copy can be
    // verified before the original is removed (a failed copy never destroys it).
    if ([newPath isEqualToString:oldMediaPath] || [fm fileExistsAtPath:newPath]) {
        for (int n = 1; n < 1000; n++) {
            NSString *candidate = [NSString stringWithFormat:@"%@-%d.%@", stem, n, newExt];
            NSString *candidatePath = [dir stringByAppendingPathComponent:candidate];
            if (![candidatePath isEqualToString:oldMediaPath] && ![fm fileExistsAtPath:candidatePath]) {
                newName = candidate;
                newPath = candidatePath;
                break;
            }
        }
    }

    NSError *copyError = nil;
    if (![fm copyItemAtPath:newURL.path toPath:newPath error:&copyError]) {
        SCILog(@"General", @"[SCInsta Gallery] Failed to copy replacement file: %@", copyError);
        if (error) *error = copyError;
        return NO;
    }

    if (![oldMediaPath isEqualToString:newPath]) {
        [fm removeItemAtPath:oldMediaPath error:nil];
    }

    self.relativePath = newName;
    self.mediaType = mediaType;

    NSDictionary *attrs = [fm attributesOfItemAtPath:newPath error:nil];
    self.fileSize = [attrs[NSFileSize] longLongValue];
    // Reset so probeMediaAtPath (which only fills when <= 0) repopulates them.
    self.pixelWidth = 0;
    self.pixelHeight = 0;
    self.durationSeconds = 0;
    [[self class] probeMediaAtPath:newPath mediaType:mediaType file:self];

    // Thumbnail path is keyed by identifier (unchanged), so drop the stale
    // on-disk thumbnail and its cache entry before regenerating.
    [fm removeItemAtPath:thumbPath error:nil];
    [SCIGalleryThumbnailCache() removeObjectForKey:thumbPath];

    NSManagedObjectContext *ctx = self.managedObjectContext ?: [SCIGalleryCoreDataStack shared].viewContext;
    NSError *saveError = nil;
    if (![ctx save:&saveError]) {
        SCILog(@"General", @"[SCInsta Gallery] Failed to save replaced entity: %@", saveError);
        if (error) *error = saveError;
        return NO;
    }

    [[self class] generateThumbnailForFile:self completion:nil];
    return YES;
}

- (SCIGallerySaveMetadata *)saveMetadata {
    SCIGallerySaveMetadata *metadata = [[SCIGallerySaveMetadata alloc] init];
    metadata.source = self.source;
    metadata.sourceUsername = self.sourceUsername;
    metadata.sourceUserPK = self.sourceUserPK;
    metadata.sourceProfileURLString = self.sourceProfileURLString;
    metadata.sourceMediaPK = self.sourceMediaPK;
    metadata.sourceMediaCode = self.sourceMediaCode;
    metadata.sourceMediaURLString = self.sourceMediaURLString;
    metadata.customName = self.customName;
    // Keep the derived copy's date/filename aligned with the original.
    metadata.importCapturedDate = self.dateAdded;
    metadata.importPostedDate = self.dateAdded;
    // Dimensions/duration deliberately left unset — the trimmed file differs and
    // is probed fresh.
    return metadata;
}

#pragma mark - Paths

- (NSString *)filePath {
    return [[SCIGalleryPaths galleryMediaDirectory] stringByAppendingPathComponent:self.relativePath];
}

- (NSURL *)fileURL {
    return [NSURL fileURLWithPath:[self filePath]];
}

- (BOOL)fileExists {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self filePath]];
}

- (NSString *)thumbnailPath {
    return [[SCIGalleryPaths galleryThumbnailsDirectory]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", self.identifier]];
}

- (BOOL)thumbnailExists {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self thumbnailPath]];
}

#pragma mark - Display helpers

- (NSString *)displayName {
    if (self.customName.length > 0) return self.customName;

    // relativePath: "<epochMs>_<rest>" — rest may be "user_slug_date.ext" or legacy "originalFilename".
    NSString *rel = self.relativePath ?: @"";
    NSRange sep = [rel rangeOfString:@"_"];
    if (sep.location != NSNotFound && sep.location + 1 < rel.length) {
        return [rel substringFromIndex:sep.location + 1];
    }
    return rel;
}

- (NSString *)sourceLabel {
    return [SCIGalleryFile labelForSource:(SCIGallerySource)self.source];
}

- (NSString *)shortSourceLabel {
    return [SCIGalleryFile shortLabelForSource:(SCIGallerySource)self.source];
}

- (NSString *)listPrimaryTitle {
    if (self.sourceUsername.length) {
        return self.sourceUsername;
    }
    return [self displayName];
}

- (NSString *)listFormattedDuration {
    if (self.durationSeconds <= 0.05) {
        return @"";
    }
    NSInteger total = (NSInteger)llround(self.durationSeconds);
    NSInteger m = total / 60;
    NSInteger s = total % 60;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

- (NSString *)listBitrateString {
    if (self.mediaType != SCIGalleryMediaTypeVideo && self.mediaType != SCIGalleryMediaTypeAudio) {
        return @"";
    }
    if (self.durationSeconds < 0.5 || self.fileSize <= 0) {
        return @"";
    }
    double mbps = (double)self.fileSize * 8.0 / self.durationSeconds / 1e6;
    if (mbps < 0.01) {
        return @"";
    }
    return [NSString stringWithFormat:@"%.1f Mbps", mbps];
}

- (NSString *)listTechnicalLine {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    BOOL isTimedMedia = (self.mediaType == SCIGalleryMediaTypeVideo || self.mediaType == SCIGalleryMediaTypeAudio);
    if (isTimedMedia) {
        NSString *d = [self listFormattedDuration];
        if (d.length) {
            [parts addObject:d];
        }
    }
    NSString *sz = [NSByteCountFormatter stringFromByteCount:self.fileSize
                                                    countStyle:NSByteCountFormatterCountStyleFile];
    if (sz.length) {
        [parts addObject:sz];
    }
    if (self.mediaType != SCIGalleryMediaTypeAudio && self.pixelWidth > 0 && self.pixelHeight > 0) {
        [parts addObject:[NSString stringWithFormat:@"%dx%d", self.pixelWidth, self.pixelHeight]];
    }
    if (isTimedMedia) {
        NSString *br = [self listBitrateString];
        if (br.length) {
            [parts addObject:br];
        }
    }
    return [parts componentsJoinedByString:@" · "];
}

- (NSString *)listDownloadDateString {
    static NSDateFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MMM d 'at' h:mm a";
    });
    return self.dateAdded ? [fmt stringFromDate:self.dateAdded] : @"";
}

- (NSURL *)preferredProfileURL {
    if (self.sourceProfileURLString.length > 0) {
        NSURL *url = [NSURL URLWithString:self.sourceProfileURLString];
        if (url) return url;
    }
    if (self.sourceUsername.length > 0) {
        NSString *encodedUsername = [self.sourceUsername stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        if (encodedUsername.length > 0) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", encodedUsername]];
            if (url) return url;
        }
    }
    return nil;
}

- (NSString *)fullInstagramMediaID {
    NSString *rawMediaPK = self.sourceMediaPK ?: @"";

    // Already a composite "<mediaPK>_<userPK>" (e.g. captured from media.id)? Use as-is.
    NSArray<NSString *> *parts = [rawMediaPK componentsSeparatedByString:@"_"];
    if (parts.count == 2) {
        NSString *m = parts[0];
        NSString *u = parts[1];
        BOOL mDigits = m.length > 0 && [m rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
        BOOL uDigits = u.length > 0 && [u rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
        if (mDigits && uDigits) return rawMediaPK;
    }

    NSString *mediaPK = parts.firstObject ?: rawMediaPK;
    if (mediaPK.length == 0) return nil;
    if ([mediaPK rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) return nil;

    NSString *userPK = [self.sourceUserPK componentsSeparatedByString:@"_"].lastObject ?: self.sourceUserPK;
    if (userPK.length == 0) return nil;
    if ([userPK rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) return nil;

    return [NSString stringWithFormat:@"%@_%@", mediaPK, userPK];
}

- (NSURL *)preferredOriginalMediaURL {
    // Stories are not posts: build https://www.instagram.com/stories/<username>/<pk>/ — never /p/, /reel/ or instagram://media (which all resolve to the feed viewer).
    if (self.source == SCIGallerySourceStories) {
        if (self.sourceMediaURLString.length > 0) {
            NSURL *stored = [NSURL URLWithString:self.sourceMediaURLString];
            NSString *scheme = stored.scheme.lowercaseString ?: @"";
            NSString *path = stored.path.lowercaseString ?: @"";
            BOOL validScheme = stored && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"instagram"]);
            // Reject stale post/reel links wrongly stored on story entries by older builds.
            BOOL stalePostURL = [path containsString:@"/p/"] || [path containsString:@"/reel/"] || [path containsString:@"/reels/"];
            if (validScheme && !stalePostURL) {
                SCILog(@"General", @"[SCInsta Gallery] Open original using stored story URL url=%@", stored.absoluteString);
                return stored;
            }
            SCILog(@"General", @"[SCInsta Gallery] Ignoring stored story URL (stale/invalid) url=%@", self.sourceMediaURLString);
        }

        NSString *identifier = [self.sourceMediaPK componentsSeparatedByString:@"_"].firstObject ?: self.sourceMediaPK;
        if (self.sourceUsername.length > 0 && identifier.length > 0) {
            NSString *encodedUsername = [self.sourceUsername stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
            NSString *encodedIdentifier = [identifier stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
            if (encodedUsername.length > 0 && encodedIdentifier.length > 0) {
                NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/stories/%@/%@/", encodedUsername, encodedIdentifier]];
                SCILog(@"General", @"[SCInsta Gallery] Open original built story URL username=%@ id=%@ url=%@", self.sourceUsername, identifier, url.absoluteString);
                return url;
            }
        }
        SCILog(@"General", @"[SCInsta Gallery] Open original story missing username/pk username=%@ mediaPK=%@", self.sourceUsername, self.sourceMediaPK);
        return nil;
    }

    // Posts/reels: prefer canonical permalinks. The generic instagram://media?id=
    // route can open carousel children as detached media and reels in the feed viewer,
    // which leaves Instagram without the original post/reel presentation context.
    NSString *pathComponent = SCIGalleryPostPathComponentForSource((SCIGallerySource)self.source);
    if (self.sourceMediaCode.length > 0) {
        if (pathComponent.length == 0) {
            SCILog(@"General", @"[SCInsta Gallery] Open original has code but no safe path source=%d code=%@", self.source, self.sourceMediaCode);
            return nil;
        }
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/%@/", pathComponent, self.sourceMediaCode]];
        SCILog(@"General", @"[SCInsta Gallery] Open original generated from code source=%d code=%@ url=%@", self.source, self.sourceMediaCode, url.absoluteString);
        return url;
    }

    if (self.sourceMediaPK.length > 0 && pathComponent.length > 0) {
        NSString *code = [SCIUtils instagramShortcodeForMediaPK:self.sourceMediaPK];
        if (code.length > 0) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/%@/", pathComponent, code]];
            SCILog(@"General", @"[SCInsta Gallery] Open original generated from media pk source=%d mediaPK=%@ code=%@ url=%@", self.source, self.sourceMediaPK, code, url.absoluteString);
            return url;
        }
        SCILog(@"General", @"[SCInsta Gallery] Open original could not derive shortcode from media pk source=%d mediaPK=%@", self.source, self.sourceMediaPK);
    }

    // Stored permalink (typically a /p/ or /reel/ web link captured at save time).
    if (self.sourceMediaURLString.length > 0) {
        NSURL *url = [NSURL URLWithString:self.sourceMediaURLString];
        NSString *scheme = url.scheme.lowercaseString ?: @"";
        if (url && ([scheme isEqualToString:@"http"] ||
                    [scheme isEqualToString:@"https"] ||
                    [scheme isEqualToString:@"instagram"])) {
            SCILog(@"General", @"[SCInsta Gallery] Open original using stored URL source=%d url=%@", self.source, url.absoluteString);
            return url;
        }
        SCILog(@"General", @"[SCInsta Gallery] Ignoring invalid stored original URL source=%d raw=%@", self.source, self.sourceMediaURLString);
    }

    // Last resort for entries that only have a full media id. This is authenticated,
    // but it is not context-preserving for reels/carousels.
    NSString *fullMediaID = [self fullInstagramMediaID];
    if (fullMediaID.length > 0) {
        NSString *encodedID = [fullMediaID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        if (encodedID.length > 0) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://media?id=%@", encodedID]];
            SCILog(@"General", @"[SCInsta Gallery] Open original using fallback media deep link source=%d id=%@ url=%@", self.source, fullMediaID, url.absoluteString);
            return url;
        }
    }

    SCILog(@"General", @"[SCInsta Gallery] Open original unavailable source=%d relativePath=%@", self.source, self.relativePath);
    return nil;
}

- (BOOL)hasOpenableProfile {
    return [self preferredProfileURL] != nil;
}

- (BOOL)hasOpenableOriginalMedia {
    return [self preferredOriginalMediaURL] != nil;
}

- (NSString *)openOriginalActionTitle {
    switch ((SCIGallerySource)self.source) {
        case SCIGallerySourceStories:
            return @"Open Story";
        case SCIGallerySourceReels:
            return @"Open Reel";
        case SCIGallerySourceFeed:
        case SCIGallerySourceProfile:
            return @"Open Post";
        default:
            return @"Open Original Post";
    }
}

+ (NSString *)labelForSource:(SCIGallerySource)source {
    switch (source) {
        case SCIGallerySourceFeed:      return @"Feed";
        case SCIGallerySourceStories:   return @"Stories";
        case SCIGallerySourceReels:     return @"Reels";
        case SCIGallerySourceProfile:   return @"Profile";
        case SCIGallerySourceDMs:       return @"DMs";
        case SCIGallerySourceThumbnail: return @"Thumb";
        case SCIGallerySourceInstants:  return @"Instants";
        case SCIGallerySourceAudioPage: return @"Audio Page";
        case SCIGallerySourceComments:  return @"Comments";
        case SCIGallerySourceOther:
        default:                      return @"Other";
    }
}

+ (NSString *)shortLabelForSource:(SCIGallerySource)source {
    switch (source) {
        case SCIGallerySourceFeed:      return @"Feed";
        case SCIGallerySourceStories:   return @"Story";
        case SCIGallerySourceReels:     return @"Reel";
        case SCIGallerySourceProfile:   return @"Profile";
        case SCIGallerySourceDMs:       return @"DMs";
        case SCIGallerySourceThumbnail: return @"Thumb";
        case SCIGallerySourceInstants:  return @"Instant";
        case SCIGallerySourceAudioPage: return @"Audio Page";
        case SCIGallerySourceComments:  return @"Comment";
        case SCIGallerySourceOther:
        default:                      return @"Other";
    }
}

+ (NSString *)symbolNameForSource:(SCIGallerySource)source {
    switch (source) {
        case SCIGallerySourceFeed:    return @"feed";
        case SCIGallerySourceStories: return @"story";
        case SCIGallerySourceReels:   return @"reels";
        case SCIGallerySourceProfile: return @"user_circle";
        case SCIGallerySourceDMs:     return @"messages";
        case SCIGallerySourceThumbnail: return @"photo_gallery";
        case SCIGallerySourceInstants: return @"instants";
        case SCIGallerySourceAudioPage: return @"audio_page";
        case SCIGallerySourceComments: return @"comment";
        case SCIGallerySourceOther:
        default:                    return @"media";
    }
}

#pragma mark - Thumbnails

+ (void)generateThumbnailForFile:(SCIGalleryFile *)file completion:(void(^)(BOOL success))completion {
    int16_t mediaType = file.mediaType;
    if (mediaType == SCIGalleryMediaTypeAudio) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES);
            });
        }
        return;
    }

    NSString *filePath = [file filePath];
    NSString *thumbPath = [file thumbnailPath];
    NSCache<NSString *, UIImage *> *cache = SCIGalleryThumbnailCache();

    UIImage *cachedThumb = [cache objectForKey:thumbPath];
    if (cachedThumb || [file thumbnailExists]) {
        if (!cachedThumb) {
            cachedThumb = [UIImage imageWithContentsOfFile:thumbPath];
            if (cachedThumb) {
                [cache setObject:cachedThumb forKey:thumbPath];
            }
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cachedThumb != nil);
            });
        }
        return;
    }

    __block BOOL shouldGenerate = NO;
    dispatch_sync(SCIGalleryThumbnailStateQueue(), ^{
        NSMutableDictionary<NSString *, NSMutableArray<void(^)(BOOL success)> *> *pending = SCIGalleryThumbnailCompletions();
        NSMutableArray<void(^)(BOOL success)> *callbacks = pending[thumbPath];
        if (callbacks) {
            if (completion) {
                [callbacks addObject:[completion copy]];
            }
            return;
        }

        shouldGenerate = YES;
        callbacks = [NSMutableArray array];
        if (completion) {
            [callbacks addObject:[completion copy]];
        }
        pending[thumbPath] = callbacks;
    });

    if (!shouldGenerate) {
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *thumb = nil;

        if (mediaType == SCIGalleryMediaTypeImage) {
            UIImage *full = [UIImage imageWithContentsOfFile:filePath];
            if (full) {
                thumb = [self resizeImage:full toSize:CGSizeMake(kThumbnailSize, kThumbnailSize)];
            }
        } else if (mediaType == SCIGalleryMediaTypeVideo) {
            NSURL *videoURL = [NSURL fileURLWithPath:filePath];
            AVAsset *asset = [AVAsset assetWithURL:videoURL];
            AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
            gen.appliesPreferredTrackTransform = YES;
            gen.maximumSize = CGSizeMake(kThumbnailSize, kThumbnailSize);

            NSError *err;
            CGImageRef cgImage = [gen copyCGImageAtTime:CMTimeMake(1, 2) actualTime:NULL error:&err];
            if (cgImage) {
                thumb = [UIImage imageWithCGImage:cgImage];
                CGImageRelease(cgImage);
            }
        }

        if (thumb) {
            NSData *jpegData = UIImageJPEGRepresentation(thumb, 0.8);
            [jpegData writeToFile:thumbPath atomically:YES];
            [cache setObject:thumb forKey:thumbPath];
        }

        __block NSArray<void(^)(BOOL success)> *callbacks = nil;
        dispatch_sync(SCIGalleryThumbnailStateQueue(), ^{
            callbacks = [[SCIGalleryThumbnailCompletions()[thumbPath] copy] ?: @[] copy];
            [SCIGalleryThumbnailCompletions() removeObjectForKey:thumbPath];
        });

        if (callbacks.count == 0) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL success = (thumb != nil);
            for (void (^callback)(BOOL success) in callbacks) {
                callback(success);
            }
        });
    });
}

static UIImage *SCIGalleryAudioPlaceholderImage(void) {
    UIUserInterfaceStyle style = UIUserInterfaceStyleLight;
    style = [UITraitCollection currentTraitCollection].userInterfaceStyle;
    
    static NSMutableDictionary<NSNumber *, UIImage *> *cachedImages = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachedImages = [NSMutableDictionary dictionary];
    });
    
    UIImage *cached = cachedImages[@(style)];
    if (cached) {
        return cached;
    }
    
    CGSize size = CGSizeMake(kThumbnailSize, kThumbnailSize);
    UIGraphicsBeginImageContextWithOptions(size, YES, 0.0);
    
    [[SCIUtils SCIColor_InstagramTertiaryBackground] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    
    UIColor *tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
    [tintColor setFill];
    
    CGFloat const w = 12.0;
    CGFloat const s = 28.0;
    CGFloat const h_middle = 130.0;
    CGFloat const h_side = 85.0;
    
    // Left bar
    CGRect leftRect = CGRectMake(150.0 - w/2.0 - s - w, 150.0 - h_side/2.0, w, h_side);
    UIBezierPath *leftPath = [UIBezierPath bezierPathWithRoundedRect:leftRect cornerRadius:w/2.0];
    [leftPath fill];
    
    // Middle bar
    CGRect middleRect = CGRectMake(150.0 - w/2.0, 150.0 - h_middle/2.0, w, h_middle);
    UIBezierPath *middlePath = [UIBezierPath bezierPathWithRoundedRect:middleRect cornerRadius:w/2.0];
    [middlePath fill];
    
    // Right bar
    CGRect rightRect = CGRectMake(150.0 + w/2.0 + s, 150.0 - h_side/2.0, w, h_side);
    UIBezierPath *rightPath = [UIBezierPath bezierPathWithRoundedRect:rightRect cornerRadius:w/2.0];
    [rightPath fill];
    
    UIImage *thumb = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (thumb) {
        cachedImages[@(style)] = thumb;
    }
    return thumb;
}

+ (UIImage *)loadThumbnailForFile:(SCIGalleryFile *)file {
    if (file.mediaType == SCIGalleryMediaTypeAudio) {
        return SCIGalleryAudioPlaceholderImage();
    }

    NSString *thumbPath = [file thumbnailPath];
    UIImage *cached = [SCIGalleryThumbnailCache() objectForKey:thumbPath];
    if (cached) {
        return cached;
    }
    if ([file thumbnailExists]) {
        UIImage *image = [UIImage imageWithContentsOfFile:thumbPath];
        if (image) {
            [SCIGalleryThumbnailCache() setObject:image forKey:thumbPath];
        }
        return image;
    }
    return nil;
}

+ (UIImage *)resizeImage:(UIImage *)image toSize:(CGSize)targetSize {
    CGFloat scale = MIN(targetSize.width / image.size.width, targetSize.height / image.size.height);
    CGSize newSize = CGSizeMake(image.size.width * scale, image.size.height * scale);

    UIGraphicsBeginImageContextWithOptions(newSize, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return resized;
}

@end

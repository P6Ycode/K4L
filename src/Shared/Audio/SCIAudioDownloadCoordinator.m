#import "SCIAudioDownloadCoordinator.h"

#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "../../Downloader/Download.h"
#import "../../Utils.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../MediaDownload/SCIDashParser.h"
#import "../MediaDownload/SCIMediaFFmpeg.h"
#import "../MediaPreview/SCIFullScreenMediaPlayer.h"
#import "../MediaPreview/SCIMediaItem.h"
#import "../UI/SCINotificationCenter.h"

static id SCIAudioObjectForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SCIAudioKVCObject(id target, NSString *key) {
    if (!target || key.length == 0) return nil;
    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SCIAudioIvarValue(id target, const char *name) {
    if (!target || !name) return nil;
    @try {
        for (Class cls = [target class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
            Ivar ivar = class_getInstanceVariable(cls, name);
            if (!ivar) continue;
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (encoding && encoding[0] == '@') {
                return object_getIvar(target, ivar);
            }
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static NSString *SCIAudioStringValue(id value) {
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] > 0 ? value : nil;
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *string = [value stringValue];
        return string.length > 0 ? string : nil;
    }
    return nil;
}

static NSURL *SCIAudioURLFromValue(id value) {
    if ([value isKindOfClass:NSURL.class]) {
        NSURL *url = value;
        if (url.scheme.length > 0 || url.isFileURL) return url;
        return nil;
    }
    NSString *string = SCIAudioStringValue(value);
    if (string.length == 0) return nil;

    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;
    if ([trimmed hasPrefix:@"//"]) {
        trimmed = [@"https:" stringByAppendingString:trimmed];
    }

    NSURL *url = [NSURL URLWithString:trimmed];
    if (!url && ![trimmed containsString:@"://"]) {
        url = [NSURL fileURLWithPath:trimmed];
    }
    if (!url.scheme.length && !url.isFileURL) return nil;
    NSString *scheme = url.scheme.lowercaseString;
    if (scheme.length > 0 && ![@[@"http", @"https", @"file"] containsObject:scheme]) return nil;
    return url;
}

static NSURL *SCIAudioURLForNames(id object, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        NSURL *url = SCIAudioURLFromValue(SCIAudioObjectForSelector(object, name));
        if (!url) url = SCIAudioURLFromValue(SCIAudioKVCObject(object, name));
        if (url) return url;
    }
    return nil;
}

static BOOL SCIAudioShouldTraverseObject(id object) {
    if (!object) return NO;
    if ([object isKindOfClass:NSString.class] ||
        [object isKindOfClass:NSNumber.class] ||
        [object isKindOfClass:NSDate.class] ||
        [object isKindOfClass:NSURL.class] ||
        [object isKindOfClass:NSData.class] ||
        [object isKindOfClass:UIImage.class] ||
        [object isKindOfClass:UIView.class] ||
        [object isKindOfClass:UIViewController.class]) {
        return NO;
    }
    NSString *name = NSStringFromClass([object class]);
    return [name containsString:@"Direct"] ||
           [name containsString:@"Audio"] ||
           [name containsString:@"Message"] ||
           [name containsString:@"Media"] ||
           [name containsString:@"GraphQL"] ||
           [name containsString:@"GQL"] ||
           [name containsString:@"Model"];
}

static NSURL *SCIAudioBestURLFromObject(id mediaObject, NSMutableSet<NSValue *> *visited, NSUInteger depth) {
    if (!mediaObject || depth > 5) return nil;
    if ([mediaObject isKindOfClass:NSURL.class] || [mediaObject isKindOfClass:NSString.class]) {
        return SCIAudioURLFromValue(mediaObject);
    }

    NSValue *identity = [NSValue valueWithNonretainedObject:mediaObject];
    if ([visited containsObject:identity]) return nil;
    [visited addObject:identity];

    NSURL *direct = SCIAudioURLForNames(mediaObject, @[
        @"audioFileUrl", @"audioFileURL", @"playableAudioURL", @"audioURL", @"audioUrl",
        @"progressiveDownloadURL", @"progressiveAudioURL", @"audioSrc", @"mediaUrl", @"mediaURL",
        @"downloadUrl", @"downloadURL", @"url"
    ]);
    if (direct) return direct;

    if ([mediaObject isKindOfClass:NSDictionary.class]) {
        for (id value in [(NSDictionary *)mediaObject allValues]) {
            NSURL *url = SCIAudioBestURLFromObject(value, visited, depth + 1);
            if (url) return url;
        }
    } else if ([mediaObject isKindOfClass:NSArray.class] || [mediaObject isKindOfClass:NSSet.class]) {
        for (id value in mediaObject) {
            NSURL *url = SCIAudioBestURLFromObject(value, visited, depth + 1);
            if (url) return url;
        }
    }

    for (NSString *name in @[@"audio", @"audioAsset", @"music", @"originalAudio", @"clipsAudio", @"sound", @"media", @"item", @"viewModel", @"message", @"messageCellViewModel", @"audioMessageViewModel", @"messageMetadata"]) {
        id nested = SCIAudioObjectForSelector(mediaObject, name) ?: SCIAudioKVCObject(mediaObject, name);
        if (nested && nested != mediaObject) {
            NSURL *url = SCIAudioBestURLFromObject(nested, visited, depth + 1);
            if (url) return url;
        }
    }

    if (SCIAudioShouldTraverseObject(mediaObject)) {
        for (Class cls = [mediaObject class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
            unsigned int count = 0;
            Ivar *ivars = class_copyIvarList(cls, &count);
            for (unsigned int i = 0; i < count; i++) {
                Ivar ivar = ivars[i];
                const char *encoding = ivar_getTypeEncoding(ivar);
                if (!encoding || encoding[0] != '@') continue;
                id value = nil;
                @try {
                    value = object_getIvar(mediaObject, ivar);
                } @catch (__unused NSException *exception) {
                    value = nil;
                }
                NSURL *url = SCIAudioBestURLFromObject(value, visited, depth + 1);
                if (url) {
                    free(ivars);
                    return url;
                }
            }
            free(ivars);
        }
    }

    return nil;
}

static NSTimeInterval SCIAudioDurationForObject(id object) {
    for (NSString *name in @[@"duration", @"durationSeconds", @"audioDuration", @"audioDurationSeconds", @"videoDuration"]) {
        id value = SCIAudioObjectForSelector(object, name) ?: SCIAudioKVCObject(object, name);
        if ([value respondsToSelector:@selector(doubleValue)] && [value doubleValue] > 0.0) {
            return [value doubleValue];
        }
    }
    return 0.0;
}

static SCIGallerySaveMetadata *SCIAudioMetadataFromItem(SCIAudioItem *item, SCIGallerySaveMetadata *metadata) {
    SCIGallerySaveMetadata *resolved = metadata ?: [[SCIGallerySaveMetadata alloc] init];
    resolved.source = (int16_t)[item gallerySource];
    if (!resolved.sourceUsername.length) {
        resolved.sourceUsername = item.artist.length > 0 ? item.artist : @"audio";
    }
    if (!resolved.sourceMediaPK.length) {
        resolved.sourceMediaPK = item.mediaIdentifier;
    }
    if (!resolved.sourceMediaURLString.length) {
        resolved.sourceMediaURLString = item.sourceURLString ?: item.url.absoluteString;
    }
    if (!resolved.customName.length && item.title.length > 0) {
        resolved.customName = item.title;
    }
    if (resolved.durationSeconds <= 0.05) {
        resolved.durationSeconds = item.duration;
    }
    return resolved;
}

static NSString *SCIAudioNotificationIdentifier(NSString *provided, SCIAudioAction action) {
    if (provided.length > 0) return provided;
    switch (action) {
        case SCIAudioActionSaveToGallery:
        case SCIAudioActionConvertAndSaveToGallery:
            return kSCINotificationDownloadGallery;
        case SCIAudioActionCopyURL:
            return kSCINotificationDownloadShare;
        case SCIAudioActionShare:
        case SCIAudioActionConvertAndShare:
        case SCIAudioActionSaveToFiles:
        case SCIAudioActionPlay:
        default:
            return kSCINotificationDownloadShare;
    }
}

static void SCIAudioConvertToM4A(NSURL *sourceURL, NSString *basename, void (^progress)(float, NSString *), void (^completion)(NSURL *, NSError *)) {
    NSString *safeBase = basename.length > 0 ? basename : NSUUID.UUID.UUIDString;
    NSURL *outputURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", safeBase]]];
    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];

    void (^runFFmpegFallback)(NSError *) = ^(NSError *avError) {
        if (![SCIMediaFFmpeg isAvailable]) {
            if (completion) completion(nil, avError ?: [SCIUtils errorWithDescription:@"Audio conversion failed"]);
            return;
        }
        if (progress) progress(0.1f, @"Finalizing audio");
        [SCIMediaFFmpeg extractAudioFileURL:sourceURL
                           preferredBasename:safeBase
                                    progress:^(double ffmpegProgress, NSString *stage) {
            if (progress) progress(0.1f + (float)(ffmpegProgress * 0.85), stage.length > 0 ? stage : @"Finalizing audio");
        }
                                  completion:^(NSURL * _Nullable ffmpegURL, NSError * _Nullable ffmpegError) {
            if (ffmpegURL && !ffmpegError) {
                if (completion) completion(ffmpegURL, nil);
                return;
            }
            if (completion) completion(nil, ffmpegError ?: avError ?: [SCIUtils errorWithDescription:@"Audio conversion failed"]);
        }
                                   cancelOut:nil];
    };

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (!export) {
        runFFmpegFallback([SCIUtils errorWithDescription:@"Audio conversion is not available for this file"]);
        return;
    }
    export.outputURL = outputURL;
    export.outputFileType = AVFileTypeAppleM4A;
    export.shouldOptimizeForNetworkUse = YES;
    if (progress) progress(0.05f, @"Converting audio");
    [export exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (export.status == AVAssetExportSessionStatusCompleted && [[NSFileManager defaultManager] fileExistsAtPath:outputURL.path]) {
                if (completion) completion(outputURL, nil);
                return;
            }
            NSError *error = export.error ?: [SCIUtils errorWithDescription:@"Audio conversion failed"];
            runFFmpegFallback(error);
        });
    }];
}

static BOOL SCIAudioShouldConvertURL(NSURL *url, BOOL explicitConvert) {
    if (explicitConvert) return YES;
    NSString *ext = url.pathExtension.lowercaseString;
    if (ext.length == 0) return YES;
    return ![@[@"m4a", @"mp3", @"aac", @"caf", @"wav"] containsObject:ext];
}

static NSString *SCIAudioBasename(SCIAudioItem *item) {
    NSString *identifier = item.mediaIdentifier.length > 0 ? item.mediaIdentifier : NSUUID.UUID.UUIDString;
    return [NSString stringWithFormat:@"scinsta_audio_%@", identifier];
}

@implementation SCIAudioDownloadCoordinator

+ (NSURL *)bestAudioURLFromMediaObject:(id)mediaObject {
    if (!mediaObject) return nil;
    NSURL *direct = SCIAudioBestURLFromObject(mediaObject, [NSMutableSet set], 0);
    if (direct) return direct;

    NSString *manifest = [SCIDashParser dashManifestForMedia:mediaObject];
    NSArray<SCIDashRepresentation *> *representations = [SCIDashParser parseManifest:manifest ?: @""];
    SCIDashRepresentation *best = nil;
    for (SCIDashRepresentation *rep in representations) {
        if (![rep.contentType.lowercaseString containsString:@"audio"] || !rep.url) continue;
        if (!best || rep.bandwidth > best.bandwidth) best = rep;
    }
    return best.url;
}

+ (SCIAudioItem *)audioItemFromMediaObject:(id)mediaObject source:(SCIAudioSource)source {
    NSURL *url = [self bestAudioURLFromMediaObject:mediaObject];
    if (!url) return nil;
    SCIAudioItem *item = [SCIAudioItem itemWithURL:url source:source];
    item.duration = SCIAudioDurationForObject(mediaObject);
    item.title = SCIAudioStringValue(SCIAudioObjectForSelector(mediaObject, @"title") ?: SCIAudioKVCObject(mediaObject, @"title") ?: SCIAudioObjectForSelector(mediaObject, @"displayTitle"));
    item.artist = SCIAudioStringValue(SCIAudioObjectForSelector(mediaObject, @"artistDisplayName") ?: SCIAudioKVCObject(mediaObject, @"artistDisplayName") ?: SCIAudioObjectForSelector(mediaObject, @"username") ?: SCIAudioKVCObject(mediaObject, @"username"));
    item.mediaIdentifier = SCIAudioStringValue(SCIAudioObjectForSelector(mediaObject, @"audioAssetId") ?: SCIAudioKVCObject(mediaObject, @"audioAssetId") ?: SCIAudioObjectForSelector(mediaObject, @"pk") ?: SCIAudioKVCObject(mediaObject, @"pk") ?: SCIAudioObjectForSelector(mediaObject, @"id") ?: SCIAudioKVCObject(mediaObject, @"id"));
    item.sourceURLString = url.absoluteString;
    return item;
}

+ (void)performAction:(SCIAudioAction)action
                 item:(SCIAudioItem *)item
            presenter:(UIViewController *)presenter
           sourceView:(UIView *)sourceView
             metadata:(SCIGallerySaveMetadata *)metadata
 notificationIdentifier:(NSString *)notificationIdentifier {
    if (!item.url) {
        SCINotify(SCIAudioNotificationIdentifier(notificationIdentifier, action), @"Could not find audio URL", nil, @"error_filled", SCINotificationToneError);
        return;
    }

    NSString *identifier = SCIAudioNotificationIdentifier(notificationIdentifier, action);
    if (action == SCIAudioActionCopyURL) {
        UIPasteboard.generalPasteboard.string = item.url.absoluteString;
        SCINotify(identifier, @"Copied audio URL", nil, @"copy_filled", SCINotificationToneSuccess);
        return;
    }

    if (action == SCIAudioActionPlay) {
        SCIMediaItem *previewItem = [SCIMediaItem itemWithFileURL:item.url];
        previewItem.mediaType = SCIMediaItemTypeAudio;
        previewItem.galleryMetadata = SCIAudioMetadataFromItem(item, metadata);
        previewItem.title = item.title.length > 0 ? item.title : @"Audio";
        [SCIFullScreenMediaPlayer showMediaItems:@[previewItem]
                                 startingAtIndex:0
                                        metadata:previewItem.galleryMetadata
                                  playbackSource:SCIFullScreenPlaybackSourceUnknown
                                      sourceView:sourceView
                                      controller:presenter
                                   pausePlayback:nil
                                  resumePlayback:nil];
        return;
    }

    BOOL convert = (action == SCIAudioActionConvertAndShare || action == SCIAudioActionConvertAndSaveToGallery);
    DownloadAction downloadAction = (action == SCIAudioActionSaveToGallery || action == SCIAudioActionConvertAndSaveToGallery) ? saveToGallery : share;
    SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:downloadAction showProgress:SCINotificationIsEnabled(identifier)];
    delegate.notificationIdentifier = identifier;
    delegate.pendingGallerySaveMetadata = SCIAudioMetadataFromItem(item, metadata);

    NSString *scheme = item.url.scheme.lowercaseString;
    if (!item.url.isFileURL && ![@[@"http", @"https"] containsObject:scheme]) {
        [delegate beginCustomProgressWithTitle:@"Downloading audio" subtitle:nil];
        [delegate showCustomErrorWithTitle:@"Audio download failed"
                                  subtitle:@"Instagram exposed an unsupported audio URL. Refresh the thread and try again."];
        return;
    }

    if (!SCIAudioShouldConvertURL(item.url, convert)) {
        [delegate downloadFileWithURL:item.url fileExtension:[item preferredFileExtension] hudLabel:nil];
        return;
    }

    [delegate beginCustomProgressWithTitle:@"Downloading audio" subtitle:nil];
    __block NSURLSessionDownloadTask *task = nil;
    __block NSURLSession *session = nil;
    __weak SCIDownloadDelegate *weakDelegate = delegate;
    delegate.customCancelHandler = ^{
        [task cancel];
        [session invalidateAndCancel];
    };

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    session = [NSURLSession sessionWithConfiguration:configuration];
    task = [session downloadTaskWithURL:item.url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        (void)response;
        __block NSURL *movedTempURL = nil;
        __block NSError *moveError = nil;
        if (location && !error) {
            NSString *ext = item.url.pathExtension.length > 0 ? item.url.pathExtension : @"m4a";
            movedTempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-raw.%@", SCIAudioBasename(item), ext]]];
            [[NSFileManager defaultManager] removeItemAtURL:movedTempURL error:nil];
            if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:movedTempURL error:&moveError]) {
                movedTempURL = nil;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !movedTempURL) {
                [weakDelegate showCustomErrorWithTitle:@"Audio download failed" subtitle:error.localizedDescription ?: moveError.localizedDescription ?: @"Refresh the source and try again if the URL expired."];
                return;
            }
            [weakDelegate updateCustomProgress:0.75f title:@"Converting audio" subtitle:nil];
            SCIAudioConvertToM4A(movedTempURL, SCIAudioBasename(item), ^(float progress, NSString *title) {
                [weakDelegate updateCustomProgress:0.75f + progress * 0.2f title:title subtitle:nil];
            }, ^(NSURL *outputURL, NSError *convertError) {
                if (!outputURL || convertError) {
                    [weakDelegate showCustomErrorWithTitle:@"Audio conversion failed" subtitle:convertError.localizedDescription];
                    return;
                }
                [weakDelegate finishWithLocalFileURL:outputURL];
            });
        });
    }];
    [task resume];
}

@end

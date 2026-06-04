#import "SCIAudioDownloadCoordinator.h"

#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "../Downloads/SCIDownloadHelpers.h"
#import "../Downloads/SCIDownloadRequest.h"
#import "../Downloads/SCIDownloadService.h"
#import "../Downloads/SCIDownloadTypes.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../MediaDownload/SCIDashParser.h"
#import "../MediaDownload/SCIMediaFFmpeg.h"
#import "../MediaPreview/SCIFullScreenMediaPlayer.h"
#import "../MediaPreview/SCIMediaItem.h"
#import "../UI/SCINotificationCenter.h"

static id SCIAudioObjectForSelector(id target, NSString *selectorName) {
  if (!target || selectorName.length == 0)
    return nil;
  SEL selector = NSSelectorFromString(selectorName);
  if (![target respondsToSelector:selector])
    return nil;
  @try {
    return ((id(*)(id, SEL))objc_msgSend)(target, selector);
  } @catch (__unused NSException *exception) {
    return nil;
  }
}

static id SCIAudioKVCObject(id target, NSString *key) {
  if (!target || key.length == 0)
    return nil;
  @try {
    return [target valueForKey:key];
  } @catch (__unused NSException *exception) {
    return nil;
  }
}

static id SCIAudioFieldCacheValue(id object, NSString *key) {
  if (!object || key.length == 0)
    return nil;
  Ivar fieldCacheIvar = NULL;
  for (Class cls = [object class]; cls && !fieldCacheIvar;
       cls = class_getSuperclass(cls)) {
    fieldCacheIvar = class_getInstanceVariable(cls, "_fieldCache");
  }
  if (!fieldCacheIvar)
    return nil;
  id fieldCache = nil;
  @try {
    fieldCache = object_getIvar(object, fieldCacheIvar);
  } @catch (__unused NSException *exception) {
    fieldCache = nil;
  }
  if (![fieldCache isKindOfClass:NSDictionary.class])
    return nil;
  return ((NSDictionary *)fieldCache)[key];
}

static id SCIAudioIvarValue(id target, const char *name) {
  if (!target || !name)
    return nil;
  @try {
    for (Class cls = [target class]; cls && cls != NSObject.class;
         cls = class_getSuperclass(cls)) {
      Ivar ivar = class_getInstanceVariable(cls, name);
      if (!ivar)
        continue;
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
  if ([value isKindOfClass:NSString.class])
    return [(NSString *)value length] > 0 ? value : nil;
  if ([value respondsToSelector:@selector(stringValue)]) {
    NSString *string = [value stringValue];
    return string.length > 0 ? string : nil;
  }
  return nil;
}

static NSURL *SCIAudioURLFromValue(id value) {
  if ([value isKindOfClass:NSURL.class]) {
    NSURL *url = value;
    if (url.scheme.length > 0 || url.isFileURL)
      return url;
    return nil;
  }
  NSString *string = SCIAudioStringValue(value);
  if (string.length == 0)
    return nil;

  NSString *trimmed = [string
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0)
    return nil;
  if ([trimmed hasPrefix:@"//"]) {
    trimmed = [@"https:" stringByAppendingString:trimmed];
  }

  NSURL *url = [NSURL URLWithString:trimmed];
  if (!url && ![trimmed containsString:@"://"]) {
    url = [NSURL fileURLWithPath:trimmed];
  }
  if (!url.scheme.length && !url.isFileURL)
    return nil;
  NSString *scheme = url.scheme.lowercaseString;
  if (scheme.length > 0 &&
      ![@[ @"http", @"https", @"file" ] containsObject:scheme])
    return nil;
  return url;
}

static NSURL *SCIAudioURLFromCollectionValue(id collection) {
  if (!collection)
    return nil;
  if ([collection isKindOfClass:NSURL.class] ||
      [collection isKindOfClass:NSString.class]) {
    return SCIAudioURLFromValue(collection);
  }

  NSArray *items = nil;
  if ([collection isKindOfClass:NSArray.class]) {
    items = collection;
  } else if ([collection isKindOfClass:NSSet.class]) {
    items = [(NSSet *)collection allObjects];
  } else if ([collection isKindOfClass:NSDictionary.class]) {
    NSDictionary *dict = collection;
    NSURL *direct = SCIAudioURLFromValue(dict[@"url"] ?: dict[@"src"] ?: dict[@"uri"]);
    if (direct)
      return direct;
    id candidates = dict[@"candidates"] ?: dict[@"items"] ?: dict[@"urls"];
    if ([candidates isKindOfClass:NSArray.class] ||
        [candidates isKindOfClass:NSSet.class]) {
      return SCIAudioURLFromCollectionValue(candidates);
    }
    return nil;
  }

  for (id item in items ?: @[]) {
    NSURL *url = nil;
    if ([item isKindOfClass:NSDictionary.class]) {
      NSDictionary *dict = item;
      url = SCIAudioURLFromValue(dict[@"url"] ?: dict[@"src"] ?: dict[@"uri"]);
    } else {
      url = SCIAudioURLFromValue(SCIAudioObjectForSelector(item, @"url")
                                     ?: SCIAudioKVCObject(item, @"url"));
      if (!url)
        url =
            SCIAudioURLFromValue(SCIAudioObjectForSelector(item, @"urlString")
                                     ?: SCIAudioKVCObject(item, @"urlString"));
      if (!url)
        url = SCIAudioURLFromValue(item);
    }
    if (url)
      return url;
  }
  return nil;
}

static NSURL *SCIAudioURLForNames(id object, NSArray<NSString *> *names) {
  for (NSString *name in names) {
    NSURL *url = SCIAudioURLFromValue(SCIAudioObjectForSelector(object, name));
    if (!url)
      url = SCIAudioURLFromValue(SCIAudioKVCObject(object, name));
    if (url)
      return url;
  }
  return nil;
}

static NSURL *SCIAudioCollectionURLForNames(id object,
                                            NSArray<NSString *> *names) {
  for (NSString *name in names) {
    NSURL *url =
        SCIAudioURLFromCollectionValue(SCIAudioObjectForSelector(object, name));
    if (!url)
      url = SCIAudioURLFromCollectionValue(SCIAudioKVCObject(object, name));
    if (url)
      return url;
  }
  return nil;
}

static NSString *SCIAudioManifestString(id value) {
  if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 10)
    return value;
  if ([value isKindOfClass:NSData.class] && [(NSData *)value length] > 10) {
    NSString *string = [[NSString alloc] initWithData:value
                                             encoding:NSUTF8StringEncoding];
    return string.length > 10 ? string : nil;
  }
  return nil;
}

static NSURL *SCIAudioURLFromDashManifest(NSString *manifest) {
  NSArray<SCIDashRepresentation *> *representations =
      [SCIDashParser parseManifest:manifest ?: @""];
  SCIDashRepresentation *best = nil;
  for (SCIDashRepresentation *rep in representations) {
    if (![rep.contentType.lowercaseString containsString:@"audio"] || !rep.url)
      continue;
    if (!best || rep.bandwidth > best.bandwidth)
      best = rep;
  }
  return best.url;
}

static NSURL *SCIAudioDashAudioURLFromObject(id object) {
  for (NSString *name in @[
         @"dashManifestData", @"videoDashManifest", @"dashManifest",
         @"audioDashManifest"
       ]) {
    NSString *manifest =
        SCIAudioManifestString(SCIAudioObjectForSelector(object, name));
    if (!manifest)
      manifest = SCIAudioManifestString(SCIAudioKVCObject(object, name));
    NSURL *url = SCIAudioURLFromDashManifest(manifest);
    if (url)
      return url;
  }

  for (NSString *key in
       @[ @"dash_manifest", @"video_dash_manifest", @"audio_dash_manifest" ]) {
    NSURL *url = SCIAudioURLFromDashManifest(
        SCIAudioManifestString(SCIAudioFieldCacheValue(object, key)));
    if (url)
      return url;
  }

  id ivarValue = SCIAudioIvarValue(object, "_dashManifestData");
  return SCIAudioURLFromDashManifest(SCIAudioManifestString(ivarValue));
}

static BOOL SCIAudioObjectLooksAudioLike(id object) {
  if (!object)
    return NO;
  NSString *className = NSStringFromClass([object class]);
  return [className containsString:@"Audio"] ||
         [className containsString:@"Music"] ||
         [className containsString:@"Sound"] ||
         [className containsString:@"Track"];
}

static BOOL SCIAudioKeyLooksAudioLike(NSString *key) {
  NSString *lower = key.lowercaseString;
  return [lower containsString:@"audio"] || [lower containsString:@"music"] ||
         [lower containsString:@"sound"] || [lower containsString:@"track"] ||
         [lower containsString:@"dash"] || [lower containsString:@"manifest"];
}

static BOOL SCIAudioKeyLooksGenericURLLike(NSString *key) {
  NSString *lower = key.lowercaseString;
  return [lower containsString:@"url"] || [lower containsString:@"uri"] ||
         [lower containsString:@"download"] ||
         [lower containsString:@"progressive"];
}

static BOOL SCIAudioDictionaryLooksAudioLike(NSDictionary *dict) {
  for (id key in dict.allKeys) {
    if ([key isKindOfClass:NSString.class] &&
        SCIAudioKeyLooksAudioLike((NSString *)key)) {
      return YES;
    }
  }
  return NO;
}

static BOOL SCIAudioBoolValue(id value) {
  if (!value)
    return NO;
  if ([value respondsToSelector:@selector(boolValue)])
    return [value boolValue];
  return NO;
}

static NSURL *SCIAudioBestVideoURLFromVersions(id versions) {
  NSArray *items = nil;
  if ([versions isKindOfClass:NSArray.class]) {
    items = versions;
  } else if ([versions isKindOfClass:NSDictionary.class]) {
    id candidates = ((NSDictionary *)versions)[@"candidates"]
                        ?: ((NSDictionary *)versions)[@"items"];
    if ([candidates isKindOfClass:NSArray.class])
      items = candidates;
  }

  NSURL *bestURL = nil;
  NSInteger bestArea = -1;
  for (id item in items ?: @[]) {
    id urlValue = nil;
    NSInteger width = 0;
    NSInteger height = 0;
    if ([item isKindOfClass:NSDictionary.class]) {
      NSDictionary *dict = item;
      urlValue = dict[@"url"] ?: dict[@"src"];
      width = [dict[@"width"] integerValue];
      height = [dict[@"height"] integerValue];
    } else {
      urlValue = SCIAudioObjectForSelector(item, @"url")
                     ?: SCIAudioKVCObject(item, @"url");
      id widthValue = SCIAudioObjectForSelector(item, @"width")
                          ?: SCIAudioKVCObject(item, @"width");
      id heightValue = SCIAudioObjectForSelector(item, @"height")
                           ?: SCIAudioKVCObject(item, @"height");
      width = [widthValue integerValue];
      height = [heightValue integerValue];
    }
    NSURL *url = SCIAudioURLFromValue(urlValue);
    if (!url)
      continue;
    NSInteger area = width * height;
    if (!bestURL || area > bestArea) {
      bestURL = url;
      bestArea = area;
    }
  }
  return bestURL;
}

static BOOL SCIAudioMediaHasAudio(id object, NSMutableSet<NSValue *> *visited,
                                  NSUInteger depth) {
  if (!object || depth > 4)
    return NO;
  NSValue *identity = [NSValue valueWithNonretainedObject:object];
  if ([visited containsObject:identity])
    return NO;
  [visited addObject:identity];

  if ([object isKindOfClass:NSDictionary.class]) {
    NSDictionary *dict = object;
    for (NSString *key in @[
           @"has_audio", @"hasAudio", @"audio_enabled", @"contains_audio",
           @"audio_detected", @"is_audio_detected", @"audio_available",
           @"is_audio_available", @"has_original_audio"
         ]) {
      if (SCIAudioBoolValue(dict[key]))
        return YES;
    }
    for (id value in dict.allValues) {
      if (SCIAudioMediaHasAudio(value, visited, depth + 1))
        return YES;
    }
    return NO;
  }
  if ([object isKindOfClass:NSArray.class] ||
      [object isKindOfClass:NSSet.class]) {
    for (id value in object) {
      if (SCIAudioMediaHasAudio(value, visited, depth + 1))
        return YES;
    }
    return NO;
  }

  for (NSString *name in @[
         @"hasAudio", @"audioEnabled", @"containsAudio", @"isAudioDetected",
         @"audioDetected", @"isAudioAvailable", @"audioAvailable",
         @"hasOriginalAudio"
       ]) {
    id value = SCIAudioObjectForSelector(object, name)
                   ?: SCIAudioKVCObject(object, name);
    if (SCIAudioBoolValue(value))
      return YES;
  }

  for (NSString *key in @[
         @"has_audio", @"audio_enabled", @"contains_audio", @"audio_detected",
         @"is_audio_detected", @"audio_available", @"is_audio_available",
         @"has_original_audio"
       ]) {
    if (SCIAudioBoolValue(SCIAudioFieldCacheValue(object, key)))
      return YES;
  }

  for (NSString *name in @[
         @"media", @"item", @"video", @"rawVideo", @"clipsMedia", @"clipsItem",
         @"post", @"clipsMetadata", @"musicInfo", @"musicMetadata",
         @"originalAudio", @"originalAudioInfo", @"originalSoundInfo",
         @"audioTrack"
       ]) {
    id nested = SCIAudioObjectForSelector(object, name)
                    ?: SCIAudioKVCObject(object, name);
    if (nested && nested != object &&
        SCIAudioMediaHasAudio(nested, visited, depth + 1))
      return YES;
  }
  for (NSString *key in @[
         @"clips_metadata", @"music_info", @"music_metadata", @"original_audio",
         @"original_audio_info", @"original_sound_info", @"audio",
         @"audio_track", @"video"
       ]) {
    id nested = SCIAudioFieldCacheValue(object, key);
    if (nested && nested != object &&
        SCIAudioMediaHasAudio(nested, visited, depth + 1))
      return YES;
  }
  return NO;
}

static NSURL *SCIAudioVideoURLFromObject(id object,
                                         NSMutableSet<NSValue *> *visited,
                                         NSUInteger depth) {
  if (!object || depth > 4)
    return nil;
  NSValue *identity = [NSValue valueWithNonretainedObject:object];
  if ([visited containsObject:identity])
    return nil;
  [visited addObject:identity];

  if ([object isKindOfClass:NSDictionary.class]) {
    NSDictionary *dict = object;
    NSURL *direct = SCIAudioURLFromValue(dict[@"video_url"] ?: dict[@"videoURL"] ?: dict[@"url"]);
    if (direct)
      return direct;
    NSURL *versionURL = SCIAudioBestVideoURLFromVersions(
        dict[@"video_versions"] ?: dict[@"videoVersions"]);
    if (versionURL)
      return versionURL;
    for (id value in dict.allValues) {
      NSURL *url = SCIAudioVideoURLFromObject(value, visited, depth + 1);
      if (url)
        return url;
    }
    return nil;
  }
  if ([object isKindOfClass:NSArray.class] ||
      [object isKindOfClass:NSSet.class]) {
    for (id value in object) {
      NSURL *url = SCIAudioVideoURLFromObject(value, visited, depth + 1);
      if (url)
        return url;
    }
    return nil;
  }

  NSURL *mediaVideoURL = [SCIUtils getVideoUrlForMedia:object];
  if (mediaVideoURL)
    return mediaVideoURL;

  NSURL *direct = SCIAudioURLForNames(object, @[
    @"videoURL", @"videoUrl", @"playableURL", @"playableUrl",
    @"progressiveDownloadURL"
  ]);
  if (direct)
    return direct;

  NSURL *fieldCacheURL = SCIAudioBestVideoURLFromVersions(
      SCIAudioFieldCacheValue(object, @"video_versions"));
  if (fieldCacheURL)
    return fieldCacheURL;

  for (NSString *name in @[
         @"media", @"item", @"video", @"rawVideo", @"clipsMedia", @"clipsItem",
         @"post", @"clipsMetadata"
       ]) {
    id nested = SCIAudioObjectForSelector(object, name)
                    ?: SCIAudioKVCObject(object, name);
    if (nested && nested != object) {
      NSURL *url = SCIAudioVideoURLFromObject(nested, visited, depth + 1);
      if (url)
        return url;
    }
  }
  for (NSString *key in @[ @"video", @"video_versions", @"clips_metadata" ]) {
    id nested = SCIAudioFieldCacheValue(object, key);
    if (nested && nested != object) {
      NSURL *url = SCIAudioVideoURLFromObject(nested, visited, depth + 1);
      if (url)
        return url;
    }
  }
  return nil;
}

static NSURL *SCIAudioFallbackVideoURLFromMediaObject(id mediaObject) {
  if (!SCIAudioMediaHasAudio(mediaObject, [NSMutableSet set], 0))
    return nil;
  return SCIAudioVideoURLFromObject(mediaObject, [NSMutableSet set], 0);
}

static BOOL SCIAudioShouldTraverseObject(id object) {
  if (!object)
    return NO;
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
  return [name containsString:@"Direct"] || [name containsString:@"Audio"] ||
         [name containsString:@"Message"] || [name containsString:@"Media"] ||
         [name containsString:@"GraphQL"] || [name containsString:@"GQL"] ||
         [name containsString:@"Model"];
}

static NSURL *SCIAudioBestURLFromObject(id mediaObject,
                                        NSMutableSet<NSValue *> *visited,
                                        NSUInteger depth) {
  if (!mediaObject || depth > 5)
    return nil;
  if ([mediaObject isKindOfClass:NSURL.class] ||
      [mediaObject isKindOfClass:NSString.class]) {
    return depth == 0 ? SCIAudioURLFromValue(mediaObject) : nil;
  }

  NSValue *identity = [NSValue valueWithNonretainedObject:mediaObject];
  if ([visited containsObject:identity])
    return nil;
  [visited addObject:identity];

  NSURL *direct = SCIAudioURLForNames(mediaObject, @[
    @"audioFileUrl", @"audioFileURL", @"playableAudioURL", @"audioURL",
    @"audioUrl", @"progressiveDownloadURL", @"progressiveDownloadUrl",
    @"progressiveAudioURL", @"progressiveAudioUrl", @"_progressiveAudioUrl",
    @"audioSrc"
  ]);
  if (direct)
    return direct;

  NSURL *collectionURL = SCIAudioCollectionURLForNames(mediaObject, @[
    @"_audioUrls", @"audioUrls", @"audioURLs", @"allAudioURLs",
    @"_allDashAudioURLs", @"allDashAudioURLs", @"sortedAudioURLsBySize"
  ]);
  if (collectionURL)
    return collectionURL;

  NSURL *dashAudioURL = SCIAudioDashAudioURLFromObject(mediaObject);
  if (dashAudioURL)
    return dashAudioURL;

  if (SCIAudioObjectLooksAudioLike(mediaObject)) {
    NSURL *genericAudioURL = SCIAudioURLForNames(
        mediaObject,
        @[ @"mediaUrl", @"mediaURL", @"downloadUrl", @"downloadURL", @"url" ]);
    if (genericAudioURL)
      return genericAudioURL;
  }

  if ([mediaObject isKindOfClass:NSDictionary.class]) {
    NSDictionary *dict = (NSDictionary *)mediaObject;
    NSURL *direct = SCIAudioURLFromValue(dict[@"audioFileUrl"] ?: dict[@"audioFileURL"] ?: dict[@"playableAudioURL"] ?: dict[@"audioURL"] ?: dict[@"audioUrl"] ?: dict[@"progressiveAudioURL"] ?: dict[@"progressiveAudioUrl"] ?: dict[@"progressiveDownloadURL"] ?: dict[@"progressiveDownloadUrl"]);
    if (direct)
      return direct;
    if (!SCIAudioDictionaryLooksAudioLike(dict))
      return nil;
    for (id value in dict.allValues) {
      NSURL *url = SCIAudioBestURLFromObject(value, visited, depth + 1);
      if (url)
        return url;
    }
  } else if ([mediaObject isKindOfClass:NSArray.class] ||
             [mediaObject isKindOfClass:NSSet.class]) {
    for (id value in mediaObject) {
      NSURL *url = SCIAudioBestURLFromObject(value, visited, depth + 1);
      if (url)
        return url;
    }
  }

  for (NSString *name in @[
         @"audio",
         @"audioAsset",
         @"music",
         @"originalAudio",
         @"originalAudioInfo",
         @"clipsAudio",
         @"sound",
         @"musicInfo",
         @"musicMetadata",
         @"originalSoundInfo",
         @"audioTrack",
         @"sundialMusicAsset",
         @"sundialOriginalAudioAsset",
         @"videoURLProvider",
         @"asMusicInfoFragment",
         @"musicAssetInfo",
         @"musicConsumptionInfo",
         @"media",
         @"item",
         @"viewModel",
         @"message",
         @"messageCellViewModel",
         @"audioMessageViewModel",
         @"messageMetadata"
       ]) {
    id nested = SCIAudioObjectForSelector(mediaObject, name)
                    ?: SCIAudioKVCObject(mediaObject, name);
    if (nested && nested != mediaObject) {
      NSURL *url = SCIAudioKeyLooksAudioLike(name)
                       ? (SCIAudioURLFromValue(nested)
                              ?: SCIAudioURLFromCollectionValue(nested))
                       : nil;
      if (!url)
        url = SCIAudioBestURLFromObject(nested, visited, depth + 1);
      if (url)
        return url;
    }
  }

  for (NSString *key in @[
         @"audio", @"audio_asset", @"music", @"music_info", @"music_metadata",
         @"music_asset_info", @"audio_asset_info", @"clips_audio",
         @"clips_metadata", @"original_audio", @"original_audio_info",
         @"original_sound_info", @"audio_track"
       ]) {
    id nested = SCIAudioFieldCacheValue(mediaObject, key);
    if (nested && nested != mediaObject) {
      NSURL *url = SCIAudioURLFromValue(nested)
                       ?: SCIAudioBestURLFromObject(nested, visited, depth + 1);
      if (url)
        return url;
    }
  }

  if (SCIAudioShouldTraverseObject(mediaObject)) {
    for (Class cls = [mediaObject class]; cls && cls != NSObject.class;
         cls = class_getSuperclass(cls)) {
      unsigned int count = 0;
      Ivar *ivars = class_copyIvarList(cls, &count);
      for (unsigned int i = 0; i < count; i++) {
        Ivar ivar = ivars[i];
        const char *encoding = ivar_getTypeEncoding(ivar);
        if (!encoding || encoding[0] != '@')
          continue;
        id value = nil;
        @try {
          value = object_getIvar(mediaObject, ivar);
        } @catch (__unused NSException *exception) {
          value = nil;
        }

        NSString *ivarName =
            [NSString stringWithUTF8String:ivar_getName(ivar) ?: ""];
        BOOL ivarIsAudioURL = SCIAudioKeyLooksAudioLike(ivarName) ||
                              (SCIAudioObjectLooksAudioLike(mediaObject) &&
                               SCIAudioKeyLooksGenericURLLike(ivarName));
        NSURL *url = ivarIsAudioURL
                         ? (SCIAudioURLFromValue(value)
                                ?: SCIAudioURLFromCollectionValue(value))
                         : nil;
        if (!url)
          url = SCIAudioBestURLFromObject(value, visited, depth + 1);
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
  for (NSString *name in @[
         @"duration", @"durationSeconds", @"audioDuration",
         @"audioDurationSeconds", @"videoDuration"
       ]) {
    id value = SCIAudioObjectForSelector(object, name)
                   ?: SCIAudioKVCObject(object, name);
    if ([value respondsToSelector:@selector(doubleValue)] &&
        [value doubleValue] > 0.0) {
      return [value doubleValue];
    }
  }
  return 0.0;
}

static SCIGallerySaveMetadata *
SCIAudioMetadataFromItem(SCIAudioItem *item, SCIGallerySaveMetadata *metadata) {
  SCIGallerySaveMetadata *resolved =
      metadata ?: [[SCIGallerySaveMetadata alloc] init];
  resolved.source = (int16_t)[item gallerySource];
  if (!resolved.sourceUsername.length) {
    resolved.sourceUsername = item.artist.length > 0 ? item.artist : @"audio";
  }
  if (!resolved.sourceMediaPK.length) {
    resolved.sourceMediaPK = item.mediaIdentifier;
  }
  if (!resolved.sourceMediaURLString.length) {
    resolved.sourceMediaURLString =
        item.sourceURLString ?: item.url.absoluteString;
  }
  if (!resolved.customName.length && item.title.length > 0) {
    resolved.customName = item.title;
  }
  if (resolved.durationSeconds <= 0.05) {
    resolved.durationSeconds = item.duration;
  }
  return resolved;
}

static NSString *SCIAudioNotificationIdentifier(NSString *provided,
                                                SCIAudioAction action) {
  if (provided.length > 0)
    return provided;
  switch (action) {
  case SCIAudioActionSaveToGallery:
  case SCIAudioActionConvertAndSaveToGallery:
    return kSCINotificationDownloadGallery;
  case SCIAudioActionCopyURL:
    return kSCINotificationDownloadShare;
  case SCIAudioActionSaveToFiles:
    return kSCINotificationDownloadAudio;
  case SCIAudioActionShare:
  case SCIAudioActionConvertAndShare:
  case SCIAudioActionPlay:
  default:
    return kSCINotificationDownloadShare;
  }
}

static void SCIAudioConvertToM4A(NSURL *sourceURL, NSString *basename,
                                 void (^progress)(float, NSString *),
                                 void (^completion)(NSURL *, NSError *)) {
  NSString *safeBase = basename.length > 0 ? basename : NSUUID.UUID.UUIDString;
  NSURL *outputURL = [NSURL
      fileURLWithPath:[NSTemporaryDirectory()
                          stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"%@.m4a", safeBase]]];
  [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];

  void (^runFFmpegFallback)(NSError *) = ^(NSError *avError) {
    if (![SCIMediaFFmpeg isAvailable]) {
      if (completion)
        completion(
            nil,
            avError
                ?: [SCIUtils errorWithDescription:@"Audio conversion failed"]);
      return;
    }
    if (progress)
      progress(0.1f, @"Finalizing audio");
    [SCIMediaFFmpeg extractAudioFileURL:sourceURL
        preferredBasename:safeBase
        progress:^(double ffmpegProgress, NSString *stage) {
          if (progress)
            progress(0.1f + (float)(ffmpegProgress * 0.85),
                     stage.length > 0 ? stage : @"Finalizing audio");
        }
        completion:^(NSURL *_Nullable ffmpegURL,
                     NSError *_Nullable ffmpegError) {
          if (ffmpegURL && !ffmpegError) {
            if (completion)
              completion(ffmpegURL, nil);
            return;
          }
          if (completion)
            completion(nil, ffmpegError ?: avError ?: [SCIUtils errorWithDescription:@"Audio conversion failed"]);
        }
        cancelOut:nil];
  };

  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
  AVAssetExportSession *export =
      [[AVAssetExportSession alloc] initWithAsset:asset
                                       presetName:AVAssetExportPresetAppleM4A];
  if (!export) {
    runFFmpegFallback(
        [SCIUtils errorWithDescription:
                      @"Audio conversion is not available for this file"]);
    return;
  }
  export.outputURL = outputURL;
  export.outputFileType = AVFileTypeAppleM4A;
  export.shouldOptimizeForNetworkUse = YES;
  if (progress)
    progress(0.05f, @"Converting audio");
  [export exportAsynchronouslyWithCompletionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      if (export.status == AVAssetExportSessionStatusCompleted &&
          [[NSFileManager defaultManager] fileExistsAtPath:outputURL.path]) {
        if (completion)
          completion(outputURL, nil);
        return;
      }
      NSError *error =
          export.error
              ?: [SCIUtils errorWithDescription:@"Audio conversion failed"];
      runFFmpegFallback(error);
    });
  }];
}

static BOOL SCIAudioShouldConvertURL(NSURL *url, BOOL explicitConvert) {
  if (explicitConvert)
    return YES;
  NSString *ext = url.pathExtension.lowercaseString;
  if (ext.length == 0)
    return YES;
  return ![@[ @"m4a", @"mp3", @"aac", @"caf", @"wav" ] containsObject:ext];
}

static NSString *SCIAudioBasename(SCIAudioItem *item) {
  NSString *identifier = item.mediaIdentifier.length > 0
                             ? item.mediaIdentifier
                             : NSUUID.UUID.UUIDString;
  return [NSString stringWithFormat:@"scinsta_audio_%@", identifier];
}

static void SCIAudioPresentSaveToFiles(NSURL *fileURL,
                                       UIViewController *presenter,
                                       UIView *sourceView,
                                       NSString *identifier) {
  if (!fileURL.isFileURL)
    return;
  UIViewController *controller = presenter ?: topMostController();
  if (!controller) {
    SCINotify(identifier, @"Could not open Files", nil, @"error_filled",
              SCINotificationToneError);
    return;
  }

  UIDocumentPickerViewController *picker =
      [[UIDocumentPickerViewController alloc] initForExportingURLs:@[ fileURL ]
                                                            asCopy:YES];
  picker.modalPresentationStyle = UIModalPresentationFormSheet;
  if (sourceView) {
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
  }
  [controller presentViewController:picker animated:YES completion:nil];
}

static void SCIAudioDownloadForSaveToFiles(SCIAudioItem *item, BOOL convert,
                                           UIViewController *presenter,
                                           UIView *sourceView,
                                           NSString *identifier) {
  BOOL showProgress = SCINotificationIsEnabled(identifier);
  __block SCINotificationPillView *pill =
      showProgress ? SCINotifyProgress(identifier, @"Downloading audio", nil)
                   : nil;

  void (^finishWithError)(NSString *, NSString *) =
      ^(NSString *title, NSString *subtitle) {
        if (pill) {
          [pill showErrorWithTitle:title subtitle:subtitle icon:nil];
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                       (int64_t)(SCINotificationPillDuration() *
                                                 NSEC_PER_SEC)),
                         dispatch_get_main_queue(), ^{
                           [pill dismiss];
                         });
        } else {
          SCINotify(identifier, title, subtitle, @"error_filled",
                    SCINotificationToneError);
        }
      };

  void (^presentFile)(NSURL *) = ^(NSURL *fileURL) {
    if (pill)
      [pill dismiss];
    SCIAudioPresentSaveToFiles(fileURL, presenter, sourceView, identifier);
  };

  void (^processDownloadedFile)(NSURL *) = ^(NSURL *sourceURL) {
    if (SCIAudioShouldConvertURL(sourceURL, convert)) {
      if (pill)
        [pill updateProgressTitle:@"Converting audio" subtitle:nil];
      SCIAudioConvertToM4A(
          sourceURL, SCIAudioBasename(item),
          ^(float progress, NSString *title) {
            (void)title;
            if (pill)
              [pill setProgress:0.75f + progress * 0.2f animated:YES];
          },
          ^(NSURL *outputURL, NSError *convertError) {
            if (outputURL)
              presentFile(outputURL);
            else
              finishWithError(@"Audio conversion failed",
                              convertError.localizedDescription
                                  ?: @"Unable to convert audio");
          });
      return;
    }
    presentFile(sourceURL);
  };

  if (item.url.isFileURL) {
    processDownloadedFile(item.url);
    return;
  }

  NSURLSessionConfiguration *configuration =
      [NSURLSessionConfiguration defaultSessionConfiguration];
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
  NSURLSessionDownloadTask *task = [session
      downloadTaskWithURL:item.url
        completionHandler:^(NSURL *location, NSURLResponse *response,
                            NSError *error) {
          (void)response;
          NSURL *movedTempURL = nil;
          NSError *moveError = nil;
          if (location && !error) {
            NSString *ext = item.url.pathExtension.length > 0
                                ? item.url.pathExtension
                                : @"m4a";
            movedTempURL = [NSURL
                fileURLWithPath:[NSTemporaryDirectory()
                                    stringByAppendingPathComponent:
                                        [NSString
                                            stringWithFormat:@"%@-raw.%@",
                                                             SCIAudioBasename(
                                                                 item),
                                                             ext]]];
            [[NSFileManager defaultManager] removeItemAtURL:movedTempURL
                                                      error:nil];
            if (![[NSFileManager defaultManager] moveItemAtURL:location
                                                         toURL:movedTempURL
                                                         error:&moveError]) {
              movedTempURL = nil;
            }
          }
          dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !movedTempURL) {
              finishWithError(@"Audio download failed", error.localizedDescription ?: moveError.localizedDescription ?: @"Refresh the source and try again if the URL expired.");
              return;
            }
            if (pill)
              [pill setProgress:0.7f animated:YES];
            processDownloadedFile(movedTempURL);
          });
        }];
  [task resume];
}

@implementation SCIAudioDownloadCoordinator

+ (NSString *)processingBasenameForAudioItem:(SCIAudioItem *)item {
  return SCIAudioBasename(item);
}

+ (BOOL)shouldConvertAudioURL:(NSURL *)url
              explicitConvert:(BOOL)explicitConvert {
  return SCIAudioShouldConvertURL(url, explicitConvert);
}

+ (void)convertAudioAtURL:(NSURL *)sourceURL
                 basename:(NSString *)basename
                 progress:(void (^)(float, NSString *))progress
               completion:(void (^)(NSURL *, NSError *))completion {
  SCIAudioConvertToM4A(sourceURL, basename, progress, completion);
}

+ (NSURL *)bestAudioURLFromMediaObject:(id)mediaObject {
  if (!mediaObject)
    return nil;
  NSURL *direct = SCIAudioBestURLFromObject(mediaObject, [NSMutableSet set], 0);
  if (direct)
    return direct;

  return SCIAudioURLFromDashManifest(
      [SCIDashParser dashManifestForMedia:mediaObject]);
}

+ (NSURL *)bestAudioDownloadURLFromMediaObject:(id)mediaObject {
  return [self bestAudioURLFromMediaObject:mediaObject]
             ?: SCIAudioFallbackVideoURLFromMediaObject(mediaObject);
}

+ (SCIAudioItem *)audioItemFromMediaObject:(id)mediaObject
                                    source:(SCIAudioSource)source {
  return [self audioItemFromMediaObject:mediaObject
                                 source:source
                     allowVideoFallback:NO];
}

+ (SCIAudioItem *)audioItemFromMediaObject:(id)mediaObject
                                    source:(SCIAudioSource)source
                        allowVideoFallback:(BOOL)allowVideoFallback {
  NSURL *url = [self bestAudioURLFromMediaObject:mediaObject];
  if (!url && allowVideoFallback) {
    url = SCIAudioFallbackVideoURLFromMediaObject(mediaObject);
  }
  if (!url)
    return nil;
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
  [self performAction:action
                        item:item
                   presenter:presenter
                  sourceView:sourceView
                    metadata:metadata
      notificationIdentifier:notificationIdentifier
              playbackSource:SCIFullScreenPlaybackSourceUnknown
               pausePlayback:nil
              resumePlayback:nil];
}

+ (void)performAction:(SCIAudioAction)action
                      item:(SCIAudioItem *)item
                 presenter:(UIViewController *)presenter
                sourceView:(UIView *)sourceView
                  metadata:(SCIGallerySaveMetadata *)metadata
    notificationIdentifier:(NSString *)notificationIdentifier
            playbackSource:(SCIFullScreenPlaybackSource)playbackSource
             pausePlayback:(SCIMediaPreviewPlaybackBlock)pausePlayback
            resumePlayback:(SCIMediaPreviewPlaybackBlock)resumePlayback {
  if (!item.url) {
    SCINotify(SCIAudioNotificationIdentifier(notificationIdentifier, action),
              @"Could not find audio URL", nil, @"error_filled",
              SCINotificationToneError);
    return;
  }

  NSString *identifier =
      SCIAudioNotificationIdentifier(notificationIdentifier, action);
  if (action == SCIAudioActionCopyURL) {
    UIPasteboard.generalPasteboard.string = item.url.absoluteString;
    SCINotify(identifier, @"Copied audio URL", nil, @"copy_filled",
              SCINotificationToneSuccess);
    return;
  }

  if (action == SCIAudioActionPlay) {
    SCIMediaItem *previewItem = [SCIMediaItem itemWithFileURL:item.url];
    previewItem.mediaType = SCIMediaItemTypeAudio;
    previewItem.galleryMetadata = SCIAudioMetadataFromItem(item, metadata);
    previewItem.title = item.title.length > 0 ? item.title : @"Audio";
    [SCIFullScreenMediaPlayer showMediaItems:@[ previewItem ]
                             startingAtIndex:0
                                    metadata:previewItem.galleryMetadata
                              playbackSource:playbackSource
                                  sourceView:sourceView
                                  controller:presenter
                               pausePlayback:pausePlayback
                              resumePlayback:resumePlayback];
    return;
  }

  BOOL saveToFilesAction = (action == SCIAudioActionSaveToFiles);
  BOOL convert = (action == SCIAudioActionConvertAndShare ||
                  action == SCIAudioActionConvertAndSaveToGallery);
  SCIDownloadDestination destination =
      saveToFilesAction ? SCIDownloadDestinationCacheOnly
                        : ((action == SCIAudioActionSaveToGallery ||
                            action == SCIAudioActionConvertAndSaveToGallery)
                               ? SCIDownloadDestinationGallery
                               : SCIDownloadDestinationShare);
  SCIGallerySaveMetadata *resolvedMetadata =
      SCIAudioMetadataFromItem(item, metadata);

  NSString *scheme = item.url.scheme.lowercaseString;
  if (!item.url.isFileURL && ![@[ @"http", @"https" ] containsObject:scheme]) {
    SCINotify(identifier, @"Audio download failed",
              @"Instagram exposed an unsupported audio URL. Refresh the thread "
              @"and try again.",
              @"error_filled", SCINotificationToneError);
    return;
  }

  if (saveToFilesAction) {
    if (item.url.isFileURL && !SCIAudioShouldConvertURL(item.url, convert)) {
      SCIAudioPresentSaveToFiles(item.url, presenter, sourceView, identifier);
      return;
    }
    SCIAudioDownloadForSaveToFiles(item, convert, presenter, sourceView,
                                   identifier);
    return;
  }

  if (!SCIAudioShouldConvertURL(item.url, convert)) {
    if (item.url.isFileURL) {
      [SCIDownloadHelpers
          submitLocalFileURL:item.url
                   extension:[item preferredFileExtension]
                 destination:destination
                    metadata:resolvedMetadata
              notificationID:identifier
                   presenter:presenter
                  anchorView:sourceView
               sourceSurface:SCIDownloadSourceSurfaceAudioPage];
    } else {
      [SCIDownloadHelpers downloadURL:item.url
                                  extension:[item preferredFileExtension]
                                destination:destination
                                   metadata:resolvedMetadata
                             notificationID:identifier
                                  presenter:presenter
                              sourceSurface:SCIDownloadSourceSurfaceAudioPage];
    }
    return;
  }

  SCIDownloadItemRequest *itemRequest =
      [SCIDownloadItemRequest itemWithRemoteURL:item.url
                                      mediaKind:SCIDownloadMediaKindAudio];
  itemRequest.preferredFileExtension = @"m4a";
  itemRequest.metadata = resolvedMetadata;
  itemRequest.requiresAudioConversion = YES;
  itemRequest.audioProcessingBasename =
      [self processingBasenameForAudioItem:item];
  SCIDownloadRequest *request =
      [SCIDownloadRequest requestWithItems:@[ itemRequest ]
                               destination:destination];
  request.metadata = resolvedMetadata;
  request.notificationIdentifier = identifier;
  request.presenter = presenter;
  request.anchorView = sourceView;
  request.sourceSurface = SCIDownloadSourceSurfaceAudioPage;
  request.titleOverride =
      item.title.length > 0 ? item.title : @"Audio download";
  request.presentationMode = SCINotificationIsEnabled(identifier)
                                 ? SCIDownloadPresentationModeQueuePill
                                 : SCIDownloadPresentationModeQuiet;
  [[SCIDownloadService shared] submitRequest:request completion:nil];
}

@end

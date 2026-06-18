#import "SCIDeletedMessagesModels.h"

NSString *SCIDeletedMessageKindToString(SCIDeletedMessageKind kind) {
    switch (kind) {
        case SCIDeletedMessageKindText:    return @"text";
        case SCIDeletedMessageKindPhoto:   return @"photo";
        case SCIDeletedMessageKindVideo:   return @"video";
        case SCIDeletedMessageKindVoice:   return @"voice";
        case SCIDeletedMessageKindGif:     return @"gif";
        case SCIDeletedMessageKindSticker: return @"sticker";
        case SCIDeletedMessageKindShare:   return @"share";
        case SCIDeletedMessageKindLink:    return @"link";
        case SCIDeletedMessageKindAudioShare: return @"audio_share";
        case SCIDeletedMessageKindReaction: return @"reaction";
        case SCIDeletedMessageKindOther:   return @"other";
        case SCIDeletedMessageKindUnknown:
        default:                           return @"unknown";
    }
}

SCIDeletedMessageKind SCIDeletedMessageKindFromString(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return SCIDeletedMessageKindUnknown;
    if ([s isEqualToString:@"text"])    return SCIDeletedMessageKindText;
    if ([s isEqualToString:@"photo"])   return SCIDeletedMessageKindPhoto;
    if ([s isEqualToString:@"video"])   return SCIDeletedMessageKindVideo;
    if ([s isEqualToString:@"voice"])   return SCIDeletedMessageKindVoice;
    if ([s isEqualToString:@"gif"])     return SCIDeletedMessageKindGif;
    if ([s isEqualToString:@"sticker"]) return SCIDeletedMessageKindSticker;
    if ([s isEqualToString:@"share"])   return SCIDeletedMessageKindShare;
    if ([s isEqualToString:@"link"])    return SCIDeletedMessageKindLink;
    if ([s isEqualToString:@"audio_share"]) return SCIDeletedMessageKindAudioShare;
    if ([s isEqualToString:@"reaction"]) return SCIDeletedMessageKindReaction;
    if ([s isEqualToString:@"other"])   return SCIDeletedMessageKindOther;
    return SCIDeletedMessageKindUnknown;
}

NSString *SCIDeletedMessageKindLocalizedName(SCIDeletedMessageKind kind) {
    switch (kind) {
        case SCIDeletedMessageKindText:    return @"Text";
        case SCIDeletedMessageKindPhoto:   return @"Photo";
        case SCIDeletedMessageKindVideo:   return @"Video";
        case SCIDeletedMessageKindVoice:   return @"Voice";
        case SCIDeletedMessageKindGif:     return @"GIF";
        case SCIDeletedMessageKindSticker: return @"Sticker";
        case SCIDeletedMessageKindShare:   return @"Share";
        case SCIDeletedMessageKindLink:    return @"Link";
        case SCIDeletedMessageKindAudioShare: return @"Audio";
        case SCIDeletedMessageKindReaction: return @"Reaction";
        case SCIDeletedMessageKindOther:   return @"Other";
        case SCIDeletedMessageKindUnknown:
        default:                           return @"Unknown";
    }
}

NSString *SCIDeletedMessageKindSymbol(SCIDeletedMessageKind kind) {
    return SCIDeletedMessageKindSymbolFilled(kind, NO);
}

NSString *SCIDeletedMessageKindSymbolFilled(SCIDeletedMessageKind kind, BOOL filled) {
    switch (kind) {
        case SCIDeletedMessageKindText:    return @"message";
        case SCIDeletedMessageKindPhoto:   return filled ? @"photo_filled" : @"photo";
        case SCIDeletedMessageKindVideo:   return filled ? @"video_filled" : @"video";
        case SCIDeletedMessageKindVoice:   return filled ? @"voice_filled" : @"voice";
        case SCIDeletedMessageKindGif:     return filled ? @"gif_filled" : @"gif";
        case SCIDeletedMessageKindSticker: return filled ? @"sticker_filled" : @"sticker";
        case SCIDeletedMessageKindShare:   return @"share";
        case SCIDeletedMessageKindLink:    return @"link";
        case SCIDeletedMessageKindAudioShare: return @"audio";
        case SCIDeletedMessageKindReaction: return @"reactions";
        case SCIDeletedMessageKindOther:   return @"message";
        case SCIDeletedMessageKindUnknown:
        default:                           return @"message";
    }
}

static NSDate *sciDateFromJSON(id v) {
    if ([v isKindOfClass:[NSNumber class]]) return [NSDate dateWithTimeIntervalSince1970:[v doubleValue]];
    return nil;
}
static NSNumber *sciDateToJSON(NSDate *d) {
    return d ? @(d.timeIntervalSince1970) : nil;
}
static NSString *sciStr(id v) {
    return [v isKindOfClass:[NSString class]] ? v : nil;
}
static double sciDouble(id v) {
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : 0;
}

@implementation SCIDeletedMessage

+ (instancetype)messageFromJSONDict:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    SCIDeletedMessage *m = [SCIDeletedMessage new];
    m.viewMode             = -1;
    m.messageId            = sciStr(dict[@"message_id"]);
    m.threadId             = sciStr(dict[@"thread_id"]);
    m.threadTitle          = sciStr(dict[@"thread_title"]);
    m.isGroup              = [dict[@"is_group"] boolValue];
    m.threadPhotoURL       = sciStr(dict[@"thread_photo_url"]);
    m.senderPk             = sciStr(dict[@"sender_pk"]);
    m.senderUsername       = sciStr(dict[@"sender_username"]);
    m.senderFullName       = sciStr(dict[@"sender_full_name"]);
    m.senderProfilePicURL  = sciStr(dict[@"sender_profile_pic_url"]);
    m.sentAt               = sciDateFromJSON(dict[@"sent_at"]);
    m.capturedAt           = sciDateFromJSON(dict[@"captured_at"]);
    m.deletedAt            = sciDateFromJSON(dict[@"deleted_at"]);
    m.kind                 = SCIDeletedMessageKindFromString(sciStr(dict[@"kind"]));
    m.text                 = sciStr(dict[@"text"]);
    m.previewText          = sciStr(dict[@"preview"]);
    m.mediaURL             = sciStr(dict[@"media_url"]);
    m.mediaPath            = sciStr(dict[@"media_path"]);
    m.thumbnailURL         = sciStr(dict[@"thumbnail_url"]);
    m.thumbnailPath        = sciStr(dict[@"thumbnail_path"]);
    m.mediaMimeType        = sciStr(dict[@"media_mime"]);
    if ([dict[@"view_mode"] isKindOfClass:[NSNumber class]]) m.viewMode = [dict[@"view_mode"] integerValue];
    m.stagedMediaPath      = sciStr(dict[@"staged_media_path"]);
    m.stagedThumbnailPath  = sciStr(dict[@"staged_thumbnail_path"]);
    m.mediaURLStaleAt      = sciDateFromJSON(dict[@"media_url_stale_at"]);
    m.durationSeconds      = sciDouble(dict[@"duration"]);
    id wf = dict[@"waveform"];
    if ([wf isKindOfClass:[NSArray class]]) m.waveform = wf;
    m.width                = sciDouble(dict[@"width"]);
    m.height               = sciDouble(dict[@"height"]);
    m.replyToMessageId     = sciStr(dict[@"reply_to_id"]);
    m.reactionEmoji        = sciStr(dict[@"reaction_emoji"]);
    m.reactionTargetPreview = sciStr(dict[@"reaction_target"]);
    if (!m.messageId.length || !m.senderPk.length) return nil;
    return m;
}

- (NSDictionary *)toJSONDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.messageId)            d[@"message_id"]            = self.messageId;
    if (self.threadId)             d[@"thread_id"]             = self.threadId;
    if (self.threadTitle.length)   d[@"thread_title"]          = self.threadTitle;
    if (self.isGroup)              d[@"is_group"]              = @YES;
    if (self.threadPhotoURL.length) d[@"thread_photo_url"]     = self.threadPhotoURL;
    if (self.senderPk)             d[@"sender_pk"]             = self.senderPk;
    if (self.senderUsername)       d[@"sender_username"]       = self.senderUsername;
    if (self.senderFullName)       d[@"sender_full_name"]      = self.senderFullName;
    if (self.senderProfilePicURL)  d[@"sender_profile_pic_url"]= self.senderProfilePicURL;
    if (self.sentAt)               d[@"sent_at"]               = sciDateToJSON(self.sentAt);
    if (self.capturedAt)           d[@"captured_at"]           = sciDateToJSON(self.capturedAt);
    if (self.deletedAt)            d[@"deleted_at"]            = sciDateToJSON(self.deletedAt);
    d[@"kind"]                     = SCIDeletedMessageKindToString(self.kind);
    if (self.text.length)          d[@"text"]                  = self.text;
    if (self.previewText.length)   d[@"preview"]               = self.previewText;
    if (self.mediaURL)             d[@"media_url"]             = self.mediaURL;
    if (self.mediaPath)            d[@"media_path"]            = self.mediaPath;
    if (self.thumbnailURL)         d[@"thumbnail_url"]         = self.thumbnailURL;
    if (self.thumbnailPath)        d[@"thumbnail_path"]        = self.thumbnailPath;
    if (self.mediaMimeType)        d[@"media_mime"]            = self.mediaMimeType;
    if (self.viewMode >= 0)        d[@"view_mode"]             = @(self.viewMode);
    if (self.stagedMediaPath)      d[@"staged_media_path"]     = self.stagedMediaPath;
    if (self.stagedThumbnailPath)  d[@"staged_thumbnail_path"] = self.stagedThumbnailPath;
    if (self.mediaURLStaleAt)      d[@"media_url_stale_at"]    = sciDateToJSON(self.mediaURLStaleAt);
    if (self.durationSeconds > 0)  d[@"duration"]              = @(self.durationSeconds);
    if (self.waveform.count)       d[@"waveform"]              = self.waveform;
    if (self.width > 0)            d[@"width"]                 = @(self.width);
    if (self.height > 0)           d[@"height"]                = @(self.height);
    if (self.replyToMessageId.length) d[@"reply_to_id"]        = self.replyToMessageId;
    if (self.reactionEmoji.length)    d[@"reaction_emoji"]     = self.reactionEmoji;
    if (self.reactionTargetPreview.length) d[@"reaction_target"] = self.reactionTargetPreview;
    return d;
}

@end

@implementation SCIDeletedMessageGroup

- (NSUInteger)count { return self.messages.count; }
- (NSDate *)lastDeletedAt { return self.latest.deletedAt ?: self.latest.capturedAt; }
- (SCIDeletedMessage *)latest { return self.messages.firstObject; }

- (NSString *)displayName {
    if (self.isGroup) {
        if (self.threadTitle.length) return self.threadTitle;
        return @"Group chat";
    }
    if (self.senderUsername.length) return [@"@" stringByAppendingString:self.senderUsername];
    if (self.senderFullName.length) return self.senderFullName;
    return @"Unknown user";
}

- (NSString *)flagKey {
    if (self.isGroup) return self.threadId.length ? [@"thread:" stringByAppendingString:self.threadId] : @"";
    return self.senderPk ?: @"";
}

@end

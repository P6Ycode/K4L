#import "SCIAudioItem.h"

@implementation SCIAudioItem

+ (instancetype)itemWithURL:(NSURL *)url source:(SCIAudioSource)source {
    if (!url.absoluteString.length) return nil;
    SCIAudioItem *item = [[self alloc] init];
    item.url = url;
    item.source = source;
    item.sourceURLString = url.absoluteString;
    return item;
}

- (id)copyWithZone:(NSZone *)zone {
    SCIAudioItem *copy = [[[self class] allocWithZone:zone] init];
    copy.url = self.url;
    copy.dashManifest = [self.dashManifest copy];
    copy.title = [self.title copy];
    copy.artist = [self.artist copy];
    copy.mediaIdentifier = [self.mediaIdentifier copy];
    copy.sourceURLString = [self.sourceURLString copy];
    copy.duration = self.duration;
    copy.bitrate = self.bitrate;
    copy.source = self.source;
    return copy;
}

- (SCIGallerySource)gallerySource {
    switch (self.source) {
        case SCIAudioSourceFeed: return SCIGallerySourceFeed;
        case SCIAudioSourceReels: return SCIGallerySourceReels;
        case SCIAudioSourceStories: return SCIGallerySourceStories;
        case SCIAudioSourceDMs:
        case SCIAudioSourceDMNotes:
            return SCIGallerySourceDMs;
        case SCIAudioSourceAudioPage: return SCIGallerySourceAudioPage;
        case SCIAudioSourceOther:
        default:
            return SCIGallerySourceOther;
    }
}

- (NSString *)preferredFileExtension {
    NSString *ext = self.url.pathExtension.lowercaseString;
    if (ext.length > 0 && ext.length <= 5) return ext;
    return @"m4a";
}

@end

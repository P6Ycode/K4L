#import "SPKMediaItem.h"
#import "../Gallery/SPKGalleryFile.h"
#import "../Gallery/SPKGallerySaveMetadata.h"

@implementation SPKMediaItem

- (instancetype)init {
    if ((self = [super init])) {
        _gallerySaveSource = -1;
    }
    return self;
}

+ (instancetype)itemWithFileURL:(NSURL *)url {
    SPKMediaItem *item = [[SPKMediaItem alloc] init];
    item.fileURL = url;
    item.mediaType = [self mediaTypeForFileExtension:url.pathExtension];
    return item;
}

+ (instancetype)itemWithImage:(UIImage *)image {
    SPKMediaItem *item = [[SPKMediaItem alloc] init];
    item.image = image;
    item.mediaType = SPKMediaItemTypeImage;
    return item;
}

+ (instancetype)itemWithGalleryFile:(SPKGalleryFile *)file {
    SPKMediaItem *item = [[SPKMediaItem alloc] init];
    item.galleryFile = file;
    item.isFromGallery = YES;
    item.fileURL = [file fileURL];
    item.mediaType = (file.mediaType == SPKGalleryMediaTypeAudio) ? SPKMediaItemTypeAudio : ((file.mediaType == SPKGalleryMediaTypeVideo) ? SPKMediaItemTypeVideo : SPKMediaItemTypeImage);
    SPKGallerySaveMetadata *meta = [[SPKGallerySaveMetadata alloc] init];
    meta.source = file.source;
    meta.sourceUsername = file.sourceUsername;
    meta.sourceUserPK = file.sourceUserPK;
    meta.sourceProfileURLString = file.sourceProfileURLString;
    meta.sourceMediaPK = file.sourceMediaPK;
    meta.sourceMediaCode = file.sourceMediaCode;
    meta.sourceMediaURLString = file.sourceMediaURLString;
    item.galleryMetadata = meta;

    UIImage *thumb = [SPKGalleryFile loadThumbnailForFile:file];
    if (thumb) {
        item.thumbnail = thumb;
    }

    return item;
}

+ (SPKMediaItemType)mediaTypeForFileExtension:(NSString *)extension {
    NSString *ext = extension.lowercaseString;
    if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
        [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"] ||
        [ext isEqualToString:@"webm"]) {
        return SPKMediaItemTypeVideo;
    }
    if ([ext isEqualToString:@"m4a"] || [ext isEqualToString:@"aac"] ||
        [ext isEqualToString:@"mp3"] || [ext isEqualToString:@"wav"] ||
        [ext isEqualToString:@"caf"] || [ext isEqualToString:@"flac"] ||
        [ext isEqualToString:@"opus"] || [ext isEqualToString:@"ogg"]) {
        return SPKMediaItemTypeAudio;
    }
    return SPKMediaItemTypeImage;
}

@end

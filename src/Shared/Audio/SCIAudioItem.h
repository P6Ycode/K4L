#import <Foundation/Foundation.h>

#import "../Gallery/SCIGalleryFile.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIAudioSource) {
    SCIAudioSourceAudioPage = 1,
    SCIAudioSourceFeed,
    SCIAudioSourceReels,
    SCIAudioSourceStories,
    SCIAudioSourceDMs,
    SCIAudioSourceDMNotes,
    SCIAudioSourceOther
};

typedef NS_ENUM(NSInteger, SCIAudioAction) {
    SCIAudioActionShare = 1,
    SCIAudioActionSaveToGallery,
    SCIAudioActionSaveToFiles,
    SCIAudioActionCopyURL,
    SCIAudioActionPlay,
    SCIAudioActionConvertAndShare,
    SCIAudioActionConvertAndSaveToGallery
};

@interface SCIAudioItem : NSObject <NSCopying>

@property (nonatomic, strong, nullable) NSURL *url;
@property (nonatomic, copy, nullable) NSString *dashManifest;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *artist;
@property (nonatomic, copy, nullable) NSString *mediaIdentifier;
@property (nonatomic, copy, nullable) NSString *sourceURLString;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic) NSInteger bitrate;
@property (nonatomic) SCIAudioSource source;

+ (nullable instancetype)itemWithURL:(NSURL *)url source:(SCIAudioSource)source;
- (SCIGallerySource)gallerySource;
- (NSString *)preferredFileExtension;

@end

NS_ASSUME_NONNULL_END

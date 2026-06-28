#import "SCIActionDescriptor.h"
#import "ActionButtonCore.h"

@implementation SCIActionDescriptor

+ (instancetype)descriptorWithIdentifier:(NSString *)identifier
                                   title:(NSString *)title
                                iconName:(NSString *)iconName
{
    SCIActionDescriptor *descriptor = [[self alloc] init];
    descriptor.identifier = identifier;
    descriptor.title = title;
    descriptor.iconName = iconName;
    return descriptor;
}

+ (NSArray<SCIActionDescriptor *> *)descriptors {
    static NSArray<SCIActionDescriptor *> *descriptors = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        descriptors = @[
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadLibrary title:@"Save to Photos" iconName:@"download"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadShare title:@"Share" iconName:@"share"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionCopyDownloadLink title:@"Copy Download URL" iconName:@"link"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionCopyMedia title:@"Copy Media" iconName:@"copy"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadGallery title:@"Save to Gallery" iconName:@"media"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionTrimSave title:@"Trim & Save" iconName:@"trim"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadAudio title:@"Save to Files" iconName:@"audio_download"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadAudioShare title:@"Share" iconName:@"share"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadAudioGallery title:@"Save to Gallery" iconName:@"media"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionPlayAudio title:@"Play" iconName:@"play"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionCopyAudioURL title:@"Copy Download URL" iconName:@"link"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadAllLibrary title:@"Save All to Photos" iconName:@"download"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadAllShare title:@"Share All" iconName:@"share"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadAllGallery title:@"Save All to Gallery" iconName:@"media"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadAllClipboard title:@"Copy All Media" iconName:@"copy"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadAllLinks title:@"Copy Download URLs" iconName:@"link"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDownloadAll title:@"Download All"iconName:@"more"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionExpand title:@"Expand" iconName:@"expand"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionViewThumbnail title:@"View Thumbnail" iconName:@"photo_gallery"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionCopyCaption title:@"Copy Caption" iconName:@"caption"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionOpenTopicSettings title:@"Settings" iconName:@"settings"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionDeletedMessagesLog title:@"Deleted Messages" iconName:@"channels"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionRepost title:@"Repost" iconName:@"repost"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionToggleStorySeenUserRule title:@"Toggle Story User Rule" iconName:@"eye"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionToggleProfileStorySeenUserRule title:@"Toggle Story Seen" iconName:@"eye"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionToggleProfileMessagesSeenUserRule title:@"Toggle Messages Seen" iconName:@"eye"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionStoryMentionsSheet title:@"Story Mentions" iconName:@"mention"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionProfileCopyInfo title:@"Copy Info" iconName:@"info"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionProfileCopyID title:@"Copy ID" iconName:@"key"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionProfileCopyUsername title:@"Copy Username" iconName:@"username"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionProfileCopyName title:@"Copy Name" iconName:@"text"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionProfileCopyBio title:@"Copy Bio" iconName:@"caption"],
            [SCIActionDescriptor descriptorWithIdentifier:kSCIActionProfileCopyLink title:@"Copy Profile URL" iconName:@"link"],
            [SCIActionDescriptor descriptorWithIdentifier:@"more" title:@"More" iconName:@"more"],
            [SCIActionDescriptor descriptorWithIdentifier:@"action" title:@"Actions" iconName:@"action"]
        ];
    });
    return descriptors;
}

+ (nullable instancetype)descriptorForIdentifier:(NSString *)identifier {
    for (SCIActionDescriptor *descriptor in [self descriptors]) {
        if ([descriptor.identifier isEqualToString:identifier]) {
            return descriptor;
        }
    }
    return nil;
}

+ (NSArray<SCIActionDescriptor *> *)availableSectionIconDescriptors {
    return @[
        [SCIActionDescriptor descriptorWithIdentifier:@"action" title:@"Actions" iconName:@"action"],
        [SCIActionDescriptor descriptorWithIdentifier:@"copy" title:@"Copy" iconName:@"copy"],
        [SCIActionDescriptor descriptorWithIdentifier:@"key" title:@"Key" iconName:@"key"],
        [SCIActionDescriptor descriptorWithIdentifier:@"caption" title:@"Caption" iconName:@"caption"],
        [SCIActionDescriptor descriptorWithIdentifier:@"download" title:@"Download" iconName:@"download"],
        [SCIActionDescriptor descriptorWithIdentifier:@"share" title:@"Share" iconName:@"share"],
        [SCIActionDescriptor descriptorWithIdentifier:@"link" title:@"Link" iconName:@"link"],
        [SCIActionDescriptor descriptorWithIdentifier:@"media" title:@"Gallery" iconName:@"media"],
        [SCIActionDescriptor descriptorWithIdentifier:@"expand" title:@"Expand" iconName:@"expand"],
        [SCIActionDescriptor descriptorWithIdentifier:@"photo_gallery" title:@"Thumbnail" iconName:@"photo_gallery"],
        [SCIActionDescriptor descriptorWithIdentifier:@"repost" title:@"Repost" iconName:@"repost"],
        [SCIActionDescriptor descriptorWithIdentifier:@"mention" title:@"Mentions" iconName:@"mention"],
        [SCIActionDescriptor descriptorWithIdentifier:@"feed" title:@"Feed" iconName:@"feed"],
        [SCIActionDescriptor descriptorWithIdentifier:@"reels" title:@"Reels" iconName:@"reels"],
        [SCIActionDescriptor descriptorWithIdentifier:@"story" title:@"Stories" iconName:@"story"],
        [SCIActionDescriptor descriptorWithIdentifier:@"messages" title:@"Messages" iconName:@"messages"],
        [SCIActionDescriptor descriptorWithIdentifier:@"profile" title:@"Profile" iconName:@"user_circle"],
        [SCIActionDescriptor descriptorWithIdentifier:@"settings" title:@"Settings" iconName:@"settings"],
        [SCIActionDescriptor descriptorWithIdentifier:@"more" title:@"More" iconName:@"more"]
    ];
}

@end

NSString *SCIActionDescriptorDisplayTitle(NSString *identifier, NSString *topicTitle) {
    if ([identifier isEqualToString:kSCIActionOpenTopicSettings] && topicTitle.length > 0) {
        return [NSString stringWithFormat:@"%@ Settings", topicTitle];
    }
    SCIActionDescriptor *descriptor = [SCIActionDescriptor descriptorForIdentifier:identifier];
    return descriptor.title ?: @"Action";
}

NSString *SCIActionDescriptorIconName(NSString *identifier) {
    SCIActionDescriptor *descriptor = [SCIActionDescriptor descriptorForIdentifier:identifier];
    return descriptor.iconName ?: @"action";
}

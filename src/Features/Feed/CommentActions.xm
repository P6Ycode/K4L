#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../AssetUtils.h"
#import "../../Shared/Downloads/SCIDownloadHelpers.h"
#import "../../Shared/Gallery/SCIGalleryFile.h"
#import "../../Shared/Gallery/SCIGalleryOriginController.h"
#import "../../Shared/Gallery/SCIGallerySaveMetadata.h"
#import "../../Shared/UI/SCINotificationCenter.h"
#import "../../Utils.h"

static NSString * const kSCICommentCopyTextPref = @"general_comments_copy_text";
static NSString * const kSCICommentMediaActionsPref = @"general_comments_media_actions";

static id SCICommentObjectForSelector(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL SCICommentBoolForSelector(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return NO;
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static id SCICommentObjectForIvar(id object, NSString *ivarName) {
    if (!object || ivarName.length == 0) return nil;
    Ivar ivar = class_getInstanceVariable([object class], ivarName.UTF8String);
    return ivar ? object_getIvar(object, ivar) : nil;
}

static NSString *SCICommentStringValue(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSURL.class]) return [(NSURL *)value absoluteString];
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    return nil;
}

static NSString *SCICommentStringForSelector(id object, NSString *selectorName) {
    return SCICommentStringValue(SCICommentObjectForSelector(object, selectorName));
}

static UIImage *SCICommentIcon(NSString *name) {
    return [SCIAssetUtils instagramIconNamed:name pointSize:24.0];
}

static id SCICommentLongPressedComment(id controller) {
    return SCICommentObjectForIvar(controller, @"_longPressedComment");
}

static NSString *SCICommentAttachmentURLString(id comment) {
    id attachment = SCICommentObjectForSelector(comment, @"commentAttachment");
    if (!attachment) attachment = SCICommentObjectForIvar(comment, @"_commentAttachment");
    if (!attachment) return nil;

    NSString *urlString = SCICommentStringForSelector(attachment, @"imageURL");
    if (urlString.length == 0) {
        urlString = SCICommentStringValue(SCICommentObjectForIvar(attachment, @"_image_imageURL"));
    }
    return urlString;
}

static NSString *SCICommentPhotoURLString(id comment) {
    id apiCommentDict = SCICommentObjectForSelector(comment, @"apiCommentDict");
    id mediaCommentInfo = SCICommentObjectForSelector(apiCommentDict, @"mediaCommentInfo");
    id media = SCICommentObjectForSelector(mediaCommentInfo, @"media");
    if (media) {
        NSURL *url = [SCIUtils getPhotoUrlForMedia:media];
        if (!url) {
            id photoObject = SCICommentObjectForSelector(media, @"photo");
            if (photoObject) url = [SCIUtils getPhotoUrl:photoObject];
        }
        if (!url) {
            id imageSpecifier = SCICommentObjectForSelector(media, @"imageSpecifier");
            NSString *specURLString = SCICommentStringForSelector(imageSpecifier, @"url");
            if (specURLString.length > 0) url = [NSURL URLWithString:specURLString];
        }
        if (url) return url.absoluteString;
    }

    return SCICommentAttachmentURLString(comment);
}

static UIImage *SCICommentUserUploadedImage(id comment) {
    id image = SCICommentObjectForSelector(comment, @"userUploadedImage");
    return [image isKindOfClass:[UIImage class]] ? (UIImage *)image : nil;
}

static SCIGallerySaveMetadata *SCICommentMediaMetadata(id comment, NSString *mediaID, NSString *mediaURLString) {
    SCIGallerySaveMetadata *metadata = [[SCIGallerySaveMetadata alloc] init];
    metadata.source = (int16_t)SCIGallerySourceComments;
    metadata.sourceMediaPK = mediaID;
    metadata.sourceMediaURLString = mediaURLString;

    id user = SCICommentObjectForSelector(comment, @"user");
    NSString *username = SCICommentStringForSelector(user, @"username");
    [SCIGalleryOriginController populateProfileMetadata:metadata username:username user:user];
    return metadata;
}

static void SCICommentDownloadMediaURL(NSURL *url, NSString *extension, SCIGallerySaveMetadata *metadata, SCIDownloadDestination destination) {
    if (!url) return;
    [SCIDownloadHelpers downloadURL:url
                                extension:extension
                            destination:destination
                                 metadata:metadata
                         notificationID:kSCINotificationDownloadGallery
                                presenter:nil
                             sourceSurface:SCIDownloadSourceSurfaceComments];
}

static void SCICommentDownloadLocalImage(UIImage *image, SCIGallerySaveMetadata *metadata, SCIDownloadDestination destination) {
    if (!image) return;
    NSString *stagedPath = [SCIDownloadHelpers stageImageForDownload:image];
    if (!stagedPath) return;
    [SCIDownloadHelpers submitLocalFileURL:[NSURL fileURLWithPath:stagedPath]
                                  extension:@"png"
                                destination:destination
                                   metadata:metadata
                             notificationID:kSCINotificationDownloadGallery
                                  presenter:nil
                                 anchorView:nil
                              sourceSurface:SCIDownloadSourceSurfaceComments];
}

static UIAction *SCICommentAction(NSString *title, NSString *iconName, void (^handler)(void)) {
    return [UIAction actionWithTitle:title
                               image:SCICommentIcon(iconName)
                          identifier:nil
                             handler:^(__unused UIAction *action) {
        if (handler) handler();
    }];
}

static NSArray<UIMenuElement *> *SCICommentMediaActionItems(id comment, NSURL *url, NSString *extension, UIImage *localImage, NSString *mediaID, NSString *copyLinkTitle, NSString *linkURLString, NSString *copyLinkToastMessage) {
    SCIGallerySaveMetadata *metadata = SCICommentMediaMetadata(comment, mediaID, url.absoluteString);
    void (^performDownload)(SCIDownloadDestination) = ^(SCIDownloadDestination destination) {
        if (url) {
            SCICommentDownloadMediaURL(url, extension, metadata, destination);
        } else if (localImage) {
            SCICommentDownloadLocalImage(localImage, metadata, destination);
        }
    };

    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    [actions addObject:SCICommentAction(@"Save to Photos", @"download", ^{
        performDownload(SCIDownloadDestinationPhotos);
    })];
    [actions addObject:SCICommentAction(@"Share", @"share", ^{
        performDownload(SCIDownloadDestinationShare);
    })];
    [actions addObject:SCICommentAction(@"Save to Gallery", @"media", ^{
        performDownload(SCIDownloadDestinationGallery);
    })];
    [actions addObject:SCICommentAction(@"Copy", @"copy", ^{
        performDownload(SCIDownloadDestinationClipboard);
    })];

    if (linkURLString.length > 0) {
        [actions addObject:SCICommentAction(copyLinkTitle, @"link", ^{
            UIPasteboard.generalPasteboard.string = linkURLString;
            SCINotify(kSCINotificationCopyGIFLink, copyLinkToastMessage, nil, @"copy_filled", SCINotificationToneSuccess);
        })];
    }

    return actions;
}

static id (*SCIOriginalCommentContextMenu)(id, SEL, id, id, CGPoint);

static id SCICommentContextMenu(id self, SEL _cmd, id collectionView, id indexPath, CGPoint point) {
    UIContextMenuConfiguration *configuration = SCIOriginalCommentContextMenu(self, _cmd, collectionView, indexPath, point);
    if (!configuration) return nil;

    id comment = SCICommentLongPressedComment(self);
    NSString *text = SCICommentStringForSelector(comment, @"text");
    BOOL mediaActionsEnabled = [SCIUtils getBoolPref:kSCICommentMediaActionsPref];

    NSString *gifID = SCICommentStringForSelector(comment, @"gifMediaId");
    NSString *gifURLString = gifID.length > 0 ? SCICommentAttachmentURLString(comment) : nil;
    BOOL offersGIFActions = mediaActionsEnabled && gifURLString.length > 0;

    NSString *photoURLString = nil;
    UIImage *photoLocalImage = nil;
    BOOL offersPhotoActions = NO;
    if (!offersGIFActions && gifID.length == 0) {
        photoURLString = SCICommentPhotoURLString(comment);
        if (photoURLString.length == 0) {
            photoLocalImage = SCICommentUserUploadedImage(comment);
        }
        BOOL isPhotoComment = SCICommentBoolForSelector(comment, @"isPhotoComment");
        offersPhotoActions = mediaActionsEnabled && (isPhotoComment || photoURLString.length > 0 || photoLocalImage != nil);
    }

    BOOL offersCopyText = text.length > 0 && [SCIUtils getBoolPref:kSCICommentCopyTextPref];
    if (!offersCopyText && !offersGIFActions && !offersPhotoActions) return configuration;

    UIContextMenuActionProvider originalProvider = [configuration valueForKey:@"actionProvider"];
    id<NSCopying> identifier = [configuration valueForKey:@"identifier"];
    UIContextMenuContentPreviewProvider previewProvider = [configuration valueForKey:@"previewProvider"];
    UIContextMenuActionProvider actionProvider = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIMenu *baseMenu = originalProvider ? originalProvider(suggestedActions) : [UIMenu menuWithChildren:suggestedActions];
        NSMutableArray<UIMenuElement *> *extraActions = [NSMutableArray array];

        if (offersCopyText) {
            [extraActions addObject:SCICommentAction(@"Copy Comment", @"copy", ^{
                UIPasteboard.generalPasteboard.string = text;
                SCINotify(kSCINotificationCopyComment, @"Comment copied", nil, @"copy_filled", SCINotificationToneSuccess);
            })];
        }

        if (offersGIFActions) {
            NSURL *gifURL = [NSURL URLWithString:gifURLString];
            NSString *pageURLString = gifID.length > 0 ? [NSString stringWithFormat:@"https://giphy.com/gifs/%@", gifID] : gifURLString;
            NSArray<UIMenuElement *> *gifActions = SCICommentMediaActionItems(comment, gifURL, @"gif", nil, gifID, @"Copy GIF Link", pageURLString, @"GIF link copied");
            [extraActions addObject:[UIMenu menuWithTitle:@"GIF Actions"
                                                     image:SCICommentIcon(@"action")
                                                identifier:nil
                                                   options:0
                                                  children:gifActions]];
        } else if (offersPhotoActions) {
            NSURL *photoURL = photoURLString.length > 0 ? [NSURL URLWithString:photoURLString] : nil;
            NSString *extension = photoURL.pathExtension.length > 0 ? photoURL.pathExtension : @"jpg";
            NSArray<UIMenuElement *> *photoActions = SCICommentMediaActionItems(comment, photoURL, extension, photoLocalImage, nil, @"Copy Download URL", photoURLString, @"Download URL copied");
            [extraActions addObject:[UIMenu menuWithTitle:@"Photo Actions"
                                                     image:SCICommentIcon(@"action")
                                                identifier:nil
                                                   options:0
                                                  children:photoActions]];
        }

        if (extraActions.count == 0) return baseMenu;
        UIMenu *inlineMenu = [UIMenu menuWithTitle:@""
                                            image:nil
                                       identifier:nil
                                          options:UIMenuOptionsDisplayInline
                                         children:extraActions];
        NSMutableArray<UIMenuElement *> *children = [baseMenu.children mutableCopy] ?: [NSMutableArray array];
        NSUInteger insertionIndex = children.count > 0 ? children.count - 1 : 0;
        [children insertObject:inlineMenu atIndex:insertionIndex];
        return [baseMenu menuByReplacingChildren:children];
    };

    return [UIContextMenuConfiguration configurationWithIdentifier:identifier
                                                   previewProvider:previewProvider
                                                    actionProvider:actionProvider];
}

extern "C" void SCIInstallCommentActionsHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:kSCICommentCopyTextPref] &&
        ![SCIUtils getBoolPref:kSCICommentMediaActionsPref]) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"IGCommentThreadViewController");
        SEL selector = @selector(collectionView:contextMenuConfigurationForItemAtIndexPath:point:);
        if (cls && class_getInstanceMethod(cls, selector)) {
            MSHookMessageEx(cls, selector, (IMP)SCICommentContextMenu, (IMP *)&SCIOriginalCommentContextMenu);
        }
    });
}

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

static NSString * const kSCICommentCopyTextPref = @"feed_comments_copy_text";
static NSString * const kSCICommentGIFActionsPref = @"feed_comments_gif_actions";

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

static NSString *SCICommentGIFURLString(id comment) {
    id attachment = SCICommentObjectForSelector(comment, @"commentAttachment");
    if (!attachment) attachment = SCICommentObjectForIvar(comment, @"_commentAttachment");
    if (!attachment) return nil;

    NSString *urlString = SCICommentStringForSelector(attachment, @"imageURL");
    if (urlString.length == 0) {
        urlString = SCICommentStringValue(SCICommentObjectForIvar(attachment, @"_image_imageURL"));
    }
    return urlString;
}

static SCIGallerySaveMetadata *SCICommentGIFMetadata(id comment, NSString *gifID, NSString *gifURLString) {
    SCIGallerySaveMetadata *metadata = [[SCIGallerySaveMetadata alloc] init];
    metadata.source = (int16_t)SCIGallerySourceComments;
    metadata.sourceMediaPK = gifID;
    metadata.sourceMediaURLString = gifURLString;

    id user = SCICommentObjectForSelector(comment, @"user");
    NSString *username = SCICommentStringForSelector(user, @"username");
    [SCIGalleryOriginController populateProfileMetadata:metadata username:username user:user];
    return metadata;
}

static void SCICommentDownloadGIF(NSURL *url, SCIGallerySaveMetadata *metadata, SCIDownloadDestination destination) {
    if (!url) return;
    [SCIDownloadHelpers downloadURL:url
                                extension:@"gif"
                            destination:destination
                                 metadata:metadata
                         notificationID:kSCINotificationDownloadGallery
                                presenter:nil
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

static id (*SCIOriginalCommentContextMenu)(id, SEL, id, id, CGPoint);

static id SCICommentContextMenu(id self, SEL _cmd, id collectionView, id indexPath, CGPoint point) {
    UIContextMenuConfiguration *configuration = SCIOriginalCommentContextMenu(self, _cmd, collectionView, indexPath, point);
    if (!configuration) return nil;

    id comment = SCICommentLongPressedComment(self);
    NSString *text = SCICommentStringForSelector(comment, @"text");
    NSString *gifID = SCICommentStringForSelector(comment, @"gifMediaId");
    NSString *gifURLString = gifID.length > 0 ? SCICommentGIFURLString(comment) : nil;
    BOOL offersCopyText = text.length > 0 && [SCIUtils getBoolPref:kSCICommentCopyTextPref];
    BOOL offersGIFActions = gifURLString.length > 0 && [SCIUtils getBoolPref:kSCICommentGIFActionsPref];
    if (!offersCopyText && !offersGIFActions) return configuration;

    UIContextMenuActionProvider originalProvider = [configuration valueForKey:@"actionProvider"];
    id<NSCopying> identifier = [configuration valueForKey:@"identifier"];
    UIContextMenuContentPreviewProvider previewProvider = [configuration valueForKey:@"previewProvider"];
    UIContextMenuActionProvider actionProvider = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIMenu *baseMenu = originalProvider ? originalProvider(suggestedActions) : [UIMenu menuWithChildren:suggestedActions];
        NSMutableArray<UIMenuElement *> *extraActions = [NSMutableArray array];

        if (offersCopyText) {
            [extraActions addObject:SCICommentAction(@"Copy Comment Text", @"copy", ^{
                UIPasteboard.generalPasteboard.string = text;
                SCINotify(kSCINotificationCopyComment, @"Comment copied", nil, @"copy_filled", SCINotificationToneSuccess);
            })];
        }

        if (offersGIFActions) {
            NSURL *gifURL = [NSURL URLWithString:gifURLString];
            SCIGallerySaveMetadata *metadata = SCICommentGIFMetadata(comment, gifID, gifURLString);
            NSString *pageURLString = gifID.length > 0 ? [NSString stringWithFormat:@"https://giphy.com/gifs/%@", gifID] : gifURLString;
            NSArray<UIMenuElement *> *gifActions = @[
                SCICommentAction(@"Save GIF to Photos", @"download", ^{
                    SCICommentDownloadGIF(gifURL, metadata, SCIDownloadDestinationPhotos);
                }),
                SCICommentAction(@"Share GIF", @"share", ^{
                    SCICommentDownloadGIF(gifURL, metadata, SCIDownloadDestinationShare);
                }),
                SCICommentAction(@"Save GIF to Gallery", @"media", ^{
                    SCICommentDownloadGIF(gifURL, metadata, SCIDownloadDestinationGallery);
                }),
                SCICommentAction(@"Copy GIF Link", @"link", ^{
                    UIPasteboard.generalPasteboard.string = pageURLString;
                    SCINotify(kSCINotificationCopyGIFLink, @"GIF link copied", nil, @"copy_filled", SCINotificationToneSuccess);
                }),
            ];
            [extraActions addObject:[UIMenu menuWithTitle:@"GIF Actions"
                                                   image:SCICommentIcon(@"action")
                                              identifier:nil
                                                 options:0
                                                children:gifActions]];
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
        ![SCIUtils getBoolPref:kSCICommentGIFActionsPref]) {
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

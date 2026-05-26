#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <AVKit/AVKit.h>

#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/Gallery/SCIGallerySaveMetadata.h"
#import "../../Shared/Audio/SCIAudioDownloadCoordinator.h"
#import "../../Shared/Audio/SCIAudioItem.h"
#import "../../Shared/MediaDownload/SCIDashParser.h"
#import "../../Shared/UI/SCIChrome.h"
#import "../../Shared/UI/SCINotificationCenter.h"
#import "../../AssetUtils.h"

static NSInteger const kSCIAudioPageDownloadButtonTag = 1351;
static NSString * const kSCIAudioPageDefaultActionKey = @"general_audio_page_default_action";
static NSString * const kSCIAudioPageActionShare = @"share";
static NSString * const kSCIAudioPageActionConvertShare = @"convert_share";
static NSString * const kSCIAudioPageActionGallery = @"gallery";
static NSString * const kSCIAudioPageActionConvertGallery = @"convert_gallery";
static NSString * const kSCIAudioPageActionPlay = @"play";
static NSString * const kSCIAudioPageActionCopyURL = @"copy_url";

static id SCIAudioPageReadIvar(id object, const char *name) {
    if (!object || !name) return nil;
    for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (ivar) return object_getIvar(object, ivar);
    }
    return nil;
}

static NSString *SCIAudioPageString(id value) {
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] > 0 ? value : nil;
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    return nil;
}

static id SCIAudioPageCall(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSURL *SCIAudioPageURL(id object, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        id value = SCIAudioPageCall(object, name);
        if (!value) {
            @try { value = [object valueForKey:name]; } @catch (__unused NSException *exception) {}
        }
        if ([value isKindOfClass:NSURL.class]) return value;
        NSString *string = SCIAudioPageString(value);
        if (string.length > 0) {
            NSURL *url = [NSURL URLWithString:string];
            if (url) return url;
        }
    }
    return nil;
}

static NSURL *SCIAudioPageResolveAudioURL(id asset) {
    NSURL *url = SCIAudioPageURL(asset, @[@"audioFileUrl", @"audioFileURL", @"progressiveDownloadURL", @"playableAudioURL", @"audioURL"]);
    if (url) return url;
    NSData *manifestData = SCIAudioPageReadIvar(asset, "_dashManifestData");
    if ([manifestData isKindOfClass:NSData.class] && manifestData.length > 0) {
        NSString *xml = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
        NSArray<SCIDashRepresentation *> *reps = [SCIDashParser parseManifest:xml ?: @""];
        SCIDashRepresentation *best = nil;
        for (SCIDashRepresentation *rep in reps) {
            if (![rep.contentType.lowercaseString containsString:@"audio"]) continue;
            if (!best || rep.bandwidth > best.bandwidth) best = rep;
        }
        return best.url;
    }
    return nil;
}

static NSString *SCIAudioPageStringForAsset(id asset, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        NSString *string = SCIAudioPageString(SCIAudioPageCall(asset, name));
        if (string.length > 0) return string;
        @try {
            string = SCIAudioPageString([asset valueForKey:name]);
            if (string.length > 0) return string;
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static UIViewController *SCIAudioPageControllerForView(UIView *view) {
    Class cls = NSClassFromString(@"IGAudioPageViewController");
    if (!cls) return nil;
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:cls]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static SCIAudioItem *SCIAudioPageItem(NSURL *url, SCIGallerySaveMetadata *metadata) {
    SCIAudioItem *item = [SCIAudioItem itemWithURL:url source:SCIAudioSourceAudioPage];
    item.artist = metadata.sourceUsername;
    item.mediaIdentifier = metadata.sourceMediaPK;
    item.sourceURLString = url.absoluteString;
    return item;
}

static void SCIAudioPagePlay(NSURL *url, UIView *sourceView) {
    AVPlayerViewController *playerVC = [[AVPlayerViewController alloc] init];
    playerVC.player = [AVPlayer playerWithURL:url];
    UIViewController *presenter = SCIAudioPageControllerForView(sourceView) ?: topMostController();
    [presenter presentViewController:playerVC animated:YES completion:^{
        [playerVC.player play];
    }];
}

static void SCIAudioPageRunAction(NSString *action, NSURL *url, UIView *sourceView, SCIGallerySaveMetadata *metadata) {
    if (![SCIUtils getBoolPref:@"general_audio_download_enabled"] && ![action isEqualToString:kSCIAudioPageActionPlay]) {
        SCINotify(kSCINotificationDownloadShare, @"Audio downloads disabled", nil, @"error_filled", SCINotificationToneError);
        return;
    }
    SCIAudioItem *item = SCIAudioPageItem(url, metadata);
    if ([action isEqualToString:kSCIAudioPageActionGallery]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionSaveToGallery item:item presenter:SCIAudioPageControllerForView(sourceView) sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadGallery];
    } else if ([action isEqualToString:kSCIAudioPageActionConvertGallery]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndSaveToGallery item:item presenter:SCIAudioPageControllerForView(sourceView) sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadGallery];
    } else if ([action isEqualToString:kSCIAudioPageActionPlay]) {
        SCIAudioPagePlay(url, sourceView);
    } else if ([action isEqualToString:kSCIAudioPageActionCopyURL]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionCopyURL item:item presenter:SCIAudioPageControllerForView(sourceView) sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadShare];
    } else if ([action isEqualToString:kSCIAudioPageActionConvertShare]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndShare item:item presenter:SCIAudioPageControllerForView(sourceView) sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadShare];
    } else {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionShare item:item presenter:SCIAudioPageControllerForView(sourceView) sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadShare];
    }
}

static NSString *SCIAudioPageIconForAction(NSString *action) {
    if ([action isEqualToString:kSCIAudioPageActionGallery]) return @"media";
    if ([action isEqualToString:kSCIAudioPageActionConvertGallery]) return @"media";
    if ([action isEqualToString:kSCIAudioPageActionConvertShare]) return @"share";
    if ([action isEqualToString:kSCIAudioPageActionPlay]) return @"play";
    if ([action isEqualToString:kSCIAudioPageActionCopyURL]) return @"link";
    return @"share";
}

static UIImage *SCIAudioPageMenuIcon(NSString *iconName) {
    return [[[SCIAssetUtils instagramIconNamed:iconName pointSize:22.0] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] imageWithTintColor:[UIColor labelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIImage *SCIAudioPageActionIcon(NSString *identifier, NSString *fallbackIconName) {
    UIImage *actionButtonIcon = SCIActionButtonMenuIconForIdentifier(identifier, 22.0);
    if (actionButtonIcon) return actionButtonIcon;
    return SCIAudioPageMenuIcon(fallbackIconName);
}

static NSDictionary *SCIAudioPageResolvedPayload(UIView *sourceView) {
    UIViewController *vc = SCIAudioPageControllerForView(sourceView);
    id asset = SCIAudioPageReadIvar(vc, "_audioAsset") ?: SCIAudioPageReadIvar(vc, "_music") ?: SCIAudioPageReadIvar(vc, "_originalAudio");
    NSURL *url = SCIAudioPageResolveAudioURL(asset);
    if (!url) {
        SCINotify(kSCINotificationDownloadShare, @"Could not find audio URL", nil, @"error_filled", SCINotificationToneError);
        return nil;
    }

    SCIGallerySaveMetadata *metadata = [[SCIGallerySaveMetadata alloc] init];
    metadata.source = (int16_t)SCIGallerySourceAudioPage;
    metadata.sourceUsername = SCIAudioPageStringForAsset(asset, @[@"artistDisplayName", @"username", @"displayArtist", @"artist"]) ?: @"audio";
    metadata.sourceMediaPK = SCIAudioPageStringForAsset(asset, @[@"audioAssetId", @"pk", @"id"]);
    return @{@"url": url, @"metadata": metadata};
}

static UIAction *SCIAudioPageMenuAction(NSString *title, NSString *action, NSString *iconIdentifier, NSString *fallbackIconName, UIView *sourceView) {
    return [UIAction actionWithTitle:title
                               image:SCIAudioPageActionIcon(iconIdentifier, fallbackIconName)
                          identifier:nil
                             handler:^(__unused UIAction *menuAction) {
        NSDictionary *payload = SCIAudioPageResolvedPayload(sourceView);
        NSURL *url = payload[@"url"];
        SCIGallerySaveMetadata *metadata = payload[@"metadata"];
        if (!url || !metadata) return;
        SCIAudioPageRunAction(action, url, sourceView, metadata);
    }];
}

static UIMenu *SCIAudioPageMenuForButton(UIButton *button) {
    return [UIMenu menuWithTitle:@""
                           image:nil
                      identifier:nil
                         options:0
                        children:@[
        SCIAudioPageMenuAction(@"Share Audio", kSCIAudioPageActionShare, kSCIActionDownloadAudio, @"share", button),
        SCIAudioPageMenuAction(@"Convert & Share", kSCIAudioPageActionConvertShare, kSCIActionDownloadAudioShare, @"share", button),
        SCIAudioPageMenuAction(@"Save Audio to Gallery", kSCIAudioPageActionGallery, kSCIActionDownloadAudioGallery, @"media", button),
        SCIAudioPageMenuAction(@"Convert & Save to Gallery", kSCIAudioPageActionConvertGallery, kSCIActionDownloadAudioGallery, @"media", button),
        SCIAudioPageMenuAction(@"Play Audio", kSCIAudioPageActionPlay, kSCIActionPlayAudio, @"play", button),
        SCIAudioPageMenuAction(@"Copy Audio URL", kSCIAudioPageActionCopyURL, kSCIActionCopyAudioURL, @"link", button)
    ]];
}

static void SCIAudioPageRunDefaultAction(UIView *sourceView) {
    NSString *action = [SCIUtils getStringPref:kSCIAudioPageDefaultActionKey];
    if (action.length == 0) action = kSCIAudioPageActionShare;

    NSDictionary *payload = SCIAudioPageResolvedPayload(sourceView);
    NSURL *url = payload[@"url"];
    SCIGallerySaveMetadata *metadata = payload[@"metadata"];
    if (!url || !metadata) return;
    SCIAudioPageRunAction(action, url, sourceView, metadata);
}

static UIView *SCIAudioPageButtonAnchor(UIView *bar) {
    UIView *share = SCIAudioPageReadIvar(bar, "shareButton");
    UIView *save = SCIAudioPageReadIvar(bar, "saveButton");
    BOOL shareValid = share && !share.hidden && !CGRectIsEmpty(share.frame);
    BOOL saveValid = save && !save.hidden && !CGRectIsEmpty(save.frame);
    if (shareValid && saveValid) {
        return CGRectGetMinX(save.frame) <= CGRectGetMinX(share.frame) ? save : share;
    }
    return saveValid ? save : (shareValid ? share : nil);
}

static UIColor *SCIAudioPageBackgroundColorFromAnchor(UIView *anchor) {
    UIColor *color = anchor.backgroundColor;
    if (color && CGColorGetAlpha(color.CGColor) > 0.01) return color;
    if (anchor.layer.backgroundColor && CGColorGetAlpha(anchor.layer.backgroundColor) > 0.01) {
        return [UIColor colorWithCGColor:anchor.layer.backgroundColor];
    }
    /// TODO: fix (use custom colors)
    if (@available(iOS 13.0, *)) {
        return UIColor.secondarySystemFillColor;
    }
    return [UIColor colorWithWhite:0.0 alpha:0.08];
}

static void SCIAudioPageInstallButton(UIView *bar) {
    if (![SCIUtils getBoolPref:@"general_audio_page_download"]) {
        [[bar viewWithTag:kSCIAudioPageDownloadButtonTag] removeFromSuperview];
        return;
    }
    UIView *anchor = SCIAudioPageButtonAnchor(bar);
    SCIChromeButton *button = (SCIChromeButton *)[bar viewWithTag:kSCIAudioPageDownloadButtonTag];
    if (![button isKindOfClass:SCIChromeButton.class] || [button isKindOfClass:SCIActionMenuButton.class]) {
        if (button) [button removeFromSuperview];
        button = [[SCIChromeButton alloc] initWithSymbol:@"" pointSize:22.0 diameter:32.0];
        button.tag = kSCIAudioPageDownloadButtonTag;
        button.translatesAutoresizingMaskIntoConstraints = YES;
        button.showsMenuAsPrimaryAction = NO;
        [button addTarget:bar action:@selector(sci_audioPageDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:button];
    }
    if (!anchor) {
        if (CGRectIsEmpty(button.frame)) {
            button.hidden = YES;
        }
        return;
    }

    NSString *defaultAction = [SCIUtils getStringPref:kSCIAudioPageDefaultActionKey];
    if (defaultAction.length == 0) defaultAction = kSCIAudioPageActionShare;
    
    BOOL isNone = [defaultAction isEqualToString:@"none"];
    NSString *iconName = isNone ? @"action" : SCIAudioPageIconForAction(defaultAction);
    
    CGFloat side = MAX(28.0, CGRectGetHeight(anchor.frame));
    CGFloat iconPointSize = MAX(16.0, MIN(22.0, side - 10.0));
    
    [button setIconResource:iconName pointSize:iconPointSize];
    button.iconTint = UIColor.labelColor;
    button.tintColor = UIColor.labelColor;
    button.iconView.tintColor = UIColor.labelColor;
    button.bubbleColor = SCIAudioPageBackgroundColorFromAnchor(anchor);
    if (!button.menu) {
        button.menu = SCIAudioPageMenuForButton(button);
    }
    button.showsMenuAsPrimaryAction = isNone;
    
    button.frame = CGRectMake(CGRectGetMinX(anchor.frame) - side - 8.0, CGRectGetMidY(anchor.frame) - side / 2.0, side, side);
    button.hidden = NO;
    [bar bringSubviewToFront:button];
}

%group SCIAudioPageDownloadHooks

%hook UIView
%new - (void)sci_audioPageDownloadTapped:(UIButton *)sender {
    if (sender.showsMenuAsPrimaryAction) return;
    SCIAudioPageRunDefaultAction(sender ?: (UIView *)self);
}
%end

%hook _TtC16IGAudioPageSwift26IGAudioPageHeaderActionBar
- (void)layoutSubviews {
    %orig;
    SCIAudioPageInstallButton((UIView *)self);
}
%end

%end

extern "C" void SCIInstallAudioPageDownloadHooksIfNeeded(void) {
    if (![SCIUtils getBoolPref:@"general_audio_download_enabled"]) return;
    if (![SCIUtils getBoolPref:@"general_audio_page_download"]) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIAudioPageDownloadHooks);
    });
}

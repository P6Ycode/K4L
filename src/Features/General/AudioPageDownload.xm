#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <AVKit/AVKit.h>

#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../Shared/Gallery/SCIGallerySaveMetadata.h"
#import "../../Shared/MediaDownload/SCIDashParser.h"
#import "../../Shared/UI/SCINotificationCenter.h"
#import "../../AssetUtils.h"

static NSInteger const kSCIAudioPageDownloadButtonTag = 1351;
static NSString * const kSCIAudioPageDefaultActionKey = @"audio_page_default_action";
static NSString * const kSCIAudioPageActionShare = @"share";
static NSString * const kSCIAudioPageActionGallery = @"gallery";
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

static void SCIAudioPageDownload(NSURL *url, NSString *identifier, DownloadAction action, SCIGallerySaveMetadata *metadata) {
    SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:SCINotificationIsEnabled(identifier)];
    delegate.notificationIdentifier = identifier;
    delegate.pendingGallerySaveMetadata = metadata;
    NSString *ext = url.pathExtension.length > 0 ? url.pathExtension.lowercaseString : @"m4a";
    [delegate downloadFileWithURL:url fileExtension:ext hudLabel:nil];
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
    if ([action isEqualToString:kSCIAudioPageActionGallery]) {
        SCIAudioPageDownload(url, kSCINotificationDownloadGallery, saveToGallery, metadata);
    } else if ([action isEqualToString:kSCIAudioPageActionPlay]) {
        SCIAudioPagePlay(url, sourceView);
    } else if ([action isEqualToString:kSCIAudioPageActionCopyURL]) {
        UIPasteboard.generalPasteboard.string = url.absoluteString;
        SCINotify(kSCINotificationDownloadShare, @"Copied audio URL", nil, @"copy_filled", SCINotificationToneSuccess);
    } else {
        SCIAudioPageDownload(url, kSCINotificationDownloadShare, share, metadata);
    }
}

static NSString *SCIAudioPageIconForAction(NSString *action) {
    if ([action isEqualToString:kSCIAudioPageActionGallery]) return @"media";
    if ([action isEqualToString:kSCIAudioPageActionPlay]) return @"play";
    if ([action isEqualToString:kSCIAudioPageActionCopyURL]) return @"link";
    return @"share";
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
    metadata.sourceUsername = SCIAudioPageStringForAsset(asset, @[@"artistDisplayName", @"username", @"displayArtist", @"artist"]) ?: @"audio";
    metadata.sourceMediaPK = SCIAudioPageStringForAsset(asset, @[@"audioAssetId", @"pk", @"id"]);
    return @{@"url": url, @"metadata": metadata};
}

static UIAction *SCIAudioPageMenuAction(NSString *title, NSString *iconName, NSString *action, NSURL *url, UIView *sourceView, SCIGallerySaveMetadata *metadata) {
    return [UIAction actionWithTitle:title
                               image:[SCIAssetUtils instagramIconNamed:iconName pointSize:20.0]
                          identifier:nil
                             handler:^(__unused UIAction *menuAction) {
        SCIAudioPageRunAction(action, url, sourceView, metadata);
    }];
}

static UIMenu *SCIAudioPageMenuForButton(UIView *sourceView) {
    NSDictionary *payload = SCIAudioPageResolvedPayload(sourceView);
    NSURL *url = payload[@"url"];
    SCIGallerySaveMetadata *metadata = payload[@"metadata"];
    if (!url || !metadata) return [UIMenu menuWithTitle:@"" children:@[]];

    return [UIMenu menuWithTitle:@"" children:@[
        SCIAudioPageMenuAction(@"Share Audio", @"share", kSCIAudioPageActionShare, url, sourceView, metadata),
        SCIAudioPageMenuAction(@"Save Audio to Gallery", @"media", kSCIAudioPageActionGallery, url, sourceView, metadata),
        SCIAudioPageMenuAction(@"Play Audio", @"play", kSCIAudioPageActionPlay, url, sourceView, metadata),
        SCIAudioPageMenuAction(@"Copy Audio URL", @"link", kSCIAudioPageActionCopyURL, url, sourceView, metadata),
    ]];
}

static void SCIAudioPageRunDefaultAction(UIView *sourceView) {
    NSString *action = [SCIUtils getStringPref:kSCIAudioPageDefaultActionKey];
    if (action.length == 0) action = kSCIAudioPageActionShare;
    if ([action isEqualToString:@"none"]) return;

    NSDictionary *payload = SCIAudioPageResolvedPayload(sourceView);
    NSURL *url = payload[@"url"];
    SCIGallerySaveMetadata *metadata = payload[@"metadata"];
    if (!url || !metadata) return;
    SCIAudioPageRunAction(action, url, sourceView, metadata);
}

static UIView *SCIAudioPageButtonAnchor(UIView *bar) {
    UIView *share = SCIAudioPageReadIvar(bar, "shareButton");
    UIView *save = SCIAudioPageReadIvar(bar, "saveButton");
    return save ?: share;
}

static void SCIAudioPageInstallButton(UIView *bar) {
    if (![SCIUtils getBoolPref:@"audio_page_download"]) {
        [[bar viewWithTag:kSCIAudioPageDownloadButtonTag] removeFromSuperview];
        return;
    }
    UIView *anchor = SCIAudioPageButtonAnchor(bar);
    if (!anchor || anchor.hidden || CGRectIsEmpty(anchor.frame)) return;
    UIButton *button = (UIButton *)[bar viewWithTag:kSCIAudioPageDownloadButtonTag];
    if (![button isKindOfClass:UIButton.class]) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = kSCIAudioPageDownloadButtonTag;
        [button addTarget:bar action:@selector(sci_audioPageDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:button];
    }
    NSString *defaultAction = [SCIUtils getStringPref:kSCIAudioPageDefaultActionKey];
    if (defaultAction.length == 0) defaultAction = kSCIAudioPageActionShare;
    
    BOOL isNone = [defaultAction isEqualToString:@"none"];
    NSString *iconName = isNone ? @"action" : SCIAudioPageIconForAction(defaultAction);
    
    CGFloat side = MAX(32.0, CGRectGetHeight(anchor.frame));
    CGFloat iconPointSize = MAX(18.0, side * 0.55);
    
    UIImage *image = [[SCIAssetUtils instagramIconNamed:iconName pointSize:iconPointSize] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = anchor.tintColor ?: UIColor.labelColor;
    
    button.showsMenuAsPrimaryAction = isNone;
    button.menu = SCIAudioPageMenuForButton(button);
    
    button.frame = CGRectMake(CGRectGetMinX(anchor.frame) - side - 8.0, CGRectGetMidY(anchor.frame) - side / 2.0, side, side);
    button.layer.cornerRadius = side / 2.0;
    button.clipsToBounds = YES;
    
    if (@available(iOS 13.0, *)) {
        button.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * (UITraitCollection *trait) {
            if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithWhite:1.0 alpha:0.12];
            } else {
                return [UIColor colorWithWhite:0.0 alpha:0.06];
            }
        }];
    } else {
        button.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.06];
    }
    
    [bar bringSubviewToFront:button];
}

%group SCIAudioPageDownloadHooks

%hook UIView
%new - (void)sci_audioPageDownloadTapped:(UIButton *)sender {
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
    if (![SCIUtils getBoolPref:@"audio_page_download"]) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIAudioPageDownloadHooks);
    });
}

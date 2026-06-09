#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

#import "../../Utils.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/Gallery/SCIGallerySaveMetadata.h"
#import "../../Shared/Audio/SCIAudioDownloadCoordinator.h"
#import "../../Shared/Audio/SCIAudioItem.h"
#import "../../Shared/MediaDownload/SCIDashParser.h"
#import "../../Shared/UI/SCIChrome.h"
#import "../../Shared/UI/SCINotificationCenter.h"
#import "../../AssetUtils.h"

static NSInteger const kSCIAudioPageDownloadButtonTag = 1351;
static const void *kSCIAudioPageButtonKey = &kSCIAudioPageButtonKey;
static NSString * const kSCIAudioPageDefaultActionKey = @"downloads_audio_page_default_action";
static NSString * const kSCIAudioPageActionFiles = @"files";
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

static void SCIAudioPageRunAction(NSString *action, NSURL *url, UIView *sourceView, SCIGallerySaveMetadata *metadata) {
    if (![SCIUtils getBoolPref:@"downloads_audio_enabled"] && ![action isEqualToString:kSCIAudioPageActionPlay]) {
        SCINotify(kSCINotificationDownloadShare, @"Audio downloads disabled", nil, @"error_filled", SCINotificationToneError);
        return;
    }
    SCIAudioItem *item = SCIAudioPageItem(url, metadata);
    UIViewController *presenter = SCIAudioPageControllerForView(sourceView) ?: topMostController();
    if ([action isEqualToString:kSCIAudioPageActionFiles]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionSaveToFiles item:item presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadAudio];
    } else if ([action isEqualToString:kSCIAudioPageActionGallery]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndSaveToGallery item:item presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadAudioGallery];
    } else if ([action isEqualToString:kSCIAudioPageActionConvertGallery]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndSaveToGallery item:item presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadAudioGallery];
    } else if ([action isEqualToString:kSCIAudioPageActionPlay]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionPlay item:item presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationPlayAudio];
    } else if ([action isEqualToString:kSCIAudioPageActionCopyURL]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionCopyURL item:item presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationCopyAudioURL];
    } else if ([action isEqualToString:kSCIAudioPageActionConvertShare]) {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndShare item:item presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadAudioShare];
    } else {
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndShare item:item presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadAudioShare];
    }
}

static NSString *SCIAudioPageIconForAction(NSString *action) {
    if ([action isEqualToString:kSCIAudioPageActionFiles]) return @"audio_download";
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
        SCIAudioPageMenuAction(@"Save to Files", kSCIAudioPageActionFiles, kSCIActionDownloadAudio, @"audio_download", button),
        SCIAudioPageMenuAction(@"Share", kSCIAudioPageActionShare, kSCIActionDownloadAudioShare, @"share", button),
        SCIAudioPageMenuAction(@"Save to Gallery", kSCIAudioPageActionGallery, kSCIActionDownloadAudioGallery, @"media", button),
        SCIAudioPageMenuAction(@"Play", kSCIAudioPageActionPlay, kSCIActionPlayAudio, @"play", button),
        SCIAudioPageMenuAction(@"Copy Download URL", kSCIAudioPageActionCopyURL, kSCIActionCopyAudioURL, @"link", button)
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
    return [SCIUtils SCIColor_InstagramSecondaryBackground];
}

static void SCIAudioPagePinEdges(UIView *view, UIView *host) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:host.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
    ]];
}

static UIButton *SCIAudioPageButtonForHost(UIView *host) {
    return objc_getAssociatedObject(host, kSCIAudioPageButtonKey);
}

static void SCIAudioPageInstallButton(UIView *bar) {
    if (![SCIUtils getBoolPref:@"downloads_audio_page_button"]) {
        [[bar viewWithTag:kSCIAudioPageDownloadButtonTag] removeFromSuperview];
        return;
    }
    UIView *anchor = SCIAudioPageButtonAnchor(bar);
    UIView *host = [bar viewWithTag:kSCIAudioPageDownloadButtonTag];
    UIButton *button = [host isKindOfClass:UIView.class] ? SCIAudioPageButtonForHost(host) : nil;
    if (![button isKindOfClass:UIButton.class] || [button isKindOfClass:SCIChromeButton.class]) {
        if (host) [host removeFromSuperview];
        host = [UIView new];
        host.tag = kSCIAudioPageDownloadButtonTag;
        host.translatesAutoresizingMaskIntoConstraints = YES;
        host.clipsToBounds = NO;

        SCIChromeCanvas *canvas = [SCIChromeCanvas new];
        canvas.userInteractionEnabled = YES;
        [host addSubview:canvas];
        SCIAudioPagePinEdges(canvas, host);

        // Keep a native UIButton as the menu source so iOS 26 can morph the
        // button image with the menu, but put it inside SCIChromeCanvas so
        // Hide UI on Capture redacts it instead of removing it from screen.
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.showsMenuAsPrimaryAction = NO;
        button.adjustsImageWhenHighlighted = YES;
        [button addTarget:bar action:@selector(sci_audioPageDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
        [canvas.contentContainer addSubview:button];
        SCIAudioPagePinEdges(button, canvas.contentContainer);
        objc_setAssociatedObject(host, kSCIAudioPageButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bar addSubview:host];
    }
    if (!anchor) {
        if (CGRectIsEmpty(host.frame)) {
            host.hidden = YES;
        }
        return;
    }

    NSString *defaultAction = [SCIUtils getStringPref:kSCIAudioPageDefaultActionKey];
    if (defaultAction.length == 0) defaultAction = kSCIAudioPageActionShare;

    BOOL isNone = [defaultAction isEqualToString:@"none"];
    NSString *iconName = isNone ? @"action" : SCIAudioPageIconForAction(defaultAction);

    CGFloat side = MAX(28.0, CGRectGetHeight(anchor.frame));

    UIImage *icon = [SCIAssetUtils instagramIconNamed:iconName pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    [button setImage:icon forState:UIControlStateNormal];
    button.tintColor = UIColor.labelColor;
    button.backgroundColor = SCIAudioPageBackgroundColorFromAnchor(anchor);
    button.layer.cornerRadius = side / 2.0;
    button.clipsToBounds = YES;
    if (!button.menu) {
        button.menu = SCIAudioPageMenuForButton(button);
    }
    button.showsMenuAsPrimaryAction = isNone;

    host.frame = CGRectMake(CGRectGetMinX(anchor.frame) - side - 8.0, CGRectGetMidY(anchor.frame) - side / 2.0, side, side);
    button.hidden = NO;
    host.hidden = NO;
    [bar bringSubviewToFront:host];
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
    // Only install/reposition if the button doesn't exist yet or the anchor moved.
    // Avoid touching the button mid-animation (menu morph) which breaks Liquid Glass.
    UIView *existing = [(UIView *)self viewWithTag:kSCIAudioPageDownloadButtonTag];
    if ([existing isKindOfClass:UIView.class] && !existing.hidden && !CGRectIsEmpty(existing.frame)) {
        UIView *anchor = SCIAudioPageButtonAnchor((UIView *)self);
        if (anchor) {
            CGFloat side = MAX(28.0, CGRectGetHeight(anchor.frame));
            CGRect expected = CGRectMake(CGRectGetMinX(anchor.frame) - side - 8.0,
                                        CGRectGetMidY(anchor.frame) - side / 2.0,
                                        side, side);
            if (CGRectEqualToRect(existing.frame, expected)) {
                return; // Nothing changed, don't touch the button.
            }
        }
    }
    SCIAudioPageInstallButton((UIView *)self);
}
%end

%end

extern "C" void SCIInstallAudioPageDownloadHooksIfNeeded(void) {
    if (![SCIUtils getBoolPref:@"downloads_audio_enabled"]) return;
    if (![SCIUtils getBoolPref:@"downloads_audio_page_button"]) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIAudioPageDownloadHooks);
    });
}

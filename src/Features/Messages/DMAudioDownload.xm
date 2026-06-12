#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

#import "../../Utils.h"
#import "../../AssetUtils.h"
#import "../../Shared/Audio/SCIAudioDMUploadCoordinator.h"
#import "../../Shared/Audio/SCIAudioDownloadCoordinator.h"
#import "../../Shared/Audio/SCIAudioItem.h"
#import "../../Shared/Gallery/SCIGallerySaveMetadata.h"
#import "../../Shared/UI/SCIIGAlertPresenter.h"
#import "../../Shared/UI/SCINotificationCenter.h"

static __unsafe_unretained id sSCIDMComposerForOverflowMenu = nil;
static BOOL sSCIDMUploadItemInjectedForOverflowMenu = NO;
static BOOL sSCIDMAudioDownloadPrismMenuPending = NO;
static id sSCIDMAudioDownloadViewModel = nil;

static id (*orig_SCIDMAudioPrismMenuViewInit3)(id, SEL, NSArray *, id, BOOL);
static id (*orig_SCIDMAudioPrismMenuViewInit5)(id, SEL, NSArray *, id, BOOL, BOOL, BOOL);

static id SCIDMAudioCandidateObject(UIView *view);

static id SCIDMAudioIvarValue(id object, const char *name) {
    if (!object || !name) return nil;
    @try {
        for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
            Ivar ivar = class_getInstanceVariable(cls, name);
            if (ivar) return object_getIvar(object, ivar);
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static id SCIDMAudioCall(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SCIDMAudioKVCObject(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *SCIDMAudioString(id value) {
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] > 0 ? value : nil;
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *string = [value stringValue];
        return string.length > 0 ? string : nil;
    }
    return nil;
}

static BOOL SCIDMAudioUsernameLooksUsable(NSString *username) {
    if (username.length == 0) return NO;
    NSString *lower = username.lowercaseString;
    if ([lower isEqualToString:@"direct"] || [lower isEqualToString:@"audio"] || [lower isEqualToString:@"media"]) return NO;
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower hasPrefix:@"instagram://"]) return NO;
    if ([username rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) return NO;
    if (username.length > 30) return NO;
    return YES;
}

static NSString *SCIDMAudioStringForNames(id object, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        NSString *string = SCIDMAudioString(SCIDMAudioCall(object, name));
        if (!string) string = SCIDMAudioString(SCIDMAudioKVCObject(object, name));
        if (SCIDMAudioUsernameLooksUsable(string)) return string;
    }
    return nil;
}

static BOOL SCIDMAudioStringMatchesPK(NSString *string, NSString *pk) {
    if (string.length == 0 || pk.length == 0) return NO;
    return [string isEqualToString:pk];
}

static NSString *SCIDMAudioPKForNames(id object, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        NSString *string = SCIDMAudioString(SCIDMAudioCall(object, name));
        if (!string) string = SCIDMAudioString(SCIDMAudioKVCObject(object, name));
        if (string.length > 0) return string;
    }
    return nil;
}

static BOOL SCIDMAudioShouldTraverseForUsername(id object) {
    if (!object) return NO;
    if ([object isKindOfClass:NSString.class] ||
        [object isKindOfClass:NSNumber.class] ||
        [object isKindOfClass:NSDate.class] ||
        [object isKindOfClass:NSURL.class] ||
        [object isKindOfClass:NSData.class] ||
        [object isKindOfClass:UIImage.class] ||
        [object isKindOfClass:UIView.class] ||
        [object isKindOfClass:UIViewController.class]) {
        return NO;
    }
    NSString *name = NSStringFromClass([object class]);
    return [name containsString:@"Direct"] ||
           [name containsString:@"Message"] ||
           [name containsString:@"Sender"] ||
           [name containsString:@"User"] ||
           [name containsString:@"Participant"] ||
           [name containsString:@"GraphQL"] ||
           [name containsString:@"GQL"] ||
           [name containsString:@"Model"];
}

static NSString *SCIDMAudioSenderPKFromObject(id object, NSMutableSet<NSValue *> *visited, NSUInteger depth) {
    if (!object || depth > 5) return nil;
    if ([object isKindOfClass:NSDictionary.class]) {
        NSString *direct = SCIDMAudioPKForNames(object, @[@"senderPk", @"senderPK", @"senderId", @"senderID", @"messageSenderId", @"messageSenderID"]);
        if (direct) return direct;
        for (NSString *key in @[@"messageMetadata", @"metadata", @"messageCellViewModel", @"viewModel", @"message", @"item"]) {
            NSString *pk = SCIDMAudioSenderPKFromObject([(NSDictionary *)object objectForKey:key], visited, depth + 1);
            if (pk) return pk;
        }
        return nil;
    }
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class]) return nil;

    NSValue *identity = [NSValue valueWithNonretainedObject:object];
    if ([visited containsObject:identity]) return nil;
    [visited addObject:identity];

    NSString *direct = SCIDMAudioPKForNames(object, @[@"senderPk", @"senderPK", @"senderId", @"senderID", @"messageSenderId", @"messageSenderID"]);
    if (direct) return direct;

    for (NSString *name in @[@"messageMetadata", @"metadata", @"messageCellViewModel", @"viewModel", @"message", @"item"]) {
        id nested = SCIDMAudioCall(object, name) ?: SCIDMAudioKVCObject(object, name);
        if (nested && nested != object) {
            NSString *pk = SCIDMAudioSenderPKFromObject(nested, visited, depth + 1);
            if (pk) return pk;
        }
    }
    return nil;
}

static BOOL SCIDMAudioObjectMatchesPK(id object, NSString *pk) {
    NSString *objectPK = SCIDMAudioPKForNames(object, @[@"pk", @"PK", @"userPk", @"userPK", @"userId", @"userID", @"id", @"identifier"]);
    return SCIDMAudioStringMatchesPK(objectPK, pk);
}

static NSString *SCIDMAudioUsernameForPKFromObject(id object, NSString *pk, NSMutableSet<NSValue *> *visited, NSUInteger depth) {
    if (!object || pk.length == 0 || depth > 7) return nil;

    if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)object;
        id keyedValue = [dict objectForKey:pk];
        NSString *username = SCIDMAudioUsernameForPKFromObject(keyedValue, pk, visited, depth + 1);
        if (username) return username;

        NSString *dictPK = SCIDMAudioPKForNames(dict, @[@"pk", @"PK", @"userPk", @"userPK", @"userId", @"userID", @"id", @"identifier"]);
        if (SCIDMAudioStringMatchesPK(dictPK, pk)) {
            NSString *direct = SCIDMAudioStringForNames(dict, @[@"username", @"userName", @"profileUsername", @"displayUsername"]);
            if (direct) return direct;
        }

        for (NSString *key in @[@"sender", @"senderUser", @"user", @"author", @"owner", @"participant", @"profile", @"threadUsers", @"users", @"participants", @"userMap"]) {
            username = SCIDMAudioUsernameForPKFromObject([dict objectForKey:key], pk, visited, depth + 1);
            if (username) return username;
        }
        for (id value in dict.allValues) {
            username = SCIDMAudioUsernameForPKFromObject(value, pk, visited, depth + 1);
            if (username) return username;
        }
        return nil;
    }

    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class]) {
        for (id value in object) {
            NSString *username = SCIDMAudioUsernameForPKFromObject(value, pk, visited, depth + 1);
            if (username) return username;
        }
        return nil;
    }

    if ([object isKindOfClass:NSString.class] ||
        [object isKindOfClass:NSNumber.class] ||
        [object isKindOfClass:NSDate.class] ||
        [object isKindOfClass:NSURL.class] ||
        [object isKindOfClass:NSData.class] ||
        [object isKindOfClass:UIImage.class]) {
        return nil;
    }

    NSValue *identity = [NSValue valueWithNonretainedObject:object];
    if ([visited containsObject:identity]) return nil;
    [visited addObject:identity];

    if (SCIDMAudioObjectMatchesPK(object, pk)) {
        NSString *direct = SCIDMAudioStringForNames(object, @[@"username", @"userName", @"profileUsername", @"displayUsername"]);
        if (direct) return direct;
    }

    for (NSString *name in @[
        @"sender", @"senderUser", @"senderInfo", @"senderViewModel", @"messageSender",
        @"threadMessageSenderViewModel", @"messageSenderViewModel", @"user", @"author",
        @"owner", @"participant", @"profile", @"threadUsers", @"users", @"participants",
        @"userMap", @"message", @"messageMetadata", @"metadata", @"viewModel",
        @"messageViewModel", @"audioMessageViewModel", @"messageCellViewModel", @"model", @"item"
    ]) {
        id nested = SCIDMAudioCall(object, name) ?: SCIDMAudioKVCObject(object, name);
        if (nested && nested != object) {
            NSString *username = SCIDMAudioUsernameForPKFromObject(nested, pk, visited, depth + 1);
            if (username) return username;
        }
    }

    if (!SCIDMAudioShouldTraverseForUsername(object)) return nil;
    for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (!encoding || encoding[0] != '@') continue;
            const char *name = ivar_getName(ivar);
            NSString *ivarName = name ? [NSString stringWithUTF8String:name] : @"";
            NSString *lower = ivarName.lowercaseString;
            BOOL priority = [lower containsString:@"sender"] || [lower containsString:@"user"] || [lower containsString:@"participant"] || [lower containsString:@"message"] || [lower containsString:@"metadata"];
            if (!priority && depth > 3) continue;
            id value = nil;
            @try {
                value = object_getIvar(object, ivar);
            } @catch (__unused NSException *exception) {
                value = nil;
            }
            NSString *username = SCIDMAudioUsernameForPKFromObject(value, pk, visited, depth + 1);
            if (username) {
                free(ivars);
                return username;
            }
        }
        free(ivars);
    }
    return nil;
}

static NSString *SCIDMAudioUsernameFromObject(id object, NSMutableSet<NSValue *> *visited, NSUInteger depth) {
    if (!object || depth > 6) return nil;
    if ([object isKindOfClass:NSDictionary.class]) {
        NSString *direct = SCIDMAudioStringForNames(object, @[@"username", @"userName", @"senderUsername", @"senderUserName", @"sender_name"]);
        if (direct) return direct;
        for (NSString *key in @[@"sender", @"senderUser", @"user", @"author", @"owner", @"participant", @"profile", @"message", @"viewModel", @"messageMetadata"]) {
            id nested = [(NSDictionary *)object objectForKey:key];
            NSString *username = SCIDMAudioUsernameFromObject(nested, visited, depth + 1);
            if (username) return username;
        }
        for (id value in [(NSDictionary *)object allValues]) {
            NSString *username = SCIDMAudioUsernameFromObject(value, visited, depth + 1);
            if (username) return username;
        }
        return nil;
    }
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class]) {
        for (id value in object) {
            NSString *username = SCIDMAudioUsernameFromObject(value, visited, depth + 1);
            if (username) return username;
        }
        return nil;
    }

    NSValue *identity = [NSValue valueWithNonretainedObject:object];
    if ([visited containsObject:identity]) return nil;
    [visited addObject:identity];

    NSString *direct = SCIDMAudioStringForNames(object, @[
        @"username", @"userName", @"senderUsername", @"senderUserName",
        @"senderName", @"senderDisplayName", @"displayUsername", @"profileUsername"
    ]);
    if (direct) return direct;

    for (NSString *name in @[
        @"sender", @"senderUser", @"senderInfo", @"senderViewModel", @"messageSender",
        @"threadMessageSenderViewModel", @"messageSenderViewModel", @"user", @"author",
        @"owner", @"participant", @"profile", @"message", @"messageMetadata", @"viewModel",
        @"messageViewModel", @"audioMessageViewModel", @"model", @"item"
    ]) {
        id nested = SCIDMAudioCall(object, name) ?: SCIDMAudioKVCObject(object, name);
        if (nested && nested != object) {
            NSString *username = SCIDMAudioUsernameFromObject(nested, visited, depth + 1);
            if (username) return username;
        }
    }

    if (!SCIDMAudioShouldTraverseForUsername(object)) return nil;
    for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (!encoding || encoding[0] != '@') continue;
            const char *name = ivar_getName(ivar);
            NSString *ivarName = name ? [NSString stringWithUTF8String:name] : @"";
            NSString *lower = ivarName.lowercaseString;
            BOOL priority = [lower containsString:@"sender"] || [lower containsString:@"user"] || [lower containsString:@"participant"] || [lower containsString:@"message"];
            if (!priority && depth > 2) continue;
            id value = nil;
            @try {
                value = object_getIvar(object, ivar);
            } @catch (__unused NSException *exception) {
                value = nil;
            }
            NSString *username = SCIDMAudioUsernameFromObject(value, visited, depth + 1);
            if (username) {
                free(ivars);
                return username;
            }
        }
        free(ivars);
    }
    return nil;
}

static NSString *SCIDMAudioResolvedUsername(id object) {
    NSString *username = SCIDMAudioUsernameFromObject(object, [NSMutableSet set], 0);
    if (username) return username;

    NSString *senderPK = SCIDMAudioSenderPKFromObject(object, [NSMutableSet set], 0);
    if (!senderPK) return nil;
    return SCIDMAudioUsernameForPKFromObject(object, senderPK, [NSMutableSet set], 0);
}

static NSString *SCIDMAudioResolvedUsernameNearView(UIView *view, id primaryObject) {
    NSString *username = SCIDMAudioResolvedUsername(primaryObject);
    if (username) return username;

    NSString *senderPK = SCIDMAudioSenderPKFromObject(primaryObject, [NSMutableSet set], 0);
    for (UIView *candidateView = view; candidateView && candidateView != candidateView.window; candidateView = candidateView.superview) {
        id candidateObject = SCIDMAudioCandidateObject(candidateView);
        username = SCIDMAudioResolvedUsername(candidateObject);
        if (username) return username;

        if (senderPK.length > 0) {
            username = SCIDMAudioUsernameForPKFromObject(candidateObject, senderPK, [NSMutableSet set], 0);
            if (username) return username;
        }
    }
    return nil;
}

static id SCIDMAudioCandidateObject(UIView *view) {
    NSArray<NSString *> *selectors = @[@"viewModel", @"messageViewModel", @"audioMessageViewModel", @"model", @"message", @"item"];
    for (NSString *selector in selectors) {
        id value = SCIDMAudioCall(view, selector);
        if (value) return value;
    }
    for (NSString *ivar in @[@"_viewModel", @"_messageViewModel", @"_audioMessageViewModel", @"_model", @"_message", @"_item"]) {
        id value = SCIDMAudioIvarValue(view, ivar.UTF8String);
        if (value) return value;
    }
    return view;
}

static SCIAudioItem *SCIDMAudioItemForView(UIView *view, SCIAudioSource source) {
    id object = SCIDMAudioCandidateObject(view);
    SCIAudioItem *item = [SCIAudioDownloadCoordinator audioItemFromMediaObject:object source:source];
    if (!item && view.superview) {
        item = [SCIAudioDownloadCoordinator audioItemFromMediaObject:SCIDMAudioCandidateObject(view.superview) source:source];
    }
    if (!item) return nil;
    NSString *username = SCIDMAudioResolvedUsernameNearView(view, object);
    if (username.length > 0) {
        item.artist = username;
    } else if (!item.artist.length) {
        item.artist = @"direct";
    }
    return item;
}

static void SCIDMPresentAudioActions(UIView *view, SCIAudioSource source) {
    SCIAudioItem *item = SCIDMAudioItemForView(view, source);
    if (!item) {
        SCINotify(kSCINotificationDownloadShare, @"Could not find audio URL", @"Refresh the thread and try again if the URL expired.", @"error_filled", SCINotificationToneError);
        return;
    }

    SCIGallerySaveMetadata *metadata = [[SCIGallerySaveMetadata alloc] init];
    metadata.source = (int16_t)[item gallerySource];
    metadata.sourceUsername = item.artist.length > 0 ? item.artist : @"direct";
    metadata.sourceMediaPK = item.mediaIdentifier;
    metadata.sourceMediaURLString = item.sourceURLString ?: item.url.absoluteString;

    UIViewController *presenter = [SCIUtils viewControllerForAncestralView:view] ?: topMostController();
    [SCIIGAlertPresenter presentActionSheetFromViewController:presenter
                                                        title:@"Audio"
                                                      message:nil
                                                      actions:@[
        [SCIIGAlertAction actionWithTitle:@"Save to Files" style:SCIIGAlertActionStyleDefault handler:^{
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionSaveToFiles item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSCINotificationDownloadAudio];
        }],
        [SCIIGAlertAction actionWithTitle:@"Share" style:SCIIGAlertActionStyleDefault handler:^{
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndShare item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSCINotificationDownloadAudioShare];
        }],
        [SCIIGAlertAction actionWithTitle:@"Save to Gallery" style:SCIIGAlertActionStyleDefault handler:^{
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndSaveToGallery item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSCINotificationDownloadAudioGallery];
        }],
        [SCIIGAlertAction actionWithTitle:@"Play" style:SCIIGAlertActionStyleDefault handler:^{
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionPlay item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSCINotificationPlayAudio];
        }],
        [SCIIGAlertAction actionWithTitle:@"Copy Download URL" style:SCIIGAlertActionStyleDefault handler:^{
        [SCIAudioDownloadCoordinator performAction:SCIAudioActionCopyURL item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSCINotificationCopyAudioURL];
        }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil]
    ]];
}

static id SCIDMComposerSenderTarget(id composer) {
    return [composer respondsToSelector:@selector(buttonDelegate)] ? ((id (*)(id, SEL))objc_msgSend)(composer, @selector(buttonDelegate)) : nil;
}

static id SCIDMMenuItem(NSString *title, UIImage *image, void (^handler)(id item)) {
    Class menuItemClass = NSClassFromString(@"IGDSMenuItem");
    SEL titleImageHandler = NSSelectorFromString(@"menuItemWithTitle:image:handler:");
    if (menuItemClass && [menuItemClass respondsToSelector:titleImageHandler]) {
        return ((id (*)(id, SEL, id, id, id))objc_msgSend)(menuItemClass, titleImageHandler, title, image, handler);
    }

    SEL initTitleImageHandler = NSSelectorFromString(@"initWithTitle:image:handler:");
    if (menuItemClass && [menuItemClass instancesRespondToSelector:initTitleImageHandler]) {
        return ((id (*)(id, SEL, id, id, id))objc_msgSend)([menuItemClass alloc], initTitleImageHandler, title, image, handler);
    }

    SEL initTitleImageStyleHandler = NSSelectorFromString(@"initWithTitle:image:style:handler:");
    if (menuItemClass && [menuItemClass instancesRespondToSelector:initTitleImageStyleHandler]) {
        return ((id (*)(id, SEL, id, id, NSInteger, id))objc_msgSend)([menuItemClass alloc], initTitleImageStyleHandler, title, image, 0, handler);
    }

    SEL itemTitleStyleBlock = NSSelectorFromString(@"itemWithTitle:style:block:");
    if (menuItemClass && [menuItemClass respondsToSelector:itemTitleStyleBlock]) {
        return ((id (*)(id, SEL, id, NSInteger, id))objc_msgSend)(menuItemClass, itemTitleStyleBlock, title, 0, handler);
    }
    return nil;
}

static id SCIDMUploadAudioMenuItemForComposer(id composer) {
    id senderTarget = SCIDMComposerSenderTarget(composer);
    if (![SCIAudioDMUploadCoordinator senderTargetSupportsAudioUpload:senderTarget]) {
        SCIWarnLog(@"AudioUpload", @"Missing direct audio sender on composer delegate: %@", senderTarget);
        return nil;
    }

    __weak id weakComposer = composer;
    return SCIDMMenuItem(@"Upload Audio", [SCIAssetUtils instagramIconNamed:@"audio_upload" pointSize:24.0], ^(__unused id item) {
        id strongComposer = weakComposer;
        if (!strongComposer) return;
        UIViewController *presenter = [SCIUtils viewControllerForAncestralView:(UIView *)strongComposer] ?: topMostController();
        [SCIAudioDMUploadCoordinator presentUploadPickerForSenderTarget:senderTarget
                                                              presenter:presenter
                                                             sourceView:(UIView *)strongComposer];
    });
}

static void SCIDMPresentDownloadAudioActionsForViewModel(id viewModel) {
    UIViewController *presenter = topMostController();
    UIView *sourceView = presenter.view;
    SCIAudioItem *audioItem = [SCIAudioDownloadCoordinator audioItemFromMediaObject:viewModel source:SCIAudioSourceDMs];
    if (!audioItem) {
        SCINotify(kSCINotificationDownloadShare,
                  @"Could not find audio URL",
                  @"Refresh the thread and try again if the URL expired.",
                  @"error_filled",
                  SCINotificationToneError);
        return;
    }

    SCIGallerySaveMetadata *metadata = [[SCIGallerySaveMetadata alloc] init];
    NSString *username = SCIDMAudioResolvedUsername(viewModel);
    metadata.source = (int16_t)[audioItem gallerySource];
    metadata.sourceUsername = username.length > 0 ? username : (audioItem.artist.length > 0 ? audioItem.artist : @"direct");
    metadata.sourceMediaPK = audioItem.mediaIdentifier;
    metadata.sourceMediaURLString = audioItem.sourceURLString ?: audioItem.url.absoluteString;

    [SCIIGAlertPresenter presentActionSheetFromViewController:presenter
                                                        title:@"Audio"
                                                      message:nil
                                                      actions:@[
        [SCIIGAlertAction actionWithTitle:@"Save to Files" style:SCIIGAlertActionStyleDefault handler:^{
            [SCIAudioDownloadCoordinator performAction:SCIAudioActionSaveToFiles item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadAudio];
        }],
        [SCIIGAlertAction actionWithTitle:@"Share" style:SCIIGAlertActionStyleDefault handler:^{
            [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndShare item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadAudioShare];
        }],
        [SCIIGAlertAction actionWithTitle:@"Save to Gallery" style:SCIIGAlertActionStyleDefault handler:^{
            [SCIAudioDownloadCoordinator performAction:SCIAudioActionConvertAndSaveToGallery item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationDownloadAudioGallery];
        }],
        [SCIIGAlertAction actionWithTitle:@"Play" style:SCIIGAlertActionStyleDefault handler:^{
            [SCIAudioDownloadCoordinator performAction:SCIAudioActionPlay item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationPlayAudio];
        }],
        [SCIIGAlertAction actionWithTitle:@"Copy Download URL" style:SCIIGAlertActionStyleDefault handler:^{
            [SCIAudioDownloadCoordinator performAction:SCIAudioActionCopyURL item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSCINotificationCopyAudioURL];
        }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil]
    ]];
}

static id SCIDMDownloadAudioMenuItemForViewModel(id viewModel) {
    if (![SCIUtils getBoolPref:@"msgs_download_audio_messages"]) return nil;
    if (![SCIAudioDownloadCoordinator bestAudioURLFromMediaObject:viewModel]) return nil;

    __strong id capturedViewModel = viewModel;
    return SCIDMMenuItem(@"Audio Actions", [SCIAssetUtils instagramIconNamed:@"action" pointSize:24.0], ^(__unused id item) {
        SCIDMPresentDownloadAudioActionsForViewModel(capturedViewModel);
    });
}

static id SCIDMPrismAudioDownloadElement(id templateElement, id viewModel) {
    Class builderClass = NSClassFromString(@"IGDSPrismMenuItemBuilder");
    if (!builderClass || !templateElement || !viewModel) return nil;
    SEL initSelector = @selector(initWithTitle:);
    SEL imageSelector = @selector(withImage:);
    SEL handlerSelector = @selector(withHandler:);
    SEL buildSelector = @selector(build);
    if (![builderClass instancesRespondToSelector:initSelector] ||
        ![builderClass instancesRespondToSelector:imageSelector] ||
        ![builderClass instancesRespondToSelector:handlerSelector] ||
        ![builderClass instancesRespondToSelector:buildSelector]) {
        return nil;
    }

    __strong id capturedViewModel = viewModel;
    void (^handler)(void) = ^{
        SCIDMPresentDownloadAudioActionsForViewModel(capturedViewModel);
    };

    id builder = ((id (*)(id, SEL, id))objc_msgSend)([builderClass alloc], initSelector, @"Audio Actions");
    builder = ((id (*)(id, SEL, id))objc_msgSend)(builder, imageSelector, [SCIAssetUtils instagramIconNamed:@"action" pointSize:24.0]);
    builder = ((id (*)(id, SEL, id))objc_msgSend)(builder, handlerSelector, handler);
    id menuItem = ((id (*)(id, SEL))objc_msgSend)(builder, buildSelector);
    if (!menuItem) return nil;

    id element = [[templateElement class] new];
    Ivar subtypeIvar = class_getInstanceVariable([templateElement class], "_subtype");
    Ivar itemIvar = class_getInstanceVariable([templateElement class], "_item_menuItem");
    if (!element || !subtypeIvar || !itemIvar) return nil;

    ptrdiff_t subtypeOffset = ivar_getOffset(subtypeIvar);
    *(uint64_t *)((uint8_t *)(__bridge void *)element + subtypeOffset) =
        *(uint64_t *)((uint8_t *)(__bridge void *)templateElement + subtypeOffset);
    object_setIvar(element, itemIvar, menuItem);
    return element;
}

static NSArray *SCIDMPrismMenuElementsWithAudioDownload(NSArray *elements) {
    if (!sSCIDMAudioDownloadPrismMenuPending) return elements;
    sSCIDMAudioDownloadPrismMenuPending = NO;

    id viewModel = sSCIDMAudioDownloadViewModel;
    sSCIDMAudioDownloadViewModel = nil;
    if (![SCIUtils getBoolPref:@"msgs_download_audio_messages"] || ![elements isKindOfClass:NSArray.class] || elements.count == 0) {
        return elements;
    }

    id newElement = SCIDMPrismAudioDownloadElement(elements.firstObject, viewModel);
    if (!newElement) return elements;

    NSMutableArray *updated = [NSMutableArray arrayWithObject:newElement];
    [updated addObjectsFromArray:elements];
    return [updated copy];
}

static id SCIDMPrismMenuViewInit3(id self, SEL _cmd, NSArray *elements, id headerText, BOOL edrEnabled) {
    return orig_SCIDMAudioPrismMenuViewInit3(self, _cmd, SCIDMPrismMenuElementsWithAudioDownload(elements), headerText, edrEnabled);
}

static id SCIDMPrismMenuViewInit5(id self, SEL _cmd, NSArray *elements, id headerText, BOOL edrEnabled, BOOL allowScrollingItems, BOOL allowMixedTextAlignment) {
    return orig_SCIDMAudioPrismMenuViewInit5(self, _cmd, SCIDMPrismMenuElementsWithAudioDownload(elements), headerText, edrEnabled, allowScrollingItems, allowMixedTextAlignment);
}

%group SCIDMAudioDownloadHooks

%hook IGDirectComposerOverflowController

- (id)_setupMenuItemGroup {
    id composer = SCIDMAudioIvarValue(self, "_composer");
    if (![SCIUtils getBoolPref:@"msgs_upload_audio_messages"] || !composer) {
        return %orig;
    }

    sSCIDMComposerForOverflowMenu = composer;
    sSCIDMUploadItemInjectedForOverflowMenu = NO;
    id result = %orig;
    sSCIDMComposerForOverflowMenu = nil;
    sSCIDMUploadItemInjectedForOverflowMenu = NO;
    return result;
}

%end

%hook IGDSMenu

- (id)initWithMenuItems:(id)menuItems edr:(_Bool)edr headerLabelText:(id)headerLabelText {
    id updatedItems = menuItems;
    if (sSCIDMComposerForOverflowMenu && !sSCIDMUploadItemInjectedForOverflowMenu && [menuItems isKindOfClass:NSArray.class]) {
        id item = SCIDMUploadAudioMenuItemForComposer(sSCIDMComposerForOverflowMenu);
        if (item) {
            NSMutableArray *mutableItems = [(NSArray *)menuItems mutableCopy];
            [mutableItems addObject:item];
            updatedItems = [mutableItems copy];
            sSCIDMUploadItemInjectedForOverflowMenu = YES;
        }
    }
    return %orig(updatedItems, edr, headerLabelText);
}

- (id)initWithMenuItems:(id)menuItems edr:(_Bool)edr headerLabelText:(id)headerLabelText enableScrollToDismiss:(_Bool)enableScrollToDismiss {
    id updatedItems = menuItems;
    if (sSCIDMComposerForOverflowMenu && !sSCIDMUploadItemInjectedForOverflowMenu && [menuItems isKindOfClass:NSArray.class]) {
        id item = SCIDMUploadAudioMenuItemForComposer(sSCIDMComposerForOverflowMenu);
        if (item) {
            NSMutableArray *mutableItems = [(NSArray *)menuItems mutableCopy];
            [mutableItems addObject:item];
            updatedItems = [mutableItems copy];
            sSCIDMUploadItemInjectedForOverflowMenu = YES;
        }
    }
    return %orig(updatedItems, edr, headerLabelText, enableScrollToDismiss);
}

%end

%hook _TtC32IGDirectMessageMenuConfiguration32IGDirectMessageMenuConfiguration

+ (id)menuConfigurationWithEligibleOptions:(id)options
                          messageViewModel:(id)viewModel
                               contentType:(id)contentType
                                 isSticker:(_Bool)isSticker
                            isMusicSticker:(_Bool)isMusicSticker
                          directNuxManager:(id)directNuxManager
                       sessionUserDefaults:(id)sessionUserDefaults
                                launcherSet:(id)launcherSet
                               userSession:(id)userSession
                                tapHandler:(id)tapHandler {
    id config = %orig(options, viewModel, contentType, isSticker, isMusicSticker, directNuxManager, sessionUserDefaults, launcherSet, userSession, tapHandler);
    if ([SCIUtils getBoolPref:@"msgs_download_audio_messages"] &&
        [SCIAudioDownloadCoordinator bestAudioURLFromMediaObject:viewModel]) {
        sSCIDMAudioDownloadPrismMenuPending = YES;
        sSCIDMAudioDownloadViewModel = viewModel;
    }
    return config;
}

%end

%end

extern "C" void SCIInstallDMAudioDownloadHooksIfNeeded(void) {
    if (![SCIUtils getBoolPref:@"downloads_audio_enabled"]) return;
    if (![SCIUtils getBoolPref:@"msgs_download_audio_messages"] &&
        ![SCIUtils getBoolPref:@"msgs_download_notes_audio"] &&
        ![SCIUtils getBoolPref:@"msgs_upload_audio_messages"]) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIDMAudioDownloadHooks);
        Class prismMenuViewClass = objc_getClass("IGDSPrismMenu.IGDSPrismMenuView");
        SEL init3 = @selector(initWithMenuElements:headerText:edrEnabled:);
        if (prismMenuViewClass && [prismMenuViewClass instancesRespondToSelector:init3]) {
            MSHookMessageEx(prismMenuViewClass,
                            init3,
                            (IMP)SCIDMPrismMenuViewInit3,
                            (IMP *)&orig_SCIDMAudioPrismMenuViewInit3);
        }
        SEL init5 = @selector(initWithMenuElements:headerText:edrEnabled:allowScrollingItems:allowMixedTextAlignment:);
        if (prismMenuViewClass && [prismMenuViewClass instancesRespondToSelector:init5]) {
            MSHookMessageEx(prismMenuViewClass,
                            init5,
                            (IMP)SCIDMPrismMenuViewInit5,
                            (IMP *)&orig_SCIDMAudioPrismMenuViewInit5);
        }
    });
}

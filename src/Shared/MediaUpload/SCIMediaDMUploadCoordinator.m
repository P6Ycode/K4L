#import "SCIMediaDMUploadCoordinator.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGalleryPickerViewController.h"
#import "../UI/SCINotificationCenter.h"

static SEL SCIMediaDMSendImageSelector(void) {
    return NSSelectorFromString(@"sendImage:");
}

static id SCIMediaDMIvarValue(id object, const char *name) {
    if (!object || !name) return nil;
    @try {
        for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
            Ivar ivar = class_getInstanceVariable(cls, name);
            if (!ivar) continue;
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (encoding && encoding[0] == '@') return object_getIvar(object, ivar);
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static id SCIMediaDMCall(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SCIMediaDMMessageSenderFromTarget(id target) {
    id sender = SCIMediaDMCall(target, @"messageSenderFeatureController") ?: SCIMediaDMIvarValue(target, "_messageSenderFeatureController");
    if (sender) return sender;
    id featureDelegate = SCIMediaDMCall(target, @"featureDelegate") ?: SCIMediaDMIvarValue(target, "_featureDelegate");
    return SCIMediaDMCall(featureDelegate, @"messageSenderFeatureController") ?: SCIMediaDMIvarValue(featureDelegate, "_messageSenderFeatureController");
}

static void SCIMediaDMNotify(NSString *title, NSString *message, BOOL success) {
    SCINotify(kSCINotificationDownloadShare,
              title,
              message,
              success ? @"checkmark_circle" : @"error_filled",
              success ? SCINotificationToneSuccess : SCINotificationToneError);
}

@interface SCIMediaDMUploadCoordinator ()
@property (nonatomic, strong) id senderTarget;
@end

static SCIMediaDMUploadCoordinator *sSCIMediaActiveDMUploadCoordinator;

@implementation SCIMediaDMUploadCoordinator

+ (BOOL)senderTargetSupportsMediaUpload:(id)senderTarget {
    id sender = SCIMediaDMMessageSenderFromTarget(senderTarget) ?: senderTarget;
    return sender && [sender respondsToSelector:SCIMediaDMSendImageSelector()];
}

+ (void)presentGalleryUploadPickerForSenderTarget:(id)senderTarget
                                        presenter:(UIViewController *)presenter
                                       sourceView:(UIView *)sourceView {
    if (![self senderTargetSupportsMediaUpload:senderTarget] || !presenter) {
        SCIMediaDMNotify(@"Media upload unavailable", @"This Instagram build does not expose the direct media sender.", NO);
        SCIWarnLog(@"MediaUpload", @"Missing direct media sender on target: %@", senderTarget);
        return;
    }

    NSSet<NSNumber *> *mediaTypes = [NSSet setWithObject:@(SCIGalleryMediaTypeImage)];
    if (![SCIGalleryPickerViewController hasSelectableFilesForAllowedMediaTypes:mediaTypes]) {
        SCIMediaDMNotify(@"No Gallery photos", @"Save a photo to Gallery first.", NO);
        return;
    }

    SCIMediaDMUploadCoordinator *coordinator = [[SCIMediaDMUploadCoordinator alloc] init];
    coordinator.senderTarget = senderTarget;
    sSCIMediaActiveDMUploadCoordinator = coordinator;

    __weak typeof(coordinator) weakCoordinator = coordinator;
    [SCIGalleryPickerViewController presentFromViewController:presenter
                                                       title:@"Gallery"
                                           allowedMediaTypes:mediaTypes
                                     allowsMultipleSelection:NO
                                                  completion:^(NSArray<SCIGalleryFile *> *selectedFiles) {
        SCIGalleryFile *file = selectedFiles.firstObject;
        NSURL *fileURL = [file fileURL];
        if (!file || ![file fileExists] || !fileURL) {
            if (sSCIMediaActiveDMUploadCoordinator == weakCoordinator) sSCIMediaActiveDMUploadCoordinator = nil;
            return;
        }
        [weakCoordinator sendImageFromURL:fileURL];
    }];
}

- (void)sendImageFromURL:(NSURL *)url {
    UIImage *image = [UIImage imageWithContentsOfFile:url.path];
    if (!image) {
        SCIMediaDMNotify(@"Media upload failed", @"Could not read the selected photo.", NO);
        if (sSCIMediaActiveDMUploadCoordinator == self) sSCIMediaActiveDMUploadCoordinator = nil;
        return;
    }

    id sender = SCIMediaDMMessageSenderFromTarget(self.senderTarget) ?: self.senderTarget;
    if (![sender respondsToSelector:SCIMediaDMSendImageSelector()]) {
        SCIMediaDMNotify(@"Media upload unavailable", @"The direct media sender disappeared before sending.", NO);
        if (sSCIMediaActiveDMUploadCoordinator == self) sSCIMediaActiveDMUploadCoordinator = nil;
        return;
    }

    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(sender, SCIMediaDMSendImageSelector(), image);
        SCIMediaDMNotify(@"Photo sent", @"Sent the selected photo to this chat.", YES);
    } @catch (__unused NSException *exception) {
        SCIMediaDMNotify(@"Media upload failed", @"Instagram rejected the selected photo.", NO);
    }
    if (sSCIMediaActiveDMUploadCoordinator == self) sSCIMediaActiveDMUploadCoordinator = nil;
}

@end

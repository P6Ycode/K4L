#import "SCIAudioDMUploadCoordinator.h"

#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGalleryPickerViewController.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../UI/SCINotificationCenter.h"

@interface SCIAudioDMUploadCoordinator () <UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) id senderTarget;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) UIView *sourceView;
@property (nonatomic, strong) SCINotificationPillView *progressView;
@end

static SCIAudioDMUploadCoordinator *sSCIAudioActiveDMUploadCoordinator;

extern void SCIDMConfirmVoiceMessageIfNeeded(void (^confirmBlock)(void), void (^cancelBlock)(void));

static SEL SCIAudioDMSendSelector(void) {
    return NSSelectorFromString(@"sendAudioWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:messageID:quotedPublishedMessage:");
}

static NSURL *SCIAudioDMTemporaryURL(NSString *extension) {
    NSString *name = [NSString stringWithFormat:@"scinsta-dm-audio-%@.%@",
                      NSUUID.UUID.UUIDString,
                      extension.length ? extension : @"m4a"];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

static id SCIAudioDMCreateWaveform(NSTimeInterval duration) {
    NSUInteger sampleCount = 50;
    NSMutableArray<NSNumber *> *averageVolume = [NSMutableArray arrayWithCapacity:sampleCount];
    for (NSUInteger i = 0; i < sampleCount; i++) {
        double phase = (double)(i % 10) / 10.0;
        [averageVolume addObject:@(0.12 + (phase * 0.18))];
    }

    Class waveformClass = NSClassFromString(@"IGDirectAudioWaveform");
    SEL initializer = NSSelectorFromString(@"initWithVolumeRecordingInterval:averageVolume:");
    if (!waveformClass || ![waveformClass instancesRespondToSelector:initializer]) return nil;

    double interval = (isfinite(duration) && duration > 0.1) ? MAX(duration / (double)sampleCount, 0.02) : 0.1;
    id waveform = ((id (*)(id, SEL, double, id))objc_msgSend)([waveformClass alloc],
                                                              initializer,
                                                              interval,
                                                              [averageVolume copy]);
    return [waveform respondsToSelector:@selector(averageVolume)] ? waveform : nil;
}

static id SCIAudioDMIvarValue(id object, const char *name) {
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

static id SCIAudioDMCall(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SCIAudioDMVoiceControllerFromTarget(id target) {
    id voiceController = SCIAudioDMCall(target, @"voiceController") ?: SCIAudioDMIvarValue(target, "_voiceController");
    if (voiceController) return voiceController;

    id featureDelegate = SCIAudioDMCall(target, @"featureDelegate") ?: SCIAudioDMIvarValue(target, "_featureDelegate");
    voiceController = SCIAudioDMCall(featureDelegate, @"voiceController") ?: SCIAudioDMIvarValue(featureDelegate, "_voiceController");
    if (voiceController) return voiceController;

    id composerTapHandler = SCIAudioDMCall(featureDelegate, @"composerTapHandler") ?: SCIAudioDMIvarValue(featureDelegate, "_composerTapHandler");
    return SCIAudioDMCall(composerTapHandler, @"voiceController") ?: SCIAudioDMIvarValue(composerTapHandler, "_voiceController");
}

static id SCIAudioDMMessageSenderFromTarget(id target) {
    id sender = SCIAudioDMCall(target, @"messageSenderFeatureController") ?: SCIAudioDMIvarValue(target, "_messageSenderFeatureController");
    if (sender) return sender;
    id featureDelegate = SCIAudioDMCall(target, @"featureDelegate") ?: SCIAudioDMIvarValue(target, "_featureDelegate");
    return SCIAudioDMCall(featureDelegate, @"messageSenderFeatureController") ?: SCIAudioDMIvarValue(featureDelegate, "_messageSenderFeatureController");
}

static void SCIAudioDMNotify(NSString *title, NSString *message, BOOL success) {
    SCINotify(kSCINotificationDownloadShare,
              title,
              message,
              success ? @"checkmark_circle" : @"error_filled",
              success ? SCINotificationToneSuccess : SCINotificationToneError);
}

@implementation SCIAudioDMUploadCoordinator

+ (BOOL)senderTargetSupportsAudioUpload:(id)senderTarget {
    id voiceController = SCIAudioDMVoiceControllerFromTarget(senderTarget);
    SEL voiceSelector = NSSelectorFromString(@"voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:sendButtonTypeTapped:");
    if (voiceController && [voiceController respondsToSelector:voiceSelector]) return YES;

    id sender = SCIAudioDMMessageSenderFromTarget(senderTarget) ?: senderTarget;
    return sender && [sender respondsToSelector:SCIAudioDMSendSelector()];
}

+ (void)presentUploadPickerForSenderTarget:(id)senderTarget
                                 presenter:(UIViewController *)presenter
                                sourceView:(UIView *)sourceView {
    if (![self senderTargetSupportsAudioUpload:senderTarget] || !presenter) {
        SCIAudioDMNotify(@"Audio upload unavailable", @"This Instagram build does not expose the direct audio sender.", NO);
        SCIWarnLog(@"AudioUpload", @"Missing direct audio sender on target: %@", senderTarget);
        return;
    }

    SCIAudioDMUploadCoordinator *coordinator = [[SCIAudioDMUploadCoordinator alloc] init];
    coordinator.senderTarget = senderTarget;
    coordinator.presenter = presenter;
    coordinator.sourceView = sourceView ?: presenter.view;
    sSCIAudioActiveDMUploadCoordinator = coordinator;

    [SCIIGAlertPresenter presentActionSheetFromViewController:presenter
                                                        title:@"Send Audio Message"
                                                      message:nil
                                                      actions:@[
        [SCIIGAlertAction actionWithTitle:@"Select Audio/Video from Files" style:SCIIGAlertActionStyleDefault handler:^{
        [coordinator presentFilesPicker];
        }],
        [SCIIGAlertAction actionWithTitle:@"Select from Gallery" style:SCIIGAlertActionStyleDefault handler:^{
            [coordinator presentGalleryPicker];
        }],
        [SCIIGAlertAction actionWithTitle:@"Select Video from Library" style:SCIIGAlertActionStyleDefault handler:^{
            [coordinator presentLibraryPicker];
        }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:^{
            if (sSCIAudioActiveDMUploadCoordinator == coordinator) sSCIAudioActiveDMUploadCoordinator = nil;
        }]
    ]];
}

- (void)presentFilesPicker {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio", @"public.movie", @"public.mpeg-4"]
                                                                                                    inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    picker.popoverPresentationController.sourceView = self.sourceView ?: self.presenter.view;
    picker.popoverPresentationController.sourceRect = self.sourceView ? self.sourceView.bounds : self.presenter.view.bounds;
    [self.presenter presentViewController:picker animated:YES completion:nil];
}

- (void)presentLibraryPicker {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        SCIAudioDMNotify(@"Library unavailable", @"Photo Library is not available on this device.", NO);
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.movie"];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    picker.popoverPresentationController.sourceView = self.sourceView ?: self.presenter.view;
    picker.popoverPresentationController.sourceRect = self.sourceView ? self.sourceView.bounds : self.presenter.view.bounds;
    [self.presenter presentViewController:picker animated:YES completion:nil];
}

- (void)presentGalleryPicker {
    __weak typeof(self) weakSelf = self;
    NSSet<NSNumber *> *mediaTypes = [NSSet setWithArray:@[@(SCIGalleryMediaTypeAudio), @(SCIGalleryMediaTypeVideo)]];
    if (![SCIGalleryPickerViewController hasSelectableFilesForAllowedMediaTypes:mediaTypes]) {
        SCIAudioDMNotify(@"No Gallery audio", @"Save audio or video to Gallery first.", NO);
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        return;
    }

    [SCIGalleryPickerViewController presentFromViewController:self.presenter
                                                        title:@"Gallery"
                                            allowedMediaTypes:mediaTypes
                                      allowsMultipleSelection:NO
                                                   completion:^(NSArray<SCIGalleryFile *> *selectedFiles) {
        SCIGalleryFile *file = selectedFiles.firstObject;
        NSURL *fileURL = [file fileURL];
        if (!file || ![file fileExists] || !fileURL) {
            SCIAudioDMNotify(@"No Gallery audio", @"Save audio or video to Gallery first.", NO);
            if (sSCIAudioActiveDMUploadCoordinator == weakSelf) sSCIAudioActiveDMUploadCoordinator = nil;
            return;
        }
        [weakSelf convertAndSendURL:fileURL];
    }];
}

- (void)beginUploadProgressWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    if (!SCINotificationIsEnabled(kSCINotificationDownloadShare)) return;
    if (!self.progressView) {
        self.progressView = SCINotifyProgress(kSCINotificationDownloadShare, title ?: @"Preparing audio", nil);
    }
    [self.progressView updateProgressTitle:title ?: @"Preparing audio" subtitle:subtitle];
    [self.progressView setProgress:0.05f animated:NO];
}

- (void)updateUploadProgress:(float)progress title:(NSString *)title subtitle:(NSString *)subtitle {
    if (!self.progressView) return;
    [self.progressView updateProgressTitle:title subtitle:subtitle];
    [self.progressView setProgress:progress animated:YES];
}

- (void)finishUploadProgressWithSuccess {
    if (self.progressView) {
        [self.progressView showSuccessWithTitle:@"Audio sent"
                                       subtitle:@"Uploaded the selected file as a voice note."
                                           icon:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SCINotificationPillDuration() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.progressView dismiss];
            self.progressView = nil;
        });
    } else {
        SCIAudioDMNotify(@"Audio sent", @"Uploaded the selected file as a voice note.", YES);
    }
}

- (void)finishUploadProgressWithErrorTitle:(NSString *)title subtitle:(NSString *)subtitle {
    if (self.progressView) {
        [self.progressView showErrorWithTitle:title ?: @"Audio upload failed" subtitle:subtitle icon:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SCINotificationPillDuration() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.progressView dismiss];
            self.progressView = nil;
        });
    } else {
        SCIAudioDMNotify(title ?: @"Audio upload failed", subtitle, NO);
    }
}

- (void)finishUploadProgressWithCancel {
    if (self.progressView) {
        [self.progressView dismiss];
        self.progressView = nil;
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) {
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        return;
    }

    [self convertAndSendURL:url];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    NSURL *url = info[UIImagePickerControllerMediaURL];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (url) {
            [self convertAndSendURL:url];
        } else if (sSCIAudioActiveDMUploadCoordinator == self) {
            sSCIAudioActiveDMUploadCoordinator = nil;
        }
    }];
}

- (void)convertAndSendURL:(NSURL *)url {
    BOOL securityScoped = [url startAccessingSecurityScopedResource];
    NSURL *inputURL = url;
    NSURL *copiedURL = SCIAudioDMTemporaryURL(url.pathExtension.length ? url.pathExtension : @"input");
    NSError *copyError = nil;
    [[NSFileManager defaultManager] removeItemAtURL:copiedURL error:nil];
    if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:copiedURL error:&copyError]) {
        inputURL = copiedURL;
    }
    if (securityScoped) [url stopAccessingSecurityScopedResource];

    if (copyError && ![inputURL isFileURL]) {
        SCIAudioDMNotify(@"Audio upload failed", copyError.localizedDescription ?: @"Could not import the selected file.", NO);
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        return;
    }

    [self beginUploadProgressWithTitle:@"Preparing audio" subtitle:@"Preparing a voice note compatible file."];

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
    NSArray<NSString *> *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSString *preset = [compatiblePresets containsObject:AVAssetExportPresetAppleM4A] ? AVAssetExportPresetAppleM4A : AVAssetExportPresetPassthrough;
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!session) {
        [self finishUploadProgressWithErrorTitle:@"Audio upload failed" subtitle:@"Could not create an audio conversion session."];
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        return;
    }

    NSURL *outputURL = SCIAudioDMTemporaryURL(@"m4a");
    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    session.outputURL = outputURL;
    session.outputFileType = AVFileTypeAppleM4A;
    [self updateUploadProgress:0.15f title:@"Converting audio" subtitle:@"Preparing a voice note compatible file."];

    [session exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (session.status != AVAssetExportSessionStatusCompleted || ![[NSFileManager defaultManager] fileExistsAtPath:outputURL.path]) {
                NSString *message = session.error.localizedDescription ?: @"Instagram may not support this media format.";
                [self finishUploadProgressWithErrorTitle:@"Audio conversion failed" subtitle:message];
                if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
                return;
            }

            [self updateUploadProgress:0.85f title:@"Sending audio" subtitle:nil];
            [self sendConvertedURL:outputURL duration:CMTimeGetSeconds(asset.duration)];
        });
    }];
}

- (void)sendConvertedURL:(NSURL *)url duration:(NSTimeInterval)duration {
    if (![SCIAudioDMUploadCoordinator senderTargetSupportsAudioUpload:self.senderTarget]) {
        [self finishUploadProgressWithErrorTitle:@"Audio upload unavailable" subtitle:@"The direct audio sender disappeared before sending."];
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        return;
    }

    NSTimeInterval safeDuration = isfinite(duration) && duration > 0 ? duration : 0;
    id waveform = SCIAudioDMCreateWaveform(safeDuration);
    if (!waveform) {
        [self finishUploadProgressWithErrorTitle:@"Audio upload unavailable" subtitle:@"Could not create an Instagram audio waveform."];
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        return;
    }

    id voiceController = SCIAudioDMVoiceControllerFromTarget(self.senderTarget);
    SEL voiceSelector = NSSelectorFromString(@"voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:sendButtonTypeTapped:");
    if (voiceController && [voiceController respondsToSelector:voiceSelector]) {
        SCIDMConfirmVoiceMessageIfNeeded(^{
            void (*sendVoice)(id, SEL, id, id, id, double, long long, id, id, long long) = (void (*)(id, SEL, id, id, id, double, long long, id, id, long long))objc_msgSend;
            sendVoice(voiceController, voiceSelector, nil, url, waveform, safeDuration, 0, nil, nil, 0);
            [self updateUploadProgress:1.0f title:@"Audio sent" subtitle:nil];
            [self finishUploadProgressWithSuccess];
            if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        }, ^{
            [self finishUploadProgressWithCancel];
            if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        });
        return;
    }

    id sender = SCIAudioDMMessageSenderFromTarget(self.senderTarget) ?: self.senderTarget;
    if (![sender respondsToSelector:SCIAudioDMSendSelector()]) {
        [self finishUploadProgressWithErrorTitle:@"Audio upload unavailable" subtitle:@"The direct audio sender disappeared before sending."];
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
        return;
    }

    SCIDMConfirmVoiceMessageIfNeeded(^{
        void (*sendAudio)(id, SEL, id, id, double, long long, id, id, id, id) = (void (*)(id, SEL, id, id, double, long long, id, id, id, id))objc_msgSend;
        sendAudio(sender,
                  SCIAudioDMSendSelector(),
                  url,
                  waveform,
                  safeDuration,
                  0,
                  nil,
                  nil,
                  nil,
                  nil);
        [self updateUploadProgress:1.0f title:@"Audio sent" subtitle:nil];
        [self finishUploadProgressWithSuccess];
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
    }, ^{
        [self finishUploadProgressWithCancel];
        if (sSCIAudioActiveDMUploadCoordinator == self) sSCIAudioActiveDMUploadCoordinator = nil;
    });
}

@end

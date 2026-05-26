#import <substrate.h>
#import <objc/runtime.h>

#import "../../Utils.h"

static NSString * const kSCIDMVoiceMessageConfirmPref = @"msgs_confirm_voice_msg";

typedef void (*SCIDMVoiceNoArgIMP)(id, SEL);
typedef void (*SCIDMVoiceLegacyRecordedIMP)(id, SEL, id, id, id, double, long long);
typedef void (*SCIDMVoiceRecordedIMP)(id, SEL, id, id, id, double, long long, id, id, long long);
typedef void (*SCIDMVoicePreviewSendIMP)(id, SEL, id, id, double, long long, id, id);

static SCIDMVoiceLegacyRecordedIMP orig_threadViewLegacyRecordedAudioClip = NULL;
static SCIDMVoiceRecordedIMP orig_threadViewRecordedAudioClip = NULL;
static SCIDMVoiceRecordedIMP orig_voiceControllerRecordedAudioClip = NULL;
static SCIDMVoicePreviewSendIMP orig_voiceRecordPreviewDidTapSend = NULL;
static SCIDMVoiceNoArgIMP orig_voiceRecordPreviewSendButton = NULL;
static SCIDMVoiceNoArgIMP orig_aiVoiceCompactBarDidTapSend = NULL;

static BOOL sSCIDMVoiceConfirmBypassing = NO;
static BOOL sSCIDMVoiceConfirmVisible = NO;

static BOOL SCIDMShouldConfirmVoiceMessage(void) {
    return [SCIUtils getBoolPref:kSCIDMVoiceMessageConfirmPref];
}

void SCIDMConfirmVoiceMessageIfNeeded(void (^confirmBlock)(void), void (^cancelBlock)(void)) {
    if (sSCIDMVoiceConfirmBypassing || !SCIDMShouldConfirmVoiceMessage()) {
        if (confirmBlock) confirmBlock();
        return;
    }

    if (sSCIDMVoiceConfirmVisible) return;

    sSCIDMVoiceConfirmVisible = YES;
    SCILog(@"General", @"[SCInsta] DM audio message confirm triggered");
    [SCIUtils showConfirmation:^{
        sSCIDMVoiceConfirmVisible = NO;
        sSCIDMVoiceConfirmBypassing = YES;
        if (confirmBlock) confirmBlock();
        sSCIDMVoiceConfirmBypassing = NO;
    } cancelHandler:^{
        sSCIDMVoiceConfirmVisible = NO;
        if (cancelBlock) cancelBlock();
    } title:@"Confirm Send Voice Message"
      message:@"Are you sure you want to send this voice message?"];
}

static void SCIDMConfirmVoiceMessage(void (^confirmBlock)(void)) {
    SCIDMConfirmVoiceMessageIfNeeded(confirmBlock, nil);
}

static void replaced_threadViewLegacyRecordedAudioClip(id self, SEL _cmd, id controller, id url, id waveform, double duration, long long entryPoint) {
    SCIDMConfirmVoiceMessage(^{
        if (orig_threadViewLegacyRecordedAudioClip) {
            orig_threadViewLegacyRecordedAudioClip(self, _cmd, controller, url, waveform, duration, entryPoint);
        }
    });
}

static void replaced_threadViewRecordedAudioClip(id self, SEL _cmd, id controller, id url, id waveform, double duration, long long entryPoint, id aiVoiceEffectApplied, id aiVoiceEffectType, long long sendButtonTypeTapped) {
    SCIDMConfirmVoiceMessage(^{
        if (orig_threadViewRecordedAudioClip) {
            orig_threadViewRecordedAudioClip(self, _cmd, controller, url, waveform, duration, entryPoint, aiVoiceEffectApplied, aiVoiceEffectType, sendButtonTypeTapped);
        }
    });
}

static void replaced_voiceControllerRecordedAudioClip(id self, SEL _cmd, id controller, id url, id waveform, double duration, long long entryPoint, id aiVoiceEffectApplied, id aiVoiceEffectType, long long sendButtonTypeTapped) {
    SCIDMConfirmVoiceMessage(^{
        if (orig_voiceControllerRecordedAudioClip) {
            orig_voiceControllerRecordedAudioClip(self, _cmd, controller, url, waveform, duration, entryPoint, aiVoiceEffectApplied, aiVoiceEffectType, sendButtonTypeTapped);
        }
    });
}

static void replaced_voiceRecordPreviewDidTapSend(id self, SEL _cmd, id url, id waveform, double duration, long long entryPoint, id aiVoiceEffectApplied, id aiVoiceEffectType) {
    SCIDMConfirmVoiceMessage(^{
        if (orig_voiceRecordPreviewDidTapSend) {
            orig_voiceRecordPreviewDidTapSend(self, _cmd, url, waveform, duration, entryPoint, aiVoiceEffectApplied, aiVoiceEffectType);
        }
    });
}

static void replaced_voiceRecordPreviewSendButton(id self, SEL _cmd) {
    SCIDMConfirmVoiceMessage(^{
        if (orig_voiceRecordPreviewSendButton) {
            orig_voiceRecordPreviewSendButton(self, _cmd);
        }
    });
}

static void replaced_aiVoiceCompactBarDidTapSend(id self, SEL _cmd) {
    SCIDMConfirmVoiceMessage(^{
        if (orig_aiVoiceCompactBarDidTapSend) {
            orig_aiVoiceCompactBarDidTapSend(self, _cmd);
        }
    });
}

static void SCIHookDMVoiceInstanceMethod(const char *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    if (!cls || !class_getInstanceMethod(cls, selector)) return;

    MSHookMessageEx(cls, selector, replacement, original);
}

void SCIInstallDMAudioMsgConfirmHooksIfEnabled(void) {
    if (!SCIDMShouldConfirmVoiceMessage()) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCIHookDMVoiceInstanceMethod("IGDirectThreadViewController",
                                     @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:),
                                     (IMP)replaced_threadViewLegacyRecordedAudioClip,
                                     (IMP *)&orig_threadViewLegacyRecordedAudioClip);
        SCIHookDMVoiceInstanceMethod("IGDirectThreadViewController",
                                     @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:sendButtonTypeTapped:),
                                     (IMP)replaced_threadViewRecordedAudioClip,
                                     (IMP *)&orig_threadViewRecordedAudioClip);
        SCIHookDMVoiceInstanceMethod("IGDirectThreadViewVoiceController",
                                     @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:sendButtonTypeTapped:),
                                     (IMP)replaced_voiceControllerRecordedAudioClip,
                                     (IMP *)&orig_voiceControllerRecordedAudioClip);
        SCIHookDMVoiceInstanceMethod("_TtC24IGDirectVoiceRecordingUI33IGDirectVoiceRecordViewController",
                                     @selector(voiceRecordPreviewContentViewControllerDidTapSendWithUrl:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:),
                                     (IMP)replaced_voiceRecordPreviewDidTapSend,
                                     (IMP *)&orig_voiceRecordPreviewDidTapSend);
        SCIHookDMVoiceInstanceMethod("_TtC29IGDirectVoiceRecordingPreview40IGDirectVoiceRecordPreviewViewController",
                                     @selector(didTapSendButton),
                                     (IMP)replaced_voiceRecordPreviewSendButton,
                                     (IMP *)&orig_voiceRecordPreviewSendButton);
        SCIHookDMVoiceInstanceMethod("_TtC20IGDirectAIVoiceUIKitP33_5754F7617E0D924F9A84EFA352BBD29A21CompactBarContentView",
                                     @selector(didTapSend),
                                     (IMP)replaced_aiVoiceCompactBarDidTapSend,
                                     (IMP *)&orig_aiVoiceCompactBarDidTapSend);
    });
}

// Rewrites Instagram's copied share links into a cleaner canonical form.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL SPKShouldSanitizeCopiedShareLinks(void) {
    return [SPKUtils getBoolPref:@"general_strip_share_link_tracking"];
}

static void SPKPollClipboardAndSanitize(NSInteger countBefore, int polls, double interval) {
    __block BOOL done = NO;
    for (int i = 0; i < polls; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((interval + (i * interval)) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (done) return;
            if ([UIPasteboard generalPasteboard].changeCount == countBefore) return;

            NSString *string = [UIPasteboard generalPasteboard].string;
            NSURL *url = string.length > 0 ? [NSURL URLWithString:string] : nil;
            NSURL *sanitized = [SPKUtils sanitizedInstagramShareURL:url];
            if (sanitized.absoluteString.length > 0 && ![sanitized.absoluteString isEqualToString:string]) {
                [UIPasteboard generalPasteboard].string = sanitized.absoluteString;
            }
            done = YES;
        });
    }
}

// IG 436+ : the external share sheet became Swift
// (IGExternalShareOptions.IGExternalShareOptionsViewController) and the dedicated
// `_shareToClipboardFromVC:` method is gone. Every share button now routes through
// `shareTo:` with an IGExternalShareOptionsType enum value. The copy-link value
// isn't recoverable from the dumped headers, so instead of matching a specific
// value we poll the pasteboard after any share: the sanitizer only rewrites when
// the clipboard actually changed AND contains an Instagram URL, so non-copy
// shares are inherently no-ops.
static void (*orig_shareTo)(id, SEL, long long);
static void replaced_shareTo(id self, SEL _cmd, long long shareType) {
    if (!SPKShouldSanitizeCopiedShareLinks()) {
        orig_shareTo(self, _cmd, shareType);
        return;
    }
    NSInteger countBefore = [UIPasteboard generalPasteboard].changeCount;
    orig_shareTo(self, _cmd, shareType);
    SPKPollClipboardAndSanitize(countBefore, 30, 0.05);
}

extern "C" void SPKInstallSharedLinkCleanupHooksIfEnabled(void) {
    if (!SPKShouldSanitizeCopiedShareLinks()) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = SPKResolveIGClass(@"IGExternalShareOptions.IGExternalShareOptionsViewController", @"IGExternalShareOptionsViewController");
        SEL selector = NSSelectorFromString(@"shareTo:");
        if (!cls || !class_getInstanceMethod(cls, selector)) return;
        MSHookMessageEx(cls, selector, (IMP)replaced_shareTo, (IMP *)&orig_shareTo);
    });
}

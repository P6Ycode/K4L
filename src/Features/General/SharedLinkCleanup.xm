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
            if (done)
                return;
            if ([UIPasteboard generalPasteboard].changeCount == countBefore)
                return;

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

// Other copy-link surfaces (e.g. the profile "..." menu's "Copy Profile URL" row)
// don't go through IGExternalShareOptionsViewController at all and write directly
// to the pasteboard from their own obfuscated/Swift presenters, so `shareTo:`
// alone misses them. Rather than chasing every surface's internal selector,
// hook every UIPasteboard write entry point and reuse the same poll mechanism
// above. Crucially, `generalPasteboard` returns an instance of the private
// `_UIConcretePasteboard` class cluster member, which has its own overrides of
// these setters — hooking the public `UIPasteboard` base class alone never
// intercepts those instances, which is why the profile menu's write slipped
// through. All the public setters above `setString:`/`setItems:options:` (and
// the private `_setItemsAndSave:options:...` family some of them funnel
// through) need covering since different call sites favor different ones.
#define SPK_HOOK_PASTEBOARD_WRITE_BODY(name, call)                        \
    if (!SPKShouldSanitizeCopiedShareLinks()) {                           \
        call;                                                             \
        return;                                                           \
    }                                                                     \
    NSInteger countBefore = [UIPasteboard generalPasteboard].changeCount; \
    call;                                                                 \
    SPKPollClipboardAndSanitize(countBefore, 30, 0.05);

static void (*orig_setString)(id, SEL, NSString *);
static void replaced_setString(id self, SEL _cmd, NSString *string) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setString, orig_setString(self, _cmd, string))
}

static void (*orig_setURL)(id, SEL, NSURL *);
static void replaced_setURL(id self, SEL _cmd, NSURL *url) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setURL, orig_setURL(self, _cmd, url))
}

static void (*orig_setStrings)(id, SEL, NSArray *);
static void replaced_setStrings(id self, SEL _cmd, NSArray *strings) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setStrings, orig_setStrings(self, _cmd, strings))
}

static void (*orig_setURLs)(id, SEL, NSArray *);
static void replaced_setURLs(id self, SEL _cmd, NSArray *urls) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setURLs, orig_setURLs(self, _cmd, urls))
}

static void (*orig_setItems)(id, SEL, NSArray *);
static void replaced_setItems(id self, SEL _cmd, NSArray *items) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setItems, orig_setItems(self, _cmd, items))
}

static void (*orig_addItems)(id, SEL, NSArray *);
static void replaced_addItems(id self, SEL _cmd, NSArray *items) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(addItems, orig_addItems(self, _cmd, items))
}

static void (*orig_setItemsOptions)(id, SEL, NSArray *, NSDictionary *);
static void replaced_setItemsOptions(id self, SEL _cmd, NSArray *items, NSDictionary *options) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setItemsOptions, orig_setItemsOptions(self, _cmd, items, options))
}

static void (*orig_setValueForPasteboardType)(id, SEL, id, NSString *);
static void replaced_setValueForPasteboardType(id self, SEL _cmd, id value, NSString *pasteboardType) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setValueForPasteboardType, orig_setValueForPasteboardType(self, _cmd, value, pasteboardType))
}

static void (*orig_setDataForPasteboardType)(id, SEL, NSData *, NSString *);
static void replaced_setDataForPasteboardType(id self, SEL _cmd, NSData *data, NSString *pasteboardType) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setDataForPasteboardType, orig_setDataForPasteboardType(self, _cmd, data, pasteboardType))
}

static void (*orig_setObjects)(id, SEL, NSArray *);
static void replaced_setObjects(id self, SEL _cmd, NSArray *objects) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setObjects, orig_setObjects(self, _cmd, objects))
}

static void (*orig_setObjectsOptions)(id, SEL, NSArray *, NSDictionary *);
static void replaced_setObjectsOptions(id self, SEL _cmd, NSArray *objects, NSDictionary *options) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setObjectsOptions, orig_setObjectsOptions(self, _cmd, objects, options))
}

static void (*orig_setObjectsLocalOnlyExpirationDate)(id, SEL, NSArray *, BOOL, NSDate *);
static void replaced_setObjectsLocalOnlyExpirationDate(id self, SEL _cmd, NSArray *objects, BOOL localOnly, NSDate *expirationDate) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setObjectsLocalOnlyExpirationDate, orig_setObjectsLocalOnlyExpirationDate(self, _cmd, objects, localOnly, expirationDate))
}

static void (*orig_setItemsAndSaveOptions)(id, SEL, NSArray *, NSDictionary *);
static void replaced_setItemsAndSaveOptions(id self, SEL _cmd, NSArray *items, NSDictionary *options) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setItemsAndSaveOptions, orig_setItemsAndSaveOptions(self, _cmd, items, options))
}

static void (*orig_setItemsAndSaveOptionsCoerce)(id, SEL, NSArray *, NSDictionary *, BOOL);
static void replaced_setItemsAndSaveOptionsCoerce(id self, SEL _cmd, NSArray *items, NSDictionary *options, BOOL coerceStringsToURLs) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setItemsAndSaveOptionsCoerce, orig_setItemsAndSaveOptionsCoerce(self, _cmd, items, options, coerceStringsToURLs))
}

static void (*orig_setItemsAndSaveOptionsCoerceDataOwner)(id, SEL, NSArray *, NSDictionary *, BOOL, id);
static void replaced_setItemsAndSaveOptionsCoerceDataOwner(id self, SEL _cmd, NSArray *items, NSDictionary *options, BOOL coerceStringsToURLs, id dataOwner) {
    SPK_HOOK_PASTEBOARD_WRITE_BODY(setItemsAndSaveOptionsCoerceDataOwner, orig_setItemsAndSaveOptionsCoerceDataOwner(self, _cmd, items, options, coerceStringsToURLs, dataOwner))
}

#undef SPK_HOOK_PASTEBOARD_WRITE_BODY

extern "C" void SPKInstallSharedLinkCleanupHooksIfEnabled(void) {
    if (!SPKShouldSanitizeCopiedShareLinks())
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class shareCls = SPKResolveIGClass(@"IGExternalShareOptions.IGExternalShareOptionsViewController", @"IGExternalShareOptionsViewController");
        SEL shareSelector = NSSelectorFromString(@"shareTo:");
        if (shareCls && class_getInstanceMethod(shareCls, shareSelector)) {
            MSHookMessageEx(shareCls, shareSelector, (IMP)replaced_shareTo, (IMP *)&orig_shareTo);
        }

        // `generalPasteboard` returns an instance of this private concrete
        // subclass; hooking only the public `UIPasteboard` base class is a
        // no-op against it. Fall back to the base class for older iOS where
        // it doesn't exist.
        Class pasteboardCls = NSClassFromString(@"_UIConcretePasteboard");
        if (!pasteboardCls)
            pasteboardCls = [UIPasteboard class];
        if (!pasteboardCls)
            return;

#define SPK_INSTALL_PASTEBOARD_HOOK(sel, name)                                                   \
    do {                                                                                         \
        SEL selector = sel;                                                                      \
        if (class_getInstanceMethod(pasteboardCls, selector)) {                                  \
            MSHookMessageEx(pasteboardCls, selector, (IMP)replaced_##name, (IMP *)&orig_##name); \
        }                                                                                        \
    } while (0)

        SPK_INSTALL_PASTEBOARD_HOOK(@selector(setString:), setString);
        SPK_INSTALL_PASTEBOARD_HOOK(@selector(setURL:), setURL);
        SPK_INSTALL_PASTEBOARD_HOOK(@selector(setStrings:), setStrings);
        SPK_INSTALL_PASTEBOARD_HOOK(@selector(setURLs:), setURLs);
        SPK_INSTALL_PASTEBOARD_HOOK(@selector(setItems:), setItems);
        SPK_INSTALL_PASTEBOARD_HOOK(@selector(addItems:), addItems);
        SPK_INSTALL_PASTEBOARD_HOOK(@selector(setItems:options:), setItemsOptions);
        SPK_INSTALL_PASTEBOARD_HOOK(NSSelectorFromString(@"setValue:forPasteboardType:"), setValueForPasteboardType);
        SPK_INSTALL_PASTEBOARD_HOOK(NSSelectorFromString(@"setData:forPasteboardType:"), setDataForPasteboardType);
        SPK_INSTALL_PASTEBOARD_HOOK(@selector(setObjects:), setObjects);
        SPK_INSTALL_PASTEBOARD_HOOK(NSSelectorFromString(@"setObjects:options:"), setObjectsOptions);
        SPK_INSTALL_PASTEBOARD_HOOK(@selector(setObjects:localOnly:expirationDate:), setObjectsLocalOnlyExpirationDate);
        SPK_INSTALL_PASTEBOARD_HOOK(NSSelectorFromString(@"_setItemsAndSave:options:"), setItemsAndSaveOptions);
        SPK_INSTALL_PASTEBOARD_HOOK(NSSelectorFromString(@"_setItemsAndSave:options:coerceStringsToURLs:"), setItemsAndSaveOptionsCoerce);
        SPK_INSTALL_PASTEBOARD_HOOK(NSSelectorFromString(@"_setItemsAndSave:options:coerceStringsToURLs:dataOwner:"), setItemsAndSaveOptionsCoerceDataOwner);

#undef SPK_INSTALL_PASTEBOARD_HOOK
    });
}

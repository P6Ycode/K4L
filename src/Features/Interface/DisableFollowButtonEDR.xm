#import <substrate.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"

static NSString * const kSCIFollowButtonAccessibilityIdentifier = @"follow-button";

static void (*orig_IGFollowButton_setEdr)(id, SEL, BOOL);
static void (*orig_IGFollowButton_setEDR)(id, SEL, BOOL);
static id (*orig_IGFollowButton_initWithViewConfiguration)(id, SEL, id);
static void (*orig_IGFollowButton_setAccessibilityIdentifier)(id, SEL, NSString *);

static BOOL SCIIsTargetFollowButton(id self) {
    if (![self respondsToSelector:@selector(accessibilityIdentifier)]) return NO;
    NSString *identifier = ((NSString *(*)(id, SEL))objc_msgSend)(self, @selector(accessibilityIdentifier));
    return [identifier isEqualToString:kSCIFollowButtonAccessibilityIdentifier];
}

static void SCISetFollowButtonEDROffIfNeeded(id self) {
    if (!SCIIsTargetFollowButton(self)) return;

    SEL setEdr = @selector(setEdr:);
    if ([self respondsToSelector:setEdr]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, setEdr, NO);
        return;
    }

    SEL setEDR = @selector(setEDR:);
    if ([self respondsToSelector:setEDR]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, setEDR, NO);
    }
}

static void hooked_IGFollowButton_setEdr(id self, SEL _cmd, BOOL edr) {
    BOOL target = SCIIsTargetFollowButton(self);
    if (orig_IGFollowButton_setEdr) {
        orig_IGFollowButton_setEdr(self, _cmd, target ? NO : edr);
    }
}

static void hooked_IGFollowButton_setEDR(id self, SEL _cmd, BOOL edr) {
    BOOL target = SCIIsTargetFollowButton(self);
    if (orig_IGFollowButton_setEDR) {
        orig_IGFollowButton_setEDR(self, _cmd, target ? NO : edr);
    }
}

static id hooked_IGFollowButton_initWithViewConfiguration(id self, SEL _cmd, id configuration) {
    id result = orig_IGFollowButton_initWithViewConfiguration
        ? orig_IGFollowButton_initWithViewConfiguration(self, _cmd, configuration)
        : self;
    SCISetFollowButtonEDROffIfNeeded(result);
    return result;
}

static void hooked_IGFollowButton_setAccessibilityIdentifier(id self, SEL _cmd, NSString *identifier) {
    if (orig_IGFollowButton_setAccessibilityIdentifier) {
        orig_IGFollowButton_setAccessibilityIdentifier(self, _cmd, identifier);
    }
    if ([identifier isEqualToString:kSCIFollowButtonAccessibilityIdentifier]) {
        SCISetFollowButtonEDROffIfNeeded(self);
    }
}

static void SCIHookIGFollowButtonSelector(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || ![cls instancesRespondToSelector:selector]) return;
    MSHookMessageEx(cls, selector, replacement, original);
}

extern "C" void SCIInstallDisableFollowButtonEDRHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"interface_disable_follow_button_edr"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = objc_getClass("IGFollowButton");
        if (!cls) return;

        SCIHookIGFollowButtonSelector(cls,
                                      @selector(setEdr:),
                                      (IMP)hooked_IGFollowButton_setEdr,
                                      (IMP *)&orig_IGFollowButton_setEdr);
        SCIHookIGFollowButtonSelector(cls,
                                      @selector(setEDR:),
                                      (IMP)hooked_IGFollowButton_setEDR,
                                      (IMP *)&orig_IGFollowButton_setEDR);
        SCIHookIGFollowButtonSelector(cls,
                                      @selector(initWithViewConfiguration:),
                                      (IMP)hooked_IGFollowButton_initWithViewConfiguration,
                                      (IMP *)&orig_IGFollowButton_initWithViewConfiguration);
        SCIHookIGFollowButtonSelector(cls,
                                      @selector(setAccessibilityIdentifier:),
                                      (IMP)hooked_IGFollowButton_setAccessibilityIdentifier,
                                      (IMP *)&orig_IGFollowButton_setAccessibilityIdentifier);
    });
}

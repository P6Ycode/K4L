#import <UIKit/UIKit.h>

#import "../../Utils.h"

static NSString * const kSCIInstantsConfirmReactionPref = @"instants_confirm_reaction";

static BOOL SCIInstantsConfirmReactionEnabled(void) {
    return [SCIUtils getBoolPref:kSCIInstantsConfirmReactionPref];
}

static BOOL SCIInstantsResponderChainContainsQuickSnap(UIResponder *responder) {
    UIResponder *current = responder;
    while (current) {
        if ([NSStringFromClass(current.class) containsString:@"QuickSnap"]) return YES;
        current = current.nextResponder;
    }
    return NO;
}

static NSString *SCIInstantsControlText(UIControl *control) {
    if (!control) return nil;
    id text = nil;
    @try { text = [control valueForKey:@"text"]; } @catch (__unused NSException *exception) {}
    if ([text isKindOfClass:NSString.class]) return text;
    return control.accessibilityLabel;
}

static BOOL SCIInstantsLooksLikeEmojiText(NSString *text) {
    if (text.length == 0 || text.length > 16) return NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9')) {
            return NO;
        }
    }
    return YES;
}

%group SCIInstantsReactionConfirmHooks

%hook IGBouncyTextButton
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if (!sel_isEqual(action, @selector(didTapToReact:)) ||
        !SCIInstantsConfirmReactionEnabled() ||
        !SCIInstantsResponderChainContainsQuickSnap((UIResponder *)self) ||
        !SCIInstantsLooksLikeEmojiText(SCIInstantsControlText((UIControl *)self))) {
        %orig;
        return;
    }

    [SCIUtils showConfirmation:^{
        %orig;
    }
                         title:@"Confirm Instant Reaction"
                       message:@"Are you sure you want to react to this Instant?"];
}
%end

%end

extern "C" void SCIInstallInstantsReactionConfirmHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIInstantsReactionConfirmHooks);
        SCILog(@"Instants", @"[SCInsta] Instants reaction confirm hooks installed");
    });
}

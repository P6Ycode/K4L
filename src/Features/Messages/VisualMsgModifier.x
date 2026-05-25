#import "../../Utils.h"

%group SCIVisualMsgModifierHooks

%hook IGDirectVisualMessage
- (NSInteger)viewMode {
    NSInteger mode = %orig;

    // * Modes *
    // 0 - View Once
    // 1 - Replayable

    if ([SCIUtils getBoolPref:@"msgs_disable_view_once"]) {
        if (mode == 0) {
            mode = 1;

            SCILog(@"General", @"[SCInsta] Modifying visual message from read-once to replayable");
        }
    }
    
    return mode;
}
%end

%end

void SCIInstallVisualMsgModifierHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"msgs_disable_view_once"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIVisualMsgModifierHooks);
    });
}

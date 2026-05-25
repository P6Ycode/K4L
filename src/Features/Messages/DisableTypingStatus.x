#import "../../Utils.h"

%group SCIDisableTypingStatusHooks

%hook IGDirectTypingStatusService
- (void)updateOutgoingStatusIsActive:(_Bool)active threadKey:(id)key threadMetadata:(id)metadata typingStatusType:(long long)type {
    if ([SCIUtils getBoolPref:@"msgs_disable_typing"]) return;

    return %orig(active, key, metadata, type);
}
%end

%end

void SCIInstallDisableTypingStatusHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"msgs_disable_typing"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIDisableTypingStatusHooks);
    });
}

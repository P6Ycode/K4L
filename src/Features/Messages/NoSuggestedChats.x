#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Channels dms tab (header)
%group SCINoSuggestedChatsHooks

%hook IGDirectInboxHeaderSectionController
- (id)viewModel {
    if ([[%orig title] isEqualToString:@"Suggested"]) {

        if ([SCIUtils getBoolPref:@"msgs_hide_suggested_chats"]) {
            SCILog(@"General", @"[SCInsta] Hiding suggested chats (header: channels tab)");

            return nil;
        }

    }

    return %orig;
}
%end

%end

void SCIInstallNoSuggestedChatsHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"msgs_hide_suggested_chats"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCINoSuggestedChatsHooks);
    });
}

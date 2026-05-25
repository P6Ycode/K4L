#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Disable story data source
%group SCIHideStoryTrayHooks

%hook IGMainStoryTrayDataSource
- (id)initWithUserSession:(id)arg1 {
    if ([SCIUtils getBoolPref:@"feed_hide_stories_tray"]) {
        SCILog(@"General", @"[SCInsta] Hiding story tray");

        return nil;
    }
    
    return %orig;
}
%end

%end

void SCIInstallHideStoryTrayHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"feed_hide_stories_tray"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIHideStoryTrayHooks);
    });
}

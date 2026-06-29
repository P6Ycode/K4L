#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Disable story data source
%group SPKHideStoryTrayHooks

%hook IGMainStoryTrayDataSource
- (id)initWithUserSession:(id)arg1 {
    if ([SPKUtils getBoolPref:@"feed_hide_stories_tray"]) {
        SPKLog(@"General", @"[Sparkle] Hiding story tray");

        return nil;
    }
    
    return %orig;
}
%end

%end

void SPKInstallHideStoryTrayHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"feed_hide_stories_tray"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKHideStoryTrayHooks);
    });
}

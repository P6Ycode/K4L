#import "../../Utils.h"

%group SCIHideFriendsMapHooks

%hook IGDirectNotesTrayRowCell
- (id)listAdapterObjects {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        if ([SCIUtils getBoolPref:@"msgs_hide_friends_map"]) {

            if ([obj isKindOfClass:%c(IGDirectNotesTrayUserViewModel)]) {

                if ([[obj valueForKey:@"notePk"] isEqualToString:@"friends_map"]) {
                    SCILog(@"General", @"[SCInsta] Hiding friends map");

                    shouldHide = YES;
                }

            }
            
        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }
    }

    return [filteredObjs copy];
}
%end

%end

void SCIInstallHideFriendsMapHooksIfEnabled(void) {
    if (![SCIUtils getBoolPref:@"msgs_hide_friends_map"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIHideFriendsMapHooks);
    });
}

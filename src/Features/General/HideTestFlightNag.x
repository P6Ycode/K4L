#import "../../Utils.h"

#import <Foundation/Foundation.h>

%group SCIHideTestFlightNagReceipt
%hook NSBundle

- (NSURL *)appStoreReceiptURL {
    NSURL *url = %orig;
    if (self == NSBundle.mainBundle && [url.lastPathComponent isEqualToString:@"sandboxReceipt"]) {
        return [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"receipt"];
    }
    return url;
}

%end
%end

%ctor {
    if ([SCIUtils getBoolPref:@"hide_testflight_nag"]) {
        %init(SCIHideTestFlightNagReceipt);
    }
}

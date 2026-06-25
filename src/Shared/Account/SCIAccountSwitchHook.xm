#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "SCIAccountManager.h"
#import "../ActionButton/ActionButtonCore.h"

// Keeps SCIAccountManager's cached account in sync with in-app account switches,
// which don't background the app (so the foreground refresh never fires). We set
// the new account BEFORE %orig so the feed/UI that rebuilds during the switch
// already reads the correct per-account namespace, and refresh the action-button
// chrome so its icons reflect the new account immediately.
static void SCIAccountSwitchNotePK(NSString *pk) {
    if (pk.length == 0) return;
    [[SCIAccountManager shared] noteSwitchedToAccountPK:pk];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIActionButtonConfigurationDidChangeNotification object:nil];
}

%hook IGAccountSwitcher

- (long long)switchToUserWithPK:(id)pk
              destinationAppSurface:(id)surface
                     destinationURL:(id)url
                         entryPoint:(long long)point
                        loggingData:(id)data {
    NSString *pkString = [pk isKindOfClass:[NSString class]] ? pk : ([pk respondsToSelector:@selector(stringValue)] ? [pk stringValue] : [pk description]);
    SCIAccountSwitchNotePK(pkString);
    return %orig;
}

- (long long)switchToUser:(id)user
        destinationAppSurface:(id)surface
               destinationURL:(id)url
                   entryPoint:(long long)point
                  loggingData:(id)data {
    SCIAccountSwitchNotePK([SCIUtils pkFromIGUser:user]);
    return %orig;
}

%end

extern "C" void SCIInstallAccountSwitchHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init;
    });
}

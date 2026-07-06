#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

#import "../../Utils.h"

// Sideloaded Instagram delivers some notifications twice: while the app is
// foregrounded, IG's realtime layer locally re-enqueues an incoming message via
// -[UNUserNotificationCenter addNotificationRequest:withCompletionHandler:],
// *while* the bundled InstagramNotificationExtension (a Notification Service
// Extension) is simultaneously delivering the same APNS push — two banners for
// one message.
//
// The local in-app copies carry IG's payload keys ("ig"/"gid") in content.userInfo,
// which the extension-delivered push does not surface through this method.
// When the toggle is on, the app is foreground, and the request looks like one
// of these in-app duplicates, swallow it (invoke the completion handler with no error and skip %orig)
// so only the extension's banner remains.

%group SPKFixDuplicateNotificationsHooks

%hook UNUserNotificationCenter

- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void (^)(NSError *error))completionHandler {
    if (![SPKUtils getBoolPref:@"tools_fix_duplicate_notifications"]) {
        %orig;
        return;
    }

    // Only the foreground app re-enqueues the local duplicate; in the background
    // the lone notification is the legitimate push, so never suppress it.
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        %orig;
        return;
    }

    NSDictionary *userInfo = request.content.userInfo;
    if ([userInfo isKindOfClass:[NSDictionary class]] &&
        userInfo[@"ig"] != nil &&
        userInfo[@"gid"] != nil) {
        // Looks like IG's in-app duplicate — drop it but still satisfy the API
        // contract by completing without error.
        if (completionHandler)
            completionHandler(nil);
        return;
    }

    %orig;
}

%end

%end

void SPKInstallFixDuplicateNotificationsHooksIfNeeded(void) {
    // Install unconditionally and gate on the pref inside the hook so the toggle
    // takes effect live, without a restart.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKFixDuplicateNotificationsHooks);
    });
}

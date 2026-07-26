#import "K4LProcessRole.h"

NSString *K4LProcessRoleName(K4LProcessRole role) {
    switch (role) {
        case K4LProcessRoleSpringBoard:
            return @"SpringBoard";
        case K4LProcessRoleBackBoard:
            return @"backboardd";
        case K4LProcessRoleScreenshotServices:
            return @"ScreenshotServicesService";
        case K4LProcessRoleMediaServer:
            return @"mediaserverd";
        case K4LProcessRoleAudioMixer:
            return @"audiomxd";
        case K4LProcessRoleCameraCapture:
            return @"cameracaptured";
        case K4LProcessRolePower:
            return @"powerd";
        case K4LProcessRoleSnapchat:
            return @"Snapchat";
        case K4LProcessRolePreferences:
            return @"K4LSnapPrefs";
        case K4LProcessRoleDaemon:
            return @"k4lsnapd";
        case K4LProcessRoleControlHelper:
            return @"k4lsnapctl";
        case K4LProcessRoleUnknown:
        default:
            return @"unknown";
    }
}

BOOL K4LProcessRoleIsInjectedProcess(K4LProcessRole role) {
    switch (role) {
        case K4LProcessRoleSpringBoard:
        case K4LProcessRoleBackBoard:
        case K4LProcessRoleScreenshotServices:
        case K4LProcessRoleMediaServer:
        case K4LProcessRoleAudioMixer:
        case K4LProcessRoleCameraCapture:
        case K4LProcessRolePower:
        case K4LProcessRoleSnapchat:
            return YES;
        case K4LProcessRoleUnknown:
        case K4LProcessRolePreferences:
        case K4LProcessRoleDaemon:
        case K4LProcessRoleControlHelper:
        default:
            return NO;
    }
}

BOOL K4LProcessRoleIsPrivilegedProcess(K4LProcessRole role) {
    return role == K4LProcessRoleDaemon;
}

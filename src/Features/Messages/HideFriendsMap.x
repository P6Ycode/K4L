#import "../../Utils.h"

static id SCIValueForSelectorOrKey(id object, NSString *name) {
    if (!object || name.length == 0) return nil;

    SEL selector = NSSelectorFromString(name);
    if ([object respondsToSelector:selector]) {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    }

    @try {
        return [object valueForKey:name];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL SCIObjectIsKindOfClassNamed(id object, NSString *className) {
    if (!object || className.length == 0) return NO;
    Class cls = NSClassFromString(className);
    return cls && [object isKindOfClass:cls];
}

static BOOL SCIShouldHideFriendsMapObject(id object) {
    if (![SCIUtils getBoolPref:@"msgs_hide_friends_map"]) return NO;

    NSString *className = NSStringFromClass([object class]);
    if ([className containsString:@"FriendMap"]) return YES;

    if (SCIObjectIsKindOfClassNamed(object, @"IGDirectNotesTrayUserViewModel")) {
        id notePk = SCIValueForSelectorOrKey(object, @"notePk");
        if ([notePk isKindOfClass:[NSString class]] && [notePk isEqualToString:@"friends_map"]) {
            return YES;
        }
    }

    id notePk = SCIValueForSelectorOrKey(object, @"notePk");
    return [notePk isKindOfClass:[NSString class]] && [notePk isEqualToString:@"friends_map"];
}

static NSArray *SCIFilterFriendsMapObjects(NSArray *originalObjs) {
    if (![originalObjs isKindOfClass:[NSArray class]]) return originalObjs;

    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];
    for (id obj in originalObjs) {
        if (SCIShouldHideFriendsMapObject(obj)) {
            SCILog(@"General", @"[SCInsta] Hiding friends map");
            continue;
        }
        [filteredObjs addObject:obj];
    }

    return [filteredObjs copy];
}

%group SCIHideFriendsMapHooks

%hook IGDirectNotesTrayRowCell
- (id)listAdapterObjects {
    return SCIFilterFriendsMapObjects(%orig());
}
%end

%hook _TtC24IGDirectNotesTrayUISwift42IGDirectNotesTrayCellListAdapterDataSource
- (id)objectsForListAdapter:(id)adapter {
    return SCIFilterFriendsMapObjects(%orig());
}
%end

%hook _TtC24IGDirectNotesTrayUISwift43IGDirectNotesTrayFriendMapSectionController
- (long long)numberOfItems {
    if ([SCIUtils getBoolPref:@"msgs_hide_friends_map"]) {
        SCILog(@"General", @"[SCInsta] Hiding friends map section");
        return 0;
    }
    return %orig();
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

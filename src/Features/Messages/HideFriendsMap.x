#import "../../Utils.h"

static id SPKValueForSelectorOrKey(id object, NSString *name) {
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

static BOOL SPKObjectIsKindOfClassNamed(id object, NSString *className) {
    if (!object || className.length == 0) return NO;
    Class cls = NSClassFromString(className);
    return cls && [object isKindOfClass:cls];
}

static BOOL SPKShouldHideFriendsMapObject(id object) {
    if (![SPKUtils getBoolPref:@"msgs_hide_friends_map"]) return NO;

    NSString *className = NSStringFromClass([object class]);
    if ([className containsString:@"FriendMap"]) return YES;

    if (SPKObjectIsKindOfClassNamed(object, @"IGDirectNotesTrayUserViewModel")) {
        id notePk = SPKValueForSelectorOrKey(object, @"notePk");
        if ([notePk isKindOfClass:[NSString class]] && [notePk isEqualToString:@"friends_map"]) {
            return YES;
        }
    }

    id notePk = SPKValueForSelectorOrKey(object, @"notePk");
    return [notePk isKindOfClass:[NSString class]] && [notePk isEqualToString:@"friends_map"];
}

static NSArray *SPKFilterFriendsMapObjects(NSArray *originalObjs) {
    if (![originalObjs isKindOfClass:[NSArray class]]) return originalObjs;

    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];
    for (id obj in originalObjs) {
        if (SPKShouldHideFriendsMapObject(obj)) {
            SPKLog(@"General", @"[Sparkle] Hiding friends map");
            continue;
        }
        [filteredObjs addObject:obj];
    }

    return [filteredObjs copy];
}

%group SPKHideFriendsMapHooks

%hook IGDirectNotesTrayRowCell
- (id)listAdapterObjects {
    return SPKFilterFriendsMapObjects(%orig());
}
%end

%hook _TtC24IGDirectNotesTrayUISwift42IGDirectNotesTrayCellListAdapterDataSource
- (id)objectsForListAdapter:(id)adapter {
    return SPKFilterFriendsMapObjects(%orig());
}
%end

%hook _TtC24IGDirectNotesTrayUISwift43IGDirectNotesTrayFriendMapSectionController
- (long long)numberOfItems {
    if ([SPKUtils getBoolPref:@"msgs_hide_friends_map"]) {
        SPKLog(@"General", @"[Sparkle] Hiding friends map section");
        return 0;
    }
    return %orig();
}
%end

%end

void SPKInstallHideFriendsMapHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"msgs_hide_friends_map"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKHideFriendsMapHooks);
    });
}

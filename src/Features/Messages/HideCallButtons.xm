#import "../../Utils.h"

static BOOL SCIShouldHideDirectCallButton(UIView *button) {
    if (![button isKindOfClass:NSClassFromString(@"IGDirectCallButton")]) return NO;
    NSString *identifier = button.accessibilityIdentifier;
    if ([identifier isEqualToString:@"audio-call"]) return [SCIUtils getBoolPref:@"msgs_hide_audio_call_btn"];
    if ([identifier isEqualToString:@"video-chat"]) return [SCIUtils getBoolPref:@"msgs_hide_video_call_btn"];
    return NO;
}

static BOOL SCIViewContainsHiddenDirectCallButton(UIView *rootView) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:rootView];
    while (queue.count > 0) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (SCIShouldHideDirectCallButton(view)) return YES;
        [queue addObjectsFromArray:view.subviews];
    }
    return NO;
}

static NSArray<UIBarButtonItem *> *SCIFilterHiddenDirectCallBarButtonItems(NSArray<UIBarButtonItem *> *items) {
    if (items.count == 0) return items;

    return [items filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(UIBarButtonItem *item, NSDictionary *_) {
            return !SCIShouldHideDirectCallButton(item.customView);
        }]];
}

static void SCIRepackNavigationBarPlatters(UIView *container) {
    NSMutableArray<UIView *> *platters = [NSMutableArray array];
    for (UIView *subview in container.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:@"_UINavigationBarPlatterView"]) {
            [platters addObject:subview];
        }
    }

    CGFloat hiddenWidth = 0.0;
    NSMutableArray<UIView *> *visiblePlatters = [NSMutableArray array];
    for (UIView *platter in platters) {
        if (SCIViewContainsHiddenDirectCallButton(platter)) {
            hiddenWidth += CGRectGetWidth(platter.frame);
            platter.hidden = YES;
        } else {
            platter.hidden = NO;
            [visiblePlatters addObject:platter];
        }
    }

    for (UIView *platter in visiblePlatters) {
        platter.transform = (hiddenWidth > 0.0 && CGRectGetMinX(platter.frame) >= 60.0)
            ? CGAffineTransformMakeTranslation(hiddenWidth, 0.0)
            : CGAffineTransformIdentity;
    }
}

%group SCIHideDirectCallButtonsHooks

%hook IGDirectThreadCallButtonsCoordinator

- (void)_didTapAudioButton {
    if ([SCIUtils getBoolPref:@"msgs_hide_audio_call_btn"]) return;
    %orig;
}

- (void)_didTapAudioButton:(id)button {
    if ([SCIUtils getBoolPref:@"msgs_hide_audio_call_btn"]) return;
    %orig;
}

- (void)_didTapVideoButton {
    if ([SCIUtils getBoolPref:@"msgs_hide_video_call_btn"]) return;
    %orig;
}

- (void)_didTapVideoButton:(id)button {
    if ([SCIUtils getBoolPref:@"msgs_hide_video_call_btn"]) return;
    %orig;
}

%end

%hook IGDirectCallButton

- (void)didMoveToWindow {
    %orig;
    UIView *button = (UIView *)self;
    if (button.window && SCIShouldHideDirectCallButton(button)) {
        button.hidden = YES;
    }
}

%end

%hook IGTallNavigationBarView

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items {
    %orig(SCIFilterHiddenDirectCallBarButtonItems(items));
}

%end

%hook IGNavigationBar

- (void)layoutSubviews {
    %orig;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:(UIView *)self];
    while (queue.count > 0) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(view.class) containsString:@"NavigationBarPlatterContainer"]) {
            SCIRepackNavigationBarPlatters(view);
            break;
        }
        [queue addObjectsFromArray:view.subviews];
    }
}

%end

%end

extern "C" void SCIInstallHideDirectCallButtonsHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIHideDirectCallButtonsHooks);
    });
}

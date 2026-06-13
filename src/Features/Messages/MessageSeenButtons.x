#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../InstagramHeaders.h"
#import "../../AssetUtils.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "../../Shared/Messages/SCIDirectSeenContext.h"
#import "../../Shared/Stories/SCIStoryContext.h"
#import "../../Shared/UI/SCIChrome.h"
#import "DeletedMessagesLog/SCIDeletedMessagesViewController.h"

#ifdef __cplusplus
extern "C" {
#endif
#ifdef __cplusplus
}
#endif

@interface UIViewController (SCIRefreshNavigationBar)
- (void)refreshRightBarButtonItems;
- (void)updateThreadNavigationBar;
@end

static NSString * const kSCISeenMessagesBarIconResource = @"eye";
static const void *kSCIDirectThreadIdAssocKey = &kSCIDirectThreadIdAssocKey;
static NSInteger kSCISeenAutoBypassCount = 0;
static NSMutableDictionary<NSString *, NSNumber *> *SCISeenAutoLastTriggerTimes = nil;
static __weak id SCIDirectActiveMarkSeenTarget = nil;
static NSString *SCIDirectActiveMarkSeenThreadId = nil;

static id SCIKVCObject(id target, NSString *key);
static id SCIFindDirectMarkSeenTarget(id root, NSMutableSet<NSValue *> *visited);

static inline BOOL SCIDirectManualSeenRulesEnabled(void) {
    return [SCIUtils getBoolPref:@"msgs_manual_seen"] || SCIDirectManualSeenThreadCount(NO) > 0;
}

static inline BOOL SCIDirectSeenHooksNeeded(void) {
    return SCIDirectManualSeenRulesEnabled() ||
           [SCIUtils getBoolPref:@"msgs_manual_visual_seen"] ||
           [SCIUtils getBoolPref:@"msgs_advance_visual_on_seen"];
}
static inline BOOL SCIAutoSeenOnSendEnabled(void) {
    return SCIDirectManualSeenRulesEnabled() && [SCIUtils getBoolPref:@"msgs_seen_on_send"];
}

static inline BOOL SCIAutoSeenOnReplyEnabled(void) {
    return SCIDirectManualSeenRulesEnabled() && [SCIUtils getBoolPref:@"msgs_seen_on_reply"];
}

static inline BOOL SCIAutoSeenOnReactionEnabled(void) {
    return SCIDirectManualSeenRulesEnabled() && [SCIUtils getBoolPref:@"msgs_seen_on_reaction"];
}

static BOOL SCIValueIsPresent(id value) {
    if (!value || value == (id)kCFNull) return NO;
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value length] > 0;
    if ([value isKindOfClass:[NSArray class]]) return [(NSArray *)value count] > 0;
    if ([value isKindOfClass:[NSDictionary class]]) return [(NSDictionary *)value count] > 0;
    return YES;
}

static id SCIFindDirectMarkSeenTarget(id root, NSMutableSet<NSValue *> *visited) {
    if (!root) return nil;

    NSValue *pointerValue = [NSValue valueWithNonretainedObject:root];
    if ([visited containsObject:pointerValue]) return nil;
    [visited addObject:pointerValue];

    SEL markSelector = @selector(markLastMessageAsSeen);
    if ([root respondsToSelector:markSelector]) return root;

    if ([root isKindOfClass:[UIView class]]) {
        id target = SCIFindDirectMarkSeenTarget([SCIUtils nearestViewControllerForView:(UIView *)root], visited);
        if (target) return target;
    }

    for (NSString *selectorName in @[
        @"object",
        @"value",
        @"containingViewController",
        @"presentingViewController",
        @"currentThread"
    ]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![root respondsToSelector:selector]) continue;

        id candidate = ((id (*)(id, SEL))objc_msgSend)(root, selector);
        id target = SCIFindDirectMarkSeenTarget(candidate, visited);
        if (target) return target;
    }

    if ([root isKindOfClass:[UIViewController class]]) {
        UIViewController *viewController = (UIViewController *)root;
        id parentTarget = SCIFindDirectMarkSeenTarget(viewController.parentViewController, visited);
        if (parentTarget) return parentTarget;

        id presentingTarget = SCIFindDirectMarkSeenTarget(viewController.presentingViewController, visited);
        if (presentingTarget) return presentingTarget;

        id navigationTarget = SCIFindDirectMarkSeenTarget(viewController.navigationController, visited);
        if (navigationTarget) return navigationTarget;

        for (UIViewController *child in [(UIViewController *)root childViewControllers]) {
            id target = SCIFindDirectMarkSeenTarget(child, visited);
            if (target) return target;
        }
    }

    for (NSString *key in @[
        @"_messageListViewController",
        @"messageListViewController",
        @"_directMessageListViewController",
        @"directMessageListViewController",
        @"_threadViewFeatureDelegateContainer",
        @"threadViewFeatureDelegateContainer",
        @"_threadViewControllerFeatureDelegate",
        @"threadViewControllerFeatureDelegate",
        @"_threadViewFeatureDelegate",
        @"threadViewFeatureDelegate",
        @"_featureDelegate",
        @"featureDelegate",
        @"_threadViewController",
        @"threadViewController",
        @"_containingViewController",
        @"containingViewController",
        @"_stateProvider",
        @"stateProvider",
        @"_delegate",
        @"delegate",
        @"_messageListController",
        @"messageListController",
        @"_messageList",
        @"messageList"
    ]) {
        id candidate = [key hasPrefix:@"_"] ? [SCIUtils getIvarForObj:root name:key.UTF8String] : SCIKVCObject(root, key);
        id target = SCIFindDirectMarkSeenTarget(candidate, visited);
        if (target) return target;
    }

    return nil;
}

static BOOL SCIMarkDirectThreadMessagesAsSeen(id controller) {
    id target = SCIFindDirectMarkSeenTarget(controller, [NSMutableSet set]);
    SCIDirectThreadContext *context = SCIDirectThreadContextFromSource(controller);
    if (!target &&
        SCIDirectActiveMarkSeenTarget &&
        SCIDirectActiveMarkSeenThreadId.length > 0 &&
        context.threadId.length > 0 &&
        [SCIDirectActiveMarkSeenThreadId isEqualToString:context.threadId]) {
        target = SCIFindDirectMarkSeenTarget(SCIDirectActiveMarkSeenTarget, [NSMutableSet set]);
        if (target) {
            SCILog(@"Messages", @"[SCInsta MessagesSeen] Using active mark target fallback threadId=%@ source=%@<%p> target=%@<%p>",
                   context.threadId ?: @"(unknown)",
                   NSStringFromClass([controller class]),
                   controller,
                   NSStringFromClass([target class]),
                   target);
        }
    }
    if (!target) {
        SCILog(@"General", @"[SCInsta MessagesSeen] No markLastMessageAsSeen target for controller=%@<%p> threadId=%@ activeThreadId=%@",
               NSStringFromClass([controller class]),
               controller,
               context.threadId ?: @"(unknown)",
               SCIDirectActiveMarkSeenThreadId ?: @"(none)");
        return NO;
    }

    kSCISeenAutoBypassCount++;
    @try {
        ((void (*)(id, SEL))objc_msgSend)(target, @selector(markLastMessageAsSeen));
        SCILog(@"General", @"[SCInsta MessagesSeen] Marked via target=%@<%p> controller=%@<%p>",
               NSStringFromClass([target class]),
               target,
               NSStringFromClass([controller class]),
               controller);
    } @catch (NSException *exception) {
        if (kSCISeenAutoBypassCount > 0) kSCISeenAutoBypassCount--;
        SCILog(@"General", @"[SCInsta MessagesSeen] markLastMessageAsSeen failed target=%@<%p> exception=%@",
               NSStringFromClass([target class]),
               target,
               exception);
        return NO;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (kSCISeenAutoBypassCount > 0) {
            kSCISeenAutoBypassCount--;
        }
    });

    return YES;
}

static BOOL SCISeenAutoShouldTrigger(id source, NSString *reason) {
    if (!source || reason.length == 0) return NO;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!SCISeenAutoLastTriggerTimes) {
        SCISeenAutoLastTriggerTimes = [NSMutableDictionary dictionary];
    }

    NSString *key = [NSString stringWithFormat:@"%@:%p", reason, source];
    NSNumber *lastTrigger = SCISeenAutoLastTriggerTimes[key];
    if (lastTrigger && (now - lastTrigger.doubleValue) < 0.75) {
        return NO;
    }

    SCISeenAutoLastTriggerTimes[key] = @(now);
    return YES;
}

static void SCITriggerAutoSeenForSource(id source, NSString *reason) {
    if (!SCIDirectManualSeenAppliesToSource(source)) {
        SCIDirectThreadContext *context = SCIDirectThreadContextFromSource(source);
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Auto seen skipped reason=%@ threadId=%@ source=%@<%p> manual seen does not apply",
               reason,
               context.threadId ?: @"(unknown)",
               NSStringFromClass([source class]),
               source);
        return;
    }
    if (!SCISeenAutoShouldTrigger(source, reason)) {
        SCIDirectThreadContext *context = SCIDirectThreadContextFromSource(source);
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Auto seen debounced reason=%@ threadId=%@ source=%@<%p>",
               reason,
               context.threadId ?: @"(unknown)",
               NSStringFromClass([source class]),
               source);
        return;
    }

    SCIDirectThreadContext *context = SCIDirectThreadContextFromSource(source);
    SCILog(@"Messages", @"[SCInsta MessagesSeen] Auto seen scheduled reason=%@ threadId=%@ source=%@<%p>",
           reason,
           context.threadId ?: @"(unknown)",
           NSStringFromClass([source class]),
           source);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIMarkDirectThreadMessagesAsSeen(source);
    });
}

void SCIMarkDirectThreadSeenAfterOutgoingMessage(id source, BOOL isReply) {
    if (isReply) {
        if (!SCIAutoSeenOnReplyEnabled()) return;
        SCITriggerAutoSeenForSource(source, @"reply");
        return;
    }

    if (!SCIAutoSeenOnSendEnabled()) return;
    SCITriggerAutoSeenForSource(source, @"send");
}

void SCIMarkDirectThreadSeenAfterReaction(id source) {
    if (!SCIAutoSeenOnReactionEnabled()) return;
    SCITriggerAutoSeenForSource(source, @"reaction");
}

// Resolves the 1:1 chat partner from a thread context. Returns nil PK for
// group chats or when the participant list can't be narrowed to a single
// non-owner user — callers fall back to the full log in that case.
static void SCIDirectResolveChatPartner(SCIDirectThreadContext *context, NSString **outPK, NSString **outName) {
    if (outPK) *outPK = nil;
    if (outName) *outName = nil;
    if (!context || context.isGroup) return;

    NSArray<NSDictionary *> *users = context.users;
    if (![users isKindOfClass:NSArray.class] || users.count == 0) return;

    // Current account PK so we can exclude ourselves from the participant list.
    NSString *currentPk = nil;
    @try {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            id session = nil;
            @try { session = [w valueForKey:@"userSession"]; } @catch (__unused id e) {}
            id user = session ? [session valueForKey:@"user"] : nil;
            for (NSString *key in @[@"pk", @"instagramUserID", @"instagramUserId", @"userID", @"userId"]) {
                id v = nil;
                @try { v = [user valueForKey:key]; } @catch (__unused id e) {}
                if ([v isKindOfClass:NSString.class] && [v length]) { currentPk = v; break; }
                if ([v isKindOfClass:NSNumber.class]) { currentPk = [v stringValue]; break; }
            }
            if (currentPk.length) break;
        }
    } @catch (__unused id e) {}

    NSMutableArray<NSDictionary *> *others = [NSMutableArray array];
    for (NSDictionary *u in users) {
        if (![u isKindOfClass:NSDictionary.class]) continue;
        NSString *pk = [u[@"pk"] isKindOfClass:NSString.class] ? u[@"pk"] : nil;
        if (!pk.length) continue;
        if (currentPk.length && [pk isEqualToString:currentPk]) continue;
        [others addObject:u];
    }

    // Only a clean 1:1 (exactly one other participant) deep-links.
    if (others.count != 1) return;

    NSDictionary *partner = others.firstObject;
    NSString *pk = [partner[@"pk"] isKindOfClass:NSString.class] ? partner[@"pk"] : nil;
    NSString *username = [partner[@"username"] isKindOfClass:NSString.class] ? partner[@"username"] : nil;
    NSString *fullName = [partner[@"fullName"] isKindOfClass:NSString.class] ? partner[@"fullName"] : nil;
    if (outPK) *outPK = pk;
    if (outName) *outName = username.length ? username : fullName;
}

static UIMenu *SCIDirectSeenButtonMenu(id source) {
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
    SCIDirectSeenDebugPrintEnabled = YES;
    SCIDirectThreadContext *context = SCIDirectThreadContextFromSource(source);
    SCIDirectSeenDebugPrintEnabled = NO;
    NSString *toggleTitle = SCIDirectCurrentThreadRuleActionTitle(context);
    if (toggleTitle.length > 0) {
        BOOL applies = SCIDirectManualSeenAppliesToSource(context);
        UIImage *toggleImage = [SCIAssetUtils instagramIconNamed:applies ? @"eye_off" : @"eye" pointSize:22.0];
        UIAction *toggleAction = [UIAction actionWithTitle:toggleTitle
                                                     image:toggleImage
                                                identifier:nil
                                                   handler:^(__unused UIAction *action) {
            NSString *title = nil;
            NSString *subtitle = nil;
            if (!SCIDirectToggleCurrentThreadRule(context, &title, &subtitle)) {
                SCILog(@"Messages", @"[SCInsta MessagesSeen] Eye menu toggle failed threadId=%@ source=%@<%p>",
                       context.threadId ?: @"(unknown)",
                       NSStringFromClass([source class]),
                       source);
                SCINotify(kSCINotificationDirectThreadSeenRule, @"Chat not found", nil, @"error_filled", SCINotificationToneError);
                return;
            }
            SCINotify(kSCINotificationDirectThreadSeenRule, title, subtitle, @"circle_check_filled", SCINotificationToneSuccess);
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([source respondsToSelector:@selector(refreshRightBarButtonItems)]) {
                    [source refreshRightBarButtonItems];
                } else if ([source respondsToSelector:@selector(updateThreadNavigationBar)]) {
                    [source updateThreadNavigationBar];
                }
            });
        }];
        [children addObject:toggleAction];
    }

    UIImage *logImage = [SCIAssetUtils instagramIconNamed:@"channels" pointSize:22.0];
    NSString *partnerPK = nil;
    NSString *partnerName = nil;
    SCIDirectResolveChatPartner(context, &partnerPK, &partnerName);
    NSString *threadId = context.isGroup ? nil : context.threadId;
    UIAction *logAction = [UIAction actionWithTitle:@"Deleted Messages"
                                              image:logImage
                                         identifier:nil
                                            handler:^(__unused UIAction *action) {
        if (threadId.length || partnerPK.length) {
            [SCIDeletedMessagesViewController presentForThreadId:threadId senderPK:partnerPK senderName:partnerName fromViewController:nil];
        } else {
            // Group chat or unresolved participant — open the full list.
            [SCIDeletedMessagesViewController presentFromViewController:nil];
        }
    }];
    [children addObject:logAction];

    UIImage *settingsImage = [SCIAssetUtils instagramIconNamed:@"settings" pointSize:22.0];
    UIAction *settingsAction = [UIAction actionWithTitle:@"Messages Settings"
                                                   image:settingsImage
                                              identifier:nil
                                                 handler:^(__unused UIAction *action) {
        SCINotify(kSCINotificationOpenTopicSettings, @"Opened settings", nil, @"settings", SCINotificationToneForIconResource(@"settings"));
        [SCIUtils showSettingsForTopicTitle:@"Messages"];
    }];
    [children addObject:settingsAction];

    return [UIMenu menuWithTitle:@"" children:children];
}

static void SCIDirectRememberActiveThreadContextForController(id controller, NSString *eventName) {
    SCIDirectThreadContext *context = SCIDirectThreadContextFromSource(controller);
    if (context.threadId.length == 0) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Active thread context not set event=%@ controller=%@<%p> missing threadId",
               eventName,
               NSStringFromClass([controller class]),
               controller);
        return;
    }

    objc_setAssociatedObject(controller, kSCIDirectThreadIdAssocKey, context.threadId, OBJC_ASSOCIATION_COPY_NONATOMIC);
    SCIDirectSetActiveThreadContext(context);

    id markTarget = SCIFindDirectMarkSeenTarget(controller, [NSMutableSet set]);
    if (markTarget) {
        SCIDirectActiveMarkSeenTarget = markTarget;
        SCIDirectActiveMarkSeenThreadId = [context.threadId copy];
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Active mark target set event=%@ threadId=%@ target=%@<%p>",
               eventName,
               context.threadId ?: @"(unknown)",
               NSStringFromClass([markTarget class]),
               markTarget);
    }
}

static void SCIDirectClearActiveThreadContextForController(id controller, NSString *eventName) {
    NSString *threadId = objc_getAssociatedObject(controller, kSCIDirectThreadIdAssocKey);
    SCIDirectThreadContext *activeContext = SCIDirectActiveThreadContext();
    if (threadId.length == 0) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Active thread context clear skipped event=%@ controller=%@<%p> no cached threadId",
               eventName,
               NSStringFromClass([controller class]),
               controller);
        return;
    }
    if (activeContext.threadId.length == 0) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Active thread context clear skipped event=%@ threadId=%@ no active context",
               eventName,
               threadId);
        return;
    }
    if (![activeContext.threadId isEqualToString:threadId]) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Active thread context clear skipped event=%@ cachedThreadId=%@ activeThreadId=%@",
               eventName,
               threadId,
               activeContext.threadId);
        return;
    }

    SCIDirectSetActiveThreadContext(nil);
    if ([SCIDirectActiveMarkSeenThreadId isEqualToString:threadId]) {
        SCIDirectActiveMarkSeenTarget = nil;
        SCIDirectActiveMarkSeenThreadId = nil;
    }
    objc_setAssociatedObject(controller, kSCIDirectThreadIdAssocKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static id (*SCIDirectOrigInboxContextMenuConfiguration)(id, SEL, id);

static id SCIDirectInboxContextMenuConfiguration(id self, SEL _cmd, id indexPath) {
    id configuration = SCIDirectOrigInboxContextMenuConfiguration(self, _cmd, indexPath);
    if (![configuration isKindOfClass:[UIContextMenuConfiguration class]]) return configuration;

    id adapter = SCIKVCObject(self, @"listAdapter");
    if (!adapter) adapter = [SCIUtils getIvarForObj:self name:"_listAdapter"];
    if (!adapter || ![indexPath respondsToSelector:@selector(section)]) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Inbox menu context skipped: missing adapter/indexPath controller=%@<%p>",
               NSStringFromClass([self class]),
               self);
        return configuration;
    }

    SEL sectionControllerSelector = NSSelectorFromString(@"sectionControllerForSection:");
    if (![adapter respondsToSelector:sectionControllerSelector]) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Inbox menu context skipped: adapter lacks sectionControllerForSection adapter=%@<%p>",
               NSStringFromClass([adapter class]),
               adapter);
        return configuration;
    }

    NSInteger section = [(NSIndexPath *)indexPath section];
    id sectionController = ((id (*)(id, SEL, NSInteger))objc_msgSend)(adapter, sectionControllerSelector, section);
    id viewModel = SCIKVCObject(sectionController, @"viewModel");
    if (!viewModel) viewModel = [SCIUtils getIvarForObj:sectionController name:"_viewModel"];
    if (!viewModel) viewModel = SCIKVCObject(sectionController, @"item");
    if (!viewModel) viewModel = [SCIUtils getIvarForObj:sectionController name:"_item"];

    if (!viewModel) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Inbox menu context skipped: missing viewModel section=%ld sectionController=%@<%p>",
               (long)section,
               NSStringFromClass([sectionController class]),
               sectionController);
        return configuration;
    }

    SCIDirectThreadContext *context = SCIDirectThreadContextFromInboxViewModel(viewModel);
    NSString *toggleTitle = SCIDirectCurrentThreadRuleActionTitle(context);
    if (toggleTitle.length == 0) {
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Inbox menu context skipped: missing thread context viewModel=%@<%p>",
               NSStringFromClass([viewModel class]),
               viewModel);
        return configuration;
    }
    UIContextMenuConfiguration *originalConfiguration = (UIContextMenuConfiguration *)configuration;
    UIContextMenuActionProvider originalProvider = SCIKVCObject(originalConfiguration, @"actionProvider");
    UIContextMenuContentPreviewProvider originalPreview = SCIKVCObject(originalConfiguration, @"previewProvider");
    id<NSCopying> originalIdentifier = SCIKVCObject(originalConfiguration, @"identifier");

    UIContextMenuActionProvider wrappedProvider = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIMenu *baseMenu = nil;
        @try {
            baseMenu = originalProvider ? originalProvider(suggestedActions) : [UIMenu menuWithChildren:suggestedActions];
        } @catch (NSException *exception) {
            SCILog(@"Messages", @"[SCInsta MessagesSeen] Inbox menu original provider failed threadId=%@ exception=%@ reason=%@",
                   context.threadId ?: @"(unknown)",
                   exception.name,
                   exception.reason);
            return [UIMenu menuWithChildren:suggestedActions ?: @[]];
        }
        if (![baseMenu isKindOfClass:[UIMenu class]]) {
            SCILog(@"Messages", @"[SCInsta MessagesSeen] Inbox menu original provider returned invalid menu threadId=%@ menu=%@",
                   context.threadId ?: @"(unknown)",
                   baseMenu);
            return [UIMenu menuWithChildren:suggestedActions ?: @[]];
        }
        NSString *currentTitle = SCIDirectCurrentThreadRuleActionTitle(context) ?: toggleTitle;
        BOOL applies = SCIDirectManualSeenAppliesToSource(context);
        UIImage *image = [SCIAssetUtils instagramIconNamed:applies ? @"eye_off" : @"eye"];
        UIAction *toggleAction = [UIAction actionWithTitle:currentTitle image:image identifier:nil handler:^(__unused UIAction *action) {
            NSString *notificationTitle = nil;
            NSString *notificationSubtitle = nil;
            if (!SCIDirectToggleCurrentThreadRule(context, &notificationTitle, &notificationSubtitle)) {
                SCILog(@"Messages", @"[SCInsta MessagesSeen] Inbox menu toggle failed threadId=%@ viewModel=%@<%p>",
                       context.threadId ?: @"(unknown)",
                       NSStringFromClass([viewModel class]),
                       viewModel);
                SCINotify(kSCINotificationDirectThreadSeenRule, @"Chat not found", nil, @"error_filled", SCINotificationToneError);
                return;
            }
            SCINotify(kSCINotificationDirectThreadSeenRule, notificationTitle, notificationSubtitle, @"circle_check_filled", SCINotificationToneSuccess);
        }];
        NSMutableArray *children = [baseMenu.children mutableCopy] ?: [NSMutableArray array];
        [children addObject:toggleAction];
        return [baseMenu menuByReplacingChildren:children];
    };

    return [UIContextMenuConfiguration configurationWithIdentifier:originalIdentifier
                                                   previewProvider:originalPreview
                                                    actionProvider:wrappedProvider];
}

static void SCIInstallDirectInboxSeenContextMenuHook(void) {
    SEL selector = NSSelectorFromString(@"networkingCoordinator_contextMenuConfigurationForThreadCellAtIndexPath:");
    for (NSString *className in @[@"IGDirectInboxViewController", @"IGDirectInboxViewControllerImpl"]) {
        Class inboxClass = NSClassFromString(className);
        if (!inboxClass || !class_getInstanceMethod(inboxClass, selector)) continue;
        MSHookMessageEx(inboxClass, selector, (IMP)SCIDirectInboxContextMenuConfiguration, (IMP *)&SCIDirectOrigInboxContextMenuConfiguration);
        SCILog(@"Messages", @"[SCInsta MessagesSeen] Installed inbox seen list context menu hook class=%@", className);
        return;
    }
    SCILog(@"Messages", @"[SCInsta MessagesSeen] Inbox seen list context menu hook not installed: selector not found");
}

static id SCIKVCObject(id target, NSString *key) {
    if (!target || key.length == 0) return nil;

    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void SCIPlayButtonTappedHaptic(void) {
    UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
    [feedback selectionChanged];
}

%group SCIMessageSeenButtonHooks

%hook IGTallNavigationBarView
- (void)setRightBarButtonItems:(NSArray <UIBarButtonItem *> *)items {
    NSMutableArray *new_items = [[items filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(UIBarButtonItem *value, NSDictionary *_) {
            if ([value.accessibilityIdentifier isEqualToString:@"sci-seen-btn"]) {
                return false;
            }
            if ([SCIUtils getBoolPref:@"msgs_hide_reels_blend"]) {
                return ![value.accessibilityIdentifier isEqualToString:@"blend-button"];
            }

            return true;
        }]
    ] mutableCopy];

    // Messages seen
    if (SCIDirectManualSeenRulesEnabled()) {
        UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:self];
        Class directThreadClass = NSClassFromString(@"IGDirectThreadViewController");
        if (directThreadClass && [nearestVC isKindOfClass:directThreadClass] && SCIDirectShouldShowSeenButtonForSource(nearestVC)) {
            SCIChromeButton *chromeButton = nil;
            UIBarButtonItem *seenButton = SCIChromeBarButtonItem(@"", 24.0, self, @selector(seenButtonHandler:), &chromeButton);
            [chromeButton setIconResource:kSCISeenMessagesBarIconResource pointSize:24.0];
            seenButton.accessibilityIdentifier = @"sci-seen-btn";
            chromeButton.bubbleColor = UIColor.clearColor;
            chromeButton.iconTint = UIColor.labelColor;
            chromeButton.menu = SCIDirectSeenButtonMenu(nearestVC);
            chromeButton.showsMenuAsPrimaryAction = NO;
            [new_items addObject:seenButton];
        }
    }

    %orig([new_items copy]);
}

// Messages seen button
%new - (void)seenButtonHandler:(UIBarButtonItem *)sender {
    (void)sender;
    SCIPlayButtonTappedHaptic();
    UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:self];
    if ([nearestVC isKindOfClass:%c(IGDirectThreadViewController)]) {
        if (SCIMarkDirectThreadMessagesAsSeen(nearestVC)) {
            SCINotify(kSCINotificationThreadMessagesMarkSeen, @"Marked messages as seen", nil, @"circle_check_filled", SCINotificationToneSuccess);
        } else {
            SCINotify(kSCINotificationThreadMessagesMarkSeen, @"Unable to mark messages as seen", nil, @"error_filled", SCINotificationToneError);
        }
    }
}
%end

%hook IGDirectThreadViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!SCIDirectSeenHooksNeeded()) return;
    SCIDirectRememberActiveThreadContextForController(self, @"viewWillAppear");
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!SCIDirectSeenHooksNeeded()) return;
    SCIDirectRememberActiveThreadContextForController(self, @"viewDidAppear");
}

- (void)viewDidDisappear:(BOOL)animated {
    if (!SCIDirectSeenHooksNeeded()) {
        %orig;
        return;
    }
    if (self.isMovingFromParentViewController || self.isBeingDismissed || self.parentViewController == nil) {
        SCIDirectClearActiveThreadContextForController(self, @"viewDidDisappear");
    } else {
        NSString *threadId = objc_getAssociatedObject(self, kSCIDirectThreadIdAssocKey);
        if (threadId.length > 0 && [SCIDirectActiveThreadContext().threadId isEqualToString:threadId]) {
            SCILog(@"Messages", @"[SCInsta MessagesSeen] Active thread context clear skipped event=viewDidDisappear threadId=%@ controller still retained",
                   threadId);
        }
    }
    %orig;
}

- (void)dealloc {
    if (SCIDirectSeenHooksNeeded()) {
        SCIDirectClearActiveThreadContextForController(self, @"dealloc");
    }
    %orig;
}
%end

// Messages seen logic
%hook IGDirectThreadViewListAdapterDataSource
- (BOOL)shouldUpdateLastSeenMessage {
    if (!SCIDirectManualSeenRulesEnabled()) return %orig;
    if (SCIDirectManualSeenAppliesToSource(self)) {
        if (kSCISeenAutoBypassCount > 0) {
            return %orig;
        }
        return false;
    }
    
    return %orig;
}
%end

%hook IGDirectMessageListViewController
- (BOOL)messageListDataSourceShouldUpdateSeenState:(id)arg1 {
    if (!SCIDirectManualSeenRulesEnabled()) return %orig;
    if (SCIDirectManualSeenAppliesToSource(self)) {
        if (kSCISeenAutoBypassCount > 0) {
            return %orig;
        }
        return false;
    }

    return %orig;
}
%end

%hook IGDirectMessageSenderFeatureController
- (void)sendMessageWithText:(id)text
            quotedMessageId:(id)quotedMessageId
           powerupsMetadata:(id)powerupsMetadata
animatedEmojiCharacterRanges:(id)animatedEmojiCharacterRanges
        imageGlyphLocations:(id)imageGlyphLocations
     messageSentSpeedMarker:(id)messageSentSpeedMarker
      localSendSpeedMarker:(id)localSendSpeedMarker
               foaLSSLogger:(id)foaLSSLogger
               foaS2SLogger:(id)foaS2SLogger
               igdS2SLogger:(id)igdS2SLogger
             e2eloggerLogId:(id)e2eloggerLogId
richTextFormatActionButtonsPressed:(id)richTextFormatActionButtonsPressed
    expressiveTextMetadata:(id)expressiveTextMetadata {
    BOOL isReply = SCIValueIsPresent(quotedMessageId);
    %orig;
    SCIMarkDirectThreadSeenAfterOutgoingMessage(self, isReply);
}

- (void)sendTextMessageWithText:(id)text
                  quotedMessage:(id)quotedMessage
               powerupsMetadata:(id)powerupsMetadata
animatedEmojiCharacterRanges:(id)animatedEmojiCharacterRanges
            imageGlyphLocations:(id)imageGlyphLocations
         messageSentSpeedMarker:(id)messageSentSpeedMarker
           localSendSpeedMarker:(id)localSendSpeedMarker
                   foaLSSLogger:(id)foaLSSLogger
                   foaS2SLogger:(id)foaS2SLogger
                   igdS2SLogger:(id)igdS2SLogger
                 e2eloggerLogId:(id)e2eloggerLogId
               metaAIPromptData:(id)metaAIPromptData
richTextFormatActionButtonsPressed:(id)richTextFormatActionButtonsPressed
             scheduledTimestamp:(id)scheduledTimestamp
        expressiveTextMetadata:(id)expressiveTextMetadata {
    BOOL isReply = SCIValueIsPresent(quotedMessage);
    %orig;
    SCIMarkDirectThreadSeenAfterOutgoingMessage(self, isReply);
}
%end

%end

void SCIInstallMessageSeenButtonHooksIfNeeded(void) {
    if (!SCIDirectManualSeenRulesEnabled() && ![SCIUtils getBoolPref:@"msgs_hide_reels_blend"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCIMessageSeenButtonHooks);
        SCIInstallDirectInboxSeenContextMenuHook();
    });
}

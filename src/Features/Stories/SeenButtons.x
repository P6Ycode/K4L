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
#import "../Messages/DeletedMessagesLog/SCIDeletedMessagesViewController.h"

#ifdef __cplusplus
extern "C" {
#endif
void SCIApplyButtonStyle(UIButton *button, NSInteger source);
#ifdef __cplusplus
}
#endif

static NSString * const kSCISeenMessagesBarIconResource = @"eye";
static NSString * const kSCIStoryMentionsBarIconResource = @"mention";
static NSInteger const kSCIActionButtonSourceDirect = 4;
static NSInteger const kSCIStorySeenButtonTag = 926001;
static NSInteger const kSCIStoryMentionsButtonTag = 926002;
static NSInteger const kSCIStoriesActionButtonTag = 921343;
static NSInteger const kSCIDirectActionButtonTag = 921344;
static NSInteger const kSCIDirectSeenButtonTag = 921345;
static const void *kSCIStoryOverlayObservedFooterAssocKey = &kSCIStoryOverlayObservedFooterAssocKey;
static const void *kSCIStoryOverlayHasObserverAssocKey = &kSCIStoryOverlayHasObserverAssocKey;
static const void *kSCIDirectSeenBottomConstraintAssocKey = &kSCIDirectSeenBottomConstraintAssocKey;
static const void *kSCIDirectSeenTrailingOverlayConstraintAssocKey = &kSCIDirectSeenTrailingOverlayConstraintAssocKey;
static const void *kSCIDirectSeenTrailingActionConstraintAssocKey = &kSCIDirectSeenTrailingActionConstraintAssocKey;
static const void *kSCIDirectSeenCenterYActionConstraintAssocKey = &kSCIDirectSeenCenterYActionConstraintAssocKey;
static const void *kSCIDirectSeenWidthConstraintAssocKey = &kSCIDirectSeenWidthConstraintAssocKey;
static const void *kSCIDirectSeenHeightConstraintAssocKey = &kSCIDirectSeenHeightConstraintAssocKey;
static const void *kSCIDirectSeenAnchoredActionButtonAssocKey = &kSCIDirectSeenAnchoredActionButtonAssocKey;
static const void *kSCIDirectThreadIdAssocKey = &kSCIDirectThreadIdAssocKey;
static const void *kSCIDirectVisualObservedInputViewAssocKey = &kSCIDirectVisualObservedInputViewAssocKey;
static const void *kSCIDirectVisualHasInputObserverAssocKey = &kSCIDirectVisualHasInputObserverAssocKey;
static void *kSCIStoryOverlayAlphaObserverContext = &kSCIStoryOverlayAlphaObserverContext;
static void *kSCIDirectVisualInputAlphaObserverContext = &kSCIDirectVisualInputAlphaObserverContext;
static NSInteger kSCISeenAutoBypassCount = 0;
static NSMutableDictionary<NSString *, NSNumber *> *SCISeenAutoLastTriggerTimes = nil;
static __weak UIView *SCIActiveStoryOverlayView = nil;

static id SCIKVCObject(id target, NSString *key);
static id SCIDirectCurrentMessageFromController(UIViewController *controller);
void SCIMarkStoryAsSeenForViewWithAdvancePref(UIView *view, NSString *advancePrefKey);

static inline BOOL SCIManualMessageSeenEnabled(void) {
    return [SCIUtils getBoolPref:@"msgs_manual_seen"];
}

static inline BOOL SCIDirectManualSeenRulesEnabled(void) {
    return [SCIUtils getBoolPref:@"msgs_manual_seen"] || SCIDirectManualSeenThreadCount(NO) > 0;
}

static inline BOOL SCIDirectSeenHooksNeeded(void) {
    return SCIDirectManualSeenRulesEnabled() ||
           [SCIUtils getBoolPref:@"msgs_manual_visual_seen"] ||
           [SCIUtils getBoolPref:@"msgs_advance_visual_on_seen"];
}

static inline BOOL SCIManualStorySeenEnabled(void) {
    return [SCIUtils getBoolPref:@"stories_manual_seen"];
}

static inline BOOL SCIStoryMentionsButtonEnabled(void) {
    return [SCIUtils getBoolPref:@"stories_mentions_btn"];
}

static inline BOOL SCIStorySeenHooksNeeded(void) {
    return [SCIUtils getBoolPref:@"stories_manual_seen"] ||
           SCIStoryManualSeenUserList(NO).count > 0 ||
           [SCIUtils getBoolPref:@"stories_mentions_btn"] ||
           [SCIUtils getBoolPref:@"stories_mark_seen_on_reply"] ||
           [SCIUtils getBoolPref:@"stories_advance_on_reply_seen"];
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

    for (NSString *selectorName in @[@"object", @"value"]) {
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
        @"_threadViewController",
        @"threadViewController",
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
    if (!target) {
        SCILog(@"General", @"[SCInsta MessagesSeen] No markLastMessageAsSeen target for controller=%@<%p>",
               NSStringFromClass([controller class]),
               controller);
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
    SCIDirectThreadContext *context = SCIDirectThreadContextFromSource(source);
    NSString *toggleTitle = SCIDirectCurrentThreadRuleActionTitle(context);
    if (toggleTitle.length > 0) {
        UIImage *toggleImage = [SCIAssetUtils instagramIconNamed:SCIDirectManualSeenListContainsThreadId(context.threadId, [SCIUtils getBoolPref:@"msgs_manual_seen"]) ? @"eye" : @"eye_off"];
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
        }];
        [children addObject:toggleAction];
    }

    UIImage *logImage = [SCIAssetUtils instagramIconNamed:@"message" pointSize:22.0];
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
        UIImage *image = [SCIAssetUtils instagramIconNamed:SCIDirectManualSeenListContainsThreadId(context.threadId, [SCIUtils getBoolPref:@"msgs_manual_seen"]) ? @"eye" : @"eye_off"];
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

static BOOL SCIOverlayIsDirectVisualOverlay(UIView *overlayView) {
    UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:overlayView];
    Class directViewerClass = NSClassFromString(@"IGDirectVisualMessageViewerController");
    return (directViewerClass && [nearestVC isKindOfClass:directViewerClass]);
}

static NSArray *SCIArrayFromCollection(id collection) {
    if (!collection ||
        [collection isKindOfClass:[NSDictionary class]] ||
        [collection isKindOfClass:[NSString class]] ||
        [collection isKindOfClass:[NSURL class]]) {
        return nil;
    }

    if ([collection isKindOfClass:[NSArray class]]) {
        return collection;
    }

    if ([collection isKindOfClass:[NSOrderedSet class]]) {
        return [(NSOrderedSet *)collection array];
    }

    if ([collection isKindOfClass:[NSSet class]]) {
        return [(NSSet *)collection allObjects];
    }

    if ([collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id item in collection) {
            [array addObject:item];
        }
        return array;
    }

    return nil;
}

static id SCIKVCObject(id target, NSString *key) {
    if (!target || key.length == 0) return nil;

    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SCIObjectForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;

    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static id SCIFirstObjectForSelectors(id target, NSArray<NSString *> *selectors) {
    if (!target || selectors.count == 0) return nil;
    for (NSString *selectorName in selectors) {
        id value = SCIObjectForSelector(target, selectorName);
        if (value) return value;
    }
    return nil;
}

static void SCIPlayButtonTappedHaptic(void) {
    UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
    [feedback selectionChanged];
}

static UIButton *SCIStorySeenButtonWithTag(UIView *container, NSInteger tag) {
    UIView *existing = [container viewWithTag:tag];
    if ([existing isKindOfClass:SCIChromeButton.class]) {
        return (UIButton *)existing;
    }
    [existing removeFromSuperview];

    SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:@"" pointSize:24.0 diameter:44.0];
    button.tag = tag;
    button.adjustsImageWhenHighlighted = YES;
    button.showsMenuAsPrimaryAction = NO;
    button.clipsToBounds = NO;
    [container addSubview:button];
    return button;
}

static void SCISetSeenButtonImage(UIButton *button, UIImage *image, NSString *logMessage) {
    UIImage *templatedImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if ([button isKindOfClass:SCIChromeButton.class]) {
        SCIChromeButton *chromeButton = (SCIChromeButton *)button;
        chromeButton.iconView.image = templatedImage;
        chromeButton.iconTint = UIColor.whiteColor;
        [button setImage:nil forState:UIControlStateNormal];
    } else {
        [button setImage:templatedImage forState:UIControlStateNormal];
    }

    SCILog(@"Capture", @"%@ tag=%ld button=%@<%p> subviews=%@ imageView=%@<%p> imageSuperview=%@<%p>",
           logMessage,
           (long)button.tag,
           NSStringFromClass(button.class),
           button,
           button.subviews,
           NSStringFromClass(button.imageView.class),
           button.imageView,
           NSStringFromClass(button.imageView.superview.class),
           button.imageView.superview);
}

static void SCIApplyStorySeenButtonStyle(UIButton *button) {
    if (!button) return;
    SCIApplyButtonStyle(button, kSCIActionButtonSourceDirect);
}

static UIView *SCIStoryFooterContainerFromOverlay(UIView *overlayView) {
    if (!overlayView) return nil;

    UIView *footerContainer = [SCIUtils getIvarForObj:overlayView name:"_footerContainerView"];
    if (![footerContainer isKindOfClass:[UIView class]]) {
        id selectorFooter = SCIObjectForSelector(overlayView, @"footerContainerView");
        footerContainer = [selectorFooter isKindOfClass:[UIView class]] ? (UIView *)selectorFooter : nil;
    }
    return footerContainer;
}

static void SCIUpdateStoryButtonsAlpha(UIView *overlayView, CGFloat alpha) {
    if (!overlayView) return;

    UIButton *actionButton = (UIButton *)[overlayView viewWithTag:kSCIStoriesActionButtonTag];
    if ([actionButton isKindOfClass:[UIButton class]]) {
        actionButton.alpha = alpha;
    }

    UIButton *seenButton = (UIButton *)[overlayView viewWithTag:kSCIStorySeenButtonTag];
    if ([seenButton isKindOfClass:[UIButton class]]) {
        seenButton.alpha = alpha;
    }

    UIButton *mentionsButton = (UIButton *)[overlayView viewWithTag:kSCIStoryMentionsButtonTag];
    if ([mentionsButton isKindOfClass:[UIButton class]]) {
        mentionsButton.alpha = alpha;
    }
}

static void SCIRemoveStoryOverlayAlphaObserverIfNeeded(UIView *overlayView) {
    UIView *observedFooter = objc_getAssociatedObject(overlayView, kSCIStoryOverlayObservedFooterAssocKey);
    BOOL hasObserver = [objc_getAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey) boolValue];
    if (observedFooter && hasObserver) {
        [observedFooter removeObserver:overlayView forKeyPath:@"alpha" context:kSCIStoryOverlayAlphaObserverContext];
    }

    objc_setAssociatedObject(overlayView, kSCIStoryOverlayObservedFooterAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void SCIEnsureStoryOverlayAlphaObserver(UIView *overlayView) {
    if (!overlayView) return;

    UIView *footerContainer = SCIStoryFooterContainerFromOverlay(overlayView);
    UIView *observedFooter = objc_getAssociatedObject(overlayView, kSCIStoryOverlayObservedFooterAssocKey);
    BOOL hasObserver = [objc_getAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey) boolValue];
    if (observedFooter && observedFooter != footerContainer && hasObserver) {
        [observedFooter removeObserver:overlayView forKeyPath:@"alpha" context:kSCIStoryOverlayAlphaObserverContext];
        objc_setAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hasObserver = NO;
    }

    if (observedFooter != footerContainer) {
        objc_setAssociatedObject(overlayView, kSCIStoryOverlayObservedFooterAssocKey, footerContainer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (footerContainer && !hasObserver) {
        [footerContainer addObserver:overlayView
                          forKeyPath:@"alpha"
                             options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                             context:kSCIStoryOverlayAlphaObserverContext];
        objc_setAssociatedObject(overlayView, kSCIStoryOverlayHasObserverAssocKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIView *SCIFindRightmostNativeButtonInView(UIView *view, UIView *overlayView) {
    if (!view || view.hidden || view.alpha < 0.01) return nil;

    UIView *rightmost = nil;
    CGFloat maxCenterX = 0.0;

    BOOL isCandidate = [view isKindOfClass:[UIButton class]] || [view isKindOfClass:[UIControl class]];
    if (!isCandidate) {
        NSString *className = NSStringFromClass(view.class);
        if ([className containsString:@"Button"] || [className containsString:@"Share"] || [className containsString:@"Like"]) {
            isCandidate = YES;
        }
    }

    if (isCandidate && CGRectGetWidth(view.frame) > 0.0) {
        CGRect rect = [view convertRect:view.bounds toView:overlayView];
        CGFloat centerX = CGRectGetMidX(rect);
        if (centerX > CGRectGetWidth(overlayView.frame) * 0.5) {
            rightmost = view;
            maxCenterX = centerX;
        }
    }

    for (UIView *subview in view.subviews) {
        UIView *candidate = SCIFindRightmostNativeButtonInView(subview, overlayView);
        if (candidate) {
            CGRect rect = [candidate convertRect:candidate.bounds toView:overlayView];
            CGFloat centerX = CGRectGetMidX(rect);
            if (centerX > maxCenterX) {
                maxCenterX = centerX;
                rightmost = candidate;
            }
        }
    }

    return rightmost;
}

static CGFloat SCIGetStoriesCustomButtonX(UIView *overlayView, CGFloat size) {
    UIView *footerContainer = nil;
    @try {
        footerContainer = [SCIUtils getIvarForObj:overlayView name:"_footerContainerView"];
        if (![footerContainer isKindOfClass:[UIView class]]) {
            id selectorFooter = SCIObjectForSelector(overlayView, @"footerContainerView");
            footerContainer = [selectorFooter isKindOfClass:[UIView class]] ? (UIView *)selectorFooter : nil;
        }
    } @catch (__unused id e) {}

    if (footerContainer) {
        UIView *nativeBtn = SCIFindRightmostNativeButtonInView(footerContainer, overlayView);
        if (nativeBtn) {
            CGRect rect = [nativeBtn convertRect:nativeBtn.bounds toView:overlayView];
            CGFloat centerX = CGRectGetMidX(rect);
            return centerX - size / 2.0;
        }
    }

    return CGRectGetWidth(overlayView.frame) - size - 6.0;
}

static CGRect SCIStorySeenBaseFrame(UIView *overlayView) {
    if (!overlayView) return CGRectZero;

    CGFloat size = 38.0;
    CGFloat y = 0.0;

    UIView *mediaView = [SCIUtils getIvarForObj:overlayView name:"_mediaView"];
    UIView *footerContainer = [SCIUtils getIvarForObj:overlayView name:"_footerContainerView"];
    if (![mediaView isKindOfClass:[UIView class]]) mediaView = nil;
    if (![footerContainer isKindOfClass:[UIView class]]) footerContainer = nil;

    if (mediaView) {
        CGRect mediaFrame = mediaView.frame;
        y = CGRectGetMaxY(mediaFrame) - size - 7.0;
        if (footerContainer && CGRectGetMinY(footerContainer.frame) < CGRectGetMaxY(mediaFrame)) {
            y -= 50.0;
        }
    } else if (footerContainer) {
        y = CGRectGetMinY(footerContainer.frame) - size - 12.0;
    } else {
        y = CGRectGetHeight(overlayView.bounds) - size - 12.0;
    }

    NSNumber *showCommentsPreview = [SCIUtils numericValueForObj:overlayView selectorName:@"showCommentsPreview"];
    if (!showCommentsPreview) {
        showCommentsPreview = [SCIUtils numericValueForObj:overlayView selectorName:@"isShowingCommentsPreview"];
    }
    if (!showCommentsPreview) {
        id kvcShowComments = SCIKVCObject(overlayView, @"showCommentsPreview");
        if ([kvcShowComments respondsToSelector:@selector(boolValue)]) {
            showCommentsPreview = @([kvcShowComments boolValue]);
        }
    }
    BOOL hasCommentsPreview = showCommentsPreview.boolValue;
    if (hasCommentsPreview) {
        UIView *hypeFaceswarmView = [SCIUtils getIvarForObj:overlayView name:"_hypeFaceswarmView"];
        if ([hypeFaceswarmView isKindOfClass:[UIView class]] && (y + size) > CGRectGetMinY(hypeFaceswarmView.frame)) {
            y = CGRectGetMinY(hypeFaceswarmView.frame) - size - 2.0;
        } else {
            y -= 35.0;
        }
    }

    CGFloat x = SCIGetStoriesCustomButtonX(overlayView, size);
    return CGRectMake(x, y, size, size);
}

static id SCIStorySectionControllerFromOverlayView(UIView *overlayView) {
    if (!overlayView) return nil;

    NSArray<NSString *> *delegateSelectors = @[@"mediaOverlayDelegate", @"retryDelegate", @"tappableOverlayDelegate", @"buttonDelegate"];
    Class sectionControllerClass = NSClassFromString(@"IGStoryFullscreenSectionController");

    for (NSString *selectorName in delegateSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![overlayView respondsToSelector:selector]) continue;

        id delegate = ((id (*)(id, SEL))objc_msgSend)(overlayView, selector);
        if (!delegate) continue;

        if (!sectionControllerClass || [delegate isKindOfClass:sectionControllerClass]) {
            return delegate;
        }
    }

    return nil;
}

static NSString *SCIStringFromValue(id value) {
    if (!value || value == (id)kCFNull) return nil;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *string = (NSString *)value;
        return string.length > 0 ? string : nil;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *string = [value stringValue];
        return string.length > 0 ? string : nil;
    }
    return [[value description] length] > 0 ? [value description] : nil;
}

static id SCIStoryMediaFromAnyObject(id object) {
    if (!object) return nil;
    id candidate = SCIFirstObjectForSelectors(object, @[@"media", @"mediaItem", @"storyItem", @"item", @"model"]);
    return candidate ?: object;
}

static BOOL SCIResolveStoryContextFromOverlay(UIView *overlayView, id *outMarkTarget, id *outSectionController, id *outMedia) {
    SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
    if (sharedContext) {
        if (outMarkTarget) *outMarkTarget = sharedContext.markSeenTarget;
        if (outSectionController) *outSectionController = sharedContext.sectionController;
        if (outMedia) *outMedia = sharedContext.media;
        return (sharedContext.media != nil);
    }

    if (!overlayView) return NO;

    SEL markSelector = NSSelectorFromString(@"fullscreenSectionController:didMarkItemAsSeen:");
    UIViewController *viewerController = [SCIUtils nearestViewControllerForView:overlayView];

    id sectionController = SCIStorySectionControllerFromOverlayView(overlayView);
    id markTarget = nil;
    id sectionDelegate = SCIObjectForSelector(sectionController, @"delegate");
    if (sectionDelegate && [sectionDelegate respondsToSelector:markSelector]) {
        markTarget = sectionDelegate;
    } else if (viewerController && [viewerController respondsToSelector:markSelector]) {
        markTarget = viewerController;
    } else {
        id overlayAncestor = SCIObjectForSelector(overlayView, @"_viewControllerForAncestor");
        if (overlayAncestor && [overlayAncestor respondsToSelector:markSelector]) {
            markTarget = overlayAncestor;
        }
    }

    if (!sectionController && markTarget) {
        sectionController = SCIFirstObjectForSelectors(markTarget, @[@"currentSectionController"]);
        if (!sectionController) {
            sectionController = [SCIUtils getIvarForObj:markTarget name:"_currentSectionController"];
        }
    }

    id media = SCIFirstObjectForSelectors(sectionController, @[@"currentStoryItem", @"currentItem", @"item"]);
    if (!media) media = SCIFirstObjectForSelectors(markTarget, @[@"currentStoryItem", @"currentItem", @"item"]);
    if (!media && viewerController) media = SCIFirstObjectForSelectors(viewerController, @[@"currentStoryItem", @"currentItem", @"item"]);
    media = SCIStoryMediaFromAnyObject(media);

    if (outMarkTarget) *outMarkTarget = markTarget;
    if (outSectionController) *outSectionController = sectionController;
    if (outMedia) *outMedia = media;

    return (media != nil);
}

static NSArray<NSDictionary *> *SCIStoryMentionsForOverlay(UIView *overlayView) {
    id markTarget = nil;
    id sectionController = nil;
    id media = nil;
    if (!SCIResolveStoryContextFromOverlay(overlayView, &markTarget, &sectionController, &media)) {
        return @[];
    }

    id mentionsCollection = SCIObjectForSelector(media, @"reelMentions");
    NSArray *mentions = SCIArrayFromCollection(mentionsCollection);
    if (mentions.count == 0) return @[];

    NSMutableArray<NSDictionary *> *userInfos = [NSMutableArray array];
    for (id mention in mentions) {
        id user = SCIKVCObject(mention, @"user");
        if (!user) user = SCIObjectForSelector(mention, @"user");
        if (!user) continue;

        NSString *username = SCIStringFromValue(SCIKVCObject(user, @"username"));
        if (!username) username = SCIStringFromValue(SCIObjectForSelector(user, @"username"));
        NSString *fullName = SCIStringFromValue(SCIKVCObject(user, @"fullName"));
        if (!fullName) fullName = SCIStringFromValue(SCIKVCObject(user, @"full_name"));

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        if (username.length > 0) entry[@"username"] = username;
        if (fullName.length > 0) entry[@"fullName"] = fullName;
        if (entry.count > 0) [userInfos addObject:entry];
    }

    return userInfos;
}

static void SCIAdvanceStoryAfterManualSeenIfNeeded(UIView *overlayView, NSString *advancePrefKey) {
    SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
    if (sharedContext) {
        SCIStoryAdvanceContextIfNeeded(sharedContext, advancePrefKey);
        return;
    }

    if (advancePrefKey.length == 0 || ![SCIUtils getBoolPref:advancePrefKey]) return;

    id sectionController = SCIStorySectionControllerFromOverlayView(overlayView);
    if (!sectionController) return;

    SCIForceStoryAutoAdvance = YES;
    BOOL advanced = NO;
    SEL advanceSelector = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
    if ([sectionController respondsToSelector:advanceSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(sectionController, advanceSelector, 1);
        advanced = YES;
    }

    if (!advanced) {
        advanceSelector = NSSelectorFromString(@"storyPlayerMediaViewDidPlayToEnd:");
        if ([sectionController respondsToSelector:advanceSelector]) {
            id mediaView = [SCIUtils getIvarForObj:sectionController name:"_mediaView"];
            if (!mediaView) mediaView = [SCIUtils getIvarForObj:overlayView name:"_mediaView"];
            ((void (*)(id, SEL, id))objc_msgSend)(sectionController, advanceSelector, mediaView);
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        SCIForceStoryAutoAdvance = NO;
    });
}

// Forward declaration — implemented in StoryMentions.x
extern void SCIPresentStoryMentionsSheet(UIView *overlayView);

static void SCIMarkCurrentStoryAsSeenFromOverlayWithAdvancePref(UIView *overlayView, NSString *advancePrefKey) {
    if (!overlayView) return;

    SCIStoryContext *sharedContext = SCIStoryContextFromOverlay(overlayView);
    if (sharedContext) {
        if (!sharedContext.markSeenTarget || !sharedContext.sectionController || !sharedContext.media) {
            SCINotify(kSCINotificationStoryMarkSeen, @"Unable to mark story as seen", nil, @"error_filled", SCINotificationToneError);
            return;
        }
        if (!SCIStoryMarkContextAsSeen(sharedContext)) {
            SCINotify(kSCINotificationStoryMarkSeen, @"Unable to mark story as seen", nil, @"error_filled", SCINotificationToneError);
            return;
        }
        SCIStoryAdvanceContextIfNeeded(sharedContext, advancePrefKey);
        SCINotify(kSCINotificationStoryMarkSeen, @"Marked story as seen", nil, @"circle_check_filled", SCINotificationToneSuccess);
        return;
    }

    id markTarget = nil;
    id sectionController = nil;
    id media = nil;
    BOOL resolved = SCIResolveStoryContextFromOverlay(overlayView, &markTarget, &sectionController, &media);
    if (!markTarget || !sectionController || !media) {
        SCINotify(kSCINotificationStoryMarkSeen, @"Unable to mark story as seen", nil, @"error_filled", SCINotificationToneError);
        return;
    }

    SEL markSelector = NSSelectorFromString(@"fullscreenSectionController:didMarkItemAsSeen:");
    SCIForcedStorySeenMediaPK = [SCIStoryMediaIdentifier(media) copy];
    SCIForceMarkStoryAsSeen = YES;
    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)(markTarget, markSelector, sectionController, media);
    } @finally {
        SCIForceMarkStoryAsSeen = NO;
        SCIForcedStorySeenMediaPK = nil;
    }

    if (resolved) {
        SCIAdvanceStoryAfterManualSeenIfNeeded(overlayView, advancePrefKey);
    }

    SCINotify(kSCINotificationStoryMarkSeen, @"Marked story as seen", nil, @"circle_check_filled", SCINotificationToneSuccess);
}

static void SCIMarkCurrentStoryAsSeenFromOverlay(UIView *overlayView) {
    SCIMarkCurrentStoryAsSeenFromOverlayWithAdvancePref(overlayView, @"stories_advance_on_manual_seen");
}

void SCIMarkStoryAsSeenForView(UIView *view) {
    SCIMarkStoryAsSeenForViewWithAdvancePref(view, nil);
}

void SCIMarkStoryAsSeenForViewWithAdvancePref(UIView *view, NSString *advancePrefKey) {
    UIView *walker = view;
    for (NSInteger depth = 0; walker && depth < 24; depth++, walker = walker.superview) {
        if ([walker isKindOfClass:%c(IGStoryFullscreenOverlayView)]) {
            SCIMarkCurrentStoryAsSeenFromOverlayWithAdvancePref(walker, advancePrefKey);
            return;
        }
    }
}

UIView *SCIActiveStoryOverlayForInteractions(void) {
    return SCIStoryActiveOverlay() ?: SCIActiveStoryOverlayView;
}

static UIView *SCIDirectOverlayViewFromController(UIViewController *controller) {
    if (!controller) return nil;

    id viewerContainer = [SCIUtils getIvarForObj:controller name:"_viewerContainerView"];
    if (!viewerContainer) viewerContainer = SCIKVCObject(controller, @"viewerContainerView");

    SEL overlaySelector = NSSelectorFromString(@"overlayView");
    if (![viewerContainer respondsToSelector:overlaySelector]) return nil;
    id overlay = ((id (*)(id, SEL))objc_msgSend)(viewerContainer, overlaySelector);
    return [overlay isKindOfClass:[UIView class]] ? (UIView *)overlay : nil;
}

static id SCIDirectCurrentMessageFromController(UIViewController *controller) {
    if (!controller) return nil;

    id dataSource = [SCIUtils getIvarForObj:controller name:"_dataSource"];
    if (!dataSource) dataSource = SCIKVCObject(controller, @"dataSource");

    id message = [SCIUtils getIvarForObj:dataSource name:"_currentMessage"];
    if (!message) message = SCIKVCObject(dataSource, @"currentMessage");
    return message;
}

static NSInteger SCIDirectCurrentIndexFromController(UIViewController *controller) {
    if (!controller) return 0;

    id dataSource = [SCIUtils getIvarForObj:controller name:"_dataSource"];
    if (!dataSource) dataSource = SCIKVCObject(controller, @"dataSource");

    for (NSString *selectorName in @[@"currentItemIndex", @"currentIndex", @"itemIndex"]) {
        NSNumber *index = [SCIUtils numericValueForObj:dataSource selectorName:selectorName];
        if (index && index.integerValue >= 0) return index.integerValue;
    }

    for (NSString *key in @[@"currentItemIndex", @"currentIndex", @"itemIndex"]) {
        id value = SCIKVCObject(dataSource, key);
        if ([value respondsToSelector:@selector(integerValue)] && [value integerValue] >= 0) {
            return [value integerValue];
        }
    }

    return 0;
}

static CGFloat SCIHeightFromFrameLikeObject(id object) {
    if (!object) return 0.0;

    if ([object isKindOfClass:[UIView class]]) {
        return ((UIView *)object).frame.size.height;
    }

    @try {
        id frameValue = [object valueForKey:@"frame"];
        if ([frameValue isKindOfClass:[NSValue class]]) {
            return ((NSValue *)frameValue).CGRectValue.size.height;
        }
    } @catch (__unused NSException *exception) {
    }

    return 0.0;
}

static CGFloat SCIDirectBottomOffset(UIViewController *controller) {
    if (!controller) return 12.0;

    id inputView = [SCIUtils getIvarForObj:controller name:"_inputView"];
    CGFloat offset = controller.view.safeAreaInsets.bottom + 12.0;
    if (inputView) {
        offset += SCIHeightFromFrameLikeObject(inputView);
    }

    return offset;
}

static UIView *SCIDirectInputViewFromController(UIViewController *controller) {
    if (!controller) return nil;

    id inputView = [SCIUtils getIvarForObj:controller name:"_inputView"];
    if (![inputView isKindOfClass:[UIView class]]) {
        inputView = SCIKVCObject(controller, @"inputView");
    }
    return [inputView isKindOfClass:[UIView class]] ? (UIView *)inputView : nil;
}

static void SCIUpdateDirectVisualButtonsAlpha(UIViewController *controller, CGFloat alpha) {
    if (!controller) return;
    UIView *overlay = SCIDirectOverlayViewFromController(controller);
    if (!overlay) return;

    UIButton *actionButton = (UIButton *)[overlay viewWithTag:kSCIDirectActionButtonTag];
    if ([actionButton isKindOfClass:[UIButton class]]) {
        actionButton.alpha = alpha;
    }

    UIButton *seenButton = (UIButton *)[overlay viewWithTag:kSCIDirectSeenButtonTag];
    if ([seenButton isKindOfClass:[UIButton class]]) {
        seenButton.alpha = alpha;
    }
}

static void SCIRemoveDirectVisualInputAlphaObserverIfNeeded(UIViewController *controller) {
    UIView *observedInputView = objc_getAssociatedObject(controller, kSCIDirectVisualObservedInputViewAssocKey);
    BOOL hasObserver = [objc_getAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey) boolValue];
    if (observedInputView && hasObserver) {
        [observedInputView removeObserver:controller forKeyPath:@"alpha" context:kSCIDirectVisualInputAlphaObserverContext];
    }

    objc_setAssociatedObject(controller, kSCIDirectVisualObservedInputViewAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void SCIEnsureDirectVisualInputAlphaObserver(UIViewController *controller) {
    if (!controller) return;

    UIView *inputView = SCIDirectInputViewFromController(controller);
    UIView *observedInputView = objc_getAssociatedObject(controller, kSCIDirectVisualObservedInputViewAssocKey);
    BOOL hasObserver = [objc_getAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey) boolValue];
    if (observedInputView && observedInputView != inputView && hasObserver) {
        [observedInputView removeObserver:controller forKeyPath:@"alpha" context:kSCIDirectVisualInputAlphaObserverContext];
        objc_setAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hasObserver = NO;
    }

    if (observedInputView != inputView) {
        objc_setAssociatedObject(controller, kSCIDirectVisualObservedInputViewAssocKey, inputView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (inputView && !hasObserver) {
        [inputView addObserver:controller
                    forKeyPath:@"alpha"
                       options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                       context:kSCIDirectVisualInputAlphaObserverContext];
        objc_setAssociatedObject(controller, kSCIDirectVisualHasInputObserverAssocKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static inline BOOL SCIShouldShowDirectVisualSeenButton(void) {
    return [SCIUtils getBoolPref:@"msgs_manual_seen"] || [SCIUtils getBoolPref:@"msgs_manual_visual_seen"];
}

static BOOL SCIDirectInvokeNoArgSelector(id object, SEL selector) {
    if (!object || !selector || ![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL))objc_msgSend)(object, selector);
    return YES;
}

static BOOL SCIDirectInvokeObjectArgSelector(id object, SEL selector, id argument) {
    if (!object || !selector || ![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
    return YES;
}

static BOOL SCIDirectInvokeIntegerArgSelector(id object, SEL selector, NSInteger argument) {
    if (!object || !selector || ![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(object, selector, argument);
    return YES;
}

static BOOL SCIDirectInvokeDismissShowNextSelector(id object) {
    SEL selector = NSSelectorFromString(@"dismissWithShowNext:completion:");
    if (!object || ![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, BOOL, id))objc_msgSend)(object, selector, YES, nil);
    return YES;
}

static NSArray *SCIDirectVisualAdvanceTargets(UIViewController *controller) {
    if (!controller) return @[];

    NSMutableArray *targets = [NSMutableArray array];
    NSArray<NSString *> *keys = @[
        @"_presentationManager",
        @"presentationManager",
        @"_viewerPresentationManager",
        @"viewerPresentationManager",
        @"_viewerContainerView",
        @"viewerContainerView",
        @"_viewerContainer",
        @"viewerContainer",
        @"_dataSource",
        @"dataSource",
        @"_delegate",
        @"delegate",
        @"_viewModel",
        @"viewModel"
    ];

    for (NSString *key in keys) {
        id target = [key hasPrefix:@"_"] ? [SCIUtils getIvarForObj:controller name:key.UTF8String] : SCIKVCObject(controller, key);
        if (target && ![targets containsObject:target]) {
            [targets addObject:target];
        }
    }

    if (![targets containsObject:controller]) {
        [targets addObject:controller];
    }

    return targets;
}

static BOOL SCIDirectAdvanceVisualViewer(UIViewController *controller) {
    if (!controller) return NO;

    SEL overlayTapSelector = NSSelectorFromString(@"fullscreenOverlay:didTapInRegion:");
    if ([controller respondsToSelector:overlayTapSelector]) {
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(controller, overlayTapSelector, nil, 3);
        return YES;
    }

    NSArray *targets = SCIDirectVisualAdvanceTargets(controller);

    for (id target in targets) {
        if (SCIDirectInvokeDismissShowNextSelector(target)) return YES;
    }

    NSArray<NSString *> *integerSelectors = @[
        @"advanceToNextItemWithNavigationAction:",
        @"advanceToNextItemWithNavigationType:",
        @"advanceToNextItemForNavigationAction:",
        @"moveToNextItemWithNavigationAction:",
        @"navigateToNextItemWithNavigationAction:"
    ];
    for (id target in targets) {
        for (NSString *selectorName in integerSelectors) {
            if (SCIDirectInvokeIntegerArgSelector(target, NSSelectorFromString(selectorName), 1)) return YES;
        }
    }

    NSArray<NSString *> *noArgSelectors = @[
        @"_advanceToNextItem",
        @"advanceToNextItem",
        @"moveToNextItem",
        @"navigateToNextItem",
        @"displayNextItem",
        @"showNextItem",
        @"goToNextItem"
    ];
    for (id target in targets) {
        for (NSString *selectorName in noArgSelectors) {
            if (SCIDirectInvokeNoArgSelector(target, NSSelectorFromString(selectorName))) return YES;
        }
    }

    overlayTapSelector = NSSelectorFromString(@"expandOverlay:didTapInRegion:");
    if ([controller respondsToSelector:overlayTapSelector]) {
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(controller, overlayTapSelector, nil, 3);
        return YES;
    }

    return SCIDirectInvokeObjectArgSelector(controller, NSSelectorFromString(@"_didTapHeaderViewDismissButton:"), nil);
}

static void SCIMarkDirectVisualMessageAsSeen(UIViewController *controller) {
    if (!controller) return;

    id message = SCIDirectCurrentMessageFromController(controller);
    if (!message) {
        SCINotify(kSCINotificationDirectVisualMarkSeen, @"Message not found", nil, @"error_filled", SCINotificationToneError);
        return;
    }

    id responders = [SCIUtils getIvarForObj:controller name:"_eventResponders"];
    if (!responders) responders = SCIKVCObject(controller, @"eventResponders");

    SEL beginPlaybackSelector = NSSelectorFromString(@"visualMessageViewerController:didBeginPlaybackForVisualMessage:atIndex:");
    Class eventHandlerClass = NSClassFromString(@"IGDirectVisualMessageViewerEventHandler");
    NSArray *responderCollection = SCIArrayFromCollection(responders);
    NSMutableArray *orderedResponders = [NSMutableArray array];
    for (id responder in responderCollection ?: (responders ? @[responders] : @[])) {
        if (eventHandlerClass && [responder isKindOfClass:eventHandlerClass]) {
            [orderedResponders addObject:responder];
        }
    }
    for (id responder in responderCollection ?: (responders ? @[responders] : @[])) {
        if (![orderedResponders containsObject:responder]) {
            [orderedResponders addObject:responder];
        }
    }

    BOOL dispatched = NO;

    SCIPendingDirectVisualMessageToMarkSeen = message;
    @try {
        for (id responder in orderedResponders) {
            if ([responder respondsToSelector:beginPlaybackSelector]) {
                dispatched = YES;
                ((void (*)(id, SEL, id, id, NSInteger))objc_msgSend)(responder, beginPlaybackSelector, controller, message, 0);
            }
        }
    } @finally {
        SCIPendingDirectVisualMessageToMarkSeen = nil;
    }
    if (!dispatched) {
        SCINotify(kSCINotificationDirectVisualMarkSeen, @"Unable to mark as seen", nil, @"error_filled", SCINotificationToneError);
        return;
    }

    if ([SCIUtils getBoolPref:@"msgs_advance_visual_on_seen"]) {
        __weak UIViewController *weakController = controller;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIDirectAdvanceVisualViewer(weakController);
        });
    }

    SCINotify(kSCINotificationDirectVisualMarkSeen, @"Marked as seen", nil, @"circle_check_filled", SCINotificationToneSuccess);
}

static void SCIInstallDirectSeenButton(UIViewController *controller) {
    UIView *overlay = SCIDirectOverlayViewFromController(controller);
    if (!overlay) return;

    UIButton *seenButton = (UIButton *)[overlay viewWithTag:kSCIDirectSeenButtonTag];
    if (!SCIShouldShowDirectVisualSeenButton()) {
        [seenButton removeFromSuperview];
        return;
    }

    if (![seenButton isKindOfClass:SCIChromeButton.class]) {
        [seenButton removeFromSuperview];
        seenButton = SCIStorySeenButtonWithTag(overlay, kSCIDirectSeenButtonTag);
        seenButton.tag = kSCIDirectSeenButtonTag;
        seenButton.adjustsImageWhenHighlighted = YES;
        UIImage *seenImage = [SCIAssetUtils instagramIconNamed:kSCISeenMessagesBarIconResource pointSize:24.0];
        SCISetSeenButtonImage(seenButton, seenImage, @"Direct seen custom icon assigned");
        [seenButton addTarget:controller action:@selector(sci_didTapDirectSeenButton:) forControlEvents:UIControlEventTouchUpInside];
    }

    seenButton.translatesAutoresizingMaskIntoConstraints = NO;
    SCIApplyStorySeenButtonStyle(seenButton);

    CGFloat size = 44.0;
    CGFloat bottomOffset = SCIDirectBottomOffset(controller);
    UIButton *actionButton = (UIButton *)[overlay viewWithTag:kSCIDirectActionButtonTag];
    BOOL actionVisible = [actionButton isKindOfClass:[UIButton class]]
        && !actionButton.hidden
        && actionButton.superview == overlay
        && CGRectGetWidth(actionButton.bounds) > 0.0
        && CGRectGetHeight(actionButton.bounds) > 0.0;

    NSLayoutConstraint *bottomConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenBottomConstraintAssocKey);
    NSLayoutConstraint *trailingOverlayConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenTrailingOverlayConstraintAssocKey);
    NSLayoutConstraint *trailingActionConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenTrailingActionConstraintAssocKey);
    NSLayoutConstraint *centerYActionConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenCenterYActionConstraintAssocKey);
    NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenWidthConstraintAssocKey);
    NSLayoutConstraint *heightConstraint = objc_getAssociatedObject(seenButton, kSCIDirectSeenHeightConstraintAssocKey);
    UIButton *anchoredActionButton = objc_getAssociatedObject(seenButton, kSCIDirectSeenAnchoredActionButtonAssocKey);

    if (!bottomConstraint || !trailingOverlayConstraint || !widthConstraint || !heightConstraint) {
        bottomConstraint = [seenButton.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor constant:-bottomOffset];
        trailingOverlayConstraint = [seenButton.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-10.0];
        widthConstraint = [seenButton.widthAnchor constraintEqualToConstant:size];
        heightConstraint = [seenButton.heightAnchor constraintEqualToConstant:size];

        [NSLayoutConstraint activateConstraints:@[
            bottomConstraint,
            trailingOverlayConstraint,
            widthConstraint,
            heightConstraint
        ]];

        objc_setAssociatedObject(seenButton, kSCIDirectSeenBottomConstraintAssocKey, bottomConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(seenButton, kSCIDirectSeenTrailingOverlayConstraintAssocKey, trailingOverlayConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(seenButton, kSCIDirectSeenWidthConstraintAssocKey, widthConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(seenButton, kSCIDirectSeenHeightConstraintAssocKey, heightConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (actionVisible && (!trailingActionConstraint || anchoredActionButton != actionButton)) {
        if (trailingActionConstraint) {
            trailingActionConstraint.active = NO;
        }
        trailingActionConstraint = [seenButton.trailingAnchor constraintEqualToAnchor:actionButton.leadingAnchor constant:-5.0];
        objc_setAssociatedObject(seenButton, kSCIDirectSeenTrailingActionConstraintAssocKey, trailingActionConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(seenButton, kSCIDirectSeenAnchoredActionButtonAssocKey, actionButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (actionVisible && (!centerYActionConstraint || anchoredActionButton != actionButton)) {
        if (centerYActionConstraint) {
            centerYActionConstraint.active = NO;
        }
        centerYActionConstraint = [seenButton.centerYAnchor constraintEqualToAnchor:actionButton.centerYAnchor];
        objc_setAssociatedObject(seenButton, kSCIDirectSeenCenterYActionConstraintAssocKey, centerYActionConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    bottomConstraint.constant = -bottomOffset;
    trailingOverlayConstraint.constant = -10.0;
    widthConstraint.constant = size;
    heightConstraint.constant = size;

    if (actionVisible && trailingActionConstraint) {
        bottomConstraint.active = NO;
        trailingOverlayConstraint.active = NO;
        trailingActionConstraint.active = YES;
        if (centerYActionConstraint) centerYActionConstraint.active = YES;
    } else {
        if (centerYActionConstraint) centerYActionConstraint.active = NO;
        if (trailingActionConstraint) trailingActionConstraint.active = NO;
        trailingOverlayConstraint.active = YES;
        bottomConstraint.active = YES;
    }

    [overlay bringSubviewToFront:seenButton];
}

// Seen buttons (in DMs)
// - Enables no seen for messages
%group SCISeenButtonHooks

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

%hook IGStoryFullscreenOverlayView
- (void)layoutSubviews {
    %orig;

    UIView *overlayView = (UIView *)self;
    SCIActiveStoryOverlayView = overlayView;
    SCIStorySetActiveOverlay(overlayView);
    SCIEnsureStoryOverlayAlphaObserver(overlayView);

    UIButton *seenButton = (UIButton *)[(UIView *)self viewWithTag:kSCIStorySeenButtonTag];
    UIButton *mentionsButton = (UIButton *)[(UIView *)self viewWithTag:kSCIStoryMentionsButtonTag];
    if (SCIOverlayIsDirectVisualOverlay((UIView *)self)) {
        [seenButton removeFromSuperview];
        [mentionsButton removeFromSuperview];
        UIView *footerContainer = SCIStoryFooterContainerFromOverlay(overlayView);
        if (footerContainer) {
            SCIUpdateStoryButtonsAlpha(overlayView, footerContainer.alpha);
        }
        return;
    }

    SCIStoryContext *storyContext = SCIStoryContextFromOverlay(overlayView);
    BOOL showSeenButton = SCIStoryManualSeenAppliesToContext(storyContext);
    if (!showSeenButton && SCIManualStorySeenEnabled() && SCIStoryManualSeenListContainsUsername(SCIStoryUsernameForContext(storyContext), YES)) {
        static NSMutableSet<NSString *> *autoSeenMarked;
        static dispatch_once_t autoSeenOnceToken;
        dispatch_once(&autoSeenOnceToken, ^{
            autoSeenMarked = [NSMutableSet set];
        });
        NSString *mediaIdentifier = SCIStoryMediaIdentifierForContext(storyContext);
        if (mediaIdentifier.length > 0 && ![autoSeenMarked containsObject:mediaIdentifier]) {
            [autoSeenMarked addObject:mediaIdentifier];
            SCIStoryMarkContextAsSeen(storyContext);
        }
    }
    if (!showSeenButton) {
        [seenButton removeFromSuperview];
        UIView *footerContainer = SCIStoryFooterContainerFromOverlay(overlayView);
        if (footerContainer) {
            SCIUpdateStoryButtonsAlpha(overlayView, footerContainer.alpha);
        }
    }

    if (showSeenButton && !seenButton) {
        seenButton = SCIStorySeenButtonWithTag((UIView *)self, kSCIStorySeenButtonTag);
        [seenButton addTarget:self action:@selector(sci_storySeenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sci_storySeenButtonLongPressed:)];
        longPress.minimumPressDuration = 0.5;
        [seenButton addGestureRecognizer:longPress];

        UIImage *seenImage = [SCIAssetUtils instagramIconNamed:kSCISeenMessagesBarIconResource pointSize:24.0];
        SCISetSeenButtonImage(seenButton, seenImage, @"Story seen custom icon assigned");
    }
    if (showSeenButton) {
        SCIApplyStorySeenButtonStyle(seenButton);
    }

    NSArray<NSDictionary *> *storyMentions = SCIStoryMentionsForOverlay(overlayView);
    BOOL showMentionsButton = SCIStoryMentionsButtonEnabled() && storyMentions.count > 0;
    if (showMentionsButton && !mentionsButton) {
        mentionsButton = SCIStorySeenButtonWithTag((UIView *)self, kSCIStoryMentionsButtonTag);
        [mentionsButton addTarget:self action:@selector(sci_storyMentionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

        UIImage *mentionsImage = [SCIAssetUtils instagramIconNamed:kSCIStoryMentionsBarIconResource pointSize:24.0];
        SCISetSeenButtonImage(mentionsButton, mentionsImage, @"Story mentions custom icon assigned");
    } else if (!showMentionsButton && mentionsButton) {
        [mentionsButton removeFromSuperview];
        mentionsButton = nil;
    }
    if (showMentionsButton) {
        SCIApplyStorySeenButtonStyle(mentionsButton);
    }

    UIButton *storyActionButton = (UIButton *)[overlayView viewWithTag:kSCIStoriesActionButtonTag];
    BOOL actionVisible = [storyActionButton isKindOfClass:[UIButton class]]
        && !storyActionButton.hidden
        && storyActionButton.superview == overlayView
        && CGRectGetWidth(storyActionButton.frame) > 0.0
        && CGRectGetHeight(storyActionButton.frame) > 0.0;
    CGRect baseFrame = SCIStorySeenBaseFrame(overlayView);
    CGFloat size = CGRectGetWidth(baseFrame);
    if (actionVisible) {
        size = CGRectGetWidth(storyActionButton.frame);
    }
    if (size <= 0.0) size = 38.0;

    CGFloat spacingReduction = 2.0;
    CGFloat y = actionVisible ? CGRectGetMinY(storyActionButton.frame) : CGRectGetMinY(baseFrame);
    CGFloat nextX = actionVisible
        ? (CGRectGetMinX(storyActionButton.frame) - size + spacingReduction)
        : CGRectGetMinX(baseFrame);

    if (showSeenButton && seenButton) {
        seenButton.frame = CGRectMake(nextX, y, size, size);
        [overlayView bringSubviewToFront:seenButton];
        nextX -= (size - spacingReduction);
    } else if (seenButton) {
        [seenButton removeFromSuperview];
        seenButton = nil;
    }

    if (showMentionsButton && mentionsButton) {
        mentionsButton.frame = CGRectMake(nextX, y, size, size);
        [overlayView bringSubviewToFront:mentionsButton];
    }

    UIView *footerContainer = SCIStoryFooterContainerFromOverlay(overlayView);
    if (footerContainer) {
        SCIUpdateStoryButtonsAlpha(overlayView, footerContainer.alpha);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context == kSCIStoryOverlayAlphaObserverContext && [keyPath isEqualToString:@"alpha"]) {
        CGFloat alpha = 1.0;
        id newAlphaValue = change[NSKeyValueChangeNewKey];
        if ([newAlphaValue respondsToSelector:@selector(floatValue)]) {
            alpha = [newAlphaValue floatValue];
        } else if ([object isKindOfClass:[UIView class]]) {
            alpha = ((UIView *)object).alpha;
        }
        SCIUpdateStoryButtonsAlpha((UIView *)self, alpha);
        return;
    }

    %orig(keyPath, object, change, context);
}

- (void)dealloc {
    SCIRemoveStoryOverlayAlphaObserverIfNeeded((UIView *)self);
    if (SCIStoryActiveOverlay() == (UIView *)self) {
        SCIStorySetActiveOverlay(nil);
    }
    if (SCIActiveStoryOverlayView == (UIView *)self) {
        SCIActiveStoryOverlayView = nil;
    }
    %orig;
}

%new - (void)sci_storySeenButtonTapped:(UIButton *)sender {
    (void)sender;
    SCIPlayButtonTappedHaptic();
    SCIMarkCurrentStoryAsSeenFromOverlay((UIView *)self);
}

%new - (void)sci_storySeenButtonLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    SCIPlayButtonTappedHaptic();
    SCIStoryContext *context = SCIStoryContextFromOverlay((UIView *)self);
    NSString *title = SCIStoryCurrentUserRuleConfirmationTitle(context);
    NSString *message = SCIStoryCurrentUserRuleConfirmationMessage(context);
    if (title.length == 0 || message.length == 0) {
        SCINotify(kSCINotificationStorySeenUserRule, @"Story user not found", nil, @"error_filled", SCINotificationToneError);
        return;
    }
    [SCIUtils showConfirmation:^{
        NSString *notificationTitle = nil;
        NSString *notificationSubtitle = nil;
        if (!SCIStoryToggleCurrentUserRule(context, &notificationTitle, &notificationSubtitle)) {
            SCINotify(kSCINotificationStorySeenUserRule, @"Story user not found", nil, @"error_filled", SCINotificationToneError);
            return;
        }
        SCINotify(kSCINotificationStorySeenUserRule, notificationTitle, notificationSubtitle, @"circle_check_filled", SCINotificationToneSuccess);
        [(UIView *)self setNeedsLayout];
    } title:title message:message];
}

%new - (void)sci_storyMentionsButtonTapped:(UIButton *)sender {
    (void)sender;
    SCIPlayButtonTappedHaptic();
    SCIPresentStoryMentionsSheet((UIView *)self);
}
%end

%hook IGDirectVisualMessageViewerController
- (void)viewDidLayoutSubviews {
    %orig;
    if (!SCIDirectSeenHooksNeeded()) return;
    UIView *inputView = SCIDirectInputViewFromController((UIViewController *)self);
    SCIEnsureDirectVisualInputAlphaObserver((UIViewController *)self);
    SCIInstallDirectSeenButton((UIViewController *)self);
    SCIUpdateDirectVisualButtonsAlpha((UIViewController *)self, inputView ? inputView.alpha : 1.0);
    __weak UIViewController *weakController = (UIViewController *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *strongController = weakController;
        if (!strongController) return;
        UIView *strongInputView = SCIDirectInputViewFromController(strongController);
        SCIInstallDirectSeenButton(strongController);
        SCIUpdateDirectVisualButtonsAlpha(strongController, strongInputView ? strongInputView.alpha : 1.0);
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (!SCIDirectSeenHooksNeeded()) {
        %orig(keyPath, object, change, context);
        return;
    }
    if (context == kSCIDirectVisualInputAlphaObserverContext && [keyPath isEqualToString:@"alpha"]) {
        CGFloat alpha = 1.0;
        id newAlphaValue = change[NSKeyValueChangeNewKey];
        if ([newAlphaValue respondsToSelector:@selector(floatValue)]) {
            alpha = [newAlphaValue floatValue];
        } else if ([object isKindOfClass:[UIView class]]) {
            alpha = ((UIView *)object).alpha;
        }
        SCIUpdateDirectVisualButtonsAlpha((UIViewController *)self, alpha);
        return;
    }

    %orig(keyPath, object, change, context);
}

- (void)dealloc {
    SCIRemoveDirectVisualInputAlphaObserverIfNeeded((UIViewController *)self);
    %orig;
}

%new - (void)sci_didTapDirectSeenButton:(UIButton *)sender {
    (void)sender;
    SCIPlayButtonTappedHaptic();
    SCIMarkDirectVisualMessageAsSeen((UIViewController *)self);
}
%end

%end

void SCIInstallSeenButtonHooksIfNeeded(void) {
    if (!SCIDirectSeenHooksNeeded() &&
        !SCIStorySeenHooksNeeded() &&
        ![SCIUtils getBoolPref:@"msgs_hide_reels_blend"]) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCISeenButtonHooks);
        SCIInstallDirectInboxSeenContextMenuHook();
    });
}

#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../AssetUtils.h"
#import "../../InstagramHeaders.h"
#import "../../Shared/Messages/SPKDirectSeenContext.h"
#import "../../Shared/Stories/SPKStoryContext.h"
#import "../../Shared/UI/SPKChrome.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "DeletedMessagesLog/SPKDeletedMessagesViewController.h"

#ifdef __cplusplus
extern "C" {
#endif
#ifdef __cplusplus
}
#endif

@interface UIViewController (SPKRefreshNavigationBar)
- (void)refreshRightBarButtonItems;
- (void)updateThreadNavigationBar;
@end

static NSString *const kSPKSeenMessagesBarIconResource = @"eye";
static const void *kSPKDirectThreadIdAssocKey = &kSPKDirectThreadIdAssocKey;
static NSInteger kSPKSeenAutoBypassCount = 0;
static NSMutableDictionary<NSString *, NSNumber *> *SPKSeenAutoLastTriggerTimes = nil;
static __weak id SPKDirectActiveMarkSeenTarget = nil;
static NSString *SPKDirectActiveMarkSeenThreadId = nil;

static id SPKKVCObject(id target, NSString *key);
static id SPKFindDirectMarkSeenTarget(id root, NSMutableSet<NSValue *> *visited);

static inline BOOL SPKDirectManualSeenRulesEnabled(void) {
    return [SPKUtils getBoolPref:@"msgs_manual_seen"] || SPKDirectManualSeenThreadCount(NO) > 0;
}

static inline BOOL SPKDirectSeenHooksNeeded(void) {
    return SPKDirectManualSeenRulesEnabled() ||
           [SPKUtils getBoolPref:@"msgs_manual_visual_seen"] ||
           [SPKUtils getBoolPref:@"msgs_advance_visual_on_seen"];
}
static inline BOOL SPKAutoSeenOnSendEnabled(void) {
    return SPKDirectManualSeenRulesEnabled() && [SPKUtils getBoolPref:@"msgs_seen_on_send"];
}

static inline BOOL SPKAutoSeenOnReplyEnabled(void) {
    return SPKDirectManualSeenRulesEnabled() && [SPKUtils getBoolPref:@"msgs_seen_on_reply"];
}

static inline BOOL SPKAutoSeenOnReactionEnabled(void) {
    return SPKDirectManualSeenRulesEnabled() && [SPKUtils getBoolPref:@"msgs_seen_on_reaction"];
}

static BOOL SPKValueIsPresent(id value) {
    if (!value || value == (id)kCFNull)
        return NO;
    if ([value isKindOfClass:[NSString class]])
        return [(NSString *)value length] > 0;
    if ([value isKindOfClass:[NSArray class]])
        return [(NSArray *)value count] > 0;
    if ([value isKindOfClass:[NSDictionary class]])
        return [(NSDictionary *)value count] > 0;
    return YES;
}

static id SPKFindDirectMarkSeenTarget(id root, NSMutableSet<NSValue *> *visited) {
    if (!root)
        return nil;

    NSValue *pointerValue = [NSValue valueWithNonretainedObject:root];
    if ([visited containsObject:pointerValue])
        return nil;
    [visited addObject:pointerValue];

    SEL markSelector = @selector(markLastMessageAsSeen);
    if ([root respondsToSelector:markSelector])
        return root;

    if ([root isKindOfClass:[UIView class]]) {
        id target = SPKFindDirectMarkSeenTarget([SPKUtils nearestViewControllerForView:(UIView *)root], visited);
        if (target)
            return target;
    }

    for (NSString *selectorName in @[
             @"object",
             @"value",
             @"containingViewController",
             @"presentingViewController",
             @"currentThread"
         ]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![root respondsToSelector:selector])
            continue;

        id candidate = ((id (*)(id, SEL))objc_msgSend)(root, selector);
        id target = SPKFindDirectMarkSeenTarget(candidate, visited);
        if (target)
            return target;
    }

    if ([root isKindOfClass:[UIViewController class]]) {
        UIViewController *viewController = (UIViewController *)root;
        id parentTarget = SPKFindDirectMarkSeenTarget(viewController.parentViewController, visited);
        if (parentTarget)
            return parentTarget;

        id presentingTarget = SPKFindDirectMarkSeenTarget(viewController.presentingViewController, visited);
        if (presentingTarget)
            return presentingTarget;

        id navigationTarget = SPKFindDirectMarkSeenTarget(viewController.navigationController, visited);
        if (navigationTarget)
            return navigationTarget;

        for (UIViewController *child in [(UIViewController *)root childViewControllers]) {
            id target = SPKFindDirectMarkSeenTarget(child, visited);
            if (target)
                return target;
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
        id candidate = [key hasPrefix:@"_"] ? [SPKUtils getIvarForObj:root name:key.UTF8String] : SPKKVCObject(root, key);
        id target = SPKFindDirectMarkSeenTarget(candidate, visited);
        if (target)
            return target;
    }

    return nil;
}

static BOOL SPKMarkDirectThreadMessagesAsSeen(id controller) {
    id target = SPKFindDirectMarkSeenTarget(controller, [NSMutableSet set]);
    SPKDirectThreadContext *context = SPKDirectThreadContextFromSource(controller);
    if (!target &&
        SPKDirectActiveMarkSeenTarget &&
        SPKDirectActiveMarkSeenThreadId.length > 0 &&
        context.threadId.length > 0 &&
        [SPKDirectActiveMarkSeenThreadId isEqualToString:context.threadId]) {
        target = SPKFindDirectMarkSeenTarget(SPKDirectActiveMarkSeenTarget, [NSMutableSet set]);
        if (target) {
            SPKLog(@"Messages", @"[Sparkle MessagesSeen] Using active mark target fallback threadId=%@ source=%@<%p> target=%@<%p>",
                   context.threadId ?: @"(unknown)",
                   NSStringFromClass([controller class]),
                   controller,
                   NSStringFromClass([target class]),
                   target);
        }
    }
    if (!target) {
        SPKLog(@"General", @"[Sparkle MessagesSeen] No markLastMessageAsSeen target for controller=%@<%p> threadId=%@ activeThreadId=%@",
               NSStringFromClass([controller class]),
               controller,
               context.threadId ?: @"(unknown)",
               SPKDirectActiveMarkSeenThreadId ?: @"(none)");
        return NO;
    }

    kSPKSeenAutoBypassCount++;
    @try {
        ((void (*)(id, SEL))objc_msgSend)(target, @selector(markLastMessageAsSeen));
        SPKLog(@"General", @"[Sparkle MessagesSeen] Marked via target=%@<%p> controller=%@<%p>",
               NSStringFromClass([target class]),
               target,
               NSStringFromClass([controller class]),
               controller);
    } @catch (NSException *exception) {
        if (kSPKSeenAutoBypassCount > 0)
            kSPKSeenAutoBypassCount--;
        SPKLog(@"General", @"[Sparkle MessagesSeen] markLastMessageAsSeen failed target=%@<%p> exception=%@",
               NSStringFromClass([target class]),
               target,
               exception);
        return NO;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (kSPKSeenAutoBypassCount > 0) {
            kSPKSeenAutoBypassCount--;
        }
    });

    return YES;
}

static BOOL SPKSeenAutoShouldTrigger(id source, NSString *reason) {
    if (!source || reason.length == 0)
        return NO;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!SPKSeenAutoLastTriggerTimes) {
        SPKSeenAutoLastTriggerTimes = [NSMutableDictionary dictionary];
    }

    NSString *key = [NSString stringWithFormat:@"%@:%p", reason, source];
    NSNumber *lastTrigger = SPKSeenAutoLastTriggerTimes[key];
    if (lastTrigger && (now - lastTrigger.doubleValue) < 0.75) {
        return NO;
    }

    SPKSeenAutoLastTriggerTimes[key] = @(now);
    return YES;
}

static void SPKTriggerAutoSeenForSource(id source, NSString *reason) {
    if (!SPKDirectManualSeenAppliesToSource(source)) {
        SPKDirectThreadContext *context = SPKDirectThreadContextFromSource(source);
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Auto seen skipped reason=%@ threadId=%@ source=%@<%p> manual seen does not apply",
               reason,
               context.threadId ?: @"(unknown)",
               NSStringFromClass([source class]),
               source);
        return;
    }
    if (!SPKSeenAutoShouldTrigger(source, reason)) {
        SPKDirectThreadContext *context = SPKDirectThreadContextFromSource(source);
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Auto seen debounced reason=%@ threadId=%@ source=%@<%p>",
               reason,
               context.threadId ?: @"(unknown)",
               NSStringFromClass([source class]),
               source);
        return;
    }

    SPKDirectThreadContext *context = SPKDirectThreadContextFromSource(source);
    SPKLog(@"Messages", @"[Sparkle MessagesSeen] Auto seen scheduled reason=%@ threadId=%@ source=%@<%p>",
           reason,
           context.threadId ?: @"(unknown)",
           NSStringFromClass([source class]),
           source);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPKMarkDirectThreadMessagesAsSeen(source);
    });
}

void SPKMarkDirectThreadSeenAfterOutgoingMessage(id source, BOOL isReply) {
    if (isReply) {
        if (!SPKAutoSeenOnReplyEnabled())
            return;
        SPKTriggerAutoSeenForSource(source, @"reply");
        return;
    }

    if (!SPKAutoSeenOnSendEnabled())
        return;
    SPKTriggerAutoSeenForSource(source, @"send");
}

void SPKMarkDirectThreadSeenAfterReaction(id source) {
    if (!SPKAutoSeenOnReactionEnabled())
        return;
    SPKTriggerAutoSeenForSource(source, @"reaction");
}

// Resolves the 1:1 chat partner from a thread context. Returns nil PK for
// group chats or when the participant list can't be narrowed to a single
// non-owner user — callers fall back to the full log in that case.
static void SPKDirectResolveChatPartner(SPKDirectThreadContext *context, NSString **outPK, NSString **outName) {
    if (outPK)
        *outPK = nil;
    if (outName)
        *outName = nil;
    if (!context || context.isGroup)
        return;

    NSArray<NSDictionary *> *users = context.users;
    if (![users isKindOfClass:NSArray.class] || users.count == 0)
        return;

    // Current account PK so we can exclude ourselves from the participant list.
    NSString *currentPk = nil;
    @try {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            id session = nil;
            @try {
                session = [w valueForKey:@"userSession"];
            } @catch (__unused id e) {
            }
            id user = session ? [session valueForKey:@"user"] : nil;
            for (NSString *key in @[ @"pk", @"instagramUserID", @"instagramUserId", @"userID", @"userId" ]) {
                id v = nil;
                @try {
                    v = [user valueForKey:key];
                } @catch (__unused id e) {
                }
                if ([v isKindOfClass:NSString.class] && [v length]) {
                    currentPk = v;
                    break;
                }
                if ([v isKindOfClass:NSNumber.class]) {
                    currentPk = [v stringValue];
                    break;
                }
            }
            if (currentPk.length)
                break;
        }
    } @catch (__unused id e) {
    }

    NSMutableArray<NSDictionary *> *others = [NSMutableArray array];
    for (NSDictionary *u in users) {
        if (![u isKindOfClass:NSDictionary.class])
            continue;
        NSString *pk = [u[@"pk"] isKindOfClass:NSString.class] ? u[@"pk"] : nil;
        if (!pk.length)
            continue;
        if (currentPk.length && [pk isEqualToString:currentPk])
            continue;
        [others addObject:u];
    }

    // Only a clean 1:1 (exactly one other participant) deep-links.
    if (others.count != 1)
        return;

    NSDictionary *partner = others.firstObject;
    NSString *pk = [partner[@"pk"] isKindOfClass:NSString.class] ? partner[@"pk"] : nil;
    NSString *username = [partner[@"username"] isKindOfClass:NSString.class] ? partner[@"username"] : nil;
    NSString *fullName = [partner[@"fullName"] isKindOfClass:NSString.class] ? partner[@"fullName"] : nil;
    if (outPK)
        *outPK = pk;
    if (outName)
        *outName = username.length ? username : fullName;
}

static UIMenu *SPKDirectSeenButtonMenu(id source) {
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
    SPKDirectSeenDebugPrintEnabled = YES;
    SPKDirectThreadContext *context = SPKDirectThreadContextFromSource(source);
    SPKDirectSeenDebugPrintEnabled = NO;
    NSString *toggleTitle = SPKDirectCurrentThreadRuleActionTitle(context);
    if (toggleTitle.length > 0) {
        BOOL applies = SPKDirectManualSeenAppliesToSource(context);
        UIImage *toggleImage = [SPKAssetUtils instagramIconNamed:applies ? @"eye_off" : @"eye" pointSize:22.0];
        UIAction *toggleAction = [UIAction actionWithTitle:toggleTitle
                                                     image:toggleImage
                                                identifier:nil
                                                   handler:^(__unused UIAction *action) {
                                                       NSString *title = nil;
                                                       NSString *subtitle = nil;
                                                       if (!SPKDirectToggleCurrentThreadRule(context, &title, &subtitle)) {
                                                           SPKLog(@"Messages", @"[Sparkle MessagesSeen] Eye menu toggle failed threadId=%@ source=%@<%p>",
                                                                  context.threadId ?: @"(unknown)",
                                                                  NSStringFromClass([source class]),
                                                                  source);
                                                           SPKNotify(kSPKNotificationDirectThreadSeenRule, @"Chat not found", nil, @"error_filled", SPKNotificationToneError);
                                                           return;
                                                       }
                                                       SPKNotify(kSPKNotificationDirectThreadSeenRule, title, subtitle, @"circle_check_filled", SPKNotificationToneSuccess);
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

    UIImage *logImage = [SPKAssetUtils instagramIconNamed:@"channels" pointSize:22.0];
    NSString *partnerPK = nil;
    NSString *partnerName = nil;
    SPKDirectResolveChatPartner(context, &partnerPK, &partnerName);
    // Pass threadId for groups too — presentForThreadId: resolves a group entry
    // via groupForThreadId:, so a group thread opens scoped to its own log.
    NSString *threadId = context.threadId;
    UIAction *logAction = [UIAction actionWithTitle:@"Deleted Messages"
                                              image:logImage
                                         identifier:nil
                                            handler:^(__unused UIAction *action) {
                                                if (threadId.length || partnerPK.length) {
                                                    [SPKDeletedMessagesViewController presentForThreadId:threadId senderPK:partnerPK senderName:partnerName fromViewController:nil];
                                                } else {
                                                    // Unresolved thread/participant — open the full list.
                                                    [SPKDeletedMessagesViewController presentFromViewController:nil];
                                                }
                                            }];
    [children addObject:logAction];

    UIImage *settingsImage = [SPKAssetUtils instagramIconNamed:@"settings" pointSize:22.0];
    UIAction *settingsAction = [UIAction actionWithTitle:@"Messages Settings"
                                                   image:settingsImage
                                              identifier:nil
                                                 handler:^(__unused UIAction *action) {
                                                     SPKNotify(kSPKNotificationOpenTopicSettings, @"Opened settings", nil, @"settings", SPKNotificationToneForIconResource(@"settings"));
                                                     [SPKUtils showSettingsForTopicTitle:@"Messages"];
                                                 }];
    [children addObject:settingsAction];

    return [UIMenu menuWithTitle:@"" children:children];
}

static void SPKDirectRememberActiveThreadContextForController(id controller, NSString *eventName) {
    SPKDirectThreadContext *context = SPKDirectThreadContextFromSource(controller);
    if (context.threadId.length == 0) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Active thread context not set event=%@ controller=%@<%p> missing threadId",
               eventName,
               NSStringFromClass([controller class]),
               controller);
        return;
    }

    objc_setAssociatedObject(controller, kSPKDirectThreadIdAssocKey, context.threadId, OBJC_ASSOCIATION_COPY_NONATOMIC);
    SPKDirectSetActiveThreadContext(context);

    id markTarget = SPKFindDirectMarkSeenTarget(controller, [NSMutableSet set]);
    if (markTarget) {
        SPKDirectActiveMarkSeenTarget = markTarget;
        SPKDirectActiveMarkSeenThreadId = [context.threadId copy];
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Active mark target set event=%@ threadId=%@ target=%@<%p>",
               eventName,
               context.threadId ?: @"(unknown)",
               NSStringFromClass([markTarget class]),
               markTarget);
    }
}

static void SPKDirectClearActiveThreadContextForController(id controller, NSString *eventName) {
    NSString *threadId = objc_getAssociatedObject(controller, kSPKDirectThreadIdAssocKey);
    SPKDirectThreadContext *activeContext = SPKDirectActiveThreadContext();
    if (threadId.length == 0) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Active thread context clear skipped event=%@ controller=%@<%p> no cached threadId",
               eventName,
               NSStringFromClass([controller class]),
               controller);
        return;
    }
    if (activeContext.threadId.length == 0) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Active thread context clear skipped event=%@ threadId=%@ no active context",
               eventName,
               threadId);
        return;
    }
    if (![activeContext.threadId isEqualToString:threadId]) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Active thread context clear skipped event=%@ cachedThreadId=%@ activeThreadId=%@",
               eventName,
               threadId,
               activeContext.threadId);
        return;
    }

    SPKDirectSetActiveThreadContext(nil);
    if ([SPKDirectActiveMarkSeenThreadId isEqualToString:threadId]) {
        SPKDirectActiveMarkSeenTarget = nil;
        SPKDirectActiveMarkSeenThreadId = nil;
    }
    objc_setAssociatedObject(controller, kSPKDirectThreadIdAssocKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static id (*SPKDirectOrigInboxContextMenuConfiguration)(id, SEL, id);

static id SPKDirectInboxContextMenuConfiguration(id self, SEL _cmd, id indexPath) {
    id configuration = SPKDirectOrigInboxContextMenuConfiguration(self, _cmd, indexPath);
    if (![configuration isKindOfClass:[UIContextMenuConfiguration class]])
        return configuration;

    id adapter = SPKKVCObject(self, @"listAdapter");
    if (!adapter)
        adapter = [SPKUtils getIvarForObj:self name:"_listAdapter"];
    if (!adapter || ![indexPath respondsToSelector:@selector(section)]) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Inbox menu context skipped: missing adapter/indexPath controller=%@<%p>",
               NSStringFromClass([self class]),
               self);
        return configuration;
    }

    SEL sectionControllerSelector = NSSelectorFromString(@"sectionControllerForSection:");
    if (![adapter respondsToSelector:sectionControllerSelector]) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Inbox menu context skipped: adapter lacks sectionControllerForSection adapter=%@<%p>",
               NSStringFromClass([adapter class]),
               adapter);
        return configuration;
    }

    NSInteger section = [(NSIndexPath *)indexPath section];
    id sectionController = ((id (*)(id, SEL, NSInteger))objc_msgSend)(adapter, sectionControllerSelector, section);
    id viewModel = SPKKVCObject(sectionController, @"viewModel");
    if (!viewModel)
        viewModel = [SPKUtils getIvarForObj:sectionController name:"_viewModel"];
    if (!viewModel)
        viewModel = SPKKVCObject(sectionController, @"item");
    if (!viewModel)
        viewModel = [SPKUtils getIvarForObj:sectionController name:"_item"];

    if (!viewModel) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Inbox menu context skipped: missing viewModel section=%ld sectionController=%@<%p>",
               (long)section,
               NSStringFromClass([sectionController class]),
               sectionController);
        return configuration;
    }

    SPKDirectThreadContext *context = SPKDirectThreadContextFromInboxViewModel(viewModel);
    NSString *toggleTitle = SPKDirectCurrentThreadRuleActionTitle(context);
    if (toggleTitle.length == 0) {
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Inbox menu context skipped: missing thread context viewModel=%@<%p>",
               NSStringFromClass([viewModel class]),
               viewModel);
        return configuration;
    }
    UIContextMenuConfiguration *originalConfiguration = (UIContextMenuConfiguration *)configuration;
    UIContextMenuActionProvider originalProvider = SPKKVCObject(originalConfiguration, @"actionProvider");
    UIContextMenuContentPreviewProvider originalPreview = SPKKVCObject(originalConfiguration, @"previewProvider");
    id<NSCopying> originalIdentifier = SPKKVCObject(originalConfiguration, @"identifier");

    UIContextMenuActionProvider wrappedProvider = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIMenu *baseMenu = nil;
        @try {
            baseMenu = originalProvider ? originalProvider(suggestedActions) : [UIMenu menuWithChildren:suggestedActions];
        } @catch (NSException *exception) {
            SPKLog(@"Messages", @"[Sparkle MessagesSeen] Inbox menu original provider failed threadId=%@ exception=%@ reason=%@",
                   context.threadId ?: @"(unknown)",
                   exception.name,
                   exception.reason);
            return [UIMenu menuWithChildren:suggestedActions ?: @[]];
        }
        if (![baseMenu isKindOfClass:[UIMenu class]]) {
            SPKLog(@"Messages", @"[Sparkle MessagesSeen] Inbox menu original provider returned invalid menu threadId=%@ menu=%@",
                   context.threadId ?: @"(unknown)",
                   baseMenu);
            return [UIMenu menuWithChildren:suggestedActions ?: @[]];
        }
        NSString *currentTitle = SPKDirectCurrentThreadRuleActionTitle(context) ?: toggleTitle;
        BOOL applies = SPKDirectManualSeenAppliesToSource(context);
        UIImage *image = [SPKAssetUtils instagramIconNamed:applies ? @"eye_off" : @"eye"];
        UIAction *toggleAction = [UIAction actionWithTitle:currentTitle
                                                     image:image
                                                identifier:nil
                                                   handler:^(__unused UIAction *action) {
                                                       NSString *notificationTitle = nil;
                                                       NSString *notificationSubtitle = nil;
                                                       if (!SPKDirectToggleCurrentThreadRule(context, &notificationTitle, &notificationSubtitle)) {
                                                           SPKLog(@"Messages", @"[Sparkle MessagesSeen] Inbox menu toggle failed threadId=%@ viewModel=%@<%p>",
                                                                  context.threadId ?: @"(unknown)",
                                                                  NSStringFromClass([viewModel class]),
                                                                  viewModel);
                                                           SPKNotify(kSPKNotificationDirectThreadSeenRule, @"Chat not found", nil, @"error_filled", SPKNotificationToneError);
                                                           return;
                                                       }
                                                       SPKNotify(kSPKNotificationDirectThreadSeenRule, notificationTitle, notificationSubtitle, @"circle_check_filled", SPKNotificationToneSuccess);
                                                   }];
        NSMutableArray *children = [baseMenu.children mutableCopy] ?: [NSMutableArray array];
        [children addObject:toggleAction];
        return [baseMenu menuByReplacingChildren:children];
    };

    return [UIContextMenuConfiguration configurationWithIdentifier:originalIdentifier
                                                   previewProvider:originalPreview
                                                    actionProvider:wrappedProvider];
}

static void SPKInstallDirectInboxSeenContextMenuHook(void) {
    SEL selector = NSSelectorFromString(@"networkingCoordinator_contextMenuConfigurationForThreadCellAtIndexPath:");
    for (NSString *className in @[ @"IGDirectInboxViewController", @"IGDirectInboxViewControllerImpl" ]) {
        Class inboxClass = NSClassFromString(className);
        if (!inboxClass || !class_getInstanceMethod(inboxClass, selector))
            continue;
        MSHookMessageEx(inboxClass, selector, (IMP)SPKDirectInboxContextMenuConfiguration, (IMP *)&SPKDirectOrigInboxContextMenuConfiguration);
        SPKLog(@"Messages", @"[Sparkle MessagesSeen] Installed inbox seen list context menu hook class=%@", className);
        return;
    }
    SPKLog(@"Messages", @"[Sparkle MessagesSeen] Inbox seen list context menu hook not installed: selector not found");
}

static id SPKKVCObject(id target, NSString *key) {
    if (!target || key.length == 0)
        return nil;

    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void SPKPlayButtonTappedHaptic(void) {
    UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
    [feedback selectionChanged];
}

%group SPKMessageSeenButtonHooks

%hook IGTallNavigationBarView
- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items {
    NSMutableArray *new_items = [[items filteredArrayUsingPredicate:
                                            [NSPredicate predicateWithBlock:^BOOL(UIBarButtonItem *value, NSDictionary *_) {
                                                if ([value.accessibilityIdentifier isEqualToString:@"spk-seen-btn"]) {
                                                    return false;
                                                }
                                                if ([SPKUtils getBoolPref:@"msgs_hide_reels_blend"]) {
                                                    return ![value.accessibilityIdentifier isEqualToString:@"blend-button"];
                                                }

                                                return true;
                                            }]] mutableCopy];

    // Messages seen
    if (SPKDirectManualSeenRulesEnabled()) {
        UIViewController *nearestVC = [SPKUtils nearestViewControllerForView:self];
        Class directThreadClass = NSClassFromString(@"IGDirectThreadViewController");
        if (directThreadClass && [nearestVC isKindOfClass:directThreadClass] && SPKDirectShouldShowSeenButtonForSource(nearestVC)) {
            SPKChromeButton *chromeButton = nil;
            UIBarButtonItem *seenButton = SPKChromeBarButtonItem(@"", 24.0, self, @selector(seenButtonHandler:), &chromeButton);
            [chromeButton setIconResource:kSPKSeenMessagesBarIconResource pointSize:24.0];
            seenButton.accessibilityIdentifier = @"spk-seen-btn";
            chromeButton.bubbleColor = UIColor.clearColor;
            chromeButton.iconTint = UIColor.labelColor;
            chromeButton.menu = SPKDirectSeenButtonMenu(nearestVC);
            chromeButton.showsMenuAsPrimaryAction = NO;
            [new_items addObject:seenButton];
        }
    }

    %orig([new_items copy]);
}

// Messages seen button
%new - (void)seenButtonHandler:(UIBarButtonItem *)sender {
(void)sender;
SPKPlayButtonTappedHaptic();
UIViewController *nearestVC = [SPKUtils nearestViewControllerForView:self];
if ([nearestVC isKindOfClass:%c(IGDirectThreadViewController)]) {
    if (SPKMarkDirectThreadMessagesAsSeen(nearestVC)) {
        SPKNotify(kSPKNotificationThreadMessagesMarkSeen, @"Marked messages as seen", nil, @"circle_check_filled", SPKNotificationToneSuccess);
    } else {
        SPKNotify(kSPKNotificationThreadMessagesMarkSeen, @"Unable to mark messages as seen", nil, @"error_filled", SPKNotificationToneError);
    }
}
}
%end

%hook IGDirectThreadViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!SPKDirectSeenHooksNeeded())
        return;
    SPKDirectRememberActiveThreadContextForController(self, @"viewWillAppear");
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!SPKDirectSeenHooksNeeded())
        return;
    SPKDirectRememberActiveThreadContextForController(self, @"viewDidAppear");
}

- (void)viewDidDisappear:(BOOL)animated {
    if (!SPKDirectSeenHooksNeeded()) {
        %orig;
        return;
    }
    if (self.isMovingFromParentViewController || self.isBeingDismissed || self.parentViewController == nil) {
        SPKDirectClearActiveThreadContextForController(self, @"viewDidDisappear");
    } else {
        NSString *threadId = objc_getAssociatedObject(self, kSPKDirectThreadIdAssocKey);
        if (threadId.length > 0 && [SPKDirectActiveThreadContext().threadId isEqualToString:threadId]) {
            SPKLog(@"Messages", @"[Sparkle MessagesSeen] Active thread context clear skipped event=viewDidDisappear threadId=%@ controller still retained",
                   threadId);
        }
    }
    %orig;
}

- (void)dealloc {
    if (SPKDirectSeenHooksNeeded()) {
        SPKDirectClearActiveThreadContextForController(self, @"dealloc");
    }
    %orig;
}
%end

// Messages seen logic
%hook IGDirectThreadViewListAdapterDataSource
- (BOOL)shouldUpdateLastSeenMessage {
    if (!SPKDirectManualSeenRulesEnabled())
        return %orig;
    if (SPKDirectManualSeenAppliesToSource(self)) {
        if (kSPKSeenAutoBypassCount > 0) {
            return %orig;
        }
        return false;
    }

    return %orig;
}
%end

%hook IGDirectMessageListViewController
- (BOOL)messageListDataSourceShouldUpdateSeenState:(id)arg1 {
    if (!SPKDirectManualSeenRulesEnabled())
        return %orig;
    if (SPKDirectManualSeenAppliesToSource(self)) {
        if (kSPKSeenAutoBypassCount > 0) {
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
    BOOL isReply = SPKValueIsPresent(quotedMessageId);
    %orig;
    SPKMarkDirectThreadSeenAfterOutgoingMessage(self, isReply);
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
    BOOL isReply = SPKValueIsPresent(quotedMessage);
    %orig;
    SPKMarkDirectThreadSeenAfterOutgoingMessage(self, isReply);
}
%end

%end

void SPKInstallMessageSeenButtonHooksIfNeeded(void) {
    if (!SPKDirectManualSeenRulesEnabled() && ![SPKUtils getBoolPref:@"msgs_hide_reels_blend"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKMessageSeenButtonHooks);
        SPKInstallDirectInboxSeenContextMenuHook();
    });
}

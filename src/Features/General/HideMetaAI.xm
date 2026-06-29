#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static inline BOOL SPKHideMetaAIDirect(void) {
    return [SPKUtils getBoolPref:@"general_hide_meta_ai_msgs"];
}

static inline BOOL SPKHideMetaAIExplore(void) {
    return [SPKUtils getBoolPref:@"general_hide_meta_ai_explore"];
}

static inline BOOL SPKHideMetaAIComments(void) {
    return [SPKUtils getBoolPref:@"general_hide_meta_ai_comments"];
}

static inline BOOL SPKHideMetaAICreation(void) {
    return [SPKUtils getBoolPref:@"general_hide_meta_ai_creation"];
}

static inline BOOL SPKHideMetaAIGlobal(void) {
    return [SPKUtils getBoolPref:@"general_hide_meta_ai_global"];
}

%group SPKHideMetaAIHooks

// Direct

// Meta AI button functionality on direct search bar
%hook IGDirectInboxViewController
- (void)searchBarMetaAIButtonTappedOnSearchBar:(id)arg1 {
    if (SPKHideMetaAIDirect())
{
        SPKLog(@"General", @"[Sparkle] Hiding meta ai: direct search bar functionality");

        return;
    }
    
    return %orig;
}
%end

// AI agents in direct new message view
%hook IGDirectRecipientGenAIBotsResult
- (id)initWithGenAIBots:(id)arg1 lastFetchedTimestamp:(id)arg2 {
    if (SPKHideMetaAIDirect())
{
        SPKLog(@"General", @"[Sparkle] Hiding meta ai: direct recipient ai agents");

        return nil;
    }
    
    return %orig;
}
%end

// Meta AI in message composer
%hook IGDirectCommandSystemListViewController
- (id)objectsForListAdapter:(id)arg1 {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        if (SPKHideMetaAIDirect()) {

            if ([obj isKindOfClass:%c(IGDirectCommandSystemViewModel)]) {
                IGDirectCommandSystemViewModel *typedObj = (IGDirectCommandSystemViewModel *)obj;
                IGDirectCommandSystemRow *cmdSystemRow = (IGDirectCommandSystemRow *)[typedObj row];

                IGDirectCommandSystemResult *_commandResult_command = MSHookIvar<IGDirectCommandSystemResult *>(cmdSystemRow, "_commandResult_command");

                if (_commandResult_command != nil) {
                    
                    // Meta AI
                    if ([[_commandResult_command title] isEqualToString:@"Meta AI"]) {
                        SPKLog(@"General", @"[Sparkle] Hiding meta ai: direct message composer suggestion");

                        shouldHide = YES;
                    }

                    // Meta AI (Imagine)
                    else if ([[_commandResult_command commandString] hasPrefix:@"/imagine"]) {
                        SPKLog(@"General", @"[Sparkle] Hiding meta ai: direct message composer /imagine suggestion");

                        shouldHide = YES;
                    }
                    
                }
            }
            
        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }
    }

    return [filteredObjs copy];
}
%end

// Suggested AI chats in direct inbox header
%hook IGDirectInboxNavigationHeaderView
- (id)initWithFrame:(CGRect)arg1
              title:(id)arg2
          titleView:(id)arg3
  directInboxConfig:(IGDirectInboxConfig *)config
        userSession:(id)arg5
    loggingDelegate:(id)arg6
{
    if (SPKHideMetaAIDirect()) {
        SPKLog(@"General", @"[Sparkle] Hiding meta ai: suggested ai chats in direct inbox header");

        @try {
            [config setValue:0 forKey:@"shouldShowAIChatsEntrypointButton"];
        }
        @catch (NSException *exception) {
            SPKLog(@"General", @"[Sparkle] WARNING: %@\n\nFull object: %@", exception.reason, config);
        }
    }

    return %orig(arg1, arg2, arg3, [config copy], arg5, arg6);
}
%end

// Meta AI "imagine" in media picker
%hook IGDirectMediaPickerViewController
- (id)initWithUserSession:(id)arg1
                   config:(IGDirectMediaPickerConfig *)config
             capabilities:(id)arg3
           threadMetadata:(id)arg4
            messageSender:(id)arg5
    threadAnalyticsLogger:(id)arg6
     multimodalPerfLogger:(id)arg7
     localSendSpeedLogger:(id)arg8
   sendAttributionFactory:(id)arg9 
{
    if (SPKHideMetaAIDirect()) {
        SPKLog(@"General", @"[Sparkle] Hiding meta ai: imagine tile in media picker");

        @try {
            IGDirectMediaPickerGalleryConfig *galleryConfig = [config valueForKey:@"galleryConfig"];

            [galleryConfig setValue:0 forKey:@"isImagineEntryPointEnabled"];
        }
        @catch (NSException *exception) {
            SPKLog(@"General", @"[Sparkle] WARNING: %@\n\nFull object: %@", exception.reason, config);
        }
    }

    return %orig(arg1, [config copy], arg3, arg4, arg5, arg6, arg7, arg8, arg9);
}
%end

// Write with meta ai in message composer
%hook IGDirectComposer
- (id)initWithLayoutSpecProvider:(id)arg1
                     userSession:(id)arg2
                 userLauncherSet:(id)arg3
                          config:(IGDirectComposerConfig *)config
                           style:(id)arg5
                            text:(id)arg6
{
    return %orig(arg1, arg2, arg3, [self patchConfig:config], arg5, arg6);
}

- (id)initWithLayoutSpecProvider:(id)arg1
                     userSession:(id)arg2
                 userLauncherSet:(id)arg3
                          config:(IGDirectComposerConfig *)config
                           style:(id)arg5
                            text:(id)arg6
           shouldUpdateModeLater:(BOOL)arg7
{
    return %orig(arg1, arg2, arg3, [self patchConfig:config], arg5, arg6, arg7);
}

- (id)_initializeWithLayoutSpecProvider:(id)arg1
                     userSession:(id)arg2
                 userLauncherSet:(id)arg3
                          config:(IGDirectComposerConfig *)config
                           style:(id)arg5
                            text:(id)arg6
           shouldUpdateModeLater:(BOOL)arg7
{
    return %orig(arg1, arg2, arg3, [self patchConfig:config], arg5, arg6, arg7);
}

- (void)setConfig:(IGDirectComposerConfig *)config {
    %orig([self patchConfig:config]);

    return;
}

%new - (IGDirectComposerConfig *)patchConfig:(IGDirectComposerConfig *)config {
    if (SPKHideMetaAIDirect()) {

        SPKLog(@"General", @"[Sparkle] Hiding meta ai: reconfiguring direct composer");

        // writeWithAIEnabled
        @try {
            [config setValue:0 forKey:@"writeWithAIEnabled"];
        }
        @catch (NSException *exception) {
            SPKLog(@"General", @"[Sparkle] WARNING: %@\n\nFull object: %@", exception.reason, config);
        }

    }

    return [config copy];
}
%end

// Demangled name: IGAIRewrite.IGAIRewriteStoryRepliesPresenter
%hook _TtC11IGAIRewrite32IGAIRewriteStoryRepliesPresenter
- (BOOL)shouldShowAIRewriteButton:(id)arg1 input:(id)arg2 {
    if (SPKHideMetaAIDirect()) {
        SPKLog(@"General", @"[Sparkle] Hiding meta ai: disable ai rewrite story reply presenter");

        return NO;
    }

    return %orig(arg1, arg2);
}

%end

// Direct sticker tray picker view
%hook IGStickerTrayListAdapterDataSource
- (id)objectsForListAdapter:(id)arg1 {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        if (SPKHideMetaAIDirect()) {

            if ([obj isKindOfClass:%c(IGDirectUnifiedComposerAIStickerModel)]) {
                SPKLog(@"General", @"[Sparkle] Hiding meta ai: AI stickers option in sticker view");
                
                shouldHide = YES;
            }
            
        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }
    }

    return [filteredObjs copy];
}
%end

// Long press menu on messages
// Demangled name: IGDirectMessageMenuConfiguration.IGDirectMessageMenuConfiguration
%hook _TtC32IGDirectMessageMenuConfiguration32IGDirectMessageMenuConfiguration
+ (id)menuConfigurationWithEligibleOptions:(id)options
                          messageViewModel:(id)arg2
                               contentType:(id)arg3
                                 isSticker:(_Bool)arg4
                            isMusicSticker:(_Bool)arg5
                          directNuxManager:(id)arg6
                       sessionUserDefaults:(id)arg7
                               launcherSet:(id)arg8
                               userSession:(id)arg9
                                tapHandler:(id)arg10
{
    // 31: Restyle
    // 41: Make AI image
    NSArray *newOptions = options;
    if (SPKHideMetaAIDirect()) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT (SELF IN %@)", @[ @(31), @(41) ]];
        newOptions = [options filteredArrayUsingPredicate:predicate];
    }

    return %orig([newOptions copy], arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10);
}
%end

// Expanded in-chat photo UI
// Demangled name: IGDirectAggregatedMediaViewerComponentsSwift.IGDirectAggregatedMediaViewerViewControllerTitleViewModelObject
%hook _TtC44IGDirectAggregatedMediaViewerComponentsSwift63IGDirectAggregatedMediaViewerViewControllerTitleViewModelObject
- (id)initWithAuthorProfileImage:(id)arg1
                  authorUsername:(id)arg2
                      canForward:(_Bool)arg3
                         canSave:(_Bool)arg4
                   canAddToStory:(_Bool)arg5
                canShowAIRestyle:(_Bool)arg6
                       canUnsend:(_Bool)arg7
                       canReport:(_Bool)arg8
                   displayConfig:(id)arg9
                       isPending:(_Bool)arg10
             isMoreMenuListStyle:(_Bool)arg11
             senderIsCurrentUser:(_Bool)arg12
             shouldHideInfoViews:(_Bool)arg13
                        subtitle:(id)arg14
                      entryPoint:(long long)arg15
                    canTapAuthor:(_Bool)arg16
{
    BOOL showAiRestyle = SPKHideMetaAIDirect() ? false : arg6;

    return %orig(arg1, arg2, arg3, arg4, arg5, showAiRestyle, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16);
}
%end

// AI generated DM channel themes
%hook IGDirectThreadThemePickerViewController
- (id)objectsForListAdapter:(id)arg1 {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        if (SPKHideMetaAIDirect()) {

            if (
                [obj isKindOfClass:%c(IGDirectThreadThemePickerOption)]
                && [[obj valueForKey:@"themeId"] isEqualToString:@"direct_ai_theme_creation"]
            ) {
                SPKLog(@"General", @"[Sparkle] Hiding meta ai: AI generated DM channel themes");
                
                shouldHide = YES;
            }
            
        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }
    }

    return [filteredObjs copy];
}
%end

// "Click to summarize" pill under DM navigation bar
%hook IGDirectThreadViewMetaAISummaryFeatureController
- (id)initWithUserSession:(id)arg1 mutableStateProvider:(id)arg2 threadViewControllerFeatureDelegate:(id)arg3 presentingViewController:(id)arg4 {
    if (SPKHideMetaAIDirect()) {
        return nil;
    }

    return %orig(arg1, arg2, arg3, arg4);
}
%end

/////////////////////////////////////////////////////////////////////////////

// Explore

// Meta AI explore search summary
%hook IGDiscoveryListKitGQLDataSource
- (id)objectsForListAdapter:(id)arg1 {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        // Meta AI summary
        if ([obj isKindOfClass:%c(IGSearchMetaAIHCMModel)]) {
            
            if (SPKHideMetaAIExplore()) {
                SPKLog(@"General", @"[Sparkle] Hiding explore meta ai search summary");

                shouldHide = YES;
            }

        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }

    }

    return [filteredObjs copy];
}
%end

// Meta AI search bar ring button
%hook IGSearchBarDonutButton
- (void)didMoveToWindow {
    %orig;

    if (SPKHideMetaAIExplore()) {
        [self removeFromSuperview];
    }
}
%end

/////////////////////////////////////////////////////////////////////////////

// Reels/Sundial

// Suggested AI searches in comment section
%hook IGCommentConfig
- (id)initWithUserSession:(id)session
   commentThreadConfiguration:(IGCommentThreadConfiguration *)threadConfig
sponsoredSupportConfiguration:(id)supportConfig
          CTAPresenterContext:(id)context
                    replyText:(id)text
              loggingDelegate:(id)loggingDelegate
     presentingViewController:(id)vc
   childCommentThreadDelegate:(id)threadDelegate 
{
    if (SPKHideMetaAIComments()) {
        [threadConfig setValue:@(YES) forKey:@"disableMetaAICarousel"];
    }
    return %orig(session, threadConfig, supportConfig, context, text, loggingDelegate, vc, threadDelegate);
}
%end

// Suggested AI searches in comment section (workaround if setting comment thread config fails)
%hook IGCommentThreadAICarousel
- (id)initWithLauncherSet:(id)arg1 hasSearchPrefix:(BOOL)arg2 {
    if (SPKHideMetaAIComments()) {
        SPKLog(@"General", @"[Sparkle] Hiding meta ai: suggested ai searches comment carousel");

        return nil;
    }

    return %orig;
}
%end

%hook _TtC34IGCommentThreadAICarouselPillSwift30IGCommentThreadAICarouselSwift
- (id)initWithLauncherSet:(id)arg1 hasSearchPrefix:(BOOL)arg2 {
    if (SPKHideMetaAIComments()) {
        SPKLog(@"General", @"[Sparkle] Hiding meta ai: suggested ai searches comment carousel");

        return nil;
    }

    return %orig;
}
%end

/////////////////////////////////////////////////////////////////////////////

// Story

// AI images "add to story" suggestion
// Demangled name: IGGalleryDestinationToolbar.IGGalleryDestinationToolbarView
%hook _TtC27IGGalleryDestinationToolbar31IGGalleryDestinationToolbarView
- (void)setTools:(id)tools {
    NSArray *newTools = [tools copy];

    if (SPKHideMetaAICreation()) {
        SPKLog(@"General", @"[Sparkle] Hiding meta ai: ai images add to story suggestion");

        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT (SELF IN %@)", @[ @(9), @(10), @(11) ]];
        newTools = [tools filteredArrayUsingPredicate:predicate];
    }

    %orig(newTools);

    return;
}
%end

// AI generated fonts in text entry
%hook IGCreationTextToolView
- (id)initWithMenuConfiguration:(unsigned long long)configuration userSession:(id)session creationEntryPoint:(long long)point isAIFontsEnabled:(_Bool)enabled genAINuxManager:(id)manager showFontBadge:(_Bool)badge {
    return %orig(configuration, session, point, SPKHideMetaAICreation() ? false : enabled, manager, badge);
}
%end

// Text rewrite in text entry
%hook IGStoryTextMentionLocationPickerView
- (id)initWithIsTextRewriteEnabled:(_Bool)arg1
             isImageRewriteEnabled:(_Bool)arg2
      isStackedToolSelectorEnabled:(_Bool)arg3
          isMentionLocationVisible:(_Bool)arg4
           isEnabledForFeedCaption:(_Bool)arg5
                  isFeedEntryPoint:(_Bool)arg6
{
    _Bool isTextRewriteEnabled = SPKHideMetaAICreation() ? false : arg1;
    _Bool isImageRewriteEnabled = SPKHideMetaAICreation() ? false : arg2;

    return %orig(isTextRewriteEnabled, isImageRewriteEnabled, arg3, arg4, arg5, arg6);
}
%end

// "Imagine background" in story editor vertical action bar
%hook _TtC17IGCreationOSSwift19IGCreationHeaderBar
- (void)setButtons:(id)buttons maxItems:(NSInteger)max {
    NSArray *filteredObjs = buttons;

    if (SPKHideMetaAICreation()) {
        filteredObjs = [filteredObjs filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(IGCreationActionBarLabeledButton *obj, NSDictionary *bindings) {

                return !(
                    obj.button
                    && [((IGCreationActionBarButton *)obj.button).accessibilityIdentifier isEqualToString:@"contextual-background"]
                );
                
            }]
        ];
    }

    %orig(filteredObjs, max);
}
%end

/////////////////////////////////////////////////////////////////////////////

// Other

// Meta AI-branded search bars
%hook IGSearchBar
- (id)initWithConfig:(IGSearchBarConfig *)config {
    return %orig([self sanitizePlaceholderForConfig:config]);
}

- (id)initWithConfig:(IGSearchBarConfig *)config userSession:(id)arg2 {
    return %orig([self sanitizePlaceholderForConfig:config], arg2);
}

- (void)setConfig:(IGSearchBarConfig *)config {
    %orig([self sanitizePlaceholderForConfig:config]);

    return;
}

%new - (IGSearchBarConfig *)sanitizePlaceholderForConfig:(IGSearchBarConfig *)config {
    if (SPKHideMetaAIGlobal()) {

        SPKLog(@"General", @"[Sparkle] Hiding meta ai: reconfiguring search bar");

        NSString *placeholder = [config valueForKey:@"placeholder"];

        if ([placeholder containsString:@"Meta AI"]) {

            // placeholder
            @try {
                [config setValue:@"Search" forKey:@"placeholder"];
            }
            @catch (NSException *exception) {
                SPKLog(@"General", @"[Sparkle] WARNING: %@\n\nFull object: %@", exception.reason, config);
            }

            // shouldAnimatePlaceholder
            @try {
                [config setValue:0 forKey:@"shouldAnimatePlaceholder"];
            }
            @catch (NSException *exception) {
                SPKLog(@"General", @"[Sparkle] WARNING: %@\n\nFull object: %@", exception.reason, config);
            }

            SPKLog(@"General", @"[Sparkle] Changed search bar placeholder from: \"%@\" to \"%@\"", placeholder, [config valueForKey:@"placeholder"]);

            // leftIconStyle
            @try {
                [config setValue:0 forKey:@"leftIconStyle"];
            }
            @catch (NSException *exception) {
                SPKLog(@"General", @"[Sparkle] WARNING: %@\n\nFull object: %@", exception.reason, config);
            }

            // rightButtonStyle
            @try {
                [config setValue:0 forKey:@"rightButtonStyle"];
            }
            @catch (NSException *exception) {
                SPKLog(@"General", @"[Sparkle] WARNING: %@\n\nFull object: %@", exception.reason, config);
            }

        }

    }

    return [config copy];
}
%end

@interface IGDirectMessageCellShortcutView : UIView
@end

%hook IGDirectMessageCellShortcutView
- (void)setViewModel:(id)viewModel {
    %orig;

    if (SPKHideMetaAIDirect() || SPKHideMetaAIGlobal()) {
        @try {
            UIButton *iconButton = MSHookIvar<UIButton *>(self, "_iconButton");
            if (iconButton != nil) {
                NSString *label = [iconButton accessibilityLabel];
                NSString *identifier = [iconButton accessibilityIdentifier];
                if ([label caseInsensitiveCompare:@"Restyle"] == NSOrderedSame ||
                    [label caseInsensitiveCompare:@"Create with Meta AI"] == NSOrderedSame ||
                    [identifier containsString:@"restyle"] ||
                    [identifier containsString:@"meta_ai"]) {
                    
                    SPKLog(@"General", @"[Sparkle] Hiding IGDirectMessageCellShortcutView in setViewModel: (label: %@, id: %@)", label, identifier);
                    self.hidden = YES;
                    [self removeFromSuperview];
                }
            }
        }
        @catch (NSException *exception) {
            SPKLog(@"General", @"[Sparkle] WARNING: Exception in setViewModel: %@", exception.reason);
        }
    }
}

- (void)layoutSubviews {
    %orig;

    if (SPKHideMetaAIDirect() || SPKHideMetaAIGlobal()) {
        @try {
            UIButton *iconButton = MSHookIvar<UIButton *>(self, "_iconButton");
            if (iconButton != nil) {
                NSString *label = [iconButton accessibilityLabel];
                NSString *identifier = [iconButton accessibilityIdentifier];
                if ([label caseInsensitiveCompare:@"Restyle"] == NSOrderedSame ||
                    [label caseInsensitiveCompare:@"Create with Meta AI"] == NSOrderedSame ||
                    [identifier containsString:@"restyle"] ||
                    [identifier containsString:@"meta_ai"]) {
                    
                    self.hidden = YES;
                    [self removeFromSuperview];
                }
            }
        }
        @catch (NSException *exception) {}
    }
}
%end

// Themed in-app buttons
%hook UIButton
- (void)didMoveToWindow {
    %orig;

    if (SPKHideMetaAIDirect() || SPKHideMetaAICreation() || SPKHideMetaAIGlobal()) {
        NSString *accessibilityID = self.accessibilityIdentifier;
        if ([accessibilityID containsString:@"meta_ai"] ||
            [accessibilityID containsString:@"restyle"] ||
            [accessibilityID containsString:@"magic_mod"] ||
            [accessibilityID containsString:@"ai_restyle"] ||
            [accessibilityID containsString:@"imagine"]) {
            
            SPKLog(@"General", @"[Sparkle] Hiding UIButton: %@", accessibilityID);
            self.hidden = YES;
            [self removeFromSuperview];
        }
    }
}

- (void)setAccessibilityIdentifier:(NSString *)accessibilityIdentifier {
    %orig;

    if (SPKHideMetaAIDirect() || SPKHideMetaAICreation() || SPKHideMetaAIGlobal()) {
        if ([accessibilityIdentifier containsString:@"meta_ai"] ||
            [accessibilityIdentifier containsString:@"restyle"] ||
            [accessibilityIdentifier containsString:@"magic_mod"] ||
            [accessibilityIdentifier containsString:@"ai_restyle"] ||
            [accessibilityIdentifier containsString:@"imagine"]) {
            
            SPKLog(@"General", @"[Sparkle] Hiding UIButton via setAccessibilityIdentifier: %@", accessibilityIdentifier);
            self.hidden = YES;
            [self removeFromSuperview];
        }
    }
}
%end

// Home feed meta ai button
%hook IGFloatingActionButton.IGFloatingActionButton
- (void)didMoveToSuperview {
    %orig;
    if (SPKHideMetaAIGlobal()) {
        [self removeFromSuperview];
        SPKLog(@"General", @"[Sparkle] Hiding meta ai: home feed meta ai button");
    }
}
%end

// Share menu recipients
%hook IGDirectRecipientListViewController
- (id)objectsForListAdapter:(id)arg1 {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        if (SPKHideMetaAIDirect()) {
            if ([obj isKindOfClass:%c(IGDirectRecipientCellViewModel)]) {

                // Meta AI (catch-all)
                if ([[[obj recipient] threadName] isEqualToString:@"Meta AI"]) {
                    SPKLog(@"General", @"[Sparkle] Hiding meta ai suggested as recipient (share menu)");

                    shouldHide = YES;
                }

            }
        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }

    }

    return [filteredObjs copy];
}
%end

%end

extern "C" void SPKInstallHideMetaAIHooksIfEnabled(void) {
    if (!SPKHideMetaAIDirect() &&
        !SPKHideMetaAIExplore() &&
        !SPKHideMetaAIComments() &&
        !SPKHideMetaAICreation() &&
        !SPKHideMetaAIGlobal()) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKHideMetaAIHooks);
    });
}

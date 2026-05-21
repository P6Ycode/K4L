#import "SCIStoryContext.h"

#import <objc/message.h>

#import "../../Tweak.h"
#import "../../Utils.h"
#import "../ActionButton/ActionButtonLookupUtils.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../../Settings/SCISettingsViewController.h"
#import "../../Settings/SCISetting.h"
#import "../../Settings/SCITopicSettingsSupport.h"
#import "../../Shared/UI/SCIMediaChrome.h"

static __weak UIView *SCIStoryActiveOverlayView;

@implementation SCIStoryContext
- (instancetype)init {
    if ((self = [super init])) {
        _currentIndex = 0;
    }
    return self;
}
@end

void SCIStorySetActiveOverlay(UIView *overlayView) {
    SCIStoryActiveOverlayView = overlayView;
}

UIView *SCIStoryActiveOverlay(void) {
    return SCIStoryActiveOverlayView;
}

static id SCIStoryFirstObjectForSelectors(id target, NSArray<NSString *> *selectors) {
    for (NSString *selectorName in selectors) {
        id value = SCIObjectForSelector(target, selectorName);
        if (!value) value = SCIKVCObject(target, selectorName);
        if (value) return value;
    }
    return nil;
}

static NSString *SCIStoryMediaID(id media);

static id SCIStorySectionControllerFromOverlay(UIView *overlayView) {
    if (!overlayView) return nil;
    NSArray<NSString *> *delegateSelectors = @[@"mediaOverlayDelegate", @"retryDelegate", @"tappableOverlayDelegate", @"buttonDelegate"];
    Class sectionControllerClass = NSClassFromString(@"IGStoryFullscreenSectionController");
    for (NSString *selectorName in delegateSelectors) {
        id delegate = SCIObjectForSelector(overlayView, selectorName);
        if (!delegate) delegate = SCIKVCObject(overlayView, selectorName);
        if (!delegate) continue;
        if (!sectionControllerClass || [delegate isKindOfClass:sectionControllerClass]) return delegate;
    }
    return nil;
}

static UIViewController *SCIStoryViewerControllerFromOverlay(UIView *overlayView) {
    id ancestor = SCIObjectForSelector(overlayView, @"_viewControllerForAncestor");
    if ([ancestor isKindOfClass:[UIViewController class]]) return ancestor;
    return [SCIUtils nearestViewControllerForView:overlayView];
}

static id SCIStoryMediaFromAnyObject(id object) {
    if (!object) return nil;
    id candidate = SCIStoryFirstObjectForSelectors(object, @[@"media", @"mediaItem", @"storyItem", @"item", @"model"]);
    return candidate ?: object;
}

static NSArray *SCIStoryItemsFromCandidate(id candidate) {
    for (NSString *selectorName in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
        NSArray *items = SCIArrayFromCollection(SCIStoryFirstObjectForSelectors(candidate, @[selectorName]));
        if (items.count > 0) return items;
    }
    SEL cachedSelector = NSSelectorFromString(@"allItemsForTrayUsingCachedValue:");
    if ([candidate respondsToSelector:cachedSelector]) {
        @try {
            NSArray *items = SCIArrayFromCollection(((id (*)(id, SEL, BOOL))objc_msgSend)(candidate, cachedSelector, YES));
            if (items.count > 0) return items;
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static NSInteger SCIStoryCurrentIndexFromControllerOrSection(id sectionController, UIViewController *controller, id currentMedia, NSArray *allMedia) {
    for (id target in @[sectionController ?: (id)NSNull.null, controller ?: (id)NSNull.null]) {
        if (target == (id)NSNull.null) continue;
        for (NSString *selectorName in @[@"currentIndex", @"currentItemIndex", @"itemIndex", @"currentPage"]) {
            NSNumber *number = [SCIUtils numericValueForObj:target selectorName:selectorName];
            if (number && number.integerValue >= 0) return number.integerValue;
            id value = SCIKVCObject(target, selectorName);
            if ([value respondsToSelector:@selector(integerValue)] && [value integerValue] >= 0) return [value integerValue];
        }
    }
    if (currentMedia && allMedia.count > 0) {
        NSUInteger idx = [allMedia indexOfObjectIdenticalTo:currentMedia];
        if (idx != NSNotFound) return (NSInteger)idx;
        NSString *currentID = SCIStoryMediaID(currentMedia);
        if (currentID.length > 0) {
            for (NSUInteger i = 0; i < allMedia.count; i++) {
                NSString *candidateID = SCIStoryMediaID(allMedia[i]);
                if ([candidateID isEqualToString:currentID]) return (NSInteger)i;
            }
        }
    }
    return 0;
}

static NSString *SCIStoryMediaID(id media) {
    for (NSString *selectorName in @[@"pk", @"id", @"mediaID", @"mediaId", @"mediaIdentifier"]) {
        NSString *identifier = SCIStringFromValue(SCIObjectForSelector(media, selectorName));
        if (identifier.length == 0) identifier = SCIStringFromValue(SCIKVCObject(media, selectorName));
        if (identifier.length > 0) return [identifier componentsSeparatedByString:@"_"].firstObject ?: identifier;
    }
    return nil;
}

static NSURL *SCIStoryURLForMedia(id media) {
    NSString *username = SCIUsernameFromMediaObject(media);
    NSString *identifier = SCIStoryMediaID(media);
    if (username.length == 0 || identifier.length == 0) return nil;
    NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSString *encodedIdentifier = [identifier stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    if (encodedUsername.length == 0 || encodedIdentifier.length == 0) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/stories/%@/%@/", encodedUsername, encodedIdentifier]];
}

SCIStoryContext *SCIStoryContextFromOverlay(UIView *overlayView) {
    if (!overlayView) return nil;
    SCIStoryContext *context = [[SCIStoryContext alloc] init];
    context.overlayView = overlayView;
    context.viewerController = SCIStoryViewerControllerFromOverlay(overlayView);
    context.sectionController = SCIStorySectionControllerFromOverlay(overlayView);

    SEL markSelector = NSSelectorFromString(@"fullscreenSectionController:didMarkItemAsSeen:");
    id sectionDelegate = SCIObjectForSelector(context.sectionController, @"delegate");
    if ([sectionDelegate respondsToSelector:markSelector]) {
        context.markSeenTarget = sectionDelegate;
    } else if ([context.viewerController respondsToSelector:markSelector]) {
        context.markSeenTarget = context.viewerController;
    } else {
        id ancestor = SCIObjectForSelector(overlayView, @"_viewControllerForAncestor");
        if ([ancestor respondsToSelector:markSelector]) context.markSeenTarget = ancestor;
    }

    if (!context.sectionController && context.markSeenTarget) {
        context.sectionController = SCIStoryFirstObjectForSelectors(context.markSeenTarget, @[@"currentSectionController"]) ?: [SCIUtils getIvarForObj:context.markSeenTarget name:"_currentSectionController"];
    }

    id media = SCIStoryFirstObjectForSelectors(context.sectionController, @[@"currentStoryItem", @"currentItem", @"item"]);
    if (!media) media = SCIStoryFirstObjectForSelectors(context.markSeenTarget, @[@"currentStoryItem", @"currentItem", @"item"]);
    if (!media) media = SCIStoryFirstObjectForSelectors(context.viewerController, @[@"currentStoryItem", @"currentItem", @"item"]);
    context.media = SCIStoryMediaFromAnyObject(media);

    id currentViewModel = SCIStoryFirstObjectForSelectors(context.viewerController, @[@"currentViewModel"]);
    NSMutableArray *resolved = [NSMutableArray array];
    for (id candidate in @[context.sectionController ?: (id)NSNull.null, currentViewModel ?: (id)NSNull.null, context.viewerController ?: (id)NSNull.null]) {
        if (candidate == (id)NSNull.null) continue;
        NSArray *items = SCIStoryItemsFromCandidate(candidate);
        if (items.count == 0) continue;
        for (id item in items) {
            id itemMedia = SCIStoryMediaFromAnyObject(item);
            if (itemMedia) [resolved addObject:itemMedia];
        }
        if (resolved.count > 0) break;
    }
    context.allMedia = resolved.count > 0 ? resolved.copy : (context.media ? @[context.media] : @[]);
    context.currentIndex = SCIStoryCurrentIndexFromControllerOrSection(context.sectionController, context.viewerController, context.media, context.allMedia);
    context.username = SCIUsernameFromMediaObject(context.media);
    context.storyURL = SCIStoryURLForMedia(context.media);
    return context.media ? context : nil;
}

SCIStoryContext *SCIStoryContextFromView(UIView *view) {
    for (UIView *walker = view; walker; walker = walker.superview) {
        if ([NSStringFromClass(walker.class) containsString:@"IGStoryFullscreenOverlayView"]) {
            return SCIStoryContextFromOverlay(walker);
        }
    }
    return SCIStoryContextFromOverlay(SCIStoryActiveOverlay());
}

SCIStoryContext *SCIStoryContextFromMedia(id media) {
    if (!media) return nil;
    SCIStoryContext *context = [[SCIStoryContext alloc] init];
    context.media = media;
    context.username = SCIUsernameFromMediaObject(media);
    context.storyURL = SCIStoryURLForMedia(media);
    return context;
}

BOOL SCIStoryMarkContextAsSeen(SCIStoryContext *context) {
    if (!context.markSeenTarget || !context.sectionController || !context.media) return NO;
    SEL markSelector = NSSelectorFromString(@"fullscreenSectionController:didMarkItemAsSeen:");
    SCIForcedStorySeenMediaPK = [SCIStoryMediaIdentifier(context.media) copy];
    SCIForceMarkStoryAsSeen = YES;
    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)(context.markSeenTarget, markSelector, context.sectionController, context.media);
    } @finally {
        SCIForceMarkStoryAsSeen = NO;
        SCIForcedStorySeenMediaPK = nil;
    }
    return YES;
}

void SCIStoryAdvanceContextIfNeeded(SCIStoryContext *context, NSString *advancePrefKey) {
    if (!context || advancePrefKey.length == 0 || ![SCIUtils getBoolPref:advancePrefKey]) return;
    id sectionController = context.sectionController;
    if (!sectionController) return;
    SCIForceStoryAutoAdvance = YES;
    SEL advanceSelector = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
    if ([sectionController respondsToSelector:advanceSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(sectionController, advanceSelector, 1);
    } else {
        SEL endSelector = NSSelectorFromString(@"storyPlayerMediaViewDidPlayToEnd:");
        if ([sectionController respondsToSelector:endSelector]) {
            id mediaView = [SCIUtils getIvarForObj:sectionController name:"_mediaView"] ?: [SCIUtils getIvarForObj:context.overlayView name:"_mediaView"];
            ((void (*)(id, SEL, id))objc_msgSend)(sectionController, endSelector, mediaView);
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        SCIForceStoryAutoAdvance = NO;
    });
}

NSString *SCIStoryUsernameForContext(SCIStoryContext *context) {
    return context.username ?: SCIUsernameFromMediaObject(context.media);
}

NSURL *SCIStoryURLForContext(SCIStoryContext *context) {
    return context.storyURL ?: SCIStoryURLForMedia(context.media);
}

NSString *SCIStoryMediaIdentifierForContext(SCIStoryContext *context) {
    return SCIStoryMediaID(context.media);
}

static NSString *SCIStoryManualSeenListKey(BOOL manualSeenEnabled) {
    (void)manualSeenEnabled;
    return @"story_seen_manual_users";
}

static NSString *SCIStoryNormalizeUsername(NSString *username);

static NSArray<NSString *> *SCIStoryManualSeenUserListForRawValue(id rawStored) {
    NSArray *stored = [rawStored isKindOfClass:[NSArray class]] ? rawStored : nil;
    if (!stored && [rawStored isKindOfClass:[NSString class]]) {
        stored = [(NSString *)rawStored componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",\n"]];
    }
    NSMutableOrderedSet<NSString *> *users = [NSMutableOrderedSet orderedSet];
    for (id value in stored) {
        NSString *username = [value isKindOfClass:[NSString class]] ? SCIStoryNormalizeUsername(value) : nil;
        if (username.length > 0) [users addObject:username];
    }
    return users.array;
}

static NSString *SCIStoryNormalizeUsername(NSString *username) {
    NSString *trimmed = [[username ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([trimmed hasPrefix:@"@"]) trimmed = [trimmed substringFromIndex:1];
    return trimmed;
}

NSArray<NSString *> *SCIStoryManualSeenUserList(BOOL manualSeenEnabled) {
    NSString *key = SCIStoryManualSeenListKey(manualSeenEnabled);
    id rawStored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (!rawStored) {
        NSArray *excluded = SCIStoryManualSeenUserListForRawValue([[NSUserDefaults standardUserDefaults] objectForKey:@"story_seen_excluded_users"]);
        NSArray *included = SCIStoryManualSeenUserListForRawValue([[NSUserDefaults standardUserDefaults] objectForKey:@"story_seen_included_users"]);
        NSMutableOrderedSet *merged = [NSMutableOrderedSet orderedSetWithArray:excluded ?: @[]];
        for (NSString *user in included ?: @[]) [merged addObject:user];
        if (merged.count > 0) {
            SCIStorySetManualSeenUserList(merged.array, manualSeenEnabled);
            return merged.array;
        }
    }
    return SCIStoryManualSeenUserListForRawValue(rawStored);
}

void SCIStorySetManualSeenUserList(NSArray<NSString *> *users, BOOL manualSeenEnabled) {
    NSMutableOrderedSet<NSString *> *normalized = [NSMutableOrderedSet orderedSet];
    for (NSString *user in users) {
        NSString *username = SCIStoryNormalizeUsername(user);
        if (username.length > 0) [normalized addObject:username];
    }
    [[NSUserDefaults standardUserDefaults] setObject:[normalized.array componentsJoinedByString:@", "] forKey:SCIStoryManualSeenListKey(manualSeenEnabled)];
}

BOOL SCIStoryManualSeenListContainsUsername(NSString *username, BOOL manualSeenEnabled) {
    NSString *normalized = SCIStoryNormalizeUsername(username);
    return normalized.length > 0 && [SCIStoryManualSeenUserList(manualSeenEnabled) containsObject:normalized];
}

BOOL SCIStoryManualSeenAppliesToContext(SCIStoryContext *context) {
    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"no_seen_receipt"];
    NSString *username = SCIStoryUsernameForContext(context);
    BOOL listed = SCIStoryManualSeenListContainsUsername(username, manualSeenEnabled);
    return manualSeenEnabled ? !listed : listed;
}

void SCIStoryToggleUsernameForCurrentManualSeenMode(NSString *username) {
    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"no_seen_receipt"];
    NSString *normalized = SCIStoryNormalizeUsername(username);
    if (normalized.length == 0) return;
    NSMutableArray<NSString *> *users = [SCIStoryManualSeenUserList(manualSeenEnabled) mutableCopy];
    if ([users containsObject:normalized]) {
        [users removeObject:normalized];
    } else {
        [users addObject:normalized];
        [users sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    }
    SCIStorySetManualSeenUserList(users, manualSeenEnabled);
}

NSString *SCIStoryManualSeenListTitle(BOOL manualSeenEnabled) {
    return manualSeenEnabled ? @"Excluded Users" : @"Included Users";
}

@interface SCIStoryManualSeenUsersViewController : SCISettingsViewController
@property (nonatomic, strong) NSMutableArray<NSString *> *users;
@property (nonatomic, assign) BOOL manualSeenEnabled;
@end

@implementation SCIStoryManualSeenUsersViewController

- (instancetype)init {
    BOOL manualSeen = [SCIUtils getBoolPref:@"no_seen_receipt"];
    if ((self = [super initWithTitle:SCIStoryManualSeenListTitle(manualSeen) sections:@[] reduceMargin:NO])) {
        _manualSeenEnabled = manualSeen;
        _users = [SCIStoryManualSeenUserList(_manualSeenEnabled) mutableCopy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addUser)];
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ addItem ]);
}

- (void)rebuildSections {
    NSMutableArray<SCISetting *> *rows = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSUInteger idx = 0; idx < self.users.count; idx++) {
        NSString *username = self.users[idx];
        SCISetting *row = [SCISetting buttonCellWithTitle:[NSString stringWithFormat:@"@%@", username]
                                                 subtitle:nil
                                                     icon:SCISettingsIcon(@"user_circle")
                                                   action:^{
            [weakSelf showUserActionsForIndex:idx];
        }];
        [rows addObject:row];
    }
    
    NSString *footer = self.manualSeenEnabled
        ? @"When Manually Mark Seen is enabled, users in this list use Instagram's default seen behavior and do not need the eye button."
        : @"When Manually Mark Seen is disabled, only users in this list require the eye button or story like/reply to mark seen.";
        
    NSArray *sections = @[
        SCITopicSection(@"", rows, footer)
    ];
    [self replaceSections:sections];
}

- (void)showUserActionsForIndex:(NSUInteger)index {
    if (index >= self.users.count) return;
    NSString *username = self.users[index];
    __weak typeof(self) weakSelf = self;
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:[NSString stringWithFormat:@"@%@", username]
                                                message:nil
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Open Profile" style:SCIIGAlertActionStyleDefault handler:^{
            NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            if (encodedUsername.length) {
                NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", encodedUsername]];
                if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
                    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                }
            }
        }],
        [SCIIGAlertAction actionWithTitle:@"Delete" style:SCIIGAlertActionStyleDestructive handler:^{
            [weakSelf.users removeObjectAtIndex:index];
            SCIStorySetManualSeenUserList(weakSelf.users, weakSelf.manualSeenEnabled);
            [weakSelf rebuildSections];
        }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil]
    ]];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    [self.users removeObjectAtIndex:indexPath.row];
    SCIStorySetManualSeenUserList(self.users, self.manualSeenEnabled);
    [self rebuildSections];
}

- (void)addUser {
    __weak typeof(self) weakSelf = self;
    [SCIIGAlertPresenter presentTextInputAlertFromViewController:self
                                                           title:@"Add User"
                                                         message:nil
                                                     placeholder:@"username"
                                                     initialText:nil
                                                 autocapitalized:NO
                                                    confirmTitle:@"Add"
                                                     cancelTitle:@"Cancel"
                                                     confirmStyle:SCIIGAlertActionStyleDefault
                                                     confirmBlock:^(NSString *text) {
        NSString *username = SCIStoryNormalizeUsername(text);
        if (username.length == 0) return;
        if (![weakSelf.users containsObject:username]) {
            [weakSelf.users addObject:username];
            [weakSelf.users sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
            SCIStorySetManualSeenUserList(weakSelf.users, weakSelf.manualSeenEnabled);
            [weakSelf rebuildSections];
        }
    } cancelBlock:nil];
}

@end

UIViewController *SCIStoryManualSeenListViewController(void) {
    return [[SCIStoryManualSeenUsersViewController alloc] init];
}

static BOOL SCIStoryCurrentUserRuleState(SCIStoryContext *context, NSString **outUsername, NSString **outListTitle, BOOL *outListed, BOOL *outManualSeenEnabled) {
    NSString *username = SCIStoryUsernameForContext(context);
    if (username.length == 0) return NO;

    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"no_seen_receipt"];
    BOOL listed = SCIStoryManualSeenListContainsUsername(username, manualSeenEnabled);
    NSString *listTitle = SCIStoryManualSeenListTitle(manualSeenEnabled);

    if (outUsername) *outUsername = username;
    if (outListTitle) *outListTitle = listTitle;
    if (outListed) *outListed = listed;
    if (outManualSeenEnabled) *outManualSeenEnabled = manualSeenEnabled;
    return YES;
}

NSString *SCIStoryCurrentUserRuleActionTitle(SCIStoryContext *context) {
    NSString *listTitle = nil;
    BOOL listed = NO;
    if (!SCIStoryCurrentUserRuleState(context, NULL, &listTitle, &listed, NULL)) return nil;

    return listed
        ? [NSString stringWithFormat:@"Remove from %@", listTitle]
        : [NSString stringWithFormat:@"Add to %@", listTitle];
}

NSString *SCIStoryCurrentUserRuleConfirmationTitle(SCIStoryContext *context) {
    NSString *listTitle = nil;
    BOOL listed = NO;
    if (!SCIStoryCurrentUserRuleState(context, NULL, &listTitle, &listed, NULL)) return nil;

    return listed
        ? [NSString stringWithFormat:@"Confirm Removal from %@", listTitle]
        : [NSString stringWithFormat:@"Confirm Addition to %@", listTitle];
}

NSString *SCIStoryCurrentUserRuleConfirmationMessage(SCIStoryContext *context) {
    NSString *username = nil;
    NSString *listTitle = nil;
    BOOL listed = NO;
    if (!SCIStoryCurrentUserRuleState(context, &username, &listTitle, &listed, NULL)) return nil;

    return listed
        ? [NSString stringWithFormat:@"Do you want to remove @%@ from %@?", username, listTitle]
        : [NSString stringWithFormat:@"Do you want to add @%@ to %@?", username, listTitle];
}

BOOL SCIStoryToggleCurrentUserRule(SCIStoryContext *context, NSString **notificationTitle, NSString **notificationSubtitle) {
    NSString *username = nil;
    NSString *listTitle = nil;
    BOOL listed = NO;
    if (!SCIStoryCurrentUserRuleState(context, &username, &listTitle, &listed, NULL)) return NO;

    SCIStoryToggleUsernameForCurrentManualSeenMode(username);
    if (notificationTitle) {
        NSString *verb = listed ? @"Removed" : @"Added";
        *notificationTitle = [NSString stringWithFormat:@"%@ @%@", verb, username];
    }
    if (notificationSubtitle) *notificationSubtitle = listTitle;
    return YES;
}

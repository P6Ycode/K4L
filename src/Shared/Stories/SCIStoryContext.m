#import "SCIStoryContext.h"

#import <objc/message.h>

#import "../../Tweak.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Utils.h"
#import "../ActionButton/ActionButtonLookupUtils.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../UI/SCINotificationCenter.h"
#import "../../Settings/SCISettingsViewController.h"
#import "../../Settings/SCISetting.h"
#import "../../Settings/SCITopicSettingsSupport.h"
#import "../../Shared/UI/SCIMediaChrome.h"

static __weak UIView *SCIStoryActiveOverlayView;
static NSString * const kSCIStoryManualSeenUserNamesKey = @"stories_manual_seen_user_names";

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
static NSString *SCIStoryFullNameFromMediaObject(id media);

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
    context.fullName = SCIStoryFullNameFromMediaObject(context.media);
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
    context.fullName = SCIStoryFullNameFromMediaObject(media);
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

NSString *SCIStoryFullNameForContext(SCIStoryContext *context) {
    return context.fullName ?: SCIStoryFullNameFromMediaObject(context.media);
}

NSURL *SCIStoryURLForContext(SCIStoryContext *context) {
    return context.storyURL ?: SCIStoryURLForMedia(context.media);
}

NSString *SCIStoryMediaIdentifierForContext(SCIStoryContext *context) {
    return SCIStoryMediaID(context.media);
}

static NSString *SCIStoryManualSeenListKey(BOOL manualSeenEnabled) {
    (void)manualSeenEnabled;
    return @"stories_manual_seen_users";
}

static NSString *SCIStoryNormalizeUsername(NSString *username);

static NSString *SCIStoryCleanDisplayName(NSString *name, NSString *username) {
    NSString *cleanName = [SCIStringFromValue(name) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *cleanUsername = SCIStoryNormalizeUsername(username);
    if (cleanName.length == 0) return nil;
    if ([SCIStoryNormalizeUsername(cleanName) isEqualToString:cleanUsername]) return nil;
    if ([[cleanName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"@"]] caseInsensitiveCompare:cleanUsername] == NSOrderedSame) return nil;
    return cleanName;
}

static NSDictionary<NSString *, NSString *> *SCIStoryManualSeenUserNameCache(void) {
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSCIStoryManualSeenUserNamesKey];
    return [stored isKindOfClass:[NSDictionary class]] ? stored : @{};
}

static NSString *SCIStoryCachedManualSeenUserName(NSString *username) {
    NSString *normalized = SCIStoryNormalizeUsername(username);
    if (normalized.length == 0) return nil;
    return SCIStoryCleanDisplayName(SCIStoryManualSeenUserNameCache()[normalized], normalized);
}

static void SCIStoryRememberManualSeenUserName(NSString *username, NSString *fullName) {
    NSString *normalized = SCIStoryNormalizeUsername(username);
    NSString *cleanName = SCIStoryCleanDisplayName(fullName, normalized);
    if (normalized.length == 0 || cleanName.length == 0) return;

    NSMutableDictionary *names = [SCIStoryManualSeenUserNameCache() mutableCopy];
    names[normalized] = cleanName;
    [[NSUserDefaults standardUserDefaults] setObject:names.copy forKey:kSCIStoryManualSeenUserNamesKey];
}

static void SCIStoryResolveAndRememberManualSeenUserName(NSString *username, void (^completion)(void)) {
    NSString *normalized = SCIStoryNormalizeUsername(username);
    if (normalized.length == 0) {
        if (completion) completion();
        return;
    }
    if (SCIStoryCachedManualSeenUserName(normalized).length > 0) {
        if (completion) completion();
        return;
    }

    NSString *encodedUsername = [normalized stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    if (encodedUsername.length == 0) {
        if (completion) completion();
        return;
    }

    [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", encodedUsername]
                                      body:nil
                                completion:^(NSDictionary *response, NSError *error) {
        NSDictionary *user = response[@"data"][@"user"];
        if (![user isKindOfClass:[NSDictionary class]]) user = response[@"user"];
        if ([user isKindOfClass:[NSDictionary class]] && !error) {
            NSString *resolvedUsername = SCIStringFromValue(user[@"username"]) ?: normalized;
            NSString *fullName = SCIStringFromValue(user[@"full_name"] ?: user[@"fullName"]);
            SCIStoryRememberManualSeenUserName(resolvedUsername, fullName);
        } else {
            SCILog(@"Stories", @"[SCInsta StorySeen] User display-name lookup failed username=%@ error=%@", normalized, error);
        }
        if (completion) completion();
    }];
}

static NSString *SCIStoryFullNameFromUserObject(id user) {
    if (!user) return nil;
    for (NSString *selectorName in @[@"fullName", @"full_name", @"displayName", @"name"]) {
        NSString *name = SCIStringFromValue(SCIStoryFirstObjectForSelectors(user, @[selectorName]));
        if (name.length > 0) return name;
    }
    return nil;
}

static NSString *SCIStoryFullNameFromMediaObject(id media) {
    if (!media) return nil;

    NSString *name = SCIStoryFullNameFromUserObject(media);
    if (name.length > 0) return name;

    for (NSString *userSelector in @[@"user", @"owner", @"author", @"sender", @"fromUser", @"userObject"]) {
        id user = SCIStoryFirstObjectForSelectors(media, @[userSelector]);
        name = SCIStoryFullNameFromUserObject(user);
        if (name.length > 0) return name;
    }

    for (NSString *nestedSelector in @[@"media", @"item", @"storyItem", @"reelShare", @"currentStoryItem", @"currentItem"]) {
        id nested = SCIStoryFirstObjectForSelectors(media, @[nestedSelector]);
        if (!nested || nested == media) continue;
        name = SCIStoryFullNameFromMediaObject(nested);
        if (name.length > 0) return name;
    }

    return nil;
}

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
        NSArray *excluded = SCIStoryManualSeenUserListForRawValue([[NSUserDefaults standardUserDefaults] objectForKey:@"stories_seen_excluded_users"]);
        NSArray *included = SCIStoryManualSeenUserListForRawValue([[NSUserDefaults standardUserDefaults] objectForKey:@"stories_seen_included_users"]);
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
    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"stories_manual_seen"];
    NSString *username = SCIStoryUsernameForContext(context);
    BOOL listed = SCIStoryManualSeenListContainsUsername(username, manualSeenEnabled);
    return manualSeenEnabled ? !listed : listed;
}

void SCIStoryToggleUsernameForCurrentManualSeenMode(NSString *username) {
    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"stories_manual_seen"];
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

static NSString *SCIStoryManualSeenListModeTitle(BOOL manualSeenEnabled) {
    return manualSeenEnabled ? @"Excluded" : @"Included";
}

static NSString *SCIStoryManualSeenListHelpText(BOOL manualSeenEnabled) {
    return manualSeenEnabled
        ? @"When Manually Mark Seen is enabled, users in this list use Instagram's default seen behavior and do not need the eye button."
        : @"When Manually Mark Seen is disabled, only users in this list require the eye button or story like/reply to mark seen.";
}

@interface SCIStoryManualSeenUsersViewController : SCISettingsViewController
@property (nonatomic, strong) NSMutableArray<NSString *> *users;
@property (nonatomic, assign) BOOL manualSeenEnabled;
@end

@implementation SCIStoryManualSeenUsersViewController

- (instancetype)init {
    BOOL manualSeen = [SCIUtils getBoolPref:@"stories_manual_seen"];
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
    UIBarButtonItem *addItem = SCIMediaChromeTopBarButtonItemWithTint(@"plus", self, @selector(addUser), [SCIUtils SCIColor_InstagramPrimaryText], @"Add user");
    UIBarButtonItem *infoItem = SCIMediaChromeTopBarButtonItemWithTint(@"info", self, @selector(showHowItWorks), [SCIUtils SCIColor_InstagramPrimaryText], @"How it works");
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ infoItem, addItem ]);
}

- (void)rebuildSections {
    NSMutableArray<SCISetting *> *rows = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSUInteger idx = 0; idx < self.users.count; idx++) {
        NSString *username = self.users[idx];
        NSString *fullName = SCIStoryCachedManualSeenUserName(username);
        NSString *handle = [@"@" stringByAppendingString:username];
        SCISetting *row = [SCISetting buttonCellWithTitle:(fullName.length > 0 ? fullName : handle)
                                                 subtitle:(fullName.length > 0 ? handle : nil)
                                                     icon:SCISettingsIcon(@"user")
                                                   action:^{
            [weakSelf showUserActionsForIndex:idx];
        }];
        [rows addObject:row];
    }
    
    NSArray *sections = @[
        SCITopicSection(@"", rows, nil)
    ];
    [self replaceSections:sections];
    self.title = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.users.count, SCIStoryManualSeenListModeTitle(self.manualSeenEnabled)];
}

- (void)showHowItWorks {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"How It Works"
                                                message:SCIStoryManualSeenListHelpText(self.manualSeenEnabled)
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"OK" style:SCIIGAlertActionStyleCancel handler:nil]
    ]];
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
        [SCIIGAlertAction actionWithTitle:@"Remove" style:SCIIGAlertActionStyleDestructive handler:^{
            [weakSelf.users removeObjectAtIndex:index];
            SCIStorySetManualSeenUserList(weakSelf.users, weakSelf.manualSeenEnabled);
            SCINotify(kSCINotificationStorySeenUserRule,
                      [NSString stringWithFormat:@"Removed @%@", username],
                      SCIStoryManualSeenListTitle(weakSelf.manualSeenEnabled),
                      @"circle_check_filled",
                      SCINotificationToneSuccess);
            [weakSelf rebuildSections];
        }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil]
    ]];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:nil
                                                                             handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || indexPath.row >= strongSelf.users.count) {
            completionHandler(NO);
            return;
        }
        NSString *username = strongSelf.users[indexPath.row];
        [strongSelf.users removeObjectAtIndex:indexPath.row];
        SCIStorySetManualSeenUserList(strongSelf.users, strongSelf.manualSeenEnabled);
        SCINotify(kSCINotificationStorySeenUserRule,
                  [NSString stringWithFormat:@"Removed @%@", username],
                  SCIStoryManualSeenListTitle(strongSelf.manualSeenEnabled),
                  @"circle_check_filled",
                  SCINotificationToneSuccess);
        [strongSelf rebuildSections];
        completionHandler(YES);
    }];
    deleteAction.image = SCISettingsIcon(@"trash");
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.row >= self.users.count) return;
    NSString *username = self.users[indexPath.row];
    [self.users removeObjectAtIndex:indexPath.row];
    SCIStorySetManualSeenUserList(self.users, self.manualSeenEnabled);
    SCINotify(kSCINotificationStorySeenUserRule,
              [NSString stringWithFormat:@"Removed @%@", username],
              SCIStoryManualSeenListTitle(self.manualSeenEnabled),
              @"circle_check_filled",
              SCINotificationToneSuccess);
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
            SCINotify(kSCINotificationStorySeenUserRule,
                      [NSString stringWithFormat:@"Added @%@", username],
                      SCIStoryManualSeenListTitle(weakSelf.manualSeenEnabled),
                      @"circle_check_filled",
                      SCINotificationToneSuccess);
            [weakSelf rebuildSections];
            SCIStoryResolveAndRememberManualSeenUserName(username, ^{
                [weakSelf rebuildSections];
            });
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

    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"stories_manual_seen"];
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
    if (!listed) {
        NSString *fullName = SCIStoryFullNameForContext(context);
        SCIStoryRememberManualSeenUserName(username, fullName);
        if (SCIStoryCleanDisplayName(fullName, username).length == 0) {
            SCIStoryResolveAndRememberManualSeenUserName(username, nil);
        }
    }
    if (notificationTitle) {
        NSString *verb = listed ? @"Removed" : @"Added";
        *notificationTitle = [NSString stringWithFormat:@"%@ @%@", verb, username];
    }
    if (notificationSubtitle) *notificationSubtitle = listTitle;
    return YES;
}

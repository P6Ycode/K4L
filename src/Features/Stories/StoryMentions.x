// Story Mentions — Gallery-style bottom sheet listing mentioned users with Follow/Following buttons.
// Triggered by the @ button in story overlays (SeenButtons.x).

#import "../../Utils.h"
#import "../../AssetUtils.h"
#import "../../InstagramHeaders.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Shared/UI/SCIMediaChrome.h"
#import "../../Shared/UI/SCINotificationCenter.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern void SCIPauseStoryPlaybackFromOverlaySubview(UIView *view);
extern void SCIResumeStoryPlaybackFromOverlaySubview(UIView *view);

static NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *SCIStoryMentionsSessionCache;
static NSMutableDictionary<NSString *, NSDictionary *> *SCIStoryMentionsFriendshipStatusCache;
static NSCache<NSString *, UIImage *> *SCIStoryMentionsAvatarCache;

static void SCIStoryMentionsEnsureSessionCaches(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCIStoryMentionsSessionCache = [NSMutableDictionary dictionary];
        SCIStoryMentionsFriendshipStatusCache = [NSMutableDictionary dictionary];
        SCIStoryMentionsAvatarCache = [[NSCache alloc] init];
        SCIStoryMentionsAvatarCache.countLimit = 128;
    });
}

static NSString *SCIStoryMentionsCacheKeyForMedia(id media) {
    if (!media) return nil;
    for (NSString *selectorName in @[@"pk", @"id", @"mediaID", @"mediaId", @"code", @"shortCode", @"shortcode"]) {
        id value = nil;
        @try {
            SEL selector = NSSelectorFromString(selectorName);
            if ([media respondsToSelector:selector]) value = ((id (*)(id, SEL))objc_msgSend)(media, selector);
        } @catch (__unused id e) {}
        NSString *string = value ? [NSString stringWithFormat:@"%@", value] : nil;
        if (string.length > 0) return [NSString stringWithFormat:@"%@:%@", selectorName, string];
    }
    return [NSString stringWithFormat:@"ptr:%p", media];
}

// ============ User PK extraction ============

// IGUser stores fields in a Pando-backed dictionary (_fieldCache).
// Standard KVC may return NSNull, so we read the dict directly.
static id SCIMentionFieldCacheValue(id obj, NSString *key) {
    if (!obj || !key) return nil;
    static Ivar fcIvar = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"IGAPIStorableObject");
        if (c) fcIvar = class_getInstanceVariable(c, "_fieldCache");
    });
    if (!fcIvar) return nil;
    NSDictionary *fc = object_getIvar(obj, fcIvar);
    if (!fc || ![fc isKindOfClass:[NSDictionary class]]) return nil;
    id val = fc[key];
    if (!val || [val isKindOfClass:[NSNull class]]) return nil;
    return val;
}

static NSString *SCIMentionUserPK(id userObj) {
    if (!userObj) return nil;
    id pk = SCIMentionFieldCacheValue(userObj, @"strong_id__");
    if (!pk) pk = SCIMentionFieldCacheValue(userObj, @"pk");
    if (!pk) {
        @try {
            Ivar pkIvar = class_getInstanceVariable([userObj class], "_pk");
            if (pkIvar) pk = object_getIvar(userObj, pkIvar);
        } @catch (__unused id e) {}
    }
    return pk ? [NSString stringWithFormat:@"%@", pk] : nil;
}

static void SCIMentionStyleFollowButton(UIButton *btn, BOOL following) {
    [btn setTitle:following ? @"Following" : @"Follow" forState:UIControlStateNormal];
    if (following) {
        btn.backgroundColor = [SCIUtils SCIColor_InstagramTertiaryBackground];
        [btn setTitleColor:[SCIUtils SCIColor_InstagramPrimaryText] forState:UIControlStateNormal];
        btn.layer.borderWidth = 1.0;
        btn.layer.borderColor = [[SCIUtils SCIColor_InstagramSeparator] colorWithAlphaComponent:0.8].CGColor;
    } else {
        btn.backgroundColor = [SCIUtils SCIColor_Primary];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.layer.borderWidth = 0.0;
    }
    btn.layer.cornerRadius = 8.0;
    btn.clipsToBounds = YES;
}

// ============ Enhanced mention extraction ============

// Enriched version that also extracts userObj, pk, and profile_pic_url
// (the SeenButtons.x version only extracts username and fullName)
static NSArray<NSDictionary *> *SCIStoryMentionsEnriched(UIView *overlayView) {
    if (!overlayView) return @[];

    // Use the same resolution path as SeenButtons.x
    id media = nil;
    @try {
        // Walk up to find IGStoryViewerViewController or IGStoryItemMediaView
        UIView *v = overlayView;
        for (NSInteger i = 0; i < 25 && v; i++, v = v.superview) {
            // Try the media view first
            SEL mediaSel = NSSelectorFromString(@"media");
            if ([v respondsToSelector:mediaSel]) {
                id candidate = ((id(*)(id,SEL))objc_msgSend)(v, mediaSel);
                if (candidate && [candidate respondsToSelector:NSSelectorFromString(@"reelMentions")]) {
                    media = candidate;
                    break;
                }
            }
        }

        // Fallback: try the view controller hierarchy
        if (!media) {
            UIResponder *r = overlayView;
            while (r) {
                if ([r isKindOfClass:[UIViewController class]]) {
                    UIViewController *vc = (UIViewController *)r;
                    // Try currentStoryItem
                    SEL csi = NSSelectorFromString(@"currentStoryItem");
                    if ([vc respondsToSelector:csi]) {
                        id item = ((id(*)(id,SEL))objc_msgSend)(vc, csi);
                        if ([item respondsToSelector:NSSelectorFromString(@"reelMentions")]) {
                            media = item;
                            break;
                        }
                    }
                    // Try currentItem
                    SEL ci = NSSelectorFromString(@"currentItem");
                    if ([vc respondsToSelector:ci]) {
                        id item = ((id(*)(id,SEL))objc_msgSend)(vc, ci);
                        if ([item respondsToSelector:NSSelectorFromString(@"reelMentions")]) {
                            media = item;
                            break;
                        }
                    }
                }
                r = r.nextResponder;
            }
        }
    } @catch (__unused id e) {}

    if (!media) return @[];

    SCIStoryMentionsEnsureSessionCaches();
    NSString *cacheKey = SCIStoryMentionsCacheKeyForMedia(media);
    NSArray<NSDictionary *> *cached = cacheKey.length > 0 ? SCIStoryMentionsSessionCache[cacheKey] : nil;
    if (cached) return cached;

    SEL mentionsSel = NSSelectorFromString(@"reelMentions");
    if (![media respondsToSelector:mentionsSel]) return @[];
    id mentionsCollection = ((id(*)(id,SEL))objc_msgSend)(media, mentionsSel);

    NSArray *mentions = nil;
    if ([mentionsCollection isKindOfClass:[NSArray class]]) {
        mentions = (NSArray *)mentionsCollection;
    } else if ([mentionsCollection isKindOfClass:[NSSet class]]) {
        mentions = [(NSSet *)mentionsCollection allObjects];
    } else if ([mentionsCollection isKindOfClass:[NSOrderedSet class]]) {
        mentions = [(NSOrderedSet *)mentionsCollection array];
    }
    if (mentions.count == 0) return @[];

    NSMutableArray<NSDictionary *> *userInfos = [NSMutableArray array];
    for (id mention in mentions) {
        id user = nil;
        @try { user = [mention valueForKey:@"user"]; } @catch (__unused id e) {}
        if (!user) continue;

        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"userObj"] = user;

        NSString *username = SCIMentionFieldCacheValue(user, @"username");
        if (username.length) info[@"username"] = username;

        NSString *fullName = SCIMentionFieldCacheValue(user, @"full_name");
        if (fullName.length) info[@"fullName"] = fullName;

        NSString *picStr = SCIMentionFieldCacheValue(user, @"profile_pic_url");
        if (picStr.length) {
            NSURL *picURL = [NSURL URLWithString:picStr];
            if (picURL) info[@"picURL"] = picURL;
        }

        if (info.count > 1) [userInfos addObject:info]; // must have userObj + at least one other field
    }
    NSArray<NSDictionary *> *result = [userInfos copy];
    if (cacheKey.length > 0) SCIStoryMentionsSessionCache[cacheKey] = result;
    return result;
}

/// ============ Bottom sheet VC ============

#define kSCIMentionAvatarSize 52.0
#define kSCIMentionRowHeight  80.0
#define kSCIMentionRowInset   16.0
#define kSCIMentionRowCornerRadius 16.0

@interface SCIMentionCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UIButton *followBtn;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation SCIMentionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        self.cardView = [[UIView alloc] init];
        self.cardView.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
        self.cardView.layer.cornerRadius = kSCIMentionRowCornerRadius;
        self.cardView.layer.borderWidth = 1.0;
        self.cardView.layer.borderColor = [[SCIUtils SCIColor_InstagramSeparator] colorWithAlphaComponent:0.3].CGColor;
        self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.cardView];
        
        self.avatarView = [[UIImageView alloc] init];
        self.avatarView.clipsToBounds = YES;
        self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
        self.avatarView.layer.cornerRadius = kSCIMentionAvatarSize / 2.0;
        self.avatarView.backgroundColor = [SCIUtils SCIColor_InstagramSeparator];
        self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.cardView addSubview:self.avatarView];
        
        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        self.nameLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        self.subLabel = [[UILabel alloc] init];
        self.subLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        self.subLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
        self.subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        self.followBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        self.followBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        self.followBtn.layer.cornerRadius = 8.0; // Concentric corner (16.0 card corner - 8.0 margin = 8.0)
        self.followBtn.clipsToBounds = YES;
        self.followBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [self.cardView addSubview:self.followBtn];
        
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.spinner.hidesWhenStopped = YES;
        self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [self.followBtn addSubview:self.spinner];
        
        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.subLabel]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 2;
        textStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.cardView addSubview:textStack];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [self.cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kSCIMentionRowInset],
            [self.cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kSCIMentionRowInset],
            [self.cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            
            [self.avatarView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:12],
            [self.avatarView.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
            [self.avatarView.widthAnchor constraintEqualToConstant:kSCIMentionAvatarSize],
            [self.avatarView.heightAnchor constraintEqualToConstant:kSCIMentionAvatarSize],
            
            [textStack.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:12],
            [textStack.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
            [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.followBtn.leadingAnchor constant:-10],
            
            [self.followBtn.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-12],
            [self.followBtn.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
            [self.followBtn.widthAnchor constraintGreaterThanOrEqualToConstant:88],
            [self.followBtn.heightAnchor constraintEqualToConstant:32],
            
            [self.spinner.centerXAnchor constraintEqualToAnchor:self.followBtn.centerXAnchor],
            [self.spinner.centerYAnchor constraintEqualToAnchor:self.followBtn.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
        if (highlighted) {
            self.cardView.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
        } else {
            self.cardView.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
        }
    } completion:nil];
}

@end
@interface SCIStoryMentionsVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *userInfos;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSString *currentUsername;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *friendshipStatuses;
@property (nonatomic, weak) UIView *storyOverlayView; // for resuming playback on dismiss
@end

@implementation SCIStoryMentionsVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.title = @"Mentions";

    // Resolve current user to hide the Follow button for yourself
    @try {
        id window = [[UIApplication sharedApplication] keyWindow];
        if ([window respondsToSelector:@selector(userSession)])
            self.currentUsername = ((IGUserSession *)[window valueForKey:@"userSession"]).user.username;
    } @catch (__unused id e) {}

    // Table view (stretching under navigation bar)
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = kSCIMentionRowHeight;
    self.tableView.estimatedRowHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.estimatedSectionFooterHeight = 0;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 12, 0);
    self.tableView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 12, 0);
    self.tableView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Bulk-fetch friendship statuses in one round trip
    SCIStoryMentionsEnsureSessionCaches();
    self.friendshipStatuses = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *missingPKs = [NSMutableArray array];
    for (NSDictionary *info in self.userInfos) {
        NSString *pk = SCIMentionUserPK(info[@"userObj"]);
        if (!pk.length) continue;
        NSDictionary *cachedStatus = SCIStoryMentionsFriendshipStatusCache[pk];
        if (cachedStatus) {
            self.friendshipStatuses[pk] = cachedStatus;
        } else {
            [missingPKs addObject:pk];
        }
    }
    if (missingPKs.count) {
        __weak typeof(self) weakSelf = self;
        [SCIInstagramAPI fetchFriendshipStatusesForPKs:missingPKs completion:^(NSDictionary *statuses, NSError *error) {
            (void)error;
            if (!statuses.count) return;
            [SCIStoryMentionsFriendshipStatusCache addEntriesFromDictionary:statuses];
            [weakSelf.friendshipStatuses addEntriesFromDictionary:statuses];
            [weakSelf.tableView reloadData];
        }];
    }

}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        UINavigationBar *navBar = self.navigationController.navigationBar;
        
        // Ensure standard translucent blur is active and not overridden by solid backgrounds
        navBar.translucent = YES;
        navBar.backgroundColor = [UIColor clearColor];
        navBar.barTintColor = nil;
        navBar.shadowImage = nil;
        
        // Match iOS Settings sheet top bar appearance exactly
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithDefaultBackground]; // system default — matches Settings sheet style
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [SCIUtils SCIColor_InstagramPrimaryText],
            NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]
        };
        
        // Use identical appearance for all states — same as Settings sheets (no transparent edge)
        navBar.standardAppearance = appearance;
        navBar.scrollEdgeAppearance = appearance;
        navBar.compactAppearance = appearance;
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Resume story playback when mentions sheet is dismissed
    if (self.storyOverlayView) {
        SCIResumeStoryPlaybackFromOverlaySubview(self.storyOverlayView);
        
        UIResponder *r = self.storyOverlayView;
        while (r) {
            if ([r isKindOfClass:[UIViewController class]]) {
                SEL sel = NSSelectorFromString(@"tryResumePlayback");
                if ([r respondsToSelector:sel]) {
                    ((void(*)(id,SEL))objc_msgSend)(r, sel);
                    break;
                }
            }
            r = r.nextResponder;
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.userInfos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *rid = @"SCIMention";
    SCIMentionCell *cell = [tableView dequeueReusableCellWithIdentifier:rid];
    if (!cell) {
        cell = [[SCIMentionCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
    }

    NSDictionary *info = self.userInfos[indexPath.row];
    NSString *username = info[@"username"] ?: @"Unknown";
    NSString *fullName = info[@"fullName"];
    NSURL *picURL = info[@"picURL"];

    cell.nameLabel.text = username;
    cell.subLabel.text = fullName ?: @"";
    cell.subLabel.hidden = !fullName.length;

    // Default avatar
    cell.avatarView.image = [SCIAssetUtils instagramIconNamed:@"user_circle" pointSize:24.0];
    cell.avatarView.tintColor = [SCIUtils SCIColor_InstagramTertiaryText];

    // Avatar fetch with session cache
    if (picURL) {
        NSString *cacheKey = picURL.absoluteString;
        objc_setAssociatedObject(cell.avatarView, @selector(cellForRowAtIndexPath:), cacheKey, OBJC_ASSOCIATION_COPY_NONATOMIC);

        UIImage *cachedAvatar = cacheKey.length > 0 ? [SCIStoryMentionsAvatarCache objectForKey:cacheKey] : nil;
        if (cachedAvatar) {
            cell.avatarView.image = cachedAvatar;
            cell.avatarView.tintColor = nil;
        } else {
            NSURL *url = [picURL copy];
            NSInteger row = indexPath.row;
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [NSData dataWithContentsOfURL:url];
                if (!data) return;
                UIImage *img = [UIImage imageWithData:data];
                if (!img) return;
                if (cacheKey.length > 0) {
                    [SCIStoryMentionsAvatarCache setObject:img forKey:cacheKey];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    UITableViewCell *c = [tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
                    if (!c || ![c isKindOfClass:[SCIMentionCell class]]) return;
                    SCIMentionCell *mc = (SCIMentionCell *)c;
                    NSString *boundKey = objc_getAssociatedObject(mc.avatarView, @selector(cellForRowAtIndexPath:));
                    if (mc.avatarView && (!boundKey || [boundKey isEqualToString:cacheKey])) {
                        mc.avatarView.image = img;
                        mc.avatarView.tintColor = nil;
                    }
                });
            });
        }
    }

    // Follow button state
    [cell.followBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [cell.spinner stopAnimating];
    cell.spinner.color = [SCIUtils SCIColor_InstagramSecondaryText];

    BOOL isMe = self.currentUsername && [username isEqualToString:self.currentUsername];
    if (isMe) {
        cell.followBtn.hidden = YES;
    } else {
        cell.followBtn.hidden = NO;
        id userObj = info[@"userObj"];

        BOOL following = NO;
        NSString *pk = SCIMentionUserPK(userObj);
        NSDictionary *status = pk ? self.friendshipStatuses[pk] : nil;
        if ([status isKindOfClass:[NSDictionary class]]) {
            following = [status[@"following"] boolValue];
        }
        SCIMentionStyleFollowButton(cell.followBtn, following);

        objc_setAssociatedObject(cell.followBtn, "userObj", userObj, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell.followBtn addTarget:self action:@selector(sci_followTapped:) forControlEvents:UIControlEventTouchUpInside];
    }

    return cell;
}

#pragma mark - Follow/Unfollow

- (void)sci_followTapped:(UIButton *)sender {
    id userObj = objc_getAssociatedObject(sender, "userObj");
    if (!userObj) return;
    NSString *pk = SCIMentionUserPK(userObj);
    if (!pk.length) return;

    BOOL currentlyFollowing = [[sender titleForState:UIControlStateNormal] isEqualToString:@"Following"];

    void (^doIt)(void) = ^{
        UIActivityIndicatorView *spinner = nil;
        for (UIView *subview in sender.subviews) {
            if ([subview isKindOfClass:[UIActivityIndicatorView class]]) {
                spinner = (UIActivityIndicatorView *)subview;
                break;
            }
        }
        NSString *savedTitle = [sender titleForState:UIControlStateNormal];
        [sender setTitle:@"" forState:UIControlStateNormal];
        sender.userInteractionEnabled = NO;
        [spinner startAnimating];

        __weak typeof(self) weakSelf = self;
        SCIAPICompletion done = ^(NSDictionary *response, NSError *error) {
            [spinner stopAnimating];
            sender.userInteractionEnabled = YES;
            BOOL ok = (response && [response[@"status"] isEqualToString:@"ok"]);
            if (ok) {
                SCIMentionStyleFollowButton(sender, !currentlyFollowing);
                NSMutableDictionary *s = [weakSelf.friendshipStatuses[pk] mutableCopy] ?: [NSMutableDictionary dictionary];
                s[@"following"] = @(!currentlyFollowing);
                NSDictionary *updatedStatus = [s copy];
                weakSelf.friendshipStatuses[pk] = updatedStatus;
                SCIStoryMentionsEnsureSessionCaches();
                SCIStoryMentionsFriendshipStatusCache[pk] = updatedStatus;
            } else {
                [sender setTitle:savedTitle forState:UIControlStateNormal];
            }
        };

        if (currentlyFollowing) [SCIInstagramAPI unfollowUserPK:pk completion:done];
        else                    [SCIInstagramAPI followUserPK:pk   completion:done];
    };
    if (!currentlyFollowing && [SCIUtils getBoolPref:@"profile_confirm_follow"]) {
        [SCIUtils showConfirmation:doIt
                             title:@"Confirm Follow"
                           message:@"Are you sure you want to follow this account?"];
    } else if (currentlyFollowing && [SCIUtils getBoolPref:@"profile_confirm_unfollow"]) {
        [SCIUtils showConfirmation:doIt
                             title:@"Confirm Unfollow"
                           message:@"Are you sure you want to unfollow this account?"];
    } else {
        doIt();
    }
}

#pragma mark - UITableViewDelegate (row tap → profile)

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.userInfos.count) return;
    NSString *username = self.userInfos[indexPath.row][@"username"];
    if (username.length == 0) return;

    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        [SCIUtils openInstagramProfileForUsername:username];
    }];
}

@end

// ============ Presentation entry point ============

extern void SCIPauseStoryPlaybackFromOverlaySubview(UIView *);
extern void SCIResumeStoryPlaybackFromOverlaySubview(UIView *);

void SCIPresentStoryMentionsSheet(UIView *overlayView) {
    NSArray<NSDictionary *> *enriched = SCIStoryMentionsEnriched(overlayView);

    UIViewController *presenter = [SCIUtils nearestViewControllerForView:overlayView];
    if (!presenter) return;
    
    SCIPauseStoryPlaybackFromOverlaySubview(overlayView);

    SCIStoryMentionsVC *vc = [[SCIStoryMentionsVC alloc] init];
    vc.userInfos = enriched;
    vc.storyOverlayView = overlayView;

    // Use a native UINavigationController wrapper to support standard dynamic page sheet behavior
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;

    UISheetPresentationController *sheet = nav.sheetPresentationController;

    if (@available(iOS 16.0, *)) {
        CGFloat headerHeight = 56.0;
        CGFloat contentHeight = MAX(1, enriched.count) * kSCIMentionRowHeight;
        CGFloat totalHeight = headerHeight + contentHeight + 40.0;
        UISheetPresentationControllerDetent *customDetent =
            [UISheetPresentationControllerDetent customDetentWithIdentifier:@"custom_fit"
                                                                   resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> ctx) {
            return MIN(totalHeight, ctx.maximumDetentValue * 0.85);
        }];
        sheet.detents = @[customDetent];
    } else {
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
    }

    sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
    sheet.prefersGrabberVisible = YES;

    SCINotify(kSCINotificationStoryMentionsSheet, @"Opened story mentions", nil, @"mention", SCINotificationToneForIconResource(@"mention"));
    [presenter presentViewController:nav animated:YES completion:nil];
}

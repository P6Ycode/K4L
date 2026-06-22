#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "ActionButtonCore.h"
#import "SCIActionButtonConfiguration.h"
#import "SCIActionDescriptor.h"
#import "../Downloads/SCIDownloadHelpers.h"
#import "../../InstagramHeaders.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../../Settings/SCIPreferences.h"
#import "../MediaDownload/SCIMediaQualityManager.h"
#import "../MediaPreview/SCIFullScreenMediaPlayer.h"
#import "../MediaPreview/SCIMediaItem.h"
#import "../MediaTrim/SCITrimEntry.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGalleryOriginController.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../Audio/SCIAudioDownloadCoordinator.h"
#import "../Audio/SCIAudioItem.h"
#import "../Stories/SCIStoryContext.h"
#import "../Messages/SCIDirectSeenContext.h"
#import "../Messages/SCIDirectUserResolver.h"
#import "../UI/SCINotificationCenter.h"
#import "../UI/SCIChrome.h"
#import "../../Features/Messages/DeletedMessagesLog/SCIDeletedMessagesViewController.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "SCIBulkMediaSelectionViewController.h"

NSString * const kSCIActionNone = @"none";
NSString * const kSCIActionDownloadLibrary = @"download_library";
NSString * const kSCIActionDownloadShare = @"download_share";
NSString * const kSCIActionCopyDownloadLink = @"copy_download_link";
NSString * const kSCIActionCopyMedia = @"copy_media";
NSString * const kSCIActionDownloadGallery = @"download_gallery";
NSString * const kSCIActionTrimSave = @"trim_save";
NSString * const kSCIActionDownloadAudio = @"download_audio";
NSString * const kSCIActionDownloadAudioShare = @"download_audio_share";
NSString * const kSCIActionDownloadAudioGallery = @"download_audio_gallery";
NSString * const kSCIActionPlayAudio = @"play_audio";
NSString * const kSCIActionCopyAudioURL = @"copy_audio_url";
NSString * const kSCIActionDownloadAll = @"download_all";
NSString * const kSCIActionDownloadAllLibrary = @"download_all_library";
NSString * const kSCIActionDownloadAllShare = @"download_all_share";
NSString * const kSCIActionDownloadAllGallery = @"download_all_gallery";
NSString * const kSCIActionDownloadAllClipboard = @"download_all_clipboard";
NSString * const kSCIActionDownloadAllLinks = @"download_all_links";
NSString * const kSCIActionExpand = @"expand";
NSString * const kSCIActionViewThumbnail = @"view_thumbnail";
NSString * const kSCIActionCopyCaption = @"copy_caption";
NSString * const kSCIActionOpenTopicSettings = @"open_topic_settings";
NSString * const kSCIActionDeletedMessagesLog = @"deleted_messages_log";
NSString * const kSCIActionRepost = @"repost";
NSString * const kSCIActionToggleStorySeenUserRule = @"toggle_story_seen_user_rule";
NSString * const kSCIActionToggleProfileStorySeenUserRule = @"toggle_profile_story_seen_user_rule";
NSString * const kSCIActionToggleProfileMessagesSeenUserRule = @"toggle_profile_messages_seen_user_rule";
NSString * const kSCIActionStoryMentionsSheet = @"story_mentions_sheet";
NSString * const kSCIActionProfileCopyInfo = @"profile_copy_info";
NSString * const kSCIActionProfileCopyID = @"profile_copy_id";
NSString * const kSCIActionProfileCopyUsername = @"profile_copy_username";
NSString * const kSCIActionProfileCopyName = @"profile_copy_name";
NSString * const kSCIActionProfileCopyBio = @"profile_copy_bio";
NSString * const kSCIActionProfileCopyLink = @"profile_copy_link";
NSString * const SCIActionButtonConfigurationDidChangeNotification = @"SCIActionButtonConfigurationDidChangeNotification";

static const void *kSCIActionButtonContextAssocKey = &kSCIActionButtonContextAssocKey;
static const void *kSCIActionButtonTapActionAssocKey = &kSCIActionButtonTapActionAssocKey;
static const void *kSCIActionButtonHapticActionAssocKey = &kSCIActionButtonHapticActionAssocKey;
static const void *kSCIActionButtonIconImageViewAssocKey = &kSCIActionButtonIconImageViewAssocKey;
static const void *kSCIActionButtonIconWidthConstraintAssocKey = &kSCIActionButtonIconWidthConstraintAssocKey;
static const void *kSCIActionButtonIconHeightConstraintAssocKey = &kSCIActionButtonIconHeightConstraintAssocKey;
static const void *kSCIActionButtonMenuSignatureAssocKey = &kSCIActionButtonMenuSignatureAssocKey;
static const void *kSCIActionButtonLastMenuActionAssocKey = &kSCIActionButtonLastMenuActionAssocKey;
static const void *kSCIActionButtonConfigurationObserverAssocKey = &kSCIActionButtonConfigurationObserverAssocKey;
static const void *kSCIActionButtonMenuHiddenAlphaAssocKey = &kSCIActionButtonMenuHiddenAlphaAssocKey;
static NSDictionary<NSString *, NSString *> *SCIPendingRepostFeedback = nil;

@interface SCIResolvedMediaEntry : NSObject
@property (nonatomic, strong, nullable) id mediaObject;
@property (nonatomic, strong, nullable) id metadataObject;
@property (nonatomic, strong, nullable) NSURL *photoURL;
@property (nonatomic, strong, nullable) NSURL *videoURL;
@property (nonatomic, copy, nullable) NSString *sourceUsername;
@property (nonatomic, copy, nullable) NSString *sourceMediaPK;
@property (nonatomic, copy, nullable) NSString *sourceMediaURLString;
@property (nonatomic, strong, nullable) NSDate *importPostedDate;
@end

static void SCIPauseDirectPlaybackFromController(UIViewController *controller);
static void SCIResumeDirectPlaybackFromController(UIViewController *controller);
static BOOL SCIActionIdentifierOpensPreview(NSString *identifier);
static id SCIResolveMediaForContext(SCIActionButtonContext *context);
static UIViewController *SCIActionContextPresenter(SCIActionButtonContext *context);
static UIView *SCIActionContextAnchorView(SCIActionButtonContext *context);
static UIColor *SCIActionButtonTintForSource(SCIActionButtonSource source);
void SCIPauseStoryPlaybackFromOverlaySubview(UIView *overlayView);
void SCIResumeStoryPlaybackFromOverlaySubview(UIView *overlayView);
SCIActionButtonContext *SCIActionButtonContextFromButton(UIButton *button);

#ifdef __cplusplus
extern "C" {
#endif
void SCIPresentStoryMentionsSheet(UIView *overlayView);
#ifdef __cplusplus
}
#endif

static BOOL SCIActionMenuButtonIsReels(UIButton *button) {
	SCIActionButtonContext *context = SCIActionButtonContextFromButton(button);
	return context.source == SCIActionButtonSourceReels;
}

static void SCIStabilizeReelsActionButtonIcon(UIButton *button) {
	if (!SCIActionMenuButtonIsReels(button) || ![button isKindOfClass:[SCIChromeButton class]]) return;

	SCIChromeButton *chromeButton = (SCIChromeButton *)button;
	chromeButton.iconTint = SCIActionButtonTintForSource(SCIActionButtonSourceReels);
	chromeButton.iconView.tintColor = chromeButton.iconTint;
	chromeButton.iconView.hidden = NO;
	chromeButton.iconView.alpha = 1.0;
	chromeButton.iconView.layer.opacity = 1.0;
	chromeButton.iconView.layer.hidden = NO;
	[chromeButton.iconView.superview bringSubviewToFront:chromeButton.iconView];
	[chromeButton setNeedsLayout];
	[chromeButton layoutIfNeeded];
}

static void SCISetReelsActionButtonMenuHidden(UIButton *button, BOOL hidden) {
	if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"26.0")) return;
	if (!SCIActionMenuButtonIsReels(button)) return;

	if (hidden) {
		if (!objc_getAssociatedObject(button, kSCIActionButtonMenuHiddenAlphaAssocKey)) {
			objc_setAssociatedObject(button, kSCIActionButtonMenuHiddenAlphaAssocKey, @(button.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		button.alpha = 0.0;
		button.layer.opacity = 0.0;
		return;
	}

	NSNumber *storedAlpha = objc_getAssociatedObject(button, kSCIActionButtonMenuHiddenAlphaAssocKey);
	CGFloat alpha = storedAlpha ? storedAlpha.doubleValue : 1.0;
	button.alpha = alpha;
	button.layer.opacity = alpha;
	objc_setAssociatedObject(button, kSCIActionButtonMenuHiddenAlphaAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UITargetedPreview *SCIReelsActionButtonMenuPreview(UIButton *button) {
	if (!SCIActionMenuButtonIsReels(button) || ![button isKindOfClass:[SCIChromeButton class]]) return nil;

	SCIStabilizeReelsActionButtonIcon(button);

	CGRect bounds = button.bounds;
	if (CGRectIsEmpty(bounds)) {
		CGFloat side = 44.0;
		bounds = CGRectMake(0.0, 0.0, side, side);
	}

	UIView *previewView = [[UIView alloc] initWithFrame:bounds];
	previewView.userInteractionEnabled = NO;
	previewView.backgroundColor = UIColor.clearColor;
	previewView.clipsToBounds = NO;

	UIView *bubbleView = [[UIView alloc] initWithFrame:bounds];
	bubbleView.userInteractionEnabled = NO;
	bubbleView.backgroundColor = [UIColor blackColor];
	bubbleView.layer.cornerRadius = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) / 2.0;
	bubbleView.clipsToBounds = YES;
	[previewView addSubview:bubbleView];

	UIPreviewParameters *parameters = [[UIPreviewParameters alloc] init];
	parameters.backgroundColor = UIColor.clearColor;
	parameters.visiblePath = [UIBezierPath bezierPathWithOvalInRect:bounds];

	if (button.superview) {
		CGPoint center = [button.superview convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) fromView:button];
		UIPreviewTarget *target = [[UIPreviewTarget alloc] initWithContainer:button.superview center:center];
		return [[UITargetedPreview alloc] initWithView:previewView parameters:parameters target:target];
	}
	return [[UITargetedPreview alloc] initWithView:previewView parameters:parameters];
}

static UITargetedPreview *SCIActionMenuButtonMenuPreview(UIButton *button) {
	UITargetedPreview *reelsPreview = SCIReelsActionButtonMenuPreview(button);
	if (reelsPreview) return reelsPreview;
	return [[UITargetedPreview alloc] initWithView:button];
}

@implementation SCIResolvedMediaEntry
@end

@implementation SCIActionMenuButton

- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
      previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration
{
	(void)interaction;
	(void)configuration;
	return SCIActionMenuButtonMenuPreview(self);
}

- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
       previewForDismissingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration
{
	(void)interaction;
	(void)configuration;
	return SCIActionMenuButtonMenuPreview(self);
}

- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
willDisplayMenuForConfiguration:(id)configuration
                      animator:(id<UIContextMenuInteractionAnimating>)animator
{
	[super contextMenuInteraction:interaction willDisplayMenuForConfiguration:configuration animator:animator];
	(void)interaction;
	(void)configuration;
	(void)animator;

	// Menu-open haptic (long-press, or tap when the button opens the menu as its primary
	// action). Lives here rather than on touch-down so it fires only when the menu actually
	// appears — a touch-down tick stacked a second haptic on top of the action's own
	// completion feedback for plain action taps.
	if (![SCIUtils getBoolPref:@"general_disable_haptics"]) {
		UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
		[feedback selectionChanged];
	}

	SCIActionButtonContext *context = SCIActionButtonContextFromButton(self);
	if (!context) return;

	SCIStabilizeReelsActionButtonIcon(self);
	[animator addAnimations:^{
		SCIStabilizeReelsActionButtonIcon(self);
	}];
	SCISetReelsActionButtonMenuHidden(self, YES);

	objc_setAssociatedObject(self, kSCIActionButtonLastMenuActionAssocKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
	if (context.source == SCIActionButtonSourceStories) {
		SCIPauseStoryPlaybackFromOverlaySubview(context.view);
	} else if (context.source == SCIActionButtonSourceDirect) {
		SCIPauseDirectPlaybackFromController(context.controller);
	}
}

- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
   willEndForConfiguration:(id)configuration
                      animator:(id<UIContextMenuInteractionAnimating>)animator
{
	[super contextMenuInteraction:interaction willEndForConfiguration:configuration animator:animator];
	(void)interaction;
	(void)configuration;

	SCIStabilizeReelsActionButtonIcon(self);
	[animator addAnimations:^{
		SCIStabilizeReelsActionButtonIcon(self);
	}];
	SCISetReelsActionButtonMenuHidden(self, NO);

	[animator addCompletion:^{
		SCIActionMenuButton *strongSelf = self;
		if (!strongSelf) return;
		SCIStabilizeReelsActionButtonIcon(strongSelf);

		SCIActionButtonContext *context = SCIActionButtonContextFromButton(strongSelf);
		NSString *lastAction = objc_getAssociatedObject(strongSelf, kSCIActionButtonLastMenuActionAssocKey);
		objc_setAssociatedObject(strongSelf, kSCIActionButtonLastMenuActionAssocKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
		if (!context) return;
		if ([lastAction isEqualToString:kSCIActionOpenTopicSettings]) return;
		if (SCIActionIdentifierOpensPreview(lastAction)) return;

		if (context.source == SCIActionButtonSourceStories) {
			SCIResumeStoryPlaybackFromOverlaySubview(context.view);
		} else if (context.source == SCIActionButtonSourceDirect) {
			SCIResumeDirectPlaybackFromController(context.controller);
		}
	}];
}

@end

@implementation SCIActionButtonContext
- (instancetype)init {
	if ((self = [super init])) {
		_currentIndexOverride = -1;
	}
	return self;
}
@end

static BOOL SCIIsVideoExtension(NSString *ext) {
	if (ext.length == 0) return NO;

	static NSSet<NSString *> *videoExts;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		videoExts = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"avi", @"webm", @"hevc", @"m3u8"]];
	});

	return [videoExts containsObject:ext.lowercaseString];
}

static NSString *SCIExtensionForURL(NSURL *url, BOOL isVideo) {
	NSString *ext = url.pathExtension;
	if (ext.length > 0) return ext;
	return isVideo ? @"mp4" : @"jpg";
}

static UIViewController *SCIViewControllerForAncestorView(UIView *view) {
	if (!view) return nil;

	id candidate = SCIObjectForSelector(view, @"_viewControllerForAncestor");
	if ([candidate isKindOfClass:[UIViewController class]]) {
		return (UIViewController *)candidate;
	}

	return [SCIUtils viewControllerForAncestralView:view];
}

static UIColor *SCIActionButtonTintForSource(SCIActionButtonSource source) {
	switch (source) {
		case SCIActionButtonSourceFeed:
        case SCIActionButtonSourceProfile:
			return [UIColor labelColor];
		case SCIActionButtonSourceReels:
		case SCIActionButtonSourceStories:
		case SCIActionButtonSourceDirect:
		case SCIActionButtonSourceInstants:
		default:
			return [UIColor whiteColor];
	}
}

static NSString *SCIDefaultActionPrefKeyForSource(SCIActionButtonSource source) {
	return SCIPrefActionButtonDefaultActionKey(SCIActionButtonTopicKeyForSource(source));
}

static SCIGallerySource SCIGallerySourceForActionSource(SCIActionButtonSource source) {
	switch (source) {
		case SCIActionButtonSourceFeed:
			return SCIGallerySourceFeed;
		case SCIActionButtonSourceReels:
			return SCIGallerySourceReels;
		case SCIActionButtonSourceStories:
			return SCIGallerySourceStories;
		case SCIActionButtonSourceDirect:
			return SCIGallerySourceDMs;
        case SCIActionButtonSourceProfile:
            return SCIGallerySourceProfile;
        case SCIActionButtonSourceInstants:
            return SCIGallerySourceInstants;
		default:
			return SCIGallerySourceOther;
	}
}

static SCIAudioSource SCIAudioSourceForActionSource(SCIActionButtonSource source) {
	switch (source) {
		case SCIActionButtonSourceFeed:
			return SCIAudioSourceFeed;
		case SCIActionButtonSourceReels:
			return SCIAudioSourceReels;
		case SCIActionButtonSourceStories:
			return SCIAudioSourceStories;
		case SCIActionButtonSourceDirect:
			return SCIAudioSourceDMs;
		case SCIActionButtonSourceProfile:
		case SCIActionButtonSourceInstants:
		default:
			return SCIAudioSourceOther;
	}
}

static NSString *SCIDownloadURLNounForActionSource(SCIActionButtonSource source) {
    switch (source) {
        case SCIActionButtonSourceStories:
            return @"Story";
        case SCIActionButtonSourceReels:
            return @"Reel";
        case SCIActionButtonSourceFeed:
        case SCIActionButtonSourceProfile:
            return @"Post";
        case SCIActionButtonSourceInstants:
            return @"Instant";
        case SCIActionButtonSourceDirect:
        default:
            return @"Media";
    }
}

static NSString *SCICopiedDownloadURLTitleForSource(SCIActionButtonSource source, BOOL plural) {
    NSString *noun = SCIDownloadURLNounForActionSource(source);
    NSString *urlWord = plural ? @"URLs" : @"URL";
    if ([noun isEqualToString:@"Media"]) {
        return [NSString stringWithFormat:@"Download %@ copied", urlWord];
    }
    return [NSString stringWithFormat:@"%@ download %@ copied", noun, urlWord];
}

static NSString *SCIProfileStringValue(id value) {
    if (!value) return nil;
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value length] > 0 ? value : nil;
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *stringValue = [value stringValue];
        return stringValue.length > 0 ? stringValue : nil;
    }
    return nil;
}

static NSString *SCIProfileUserPK(id user) {
    NSString *pk = SCIProfileStringValue(SCIKVCObject(user, @"pk"));
    if (pk.length == 0) pk = SCIProfileStringValue(SCIKVCObject(user, @"id"));
    return pk;
}

static NSString *SCIProfileUsername(id user) {
    return SCIProfileStringValue(SCIKVCObject(user, @"username"));
}

static NSString *SCIProfileFullName(id user) {
    for (NSString *key in @[@"fullName", @"full_name", @"name"]) {
        NSString *name = SCIProfileStringValue(SCIKVCObject(user, key));
        if (name.length > 0) return name;
    }
    return nil;
}

static NSString *SCIProfileBiography(id user) {
    for (NSString *key in @[@"biography", @"bio"]) {
        NSString *bio = SCIProfileStringValue(SCIKVCObject(user, key));
        if (bio.length > 0) return bio;
    }
    return nil;
}

static NSURL *SCIProfileURL(id user) {
    NSString *username = SCIProfileUsername(user);
    if (username.length == 0) return nil;
    NSString *encoded = [username stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    if (encoded.length == 0) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/", encoded]];
}

static NSNumber *SCIProfileNumberValue(id value) {
    if (!value) return nil;
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value respondsToSelector:@selector(integerValue)]) return @([value integerValue]);
    for (NSString *key in @[@"value", @"number", @"count"]) {
        id nested = SCIKVCObject(value, key);
        if (nested && nested != value) {
            NSNumber *number = SCIProfileNumberValue(nested);
            if (number) return number;
        }
    }
    return nil;
}

static NSNumber *SCIProfileNumericSelectorValue(id target, SEL selector) {
    if (!target || !selector || ![target respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) return nil;

    const char *type = signature.methodReturnType;
    while (type && (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' || *type == 'O' || *type == 'R' || *type == 'V')) {
        type++;
    }
    if (!type) return nil;

    switch (type[0]) {
        case '@':
            return SCIProfileNumberValue(((id (*)(id, SEL))objc_msgSend)(target, selector));
        case 'q':
            return @(((long long (*)(id, SEL))objc_msgSend)(target, selector));
        case 'Q':
            return @(((unsigned long long (*)(id, SEL))objc_msgSend)(target, selector));
        case 'i':
            return @(((int (*)(id, SEL))objc_msgSend)(target, selector));
        case 'I':
            return @(((unsigned int (*)(id, SEL))objc_msgSend)(target, selector));
        case 'l':
            return @(((long (*)(id, SEL))objc_msgSend)(target, selector));
        case 'L':
            return @(((unsigned long (*)(id, SEL))objc_msgSend)(target, selector));
        case 's':
            return @(((short (*)(id, SEL))objc_msgSend)(target, selector));
        case 'S':
            return @(((unsigned short (*)(id, SEL))objc_msgSend)(target, selector));
        default:
            return nil;
    }
}

static BOOL SCIProfileNameMatchesCountKind(NSString *name, BOOL followers) {
    NSString *lower = name.lowercaseString;
    if (![lower containsString:@"count"]) return NO;
    if (followers) {
        return ([lower containsString:@"follower"] ||
                [lower containsString:@"followedby"] ||
                [lower containsString:@"followed_by"]) &&
               ![lower containsString:@"following"];
    }
    return [lower containsString:@"following"] ||
           [lower containsString:@"followings"] ||
           [lower containsString:@"edgefollow"];
}

static NSNumber *SCIProfileIvarNumberValue(id object, Ivar ivar) {
    if (!object || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type) return nil;
    while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' || *type == 'O' || *type == 'R' || *type == 'V') {
        type++;
    }
    if (type[0] == '@') {
        @try {
            return SCIProfileNumberValue(object_getIvar(object, ivar));
        } @catch (__unused NSException *exception) {
            return nil;
        }
    }

    ptrdiff_t offset = ivar_getOffset(ivar);
    const uint8_t *bytes = (const uint8_t *)(__bridge const void *)object;
    const void *slot = bytes + offset;
    switch (type[0]) {
        case 'q': return @(*(const long long *)slot);
        case 'Q': return @(*(const unsigned long long *)slot);
        case 'i': return @(*(const int *)slot);
        case 'I': return @(*(const unsigned int *)slot);
        case 'l': return @(*(const long *)slot);
        case 'L': return @(*(const unsigned long *)slot);
        case 's': return @(*(const short *)slot);
        case 'S': return @(*(const unsigned short *)slot);
        default: return nil;
    }
}

static NSString *SCIProfileInfoString(NSNumber *value) {
    if (!value) return nil;
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    return [formatter stringFromNumber:value];
}

static NSString *SCIProfilePrivacyText(id user) {
    NSNumber *privacyStatus = SCIProfileNumberValue(SCIKVCObject(user, @"privacyStatus"));
    if (privacyStatus) {
        if (privacyStatus.integerValue == 2) return @"Private Profile";
        if (privacyStatus.integerValue == 1) return @"Public Profile";
    }

    id privateValue = SCIKVCObject(user, @"isPrivate");
    if (!privateValue) privateValue = SCIKVCObject(user, @"privateAccount");
    if (!privateValue) privateValue = SCIKVCObject(user, @"isPrivateAccount");
    if ([privateValue respondsToSelector:@selector(boolValue)]) {
        return [privateValue boolValue] ? @"Private Profile" : @"Public Profile";
    }

    return nil;
}

static UIAction *SCIProfileDisabledInfoAction(NSString *title, NSString *resourceName) {
    UIAction *action = [UIAction actionWithTitle:title
                                           image:[SCIAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"info") pointSize:22.0]
                                      identifier:nil
                                         handler:^(__unused UIAction *menuAction) {}];
    action.attributes = UIMenuElementAttributesDisabled;
    return action;
}

static NSNumber *SCIProfileFollowerCount(id user);
static NSNumber *SCIProfileFollowingCount(id user);

static NSArray<UIMenuElement *> *SCIProfileInfoMenuElements(id user) {
    if (!user) return @[];

    NSMutableArray<UIMenuElement *> *infoItems = [NSMutableArray array];
    NSString *privacyText = SCIProfilePrivacyText(user);
    if (privacyText.length > 0) {
        [infoItems addObject:SCIProfileDisabledInfoAction(privacyText, [privacyText containsString:@"Private"] ? @"lock" : @"unlock")];
    }

    NSString *followers = SCIProfileInfoString(SCIProfileFollowerCount(user));
    if (followers.length > 0) {
        [infoItems addObject:SCIProfileDisabledInfoAction([NSString stringWithFormat:@"Followers: %@", followers], @"users")];
    }

    NSString *following = SCIProfileInfoString(SCIProfileFollowingCount(user));
    if (following.length > 0) {
        [infoItems addObject:SCIProfileDisabledInfoAction([NSString stringWithFormat:@"Following: %@", following], @"users")];
    }

    return infoItems;
}

static NSArray *SCIProfileCountCandidates(id user) {
    if (!user) return @[];

    NSMutableArray *candidates = [NSMutableArray arrayWithObject:user];
    NSMutableSet<NSValue *> *seen = [NSMutableSet setWithObject:[NSValue valueWithNonretainedObject:user]];
    NSArray<NSString *> *keys = @[
        @"userGQL", @"profileUser", @"user", @"wrappedUser", @"baseUser",
        @"profile", @"profileModel", @"profileContext", @"profileHeader",
        @"header", @"model", @"viewModel", @"userInfo", @"data", @"fieldCache",
        @"additionalData", @"additionalUserData", @"profileData", @"graphqlUser"
    ];

    for (NSUInteger depth = 0; depth < 2; depth++) {
        NSArray *snapshot = [candidates copy];
        for (id candidate in snapshot) {
            for (NSString *key in keys) {
                id nested = SCIKVCObject(candidate, key) ?: SCIObjectForSelector(candidate, key);
                if (!nested ||
                    [nested isKindOfClass:[NSString class]] ||
                    [nested isKindOfClass:[NSNumber class]] ||
                    [nested isKindOfClass:[NSURL class]]) {
                    continue;
                }
                NSValue *seenKey = [NSValue valueWithNonretainedObject:nested];
                if ([seen containsObject:seenKey]) continue;
                [seen addObject:seenKey];
                [candidates addObject:nested];
            }
        }
    }

    return candidates;
}

static NSNumber *SCIProfileCountForUser(id user, NSArray<NSString *> *keys) {
    for (id candidate in SCIProfileCountCandidates(user)) {
        for (NSString *key in keys) {
            NSNumber *value = [SCIUtils numericValueForObj:candidate selectorName:key];
            if (value) return value;
            value = SCIProfileNumberValue(SCIObjectForSelector(candidate, key));
            if (value) return value;
            value = SCIProfileNumberValue(SCIKVCObject(candidate, key));
            if (value) return value;
        }
    }
    return nil;
}

static NSNumber *SCIProfileRuntimeCountForUser(id user, BOOL followers) {
    for (id candidate in SCIProfileCountCandidates(user)) {
        for (Class cls = [candidate class]; cls && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            for (unsigned int index = 0; index < methodCount; index++) {
                SEL selector = method_getName(methods[index]);
                NSString *name = NSStringFromSelector(selector);
                if (!SCIProfileNameMatchesCountKind(name, followers)) continue;
                NSNumber *value = SCIProfileNumericSelectorValue(candidate, selector);
                if (value) {
                    free(methods);
                    return value;
                }
            }
            free(methods);

            unsigned int ivarCount = 0;
            Ivar *ivars = class_copyIvarList(cls, &ivarCount);
            for (unsigned int index = 0; index < ivarCount; index++) {
                NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[index]) ?: ""];
                if (!SCIProfileNameMatchesCountKind(name, followers)) continue;
                NSNumber *value = SCIProfileIvarNumberValue(candidate, ivars[index]);
                if (value) {
                    free(ivars);
                    return value;
                }
            }
            free(ivars);
        }
    }
    return nil;
}

static NSNumber *SCIProfileFollowerCount(id user) {
    NSNumber *value = SCIProfileCountForUser(user, @[
        @"followerCount",
        @"followersCount",
        @"follower_count",
        @"followers_count",
        @"edgeFollowedBy",
        @"edge_followed_by",
        @"followedByCount",
        @"followed_by_count"
    ]);
    return value ?: SCIProfileRuntimeCountForUser(user, YES);
}

static NSNumber *SCIProfileFollowingCount(id user) {
    NSNumber *value = SCIProfileCountForUser(user, @[
        @"followingCount",
        @"followingsCount",
        @"following_count",
        @"followings_count",
        @"edgeFollow",
        @"edge_follow",
        @"followCount"
    ]);
    return value ?: SCIProfileRuntimeCountForUser(user, NO);
}



static NSString *SCIProfileInfoSignature(id user) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *privacy = SCIProfilePrivacyText(user);
    if (privacy.length > 0) [parts addObject:privacy];
    NSString *followers = SCIProfileInfoString(SCIProfileFollowerCount(user));
    if (followers.length > 0) [parts addObject:[NSString stringWithFormat:@"followers:%@", followers]];
    NSString *following = SCIProfileInfoString(SCIProfileFollowingCount(user));
    if (following.length > 0) [parts addObject:[NSString stringWithFormat:@"following:%@", following]];
    return [parts componentsJoinedByString:@"|"];
}

static NSString *SCIProfileDefaultCopyInfoIdentifier(void) {
    NSString *identifier = [SCIUtils getStringPref:@"profile_action_btn_default_copy_info_action"] ?: kSCIActionProfileCopyUsername;
    NSDictionary<NSString *, NSString *> *legacyMap = @{
        @"id": kSCIActionProfileCopyID,
        @"username": kSCIActionProfileCopyUsername,
        @"name": kSCIActionProfileCopyName,
        @"bio": kSCIActionProfileCopyBio,
        @"link": kSCIActionProfileCopyLink
    };
    identifier = legacyMap[identifier] ?: identifier;
    NSSet<NSString *> *supported = [NSSet setWithArray:@[
        kSCIActionProfileCopyID,
        kSCIActionProfileCopyUsername,
        kSCIActionProfileCopyName,
        kSCIActionProfileCopyBio,
        kSCIActionProfileCopyLink
    ]];
    return [supported containsObject:identifier] ? identifier : kSCIActionProfileCopyUsername;
}

static NSString *SCIProfileCopyValueForIdentifier(id user, NSString *identifier) {
    if ([identifier isEqualToString:kSCIActionProfileCopyID]) return SCIProfileUserPK(user);
    if ([identifier isEqualToString:kSCIActionProfileCopyName]) return SCIProfileFullName(user);
    if ([identifier isEqualToString:kSCIActionProfileCopyBio]) return SCIProfileBiography(user);
    if ([identifier isEqualToString:kSCIActionProfileCopyLink]) return SCIProfileURL(user).absoluteString;
    return SCIProfileUsername(user);
}

static NSString *SCIProfileCopySuccessTitleForIdentifier(NSString *identifier) {
    if ([identifier isEqualToString:kSCIActionProfileCopyID]) return @"ID copied";
    if ([identifier isEqualToString:kSCIActionProfileCopyName]) return @"Name copied";
    if ([identifier isEqualToString:kSCIActionProfileCopyBio]) return @"Bio copied";
    if ([identifier isEqualToString:kSCIActionProfileCopyLink]) return @"Profile link copied";
    return @"Username copied";
}

static BOOL SCIIsProfileCopyActionIdentifier(NSString *identifier) {
    return [@[
        kSCIActionProfileCopyInfo,
        kSCIActionProfileCopyID,
        kSCIActionProfileCopyUsername,
        kSCIActionProfileCopyName,
        kSCIActionProfileCopyBio,
        kSCIActionProfileCopyLink
    ] containsObject:identifier];
}

static BOOL SCIExecuteProfileCopyAction(NSString *identifier, SCIActionButtonContext *context) {
    id user = SCIResolveMediaForContext(context);
    if (!user) {
        SCINotify(kSCIActionProfileCopyInfo, @"Profile unavailable", nil, @"error_filled", SCINotificationToneError);
        return YES;
    }
    NSString *copyIdentifier = [identifier isEqualToString:kSCIActionProfileCopyInfo] ? SCIProfileDefaultCopyInfoIdentifier() : identifier;
    NSString *value = SCIProfileCopyValueForIdentifier(user, copyIdentifier);
    if (value.length == 0) {
        SCINotify(kSCIActionProfileCopyInfo, @"Nothing to copy", nil, @"error_filled", SCINotificationToneError);
        return YES;
    }
    UIPasteboard.generalPasteboard.string = value;
    SCINotify(kSCIActionProfileCopyInfo, SCIProfileCopySuccessTitleForIdentifier(copyIdentifier), nil, @"circle_check_filled", SCINotificationToneSuccess);
    return YES;
}

static BOOL SCIActionMediaLooksLikeReel(id media) {
    if (!media) return NO;
    for (NSString *selectorName in @[@"isReelMedia", @"isClipsMedia", @"isClipsItem", @"isReel", @"isInstagramReel"]) {
        NSNumber *value = [SCIUtils numericValueForObj:media selectorName:selectorName];
        if (value.boolValue) return YES;
    }
    for (NSString *key in @[@"productType", @"mediaType", @"mediaSource", @"inventorySource", @"clipsTabEntryPoint"]) {
        NSString *value = SCIStringFromValue(SCIObjectForSelector(media, key));
        if (value.length == 0) value = SCIStringFromValue(SCIKVCObject(media, key));
        NSString *lower = value.lowercaseString;
        if ([lower containsString:@"clips"] || [lower containsString:@"reel"]) return YES;
    }
    return NO;
}

static SCIGallerySaveMetadata *SCIGalleryMetadata(SCIActionButtonSource source, NSString *username, id media) {
	SCIGallerySaveMetadata *meta = [[SCIGallerySaveMetadata alloc] init];
    SCIGallerySource gallerySource = SCIGallerySourceForActionSource(source);
    if (source == SCIActionButtonSourceFeed && SCIActionMediaLooksLikeReel(media)) {
        gallerySource = SCIGallerySourceReels;
    }
	meta.source = (int16_t)gallerySource;
	if (username.length > 0) {
		meta.sourceUsername = username;
	}
    if (source == SCIActionButtonSourceProfile) {
        [SCIGalleryOriginController populateProfileMetadata:meta username:username user:media];
    } else {
        [SCIGalleryOriginController populateMetadata:meta fromMedia:media];
    }
	return meta;
}

static NSString *SCIExplicitSourceUsernameFromObject(id object) {
    NSString *username = SCIStringFromValue(SCIObjectForSelector(object, @"sourceUsername") ?: SCIKVCObject(object, @"sourceUsername"));
    return username.length > 0 ? username : nil;
}

static NSDate *SCIDateFromActionValue(id value) {
    if ([value isKindOfClass:NSDate.class]) return (NSDate *)value;
    if ([value respondsToSelector:@selector(doubleValue)]) {
        double timestamp = [value doubleValue];
        if (timestamp <= 0) return nil;
        if (timestamp > 100000000000.0) timestamp /= 1000.0;
        return [NSDate dateWithTimeIntervalSince1970:timestamp];
    }
    return nil;
}

static NSString *SCIUsernameForEntry(SCIResolvedMediaEntry *entry, NSString *fallbackUsername) {
    NSString *username = entry.sourceUsername;
    if (username.length == 0) username = SCIExplicitSourceUsernameFromObject(entry.metadataObject ?: entry.mediaObject);
    if (username.length == 0) username = SCIExplicitSourceUsernameFromObject(entry.mediaObject);
    if (username.length == 0) username = SCIUsernameFromMediaObject(entry.metadataObject ?: entry.mediaObject);
    if (username.length == 0) username = fallbackUsername;
    return username;
}

static void SCIApplyEntryMetadata(SCIGallerySaveMetadata *meta, SCIResolvedMediaEntry *entry) {
    if (!meta || !entry) return;
    if (entry.sourceUsername.length > 0) meta.sourceUsername = entry.sourceUsername;
    if (entry.sourceMediaPK.length > 0) meta.sourceMediaPK = entry.sourceMediaPK;
    if (entry.sourceMediaURLString.length > 0) meta.sourceMediaURLString = entry.sourceMediaURLString;
    if (entry.importPostedDate) meta.importPostedDate = entry.importPostedDate;
}

extern "C" NSString *SCIActionButtonTitleForIdentifier(NSString *identifier) {
	return SCIActionDescriptorDisplayTitle(identifier, nil);
}

static NSArray<NSString *> *SCIBulkActionChildIdentifiers(void) {
    return @[
        kSCIActionDownloadAllLibrary,
        kSCIActionDownloadAllShare,
        kSCIActionDownloadAllGallery,
        kSCIActionDownloadAllClipboard,
        kSCIActionDownloadAllLinks
    ];
}

static BOOL SCIIsBulkChildActionIdentifier(NSString *identifier) {
    return [SCIBulkActionChildIdentifiers() containsObject:identifier];
}

static BOOL SCIIsBulkDownloadActionIdentifier(NSString *identifier) {
    return [@[
        kSCIActionDownloadAllLibrary,
        kSCIActionDownloadAllShare,
        kSCIActionDownloadAllGallery
    ] containsObject:identifier];
}

static BOOL SCIIsBulkCopyActionIdentifier(NSString *identifier) {
    return [@[
        kSCIActionDownloadAllClipboard,
        kSCIActionDownloadAllLinks
    ] containsObject:identifier];
}

static NSString *SCIBaseActionIdentifierForBulkChild(NSString *identifier) {
    if ([identifier isEqualToString:kSCIActionDownloadAllLibrary]) return kSCIActionDownloadLibrary;
    if ([identifier isEqualToString:kSCIActionDownloadAllShare]) return kSCIActionDownloadShare;
    if ([identifier isEqualToString:kSCIActionDownloadAllGallery]) return kSCIActionDownloadGallery;
    if ([identifier isEqualToString:kSCIActionDownloadAllClipboard]) return kSCIActionCopyMedia;
    if ([identifier isEqualToString:kSCIActionDownloadAllLinks]) return kSCIActionCopyDownloadLink;
    return identifier;
}

static SCIStoryContext *SCIStoryContextForActionButtonContext(SCIActionButtonContext *context) {
    if (context.source != SCIActionButtonSourceStories) return nil;
    SCIStoryContext *storyContext = SCIStoryContextFromView(context.view);
    if (storyContext) return storyContext;
    return SCIStoryContextFromOverlay(SCIStoryActiveOverlay());
}

static NSString *SCIActionButtonDisplayTitleForContext(NSString *identifier,
                                                       SCIActionButtonContext *context,
                                                       SCIResolvedMediaEntry *currentEntry) {
    if ([identifier isEqualToString:kSCIActionToggleStorySeenUserRule]) {
        NSString *title = SCIStoryCurrentUserRuleActionTitle(SCIStoryContextForActionButtonContext(context));
        return title ?: SCIActionDescriptorDisplayTitle(identifier, context.settingsTitle);
    }
    if ([identifier isEqualToString:kSCIActionToggleProfileStorySeenUserRule]) {
        id user = SCIResolveMediaForContext(context);
        NSString *pk = user ? [SCIUtils pkFromIGUser:user] : nil;
        if (pk.length > 0) {
            BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"stories_manual_seen"];
            BOOL listed = SCIStoryManualSeenListContainsUser(pk, manualSeenEnabled);
            BOOL applies = manualSeenEnabled ? !listed : listed;
            return applies ? @"Start Marking Stories as Seen" : @"Stop Marking Stories as Seen";
        }
        return @"Toggle Story Seen";
    }
    if ([identifier isEqualToString:kSCIActionToggleProfileMessagesSeenUserRule]) {
        id user = SCIResolveMediaForContext(context);
        NSString *pk = user ? [SCIUtils pkFromIGUser:user] : nil;
        if (pk.length > 0) {
            BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"msgs_manual_seen"];
            NSDictionary *existingEntry = SCIDirectManualSeenThreadEntryForUserPK(pk, manualSeenEnabled);
            BOOL listed = (existingEntry != nil);
            BOOL applies = manualSeenEnabled ? !listed : listed;
            return applies ? @"Start Marking Messages as Seen" : @"Stop Marking Messages as Seen";
        }
        return @"Toggle Messages Seen";
    }
    if ([identifier isEqualToString:kSCIActionCopyMedia]) {
        BOOL isVideo = (currentEntry.videoURL != nil);
        if (isVideo) {
            return (context.source == SCIActionButtonSourceReels) ? @"Copy Reel" : @"Copy Video";
        }
        return @"Copy Photo";
    }
	return SCIActionDescriptorDisplayTitle(identifier, context.settingsTitle);
}

static NSString *SCIResolvedSettingsTitleForContext(SCIActionButtonContext *context) {
    if (context.settingsTitle.length > 0) return context.settingsTitle;
    return SCIActionButtonTopicTitleForSource(context.source);
}

static BOOL SCIStoryMediaHasMentions(id media) {
    NSArray *mentions = SCIArrayFromCollection(SCIObjectForSelector(media, @"reelMentions") ?: SCIKVCObject(media, @"reelMentions"));
    return mentions.count > 0;
}

static UIImage *SCIIconForActionIdentifier(NSString *identifier, SCIActionButtonSource source, CGFloat size, SCIActionButtonContext *context) {
	if (SCIIsBulkChildActionIdentifier(identifier)) {
		return SCIIconForActionIdentifier(SCIBaseActionIdentifierForBulkChild(identifier), source, size, context);
	}

	NSString *iconName = SCIActionDescriptorIconName(identifier);

	if (source == SCIActionButtonSourceReels) {
		NSString *reelsIconName = [NSString stringWithFormat:@"%@_reels", iconName];
		UIImage *reelsImage = [SCIAssetUtils resolvedImageNamed:reelsIconName
		                                     fallbackSystemName:nil
		                                              pointSize:size
		                                                 weight:UIImageSymbolWeightUnspecified
		                                                 source:SCIResolvedImageSourceInstagramIcon
		                                          renderingMode:UIImageRenderingModeAlwaysTemplate];
		if (reelsImage) {
			return reelsImage;
		}
	}

    if ([identifier isEqualToString:kSCIActionToggleStorySeenUserRule]) {
        SCIStoryContext *storyCtx = SCIStoryContextForActionButtonContext(context);
        BOOL applies = storyCtx ? SCIStoryManualSeenAppliesToContext(storyCtx) : YES;
        return [SCIAssetUtils instagramIconNamed:applies ? @"eye_off" : @"eye" pointSize:size];
    }
    if ([identifier isEqualToString:kSCIActionToggleProfileStorySeenUserRule]) {
        id user = context ? SCIResolveMediaForContext(context) : nil;
        NSString *pk = user ? [SCIUtils pkFromIGUser:user] : nil;
        BOOL applies = YES;
        if (pk.length > 0) {
            BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"stories_manual_seen"];
            BOOL listed = SCIStoryManualSeenListContainsUser(pk, manualSeenEnabled);
            applies = manualSeenEnabled ? !listed : listed;
        }
        return [SCIAssetUtils instagramIconNamed:applies ? @"eye_off" : @"eye" pointSize:size];
    }
    if ([identifier isEqualToString:kSCIActionToggleProfileMessagesSeenUserRule]) {
        id user = context ? SCIResolveMediaForContext(context) : nil;
        NSString *pk = user ? [SCIUtils pkFromIGUser:user] : nil;
        BOOL applies = YES;
        if (pk.length > 0) {
            BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"msgs_manual_seen"];
            NSDictionary *existingEntry = SCIDirectManualSeenThreadEntryForUserPK(pk, manualSeenEnabled);
            applies = manualSeenEnabled ? !(existingEntry != nil) : (existingEntry != nil);
        }
        return [SCIAssetUtils instagramIconNamed:applies ? @"eye_off" : @"eye" pointSize:size];
    }

	return [SCIAssetUtils instagramIconNamed:iconName pointSize:size];
}

static SCIFullScreenPlaybackSource SCIPlaybackSourceForActionSource(SCIActionButtonSource source) {
    switch (source) {
        case SCIActionButtonSourceFeed:
            return SCIFullScreenPlaybackSourceFeed;
        case SCIActionButtonSourceProfile:
            return SCIFullScreenPlaybackSourceProfile;
        case SCIActionButtonSourceReels:
            return SCIFullScreenPlaybackSourceReels;
        case SCIActionButtonSourceStories:
            return SCIFullScreenPlaybackSourceStories;
        case SCIActionButtonSourceDirect:
            return SCIFullScreenPlaybackSourceDirect;
        case SCIActionButtonSourceInstants:
            return SCIFullScreenPlaybackSourceInstants;
        default:
            return SCIFullScreenPlaybackSourceUnknown;
    }
}

static void SCIPausePlaybackForPreviewContext(SCIActionButtonContext *context) {
    if (!context) return;

    switch (context.source) {
        case SCIActionButtonSourceStories:
            SCIPauseStoryPlaybackFromOverlaySubview(context.view);
            return;
        case SCIActionButtonSourceDirect:
            SCIPauseDirectPlaybackFromController(context.controller);
            return;
        case SCIActionButtonSourceFeed:
        case SCIActionButtonSourceReels:
        case SCIActionButtonSourceProfile:
        default:
            return;
    }
}

static void SCIResumePlaybackForPreviewContext(SCIActionButtonContext *context) {
    if (!context) return;

    switch (context.source) {
        case SCIActionButtonSourceStories:
            SCIResumeStoryPlaybackFromOverlaySubview(context.view);
            return;
        case SCIActionButtonSourceDirect:
            SCIResumeDirectPlaybackFromController(context.controller);
            return;
        case SCIActionButtonSourceFeed:
        case SCIActionButtonSourceReels:
        case SCIActionButtonSourceProfile:
        default:
            return;
    }
}

static BOOL SCIActionIdentifierOpensPreview(NSString *identifier) {
    return [identifier isEqualToString:kSCIActionExpand] ||
           [identifier isEqualToString:kSCIActionViewThumbnail] ||
           [identifier isEqualToString:kSCIActionStoryMentionsSheet];
}

static SCIMediaPreviewPlaybackBlock SCIPausePlaybackBlockForContext(SCIActionButtonContext *context) {
    if (!context) return nil;
    __weak UIView *sourceView = context.view;
    __weak UIViewController *sourceController = context.controller;
    SCIActionButtonSource source = context.source;
    return [^{
        SCIActionButtonContext *previewContext = [[SCIActionButtonContext alloc] init];
        previewContext.source = source;
        previewContext.view = sourceView;
        previewContext.controller = sourceController;
        SCIPausePlaybackForPreviewContext(previewContext);
    } copy];
}

static SCIMediaPreviewPlaybackBlock SCIResumePlaybackBlockForContext(SCIActionButtonContext *context) {
    if (!context) return nil;
    __weak UIView *sourceView = context.view;
    __weak UIViewController *sourceController = context.controller;
    SCIActionButtonSource source = context.source;
    return [^{
        SCIActionButtonContext *previewContext = [[SCIActionButtonContext alloc] init];
        previewContext.source = source;
        previewContext.view = sourceView;
        previewContext.controller = sourceController;
        SCIResumePlaybackForPreviewContext(previewContext);
    } copy];
}

UIImage *SCIActionButtonMenuIconForIdentifier(NSString *identifier, CGFloat size) {
	return SCIIconForActionIdentifier(identifier, SCIActionButtonSourceFeed, size, nil);
}

static UIImage *SCIActionButtonMenuIconForContext(NSString *identifier, SCIActionButtonContext *context, CGFloat size) {
	SCIActionButtonSource menuSource = (context.source == SCIActionButtonSourceReels)
		? SCIActionButtonSourceFeed
		: context.source;
	return SCIIconForActionIdentifier(identifier, menuSource, size, context);
}

static NSInteger SCIClampedIndex(NSInteger index, NSInteger count) {
	if (count <= 0) return 0;
	if (index < 0) return 0;
	if (index >= count) return count - 1;
	return index;
}

static NSURL *SCIURLFromURLCollectionValue(id collection) {
	if (!collection) return nil;

	NSArray *items = SCIArrayFromCollection(collection);
	if (!items) return SCIURLFromValue(collection);

	for (id item in items) {
		NSURL *url = nil;
		if ([item isKindOfClass:[NSDictionary class]]) {
			NSDictionary *dict = (NSDictionary *)item;
			url = SCIURLFromValue(dict[@"url"] ?: dict[@"urlString"]);
		} else {
			url = SCIURLFromValue(SCIObjectForSelector(item, @"url"));
			if (!url) url = SCIURLFromValue(SCIObjectForSelector(item, @"urlString"));
			if (!url) url = SCIURLFromValue(item);
		}
		if (url) return url;
	}

	return nil;
}

static NSURL *SCIURLFromAssetLikeObject(id object, BOOL videoHint) {
	if (!object) return nil;

	NSArray<NSString *> *primarySelectors = videoHint
		? @[@"videoURL", @"videoUrl", @"downloadURL", @"url", @"urlString"]
		: @[@"imageURL", @"imageUrl", @"displayURL", @"thumbnailURL", @"url", @"urlString"];

	for (NSString *selectorName in primarySelectors) {
		NSURL *url = SCIURLFromValue(SCIObjectForSelector(object, selectorName));
		if (!url) url = SCIURLFromValue(SCIKVCObject(object, selectorName));
		if (url) return url;
	}

	if (videoHint) {
		for (NSString *selectorName in @[@"allVideoURLs", @"sortedVideoURLsBySize", @"videoURLs", @"videoUrls"]) {
			NSURL *url = SCIURLFromURLCollectionValue(SCIObjectForSelector(object, selectorName));
			if (!url) url = SCIURLFromURLCollectionValue(SCIKVCObject(object, selectorName));
			if (url) return url;
		}
	} else {
		SEL imageURLForWidth = NSSelectorFromString(@"imageURLForWidth:");
		if ([object respondsToSelector:imageURLForWidth]) {
			NSURL *url = ((id (*)(id, SEL, CGFloat))objc_msgSend)(object, imageURLForWidth, 100000.0);
			if ([url isKindOfClass:[NSURL class]]) return url;
		}
	}

	return nil;
}

static id SCIFieldCacheValue(id obj, NSString *key) {
    if (!obj || key.length == 0) return nil;

    static Ivar fieldCacheIvar = NULL;
    static Class storableClass = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        storableClass = NSClassFromString(@"IGAPIStorableObject");
        if (storableClass) {
            fieldCacheIvar = class_getInstanceVariable(storableClass, "_fieldCache");
        }
    });

    if (!fieldCacheIvar || !storableClass || ![obj isKindOfClass:storableClass]) return nil;

    id fieldCache = nil;
    @try {
        fieldCache = object_getIvar(obj, fieldCacheIvar);
    } @catch (__unused NSException *exception) {
        return nil;
    }

    if (![fieldCache isKindOfClass:[NSDictionary class]]) return nil;
    id value = ((NSDictionary *)fieldCache)[key];
    if (!value || [value isKindOfClass:[NSNull class]]) return nil;
    return value;
}

static id SCIUnderlyingMediaObjectForAction(id object) {
    if (!object) return nil;

    if ([SCIUtils getPhotoUrlForMedia:object] || [SCIUtils getVideoUrlForMedia:object]) {
        return object;
    }

    for (NSString *selectorName in @[@"photo", @"rawPhoto", @"video", @"rawVideo"]) {
        id nestedAsset = SCIObjectForSelector(object, selectorName);
        if (!nestedAsset) nestedAsset = SCIKVCObject(object, selectorName);
        if (nestedAsset && nestedAsset != object) {
            return object;
        }
    }

    for (NSString *selectorName in @[@"media", @"item", @"storyItem", @"visualMessage", @"explorePostInFeed", @"rootItem", @"clipsItem", @"clipsMedia", @"post"]) {
        id nested = SCIObjectForSelector(object, selectorName);
        if (!nested) nested = SCIKVCObject(object, selectorName);
        if (nested && nested != object) {
            id resolved = SCIUnderlyingMediaObjectForAction(nested);
            if (resolved) return resolved;
        }
    }

    return object;
}

static NSURL *SCIBestCandidatePhotoURLFromCandidates(id candidates) {
    if (![candidates isKindOfClass:[NSArray class]] || [(NSArray *)candidates count] == 0) {
        return nil;
    }

    NSDictionary *bestCandidate = nil;
    NSInteger bestWidth = 0;
    for (id candidate in (NSArray *)candidates) {
        if (![candidate isKindOfClass:[NSDictionary class]]) continue;
        NSInteger width = [((NSDictionary *)candidate)[@"width"] integerValue];
        if (width > bestWidth) {
            bestWidth = width;
            bestCandidate = candidate;
        }
    }

    NSString *urlString = bestCandidate[@"url"];
    return urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
}

static NSURL *SCIHDPhotoURLForMediaObject(id mediaObject) {
    id imageVersions = SCIFieldCacheValue(mediaObject, @"image_versions2");
    id candidates = [imageVersions isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)imageVersions)[@"candidates"] : nil;
    if (!candidates) {
        candidates = SCIFieldCacheValue(mediaObject, @"candidates");
    }

    NSURL *fieldCacheURL = SCIBestCandidatePhotoURLFromCandidates(candidates);
    if (fieldCacheURL) return fieldCacheURL;

    id photoObject = SCIObjectForSelector(mediaObject, @"photo");
    if (!photoObject) return nil;

    Ivar originalVersionsIvar = class_getInstanceVariable([photoObject class], "_originalImageVersions");
    if (!originalVersionsIvar) return nil;

    id originalVersions = nil;
    @try {
        originalVersions = object_getIvar(photoObject, originalVersionsIvar);
    } @catch (__unused NSException *exception) {
        return nil;
    }

    if (![originalVersions isKindOfClass:[NSArray class]] || [(NSArray *)originalVersions count] == 0) {
        return nil;
    }

    NSURL *bestURL = nil;
    NSInteger bestWidth = 0;
    for (id item in (NSArray *)originalVersions) {
        NSURL *url = nil;
        NSInteger width = 0;
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSString *urlString = ((NSDictionary *)item)[@"url"];
            if (urlString.length > 0) url = [NSURL URLWithString:urlString];
            width = [((NSDictionary *)item)[@"width"] integerValue];
        } else {
            if ([item respondsToSelector:@selector(url)]) {
                url = SCIURLFromValue([item valueForKey:@"url"]);
            }
            if ([item respondsToSelector:@selector(width)]) {
                width = [[item valueForKey:@"width"] integerValue];
            }
        }
        if (url && width > bestWidth) {
            bestWidth = width;
            bestURL = url;
        }
    }

    return bestURL;
}

static NSURL *SCIFieldCachePhotoURLForMediaObject(id mediaObject) {
    id imageVersions = SCIFieldCacheValue(mediaObject, @"image_versions2");
    id candidates = [imageVersions isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)imageVersions)[@"candidates"] : nil;
    if (!candidates) {
        candidates = SCIFieldCacheValue(mediaObject, @"candidates");
    }
    return SCIBestCandidatePhotoURLFromCandidates(candidates);
}

static NSURL *SCIBestDownloadURLForMediaObject(id mediaObject) {
    if (!mediaObject) return nil;

    mediaObject = SCIUnderlyingMediaObjectForAction(mediaObject);

    NSURL *videoURL = [SCIUtils getVideoUrlForMedia:mediaObject];
    if (videoURL) return videoURL;

    NSURL *hdPhotoURL = SCIHDPhotoURLForMediaObject(mediaObject);
    if (hdPhotoURL) return hdPhotoURL;

    NSURL *photoURL = [SCIUtils getPhotoUrlForMedia:mediaObject];
    if (photoURL) return photoURL;

    return SCIFieldCachePhotoURLForMediaObject(mediaObject);
}

static NSURL *SCICoverURLForMediaObject(id mediaObject) {
    if (!mediaObject) return nil;

    mediaObject = SCIUnderlyingMediaObjectForAction(mediaObject);

    NSURL *hdPhotoURL = SCIHDPhotoURLForMediaObject(mediaObject);
    if (hdPhotoURL) return hdPhotoURL;

    NSURL *photoURL = [SCIUtils getPhotoUrlForMedia:mediaObject];
    if (photoURL) return photoURL;

    return SCIFieldCachePhotoURLForMediaObject(mediaObject);
}

static SCIResolvedMediaEntry *SCIEntryFromMediaObject(id mediaObject) {
	if (!mediaObject) return nil;

    NSURL *instantsURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"scinstaMediaURL") ?: SCIKVCObject(mediaObject, @"scinstaMediaURL"));
    NSURL *instantsPhotoURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"scinstaPhotoURL") ?: SCIKVCObject(mediaObject, @"scinstaPhotoURL"));
    NSURL *instantsVideoURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"scinstaVideoURL") ?: SCIKVCObject(mediaObject, @"scinstaVideoURL"));
    NSNumber *instantsIsVideoNumber = [SCIUtils numericValueForObj:mediaObject selectorName:@"scinstaIsVideo"];
    BOOL instantsHasHint = instantsURL || instantsPhotoURL || instantsVideoURL || instantsIsVideoNumber != nil;
    if (instantsHasHint) {
        SCIResolvedMediaEntry *entry = [[SCIResolvedMediaEntry alloc] init];
        entry.mediaObject = mediaObject;
        entry.metadataObject = mediaObject;
        entry.sourceUsername = SCIExplicitSourceUsernameFromObject(mediaObject);
        entry.sourceMediaPK = SCIStringFromValue(SCIObjectForSelector(mediaObject, @"sourceMediaPK") ?: SCIKVCObject(mediaObject, @"sourceMediaPK"));
        entry.sourceMediaURLString = SCIStringFromValue(SCIObjectForSelector(mediaObject, @"sourceMediaURLString") ?: SCIKVCObject(mediaObject, @"sourceMediaURLString"));
        entry.importPostedDate = SCIDateFromActionValue(SCIObjectForSelector(mediaObject, @"importPostedDate") ?: SCIKVCObject(mediaObject, @"importPostedDate") ?: SCIObjectForSelector(mediaObject, @"takenAt") ?: SCIKVCObject(mediaObject, @"takenAt"));
        BOOL isVideo = instantsIsVideoNumber ? instantsIsVideoNumber.boolValue : SCIIsVideoExtension((instantsVideoURL ?: instantsURL).pathExtension);
        if (isVideo) {
            entry.videoURL = instantsVideoURL ?: instantsURL;
            entry.photoURL = instantsPhotoURL;
        } else {
            entry.photoURL = instantsPhotoURL ?: instantsURL;
            if (!entry.photoURL && instantsVideoURL) {
                entry.videoURL = instantsVideoURL;
            }
        }
        return (entry.photoURL || entry.videoURL) ? entry : nil;
    }

    NSURL *directURL = SCIURLFromValue(mediaObject);
    if (directURL) {
        SCIResolvedMediaEntry *entry = [[SCIResolvedMediaEntry alloc] init];
        entry.mediaObject = mediaObject;
        entry.metadataObject = mediaObject;
        if (SCIIsVideoExtension(directURL.pathExtension)) {
            entry.videoURL = directURL;
        } else {
            entry.photoURL = directURL;
        }
        return entry;
    }

    mediaObject = SCIUnderlyingMediaObjectForAction(mediaObject);

	SCIResolvedMediaEntry *entry = [[SCIResolvedMediaEntry alloc] init];
	entry.mediaObject = mediaObject;
	entry.metadataObject = mediaObject;

    if (!entry.photoURL) {
        entry.photoURL = [SCIUtils getPhotoUrlForMedia:mediaObject];
    }
    if (!entry.videoURL) {
        entry.videoURL = [SCIUtils getVideoUrlForMedia:mediaObject];
    }

	id photoObject = SCIObjectForSelector(mediaObject, @"photo");
	if (!photoObject) photoObject = SCIObjectForSelector(mediaObject, @"rawPhoto");
	if (photoObject) {
		entry.photoURL = [SCIUtils getPhotoUrl:photoObject];
		if (!entry.photoURL) {
			entry.photoURL = SCIURLFromAssetLikeObject(photoObject, NO);
		}
	}

	if (!entry.photoURL) entry.photoURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"imageURL"));
	if (!entry.photoURL) entry.photoURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"imageUrl"));
	if (!entry.photoURL) {
		id imageSpecifier = SCIObjectForSelector(mediaObject, @"imageSpecifier");
		entry.photoURL = SCIURLFromValue(SCIObjectForSelector(imageSpecifier, @"url"));
	}
	if (!entry.photoURL) entry.photoURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"displayURL"));
	if (!entry.photoURL) entry.photoURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"thumbnailURL"));
    if (!entry.photoURL) entry.photoURL = [SCIUtils getBestProfilePictureURLForUser:mediaObject];

	id videoObject = SCIObjectForSelector(mediaObject, @"video");
	if (!videoObject) videoObject = SCIObjectForSelector(mediaObject, @"rawVideo");
	if (videoObject) {
		entry.videoURL = [SCIUtils getVideoUrl:videoObject];
		if (!entry.videoURL) {
			entry.videoURL = SCIURLFromAssetLikeObject(videoObject, YES);
		}
	}

	if (!entry.videoURL) entry.videoURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"videoURL"));
	if (!entry.videoURL) entry.videoURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"videoUrl"));

	NSURL *genericURL = SCIURLFromValue(SCIObjectForSelector(mediaObject, @"url"));
	if (genericURL) {
		if (!entry.videoURL && SCIIsVideoExtension(genericURL.pathExtension)) {
			entry.videoURL = genericURL;
		} else if (!entry.photoURL && !SCIIsVideoExtension(genericURL.pathExtension)) {
			entry.photoURL = genericURL;
		}
	}

	if (!entry.photoURL && !entry.videoURL) {
		return nil;
	}

	return entry;
}

NSArray *SCIActionButtonCarouselChildren(id media) {
    if (!media) return @[];

    for (NSString *selectorName in @[@"items", @"carouselMedia", @"carouselChildren", @"children", @"carousel_media"]) {
        id value = SCIObjectForSelector(media, selectorName);
        if (!value) value = SCIKVCObject(media, selectorName);
        NSArray *items = SCIArrayFromCollection(value);
        if (items.count > 0) return items;
    }

    return @[];
}

static NSArray<SCIResolvedMediaEntry *> *SCIEntriesFromMedia(id media) {
	if (!media) return @[];

	NSMutableArray<SCIResolvedMediaEntry *> *entries = [NSMutableArray array];

    NSArray *directCollection = SCIArrayFromCollection(media);
    if (directCollection.count > 0) {
        for (id item in directCollection) {
            SCIResolvedMediaEntry *entry = SCIEntryFromMediaObject(item);
            if (!entry) {
                id nestedMedia = SCIObjectForSelector(item, @"media") ?: SCIKVCObject(item, @"media");
                entry = SCIEntryFromMediaObject(nestedMedia);
                if (entry && !entry.metadataObject) {
                    entry.metadataObject = nestedMedia ?: item;
                }
            }
            if (entry) {
                if (!entry.mediaObject) entry.mediaObject = item;
                if (!entry.metadataObject) entry.metadataObject = item;
                [entries addObject:entry];
            }
        }
        if (entries.count > 0) return entries;
    }

	NSArray *items = SCIActionButtonCarouselChildren(media);

	if (items.count > 0) {
		for (id item in items) {
            id nestedMedia = SCIObjectForSelector(item, @"media") ?: SCIKVCObject(item, @"media");
			SCIResolvedMediaEntry *entry = SCIEntryFromMediaObject(nestedMedia);
			if (!entry) entry = SCIEntryFromMediaObject(SCIObjectForSelector(item, @"visualMessage") ?: SCIKVCObject(item, @"visualMessage"));
			if (!entry) entry = SCIEntryFromMediaObject(SCIObjectForSelector(item, @"item") ?: SCIKVCObject(item, @"item"));
			if (!entry) entry = SCIEntryFromMediaObject(item);
			if (entry) {
				if (!entry.mediaObject) {
                    entry.mediaObject = item;
                }
                if (!entry.metadataObject) {
                    entry.metadataObject = nestedMedia ?: item;
                }
				[entries addObject:entry];
			}
		}
	} else {
        SCIResolvedMediaEntry *directEntry = SCIEntryFromMediaObject(media);
        if (directEntry) return @[directEntry];

        id nested = SCIObjectForSelector(media, @"media");
        if (!nested) nested = SCIKVCObject(media, @"media");
		SCIResolvedMediaEntry *singleEntry = SCIEntryFromMediaObject(nested);
		if (!singleEntry) {
			singleEntry = SCIEntryFromMediaObject(media);
		}
		if (singleEntry) [entries addObject:singleEntry];
	}

	return entries;
}

static NSArray<SCIMediaItem *> *SCIPlayerItemsFromEntries(NSArray<SCIResolvedMediaEntry *> *entries, SCIActionButtonSource source, NSString *username, id media) {
	NSMutableArray<SCIMediaItem *> *items = [NSMutableArray array];

	NSInteger index = 0;
	for (SCIResolvedMediaEntry *entry in entries) {
		NSURL *url = entry.videoURL ?: entry.photoURL;
		if (!url) {
			index++;
			continue;
		}
        id metadataObject = entry.metadataObject ?: entry.mediaObject ?: media;
        NSString *itemUsername = source == SCIActionButtonSourceInstants ? SCIUsernameForEntry(entry, username) : username;

		SCIMediaItem *item = [SCIMediaItem itemWithFileURL:url];
		item.mediaType = entry.videoURL ? SCIMediaItemTypeVideo : SCIMediaItemTypeImage;
		item.gallerySaveSource = SCIGallerySourceForActionSource(source);
		item.galleryMetadata = SCIGalleryMetadata(source, itemUsername, metadataObject);
        SCIApplyEntryMetadata(item.galleryMetadata, entry);
		if (metadataObject != media && source != SCIActionButtonSourceInstants) {
			[SCIGalleryOriginController populateMetadata:item.galleryMetadata fromMedia:media];
			if (entries.count > 1) {
				item.galleryMetadata.sourceMediaURLString = [SCIUtils appendImgIndex:index toURLString:item.galleryMetadata.sourceMediaURLString];
			}
		}
        item.sourceMediaObject = metadataObject;
		if (itemUsername.length > 0) item.title = itemUsername;
		[items addObject:item];
		index++;
	}

	return items;
}

static UIView *SCIDirectMediaView(UIViewController *controller) {
	if (!controller) return nil;
	id viewerContainer = [SCIUtils getIvarForObj:controller name:"_viewerContainerView"];
	if (!viewerContainer) viewerContainer = SCIKVCObject(controller, @"viewerContainerView");
	id mediaView = SCIObjectForSelector(viewerContainer, @"mediaView");
	return [mediaView isKindOfClass:[UIView class]] ? (UIView *)mediaView : nil;
}

extern "C" void SCIPauseStoryPlaybackFromOverlaySubview(UIView *overlayView) {
	UIViewController *ancestorController = SCIViewControllerForAncestorView(overlayView);
	if (!ancestorController) return;

	if ([ancestorController respondsToSelector:NSSelectorFromString(@"pauseWithReason:")]) {
		((void (*)(id, SEL, NSInteger))objc_msgSend)(ancestorController, NSSelectorFromString(@"pauseWithReason:"), 1);
	} else if ([ancestorController respondsToSelector:NSSelectorFromString(@"pauseWithReason:callsiteContext:")]) {
		((void (*)(id, SEL, NSInteger, id))objc_msgSend)(ancestorController, NSSelectorFromString(@"pauseWithReason:callsiteContext:"), 1, nil);
	} else if ([ancestorController respondsToSelector:NSSelectorFromString(@"pause")]) {
		((void (*)(id, SEL))objc_msgSend)(ancestorController, NSSelectorFromString(@"pause"));
	}
}

extern "C" void SCIResumeStoryPlaybackFromOverlaySubview(UIView *overlayView) {
	UIViewController *ancestorController = SCIViewControllerForAncestorView(overlayView);
	if (!ancestorController) return;

	if ([ancestorController respondsToSelector:NSSelectorFromString(@"tryResumePlayback")]) {
		((void (*)(id, SEL))objc_msgSend)(ancestorController, NSSelectorFromString(@"tryResumePlayback"));
	} else if ([ancestorController respondsToSelector:NSSelectorFromString(@"tryResumePlaybackWithReason:")]) {
		((void (*)(id, SEL, NSInteger))objc_msgSend)(ancestorController, NSSelectorFromString(@"tryResumePlaybackWithReason:"), 1);
	} else if ([ancestorController respondsToSelector:NSSelectorFromString(@"resumePlayback")]) {
		((void (*)(id, SEL))objc_msgSend)(ancestorController, NSSelectorFromString(@"resumePlayback"));
	} else if ([ancestorController respondsToSelector:NSSelectorFromString(@"play")]) {
		((void (*)(id, SEL))objc_msgSend)(ancestorController, NSSelectorFromString(@"play"));
	}
}

static void SCIPauseDirectPlaybackFromController(UIViewController *controller) {
	UIView *mediaView = SCIDirectMediaView(controller);
	SEL pauseSelector = NSSelectorFromString(@"pauseWithReason:");
	if (mediaView && [mediaView respondsToSelector:pauseSelector]) {
		((void (*)(id, SEL, NSInteger))objc_msgSend)(mediaView, pauseSelector, 0);
	}
}

static void SCIResumeDirectPlaybackFromController(UIViewController *controller) {
	UIView *mediaView = SCIDirectMediaView(controller);
	SEL playSelector = NSSelectorFromString(@"play");
	if (mediaView && [mediaView respondsToSelector:playSelector]) {
		((void (*)(id, SEL))objc_msgSend)(mediaView, playSelector);
	}
}

static UIImage *SCIButtonDefaultImage(NSString *identifier, SCIActionButtonSource source, SCIActionButtonContext *context) {
	CGFloat size = 24.0;
	if (source == SCIActionButtonSourceReels) {
		size = 44.0;
	} else if ([identifier isEqualToString:kSCIActionDownloadShare] ||
			   [identifier isEqualToString:kSCIActionViewThumbnail] ||
               [identifier isEqualToString:kSCIActionDownloadGallery]) {
		size = 23.0;
	}

    NSString *resolvedIdentifier = identifier;
    if (source == SCIActionButtonSourceProfile && [identifier isEqualToString:kSCIActionProfileCopyInfo]) {
        resolvedIdentifier = SCIProfileDefaultCopyInfoIdentifier();
    }

	return SCIIconForActionIdentifier(resolvedIdentifier, source, size, context);
}

static CGSize SCICustomButtonIconDisplaySize(NSString *identifier, SCIActionButtonSource source, UIImage *image, UIButton *button) {
    if (!image) return CGSizeZero;

    CGFloat width = image.size.width;
    CGFloat height = image.size.height;

    if (source == SCIActionButtonSourceReels) {
        if ([identifier isEqualToString:kSCIActionDownloadShare] ||
            [identifier isEqualToString:kSCIActionDownloadAudioShare]) {
            width = height = 38.0;
        } else if ([identifier isEqualToString:kSCIActionNone] ||
                   [identifier isEqualToString:kSCIActionViewThumbnail] ||
                   [identifier isEqualToString:kSCIActionDownloadGallery] ||
                   [identifier isEqualToString:kSCIActionCopyMedia] ||
                   [identifier isEqualToString:kSCIActionTrimSave] ||
                   [identifier isEqualToString:kSCIActionDownloadAudio] ||
                   [identifier isEqualToString:kSCIActionDownloadAudioGallery] ||
                   [identifier isEqualToString:kSCIActionPlayAudio] ||
                   [identifier isEqualToString:kSCIActionCopyCaption]) {
            // Actions without a dedicated 44pt _reels asset render at 28pt.
            width = height = 28.0;
        }
    }

    CGFloat maxWidth = CGRectGetWidth(button.bounds) > 0.0 ? CGRectGetWidth(button.bounds) : 44.0;
    CGFloat maxHeight = CGRectGetHeight(button.bounds) > 0.0 ? CGRectGetHeight(button.bounds) : 44.0;

    return CGSizeMake(MAX(1.0, MIN(maxWidth, width)), MAX(1.0, MIN(maxHeight, height)));
}

static UIImageView *SCIEnsureCustomIconImageView(UIButton *button) {
	UIImageView *imageView = objc_getAssociatedObject(button, kSCIActionButtonIconImageViewAssocKey);
	if ([imageView isKindOfClass:[UIImageView class]]) return imageView;

	imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
	imageView.translatesAutoresizingMaskIntoConstraints = NO;
	imageView.contentMode = UIViewContentModeScaleAspectFit;
	imageView.userInteractionEnabled = NO;
	[button addSubview:imageView];

	[NSLayoutConstraint activateConstraints:@[
		[imageView.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
		[imageView.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
		[imageView.widthAnchor constraintLessThanOrEqualToAnchor:button.widthAnchor],
		[imageView.heightAnchor constraintLessThanOrEqualToAnchor:button.heightAnchor],
	]];

	NSLayoutConstraint *widthConstraint = [imageView.widthAnchor constraintEqualToConstant:24.0];
	NSLayoutConstraint *heightConstraint = [imageView.heightAnchor constraintEqualToConstant:24.0];
	widthConstraint.active = YES;
	heightConstraint.active = YES;

	objc_setAssociatedObject(button, kSCIActionButtonIconImageViewAssocKey, imageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(button, kSCIActionButtonIconWidthConstraintAssocKey, widthConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(button, kSCIActionButtonIconHeightConstraintAssocKey, heightConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return imageView;
}

static void SCISetButtonVisualImage(UIButton *button, UIImage *image, SCIActionButtonSource source, NSString *identifier) {
	UIImage *templatedImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	if ([button isKindOfClass:[SCIChromeButton class]]) {
		SCIChromeButton *chromeButton = (SCIChromeButton *)button;
		if (source == SCIActionButtonSourceReels) {
			chromeButton.iconView.contentMode = UIViewContentModeScaleAspectFit;
			CGSize displaySize = SCICustomButtonIconDisplaySize(identifier, source, templatedImage, button);
			NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(chromeButton, kSCIActionButtonIconWidthConstraintAssocKey);
			NSLayoutConstraint *heightConstraint = objc_getAssociatedObject(chromeButton, kSCIActionButtonIconHeightConstraintAssocKey);
			if (!widthConstraint) {
				widthConstraint = [chromeButton.iconView.widthAnchor constraintEqualToConstant:displaySize.width];
				heightConstraint = [chromeButton.iconView.heightAnchor constraintEqualToConstant:displaySize.height];
				widthConstraint.active = YES;
				heightConstraint.active = YES;
				objc_setAssociatedObject(chromeButton, kSCIActionButtonIconWidthConstraintAssocKey, widthConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				objc_setAssociatedObject(chromeButton, kSCIActionButtonIconHeightConstraintAssocKey, heightConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			} else {
				widthConstraint.constant = displaySize.width;
				heightConstraint.constant = displaySize.height;
			}
		} else {
			NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(chromeButton, kSCIActionButtonIconWidthConstraintAssocKey);
			NSLayoutConstraint *heightConstraint = objc_getAssociatedObject(chromeButton, kSCIActionButtonIconHeightConstraintAssocKey);
			if (widthConstraint) {
				widthConstraint.active = NO;
				heightConstraint.active = NO;
				objc_setAssociatedObject(chromeButton, kSCIActionButtonIconWidthConstraintAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				objc_setAssociatedObject(chromeButton, kSCIActionButtonIconHeightConstraintAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			}
			chromeButton.iconView.contentMode = UIViewContentModeCenter;
		}
		chromeButton.iconView.image = templatedImage;
		chromeButton.iconTint = SCIActionButtonTintForSource(source);
		[button setImage:nil forState:UIControlStateNormal];
		return;
	}

	UIImageView *customIconView = objc_getAssociatedObject(button, kSCIActionButtonIconImageViewAssocKey);
	if ([customIconView isKindOfClass:[UIImageView class]]) {
		customIconView.hidden = YES;
		customIconView.image = nil;
	}
	[button setImage:templatedImage forState:UIControlStateNormal];
}

static id SCIResolveMediaForContext(SCIActionButtonContext *context) {
	if (!context) return nil;
	if (context.mediaOverride) return context.mediaOverride;
	if (context.mediaResolver) return context.mediaResolver(context);
	return nil;
}

static id SCIResolveBulkMediaForContext(SCIActionButtonContext *context) {
    if (!context) return nil;
    if (context.bulkMediaResolver) return context.bulkMediaResolver(context);
    return SCIResolveMediaForContext(context);
}

static NSInteger SCIResolveCurrentIndexForContext(SCIActionButtonContext *context) {
	if (!context) return 0;
	if (context.currentIndexOverride >= 0) return context.currentIndexOverride;
	if (context.currentIndexResolver) return context.currentIndexResolver(context);
	return 0;
}

static NSArray<SCIResolvedMediaEntry *> *SCIBulkEntriesForContext(SCIActionButtonContext *context) {
    id bulkMedia = SCIResolveBulkMediaForContext(context);
    return SCIEntriesFromMedia(bulkMedia);
}

static NSArray<SCIResolvedMediaEntry *> *SCIDownloadableEntries(NSArray<SCIResolvedMediaEntry *> *entries) {
    NSMutableArray<SCIResolvedMediaEntry *> *filtered = [NSMutableArray array];
    for (SCIResolvedMediaEntry *entry in entries) {
        NSURL *url = entry.videoURL ?: entry.photoURL;
        if (url) [filtered addObject:entry];
    }
    return filtered;
}

static UIViewController *SCIActionContextPresenter(SCIActionButtonContext *context) {
    if (context.controller.view.window) return context.controller;
    UIViewController *ancestor = SCIViewControllerForAncestorView(context.view);
    if (ancestor.view.window) return ancestor;
    return topMostController();
}

static UIView *SCIActionContextAnchorView(SCIActionButtonContext *context) {
    if ([context.view isKindOfClass:[UIView class]] && context.view.window) return context.view;
    return SCIActionContextPresenter(context).view;
}

static NSArray<SCIDownloadItemRequest *> *SCIBulkDownloadItemsFromEntries(NSArray<SCIResolvedMediaEntry *> *entries,
                                                                          SCIActionButtonSource source,
                                                                          NSString *username,
                                                                          id media) {
    NSMutableArray<SCIDownloadItemRequest *> *items = [NSMutableArray array];
    NSInteger index = 0;
    for (SCIResolvedMediaEntry *entry in entries) {
        NSURL *url = entry.videoURL ?: entry.photoURL;
        if (!url) {
            index++;
            continue;
        }
        BOOL isVideo = (entry.videoURL != nil);
        id metadataObject = entry.metadataObject ?: entry.mediaObject ?: media;
        NSString *itemUsername = source == SCIActionButtonSourceInstants ? SCIUsernameForEntry(entry, username) : username;
        SCIGallerySaveMetadata *meta = SCIGalleryMetadata(source, itemUsername, metadataObject);
        SCIApplyEntryMetadata(meta, entry);
        if (metadataObject != media && source != SCIActionButtonSourceInstants) {
            [SCIGalleryOriginController populateMetadata:meta fromMedia:media];
            if (entries.count > 1) {
                meta.sourceMediaURLString = [SCIUtils appendImgIndex:index toURLString:meta.sourceMediaURLString];
            }
        }
        NSString *extension = SCIExtensionForURL(url, isVideo);
        SCIDownloadMediaKind kind = isVideo ? SCIDownloadMediaKindVideo : SCIDownloadMediaKindImage;
        SCIDownloadItemRequest *item = url.isFileURL
            ? [SCIDownloadItemRequest itemWithLocalPath:url.path mediaKind:kind]
            : [SCIDownloadItemRequest itemWithRemoteURL:url mediaKind:kind];
        item.preferredFileExtension = extension;
        item.metadata = meta;
        item.index = index;
        item.linkString = SCIBestDownloadURLForMediaObject(metadataObject).absoluteString ?: url.absoluteString;
        item.expectedFilenameStem = [[SCIDownloadHelpers preferredFilenameForURL:url mediaKind:kind metadata:meta] stringByDeletingPathExtension];
        [items addObject:item];
        index++;
    }
    return items;
}

static NSArray<NSString *> *SCIBulkDownloadLinksFromEntries(NSArray<SCIResolvedMediaEntry *> *entries, id media) {
    NSMutableOrderedSet<NSString *> *links = [NSMutableOrderedSet orderedSet];
    for (SCIResolvedMediaEntry *entry in entries) {
        id metadataObject = entry.metadataObject ?: entry.mediaObject ?: media;
        NSURL *bestURL = SCIBestDownloadURLForMediaObject(metadataObject) ?: entry.videoURL ?: entry.photoURL;
        if (bestURL.absoluteString.length > 0) {
            [links addObject:bestURL.absoluteString];
        }
    }
    return links.array;
}

NSArray<NSString *> *SCIConfiguredBulkActionIdentifiersForSource(SCIActionButtonSource source) {
    NSMutableOrderedSet<NSString *> *ordered = [NSMutableOrderedSet orderedSet];
    [ordered addObjectsFromArray:SCIActionButtonConfiguredBulkDownloadActionsForSource(source)];
    [ordered addObjectsFromArray:SCIActionButtonConfiguredBulkCopyActionsForSource(source)];
    return ordered.array;
}

static NSArray<UIMenuElement *> *SCIBulkActionMenuElementsForIdentifiers(NSArray<NSString *> *identifiers,
                                                                         void (^selectionHandler)(NSString *identifier)) {
    NSMutableArray<UIMenuElement *> *elements = [NSMutableArray array];
    for (NSString *identifier in identifiers) {
        UIImage *image = SCIActionButtonMenuIconForIdentifier(identifier, 22.0);
        NSString *title = SCIActionButtonTitleForIdentifier(identifier);
        [elements addObject:[UIAction actionWithTitle:title
                                                image:image
                                           identifier:nil
                                              handler:^(__unused UIAction *action) {
            selectionHandler(identifier);
        }]];
    }
    return elements;
}

static NSArray<NSString *> *SCIFilterBulkActionIdentifiers(NSArray<NSString *> *identifiers,
                                                           BOOL (^predicate)(NSString *identifier)) {
    NSMutableArray<NSString *> *filtered = [NSMutableArray array];
    for (NSString *identifier in identifiers) {
        if (predicate && predicate(identifier)) {
            [filtered addObject:identifier];
        }
    }
    return filtered;
}

static UIMenu *SCIBulkActionMenuForContext(SCIActionButtonContext *context,
                                           NSArray<SCIResolvedMediaEntry *> *entries,
                                           NSString *username,
                                           id media,
                                           NSArray<NSString *> *configuredIdentifiers) {
    NSArray<SCIResolvedMediaEntry *> *downloadableEntries = SCIDownloadableEntries(entries);
    if (downloadableEntries.count < 2) {
        return nil;
    }

    __weak SCIActionButtonContext *weakContext = context;
    NSArray<UIMenuElement *> *children = SCIBulkActionMenuElementsForIdentifiers(configuredIdentifiers, ^(NSString *identifier) {
        SCIActionButtonContext *strongContext = weakContext;
        if (strongContext) {
            SCIExecuteActionIdentifier(identifier, strongContext, NO);
        }
    });
    if (children.count == 0) return nil;
    return [UIMenu menuWithTitle:@"" children:children];
}

static void SCIPresentBulkActionChooser(SCIActionButtonContext *context,
                                        NSArray<SCIResolvedMediaEntry *> *entries,
                                        NSString *username,
                                        id media) {
    UIMenu *menu = SCIBulkActionMenuForContext(context, entries, username, media, SCIConfiguredBulkActionIdentifiersForSource(context.source));
    if (!menu) {
        SCINotify(kSCIActionDownloadAllLibrary, @"No bulk media available", nil, @"error_filled", SCINotificationToneError);
    }
}

// Renders `children` as a labeled, collapsible submenu — but when there is only
// one child, returns that child inline instead, so single-element submenus never
// add a redundant nesting level. Used everywhere a submenu/section is built so
// the behavior is uniform across built-in and custom sections.
static UIMenuElement *SCISubmenuOrSingleElement(NSString *title, UIImage *image, NSArray<UIMenuElement *> *children) {
    if (children.count == 0) return nil;
    if (children.count == 1) return children.firstObject;
    return [UIMenu menuWithTitle:title ?: @""
                           image:image
                      identifier:nil
                         options:0
                        children:children];
}

static UIMenuElement *SCIBulkActionMenuElementForContext(SCIActionButtonContext *context,
                                                         NSArray<SCIResolvedMediaEntry *> *entries,
                                                         NSString *username,
                                                         id media,
                                                         NSArray<NSString *> *configuredIdentifiers,
                                                         NSString *title,
                                                         NSString *iconIdentifier) {
    UIMenu *menu = SCIBulkActionMenuForContext(context, entries, username, media, configuredIdentifiers);
    if (!menu) return nil;
    return SCISubmenuOrSingleElement(title,
                                     SCIActionButtonMenuIconForContext(iconIdentifier ?: kSCIActionDownloadAll, context, 22.0),
                                     menu.children);
}

static NSString *SCIResolvedBulkUsernameForContext(SCIActionButtonContext *context, NSArray<SCIResolvedMediaEntry *> *entries, id media) {
    NSString *username = (context.source == SCIActionButtonSourceDirect)
        ? SCIDirectUsernameFromController(context.controller)
        : SCIUsernameFromMediaObject(media);
    if (username.length > 0) return username;
    for (SCIResolvedMediaEntry *entry in entries) {
        username = SCIUsernameFromMediaObject(entry.metadataObject ?: entry.mediaObject);
        if (username.length > 0) return username;
    }
    return nil;
}

static id SCICheapObjectValueForAudioKey(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    id value = SCIFieldCacheValue(object, key);
    if (!value) value = SCIObjectForSelector(object, key);
    if (!value) value = SCIKVCObject(object, key);
    return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL SCICheapAudioValueExists(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = SCICheapObjectValueForAudioKey(object, key);
        if (!value) continue;
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] == 0) continue;
        if ([value isKindOfClass:[NSArray class]] && [(NSArray *)value count] == 0) continue;
        if ([value isKindOfClass:[NSDictionary class]] && [(NSDictionary *)value count] == 0) continue;
        return YES;
    }
    return NO;
}

static BOOL SCICheapAudioBoolValue(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = SCICheapObjectValueForAudioKey(object, key);
        if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) return YES;
    }
    return NO;
}

static NSArray *SCIFeedAudioVisibilityCandidates(SCIResolvedMediaEntry *entry, id media) {
    NSMutableArray *candidates = [NSMutableArray array];
    for (id candidate in @[media ?: NSNull.null, entry.metadataObject ?: NSNull.null, entry.mediaObject ?: NSNull.null]) {
        if (candidate == NSNull.null || [candidates containsObject:candidate]) continue;
        [candidates addObject:candidate];
    }
    return candidates;
}

static BOOL SCIFeedEntryMayHaveDownloadableAudio(SCIResolvedMediaEntry *entry, id media) {
    static NSArray<NSString *> *metadataKeys = nil;
    static NSArray<NSString *> *boolKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        metadataKeys = @[
            @"audio", @"audio_url", @"audioURL", @"audioFileUrl", @"audioFileFastStartUrl", @"audioSrc",
            @"music", @"music_info", @"musicInfo", @"music_metadata", @"musicMetadata", @"musicAssetInfo",
            @"audio_asset", @"audioAsset", @"audio_asset_info", @"audioAssetInfo",
            @"clips_audio", @"clipsAudio", @"clips_metadata", @"clipsMetadata",
            @"original_audio", @"originalAudio", @"original_audio_info", @"originalAudioInfo",
            @"original_sound_info", @"originalSoundInfo",
            @"video_dash_manifest", @"videoDashManifest", @"dashManifest"
        ];
        boolKeys = @[@"has_audio", @"hasAudio", @"has_original_audio", @"hasOriginalAudio", @"contains_audio", @"containsAudio"];
    });

    for (id candidate in SCIFeedAudioVisibilityCandidates(entry, media)) {
        if (SCICheapAudioValueExists(candidate, metadataKeys) || SCICheapAudioBoolValue(candidate, boolKeys)) {
            return YES;
        }
    }

    return NO;
}

static BOOL SCIFeedEntryMayHaveDirectAudioURL(SCIResolvedMediaEntry *entry, id media) {
    static NSArray<NSString *> *directKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        directKeys = @[
            @"audio", @"audio_url", @"audioURL", @"audioFileUrl", @"audioFileFastStartUrl", @"audioSrc",
            @"video_dash_manifest", @"videoDashManifest", @"dashManifest"
        ];
    });

    for (id candidate in SCIFeedAudioVisibilityCandidates(entry, media)) {
        if (SCICheapAudioValueExists(candidate, directKeys)) return YES;
    }
    return NO;
}

static BOOL SCIIsActionVisible(SCIActionButtonContext *context,
							   SCIActionButtonConfiguration *configuration,
							   NSString *identifier,
							   id media,
							   NSArray<SCIResolvedMediaEntry *> *entries,
							   NSInteger currentIndex) {
	if (identifier.length == 0) return NO;
	if ([configuration.disabledActions containsObject:identifier] || [configuration.unassignedActions containsObject:identifier]) {
		return NO;
	}

    if ([identifier isEqualToString:kSCIActionToggleStorySeenUserRule]) {
        return context.source == SCIActionButtonSourceStories &&
               SCIStoryCurrentUserRuleActionTitle(SCIStoryContextForActionButtonContext(context)).length > 0;
    }
    if ([identifier isEqualToString:kSCIActionToggleProfileStorySeenUserRule]) {
        return context.source == SCIActionButtonSourceProfile &&
               SCIResolveMediaForContext(context) != nil;
    }
    if ([identifier isEqualToString:kSCIActionToggleProfileMessagesSeenUserRule]) {
        return context.source == SCIActionButtonSourceProfile &&
               SCIResolveMediaForContext(context) != nil;
    }
    if ([identifier isEqualToString:kSCIActionStoryMentionsSheet]) {
        return context.source == SCIActionButtonSourceStories && SCIStoryMediaHasMentions(media);
    }
    if (context.source == SCIActionButtonSourceProfile && [identifier isEqualToString:kSCIActionProfileCopyInfo]) {
        return media != nil;
    }
    if (context.source == SCIActionButtonSourceProfile && [identifier isEqualToString:kSCIActionOpenTopicSettings]) {
        return SCIResolvedSettingsTitleForContext(context).length > 0;
    }
    if (context.source == SCIActionButtonSourceDirect && [identifier isEqualToString:kSCIActionDeletedMessagesLog]) {
        return YES;
    }

    if (entries.count == 0) return NO;

	NSInteger idx = SCIClampedIndex(currentIndex, (NSInteger)entries.count);
	SCIResolvedMediaEntry *currentEntry = entries[idx];
	NSURL *currentURL = currentEntry.videoURL ?: currentEntry.photoURL;

	if ([identifier isEqualToString:kSCIActionViewThumbnail]) {
		if (!currentEntry.videoURL) return NO;
		// For stories, photo items may falsely expose a videoURL.
		// Only show thumbnail if no photoURL exists (pure video),
		// or if both exist but are distinct URLs.
		if (context.source == SCIActionButtonSourceStories && currentEntry.photoURL) {
			return ![currentEntry.videoURL isEqual:currentEntry.photoURL];
		}
		return YES;
	}
	if ([identifier isEqualToString:kSCIActionTrimSave]) {
		// Video-only, but unlike thumbnail/download we can't rely on a resolved
		// videoURL — feed-inline reels resolve it lazily. Fall back to a cheap
		// media-object video check (duration / resolvable URL).
		if (currentEntry.videoURL) {
			if (context.source == SCIActionButtonSourceStories && currentEntry.photoURL) {
				return ![currentEntry.videoURL isEqual:currentEntry.photoURL];
			}
			return YES;
		}
		id mediaObj = currentEntry.mediaObject ?: media;
		return [SCIMediaQualityManager mediaObjectIsVideo:mediaObj];
	}
	if ([identifier isEqualToString:kSCIActionDownloadLibrary] ||
		[identifier isEqualToString:kSCIActionDownloadShare] ||
		[identifier isEqualToString:kSCIActionCopyDownloadLink] ||
        [identifier isEqualToString:kSCIActionCopyMedia] ||
		[identifier isEqualToString:kSCIActionDownloadGallery]) {
		return currentURL != nil;
	}
    if ([identifier isEqualToString:kSCIActionDownloadAudio] ||
        [identifier isEqualToString:kSCIActionDownloadAudioShare] ||
        [identifier isEqualToString:kSCIActionDownloadAudioGallery]) {
        if (context.source == SCIActionButtonSourceFeed) {
            return SCIFeedEntryMayHaveDownloadableAudio(currentEntry, media);
        }
        id audioMedia = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
        return [SCIAudioDownloadCoordinator bestAudioDownloadURLFromMediaObject:audioMedia] != nil;
    }
    if ([identifier isEqualToString:kSCIActionPlayAudio] ||
        [identifier isEqualToString:kSCIActionCopyAudioURL]) {
        if (context.source == SCIActionButtonSourceFeed) {
            return SCIFeedEntryMayHaveDirectAudioURL(currentEntry, media);
        }
        id audioMedia = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
        return [SCIAudioDownloadCoordinator bestAudioURLFromMediaObject:audioMedia] != nil;
    }
	if ([identifier isEqualToString:kSCIActionCopyCaption]) {
		return context.captionResolver != nil && [context.captionResolver(context, media, entries, idx) length] > 0;
	}
	if ([identifier isEqualToString:kSCIActionOpenTopicSettings]) {
		return SCIResolvedSettingsTitleForContext(context).length > 0;
	}
	if ([identifier isEqualToString:kSCIActionRepost]) {
		return context.repostHandler != nil;
    }
    if (SCIIsBulkChildActionIdentifier(identifier)) {
        id bulkMedia = SCIResolveBulkMediaForContext(context);
        NSArray<SCIResolvedMediaEntry *> *bulkEntries = SCIDownloadableEntries(SCIEntriesFromMedia(bulkMedia));
        if (bulkEntries.count <= 1) return NO;
        if (SCIIsBulkDownloadActionIdentifier(identifier)) {
            return ![configuration.disabledActions containsObject:kSCIActionDownloadLibrary] ||
                   ![configuration.disabledActions containsObject:kSCIActionDownloadShare] ||
                   ![configuration.disabledActions containsObject:kSCIActionDownloadGallery];
        }
        if (SCIIsBulkCopyActionIdentifier(identifier)) {
            return ![configuration.disabledActions containsObject:kSCIActionCopyDownloadLink] ||
                   ![configuration.disabledActions containsObject:kSCIActionCopyMedia];
        }
    }
	if (context.visibilityResolver) {
		return context.visibilityResolver(context, identifier, media, entries, idx);
	}
	return YES;
}

static NSArray<NSString *> *SCIVisibleActionsForContext(SCIActionButtonContext *context, id media, NSArray<SCIResolvedMediaEntry *> *entries, NSInteger currentIndex) {
	SCIActionButtonConfiguration *configuration = [SCIActionButtonConfiguration configurationForSource:context.source
																						  topicTitle:context.settingsTitle ?: SCIActionButtonTopicTitleForSource(context.source)
																					supportedActions:context.supportedActions ?: SCIActionButtonSupportedActionsForSource(context.source)
																					 defaultSections:SCIActionButtonDefaultSectionsForSource(context.source)];
	NSArray<NSString *> *supportedActions = configuration.supportedActions ?: @[];
	if (supportedActions.count == 0) return @[];

	NSMutableArray<NSString *> *visible = [NSMutableArray array];
	for (NSString *identifier in supportedActions) {
		if (SCIIsActionVisible(context, configuration, identifier, media, entries, currentIndex)) {
			[visible addObject:identifier];
		}
	}
	return visible;
}

static NSString *SCIResolvedDefaultActionIdentifier(NSArray<NSString *> *visibleIdentifiers, SCIActionButtonSource source) {
	if (visibleIdentifiers.count == 0) return nil;

	NSString *saved = [SCIUtils getStringPref:SCIDefaultActionPrefKeyForSource(source)];
    if (source == SCIActionButtonSourceProfile && saved.length > 0) {
        NSDictionary<NSString *, NSString *> *legacyMap = @{
            @"copy_info": kSCIActionProfileCopyInfo,
            @"view_picture": kSCIActionExpand,
            @"share_picture": kSCIActionDownloadShare,
            @"save_picture_gallery": kSCIActionDownloadGallery,
            @"profile_settings": kSCIActionOpenTopicSettings
        };
        saved = legacyMap[saved] ?: saved;
    }
	if ([saved isEqualToString:kSCIActionNone]) return kSCIActionNone;
	if ([saved isEqualToString:kSCIActionDownloadAll] && [visibleIdentifiers containsObject:kSCIActionDownloadAllLibrary]) {
        return kSCIActionDownloadAllLibrary;
    }
	if (saved.length > 0 && [visibleIdentifiers containsObject:saved]) return saved;
	if (saved.length > 0) return kSCIActionNone;
    if (source == SCIActionButtonSourceProfile) return kSCIActionNone;
	if ([visibleIdentifiers containsObject:kSCIActionDownloadLibrary]) return kSCIActionDownloadLibrary;
	return visibleIdentifiers.firstObject;
}

static NSString *SCIActionButtonMenuSignature(SCIActionButtonContext *context,
											  SCIActionButtonConfiguration *configuration,
											  NSArray<NSString *> *visibleActions,
											  NSString *defaultIdentifier,
                                              NSUInteger bulkEntryCount) {
    NSString *dynamicStoryRuleTitle = [visibleActions containsObject:kSCIActionToggleStorySeenUserRule]
        ? SCIStoryCurrentUserRuleActionTitle(SCIStoryContextForActionButtonContext(context))
        : @"";
    NSString *dynamicProfileStoryRuleTitle = [visibleActions containsObject:kSCIActionToggleProfileStorySeenUserRule]
        ? SCIActionButtonDisplayTitleForContext(kSCIActionToggleProfileStorySeenUserRule, context, nil)
        : @"";
    NSString *dynamicProfileMessagesRuleTitle = [visibleActions containsObject:kSCIActionToggleProfileMessagesSeenUserRule]
        ? SCIActionButtonDisplayTitleForContext(kSCIActionToggleProfileMessagesSeenUserRule, context, nil)
        : @"";
    NSString *profileInfoSignature = (context.source == SCIActionButtonSourceProfile)
        ? SCIProfileInfoSignature(SCIResolveMediaForContext(context))
        : @"";
    id media = SCIResolveMediaForContext(context);
    NSInteger currentIndex = SCIResolveCurrentIndexForContext(context);
	return [NSString stringWithFormat:@"%@|%@|%@|bulk:%lu|%@|%@|%@|%@|%@|%p|idx:%ld",
			SCIActionButtonTopicKeyForSource(context.source),
			defaultIdentifier ?: @"",
			[visibleActions componentsJoinedByString:@","],
            (unsigned long)bulkEntryCount,
            dynamicStoryRuleTitle ?: @"",
            dynamicProfileStoryRuleTitle ?: @"",
            dynamicProfileMessagesRuleTitle ?: @"",
            profileInfoSignature ?: @"",
			configuration.dictionaryRepresentation.description ?: @"",
            media,
            (long)currentIndex];
}

void SCIArmPendingRepostFeedback(SCIActionButtonContext *context) {
	if (!context) return;

	NSString *sourceValue = [NSString stringWithFormat:@"%ld", (long)context.source];
	SCIPendingRepostFeedback = @{
		@"title": @"Tapped repost button",
		@"iconResource": @"ig_icon_reshare_outline_24",
		@"source": sourceValue
	};
}

NSDictionary<NSString *, NSString *> *SCIConsumePendingRepostFeedback(SCIActionButtonSource source) {
	NSString *expectedSource = [NSString stringWithFormat:@"%ld", (long)source];
	if (![SCIPendingRepostFeedback[@"source"] isEqualToString:expectedSource]) return nil;

	NSDictionary<NSString *, NSString *> *feedback = SCIPendingRepostFeedback;
	SCIPendingRepostFeedback = nil;
	return feedback;
}

static void SCIShowExtractedVideoCover(NSURL *videoURL, SCIGallerySaveMetadata *metadata, SCIActionButtonContext *context) {
	if (!videoURL) {
		SCINotify(kSCINotificationViewThumbnail, @"Cover unavailable", nil, @"error_filled", SCINotificationToneError);
		return;
	}

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
		AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
		generator.appliesPreferredTrackTransform = YES;
		generator.maximumSize = CGSizeMake(2160, 2160);

		NSError *error = nil;
		CGImageRef imageRef = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(0.0, 600) actualTime:NULL error:&error];
		if (!imageRef) {
			dispatch_async(dispatch_get_main_queue(), ^{
				SCINotify(kSCINotificationViewThumbnail, @"Cover unavailable", error.localizedDescription ?: @"", @"error_filled", SCINotificationToneError);
			});
			return;
		}

		UIImage *image = [UIImage imageWithCGImage:imageRef];
		CGImageRelease(imageRef);

		dispatch_async(dispatch_get_main_queue(), ^{
			[SCIFullScreenMediaPlayer showImage:image
                                      metadata:metadata
                                playbackSource:SCIPlaybackSourceForActionSource(context.source)
                                    sourceView:context.view
                                    controller:context.controller
                                 pausePlayback:SCIPausePlaybackBlockForContext(context)
                                resumePlayback:SCIResumePlaybackBlockForContext(context)];
		});
	});
}

static BOOL SCIExecuteBulkChildAction(NSString *identifier,
                                      SCIActionButtonContext *context,
                                      NSArray<SCIResolvedMediaEntry *> *entries,
                                      NSString *username,
                                      id media) {
    NSArray<SCIResolvedMediaEntry *> *downloadableEntries = SCIDownloadableEntries(entries);
    if (downloadableEntries.count < 2) {
        SCINotify(identifier, @"No bulk media available", nil, @"error_filled", SCINotificationToneError);
        return YES;
    }

    NSArray<SCIDownloadItemRequest *> *bulkItems = SCIBulkDownloadItemsFromEntries(downloadableEntries, context.source, username, media);
    UIViewController *presenter = SCIActionContextPresenter(context);
    UIView *anchorView = SCIActionContextAnchorView(context);
    SCIDownloadSourceSurface surface = [SCIDownloadHelpers sourceSurfaceForActionButtonSource:context.source];

    if ([SCIDownloadHelpers performBulkDownloadIdentifier:identifier
                                                    items:bulkItems
                                                presenter:presenter
                                               anchorView:anchorView
                                            sourceSurface:surface]) {
        return YES;
    }
    if ([identifier isEqualToString:kSCIActionDownloadAllLinks]) {
        NSArray<NSString *> *bulkLinks = SCIBulkDownloadLinksFromEntries(downloadableEntries, media);
        if (bulkLinks.count == 0) {
            SCINotify(identifier, @"No links available", nil, @"error_filled", SCINotificationToneError);
            return YES;
        }
        [UIPasteboard generalPasteboard].string = [bulkLinks componentsJoinedByString:@"\n"];
        SCINotify(identifier, SCICopiedDownloadURLTitleForSource(context.source, YES), [NSString stringWithFormat:@"%lu item%@", (unsigned long)bulkLinks.count, bulkLinks.count == 1 ? @"" : @"s"], @"copy_filled", SCINotificationToneForIconResource(@"copy_filled"));
        return YES;
    }

    return NO;
}

static BOOL SCIExecuteCommonAction(NSString *identifier,
								   SCIActionButtonContext *context,
								   SCIResolvedMediaEntry *currentEntry,
								   NSArray<SCIResolvedMediaEntry *> *entries,
								   NSInteger resolvedIndex,
								   NSString *username,
								   SCIGallerySaveMetadata *meta,
								   id media) {
	NSURL *currentURL = currentEntry.videoURL ?: currentEntry.photoURL;
	BOOL isVideo = (currentEntry.videoURL != nil);
	BOOL shouldNotify = SCINotificationIsEnabled(identifier);

	if ([identifier isEqualToString:kSCIActionDownloadAll]) {
		return YES;
	}
    if (SCIIsBulkChildActionIdentifier(identifier)) {
        return SCIExecuteBulkChildAction(identifier, context, entries, username, media);
    }

    if ([identifier isEqualToString:kSCIActionDownloadAudio] ||
        [identifier isEqualToString:kSCIActionDownloadAudioShare] ||
        [identifier isEqualToString:kSCIActionDownloadAudioGallery]) {
        id audioMedia = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
        SCIAudioItem *audioItem = [SCIAudioDownloadCoordinator audioItemFromMediaObject:audioMedia
                                                                                 source:SCIAudioSourceForActionSource(context.source)
                                                                    allowVideoFallback:YES];
        if (!audioItem && media && media != audioMedia) {
            audioItem = [SCIAudioDownloadCoordinator audioItemFromMediaObject:media
                                                                       source:SCIAudioSourceForActionSource(context.source)
                                                          allowVideoFallback:YES];
        }
        if (!audioItem) {
            SCINotify(identifier, @"No audio available", nil, @"error_filled", SCINotificationToneError);
            return YES;
        }
        if (audioItem.artist.length == 0) audioItem.artist = username;
        if (audioItem.sourceURLString.length == 0) audioItem.sourceURLString = audioItem.url.absoluteString;

        SCIAudioAction audioAction = SCIAudioActionConvertAndShare;
        if ([identifier isEqualToString:kSCIActionDownloadAudioGallery]) {
            audioAction = SCIAudioActionConvertAndSaveToGallery;
        } else if ([identifier isEqualToString:kSCIActionDownloadAudio]) {
            audioAction = SCIAudioActionSaveToFiles;
        }
        [SCIAudioDownloadCoordinator performAction:audioAction
                                             item:audioItem
                                        presenter:SCIActionContextPresenter(context)
                                       sourceView:SCIActionContextAnchorView(context)
                                         metadata:meta
                           notificationIdentifier:identifier
                                 playbackSource:SCIPlaybackSourceForActionSource(context.source)
                                  pausePlayback:SCIPausePlaybackBlockForContext(context)
                                 resumePlayback:SCIResumePlaybackBlockForContext(context)];
        return YES;
    }

    if ([identifier isEqualToString:kSCIActionPlayAudio] ||
        [identifier isEqualToString:kSCIActionCopyAudioURL]) {
        id audioMedia = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
        SCIAudioItem *audioItem = [SCIAudioDownloadCoordinator audioItemFromMediaObject:audioMedia
                                                                                 source:SCIAudioSourceForActionSource(context.source)];
        if (!audioItem && media && media != audioMedia) {
            audioItem = [SCIAudioDownloadCoordinator audioItemFromMediaObject:media
                                                                       source:SCIAudioSourceForActionSource(context.source)];
        }
        if (!audioItem) {
            SCINotify(identifier, @"No audio available", nil, @"error_filled", SCINotificationToneError);
            return YES;
        }
        if (audioItem.artist.length == 0) audioItem.artist = username;
        if (audioItem.sourceURLString.length == 0) audioItem.sourceURLString = audioItem.url.absoluteString;

        SCIAudioAction audioAction = [identifier isEqualToString:kSCIActionPlayAudio] ? SCIAudioActionPlay : SCIAudioActionCopyURL;
        [SCIAudioDownloadCoordinator performAction:audioAction
                                             item:audioItem
                                        presenter:SCIActionContextPresenter(context)
                                       sourceView:SCIActionContextAnchorView(context)
                                         metadata:meta
                           notificationIdentifier:identifier
                                 playbackSource:SCIPlaybackSourceForActionSource(context.source)
                                  pausePlayback:SCIPausePlaybackBlockForContext(context)
                                 resumePlayback:SCIResumePlaybackBlockForContext(context)];
        return YES;
    }

	if ([identifier isEqualToString:kSCIActionTrimSave]) {
		id mediaForTrim = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
		[SCITrimEntry beginTrimAndSaveForMediaObject:mediaForTrim
		                                    photoURL:currentEntry.photoURL
		                                    videoURL:currentEntry.videoURL
		                                    metadata:meta
		                                   presenter:SCIActionContextPresenter(context)];
		return YES;
	}

	if ([identifier isEqualToString:kSCIActionDownloadLibrary] ||
		[identifier isEqualToString:kSCIActionDownloadShare] ||
		[identifier isEqualToString:kSCIActionDownloadGallery]) {
		if (!currentURL) {
			SCINotify(identifier, @"No downloadable media", nil, @"error_filled", SCINotificationToneError);
			return YES;
		}

		SCIDownloadDestination destination = SCIDownloadDestinationPhotos;
		if ([identifier isEqualToString:kSCIActionDownloadShare]) destination = SCIDownloadDestinationShare;
		else if ([identifier isEqualToString:kSCIActionDownloadGallery]) destination = SCIDownloadDestinationGallery;

        id mediaForDownload = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
        UIViewController *presenter = SCIActionContextPresenter(context);
        UIView *anchorView = SCIActionContextAnchorView(context);
        SCIDownloadSourceSurface surface = [SCIDownloadHelpers sourceSurfaceForActionButtonSource:context.source];
        if ([SCIMediaQualityManager handleDownloadDestination:destination
                                             identifier:identifier
                                              presenter:presenter
                                             sourceView:anchorView
                                              mediaObject:mediaForDownload
                                                photoURL:currentEntry.photoURL
                                                videoURL:currentEntry.videoURL
                                         galleryMetadata:meta
                                           showProgress:shouldNotify
                                          sourceSurface:surface]) {
            return YES;
        }

        [SCIDownloadHelpers downloadURL:currentURL
                                    extension:SCIExtensionForURL(currentURL, isVideo)
                                destination:destination
                                     metadata:meta
                             notificationID:identifier
                                    presenter:presenter
                                 sourceSurface:surface];
		return YES;
	}

	if ([identifier isEqualToString:kSCIActionCopyDownloadLink]) {
        NSURL *bestURL = currentEntry.videoURL ?: currentEntry.photoURL;
        if (!bestURL) {
            id mediaForCopy = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
            bestURL = SCIBestDownloadURLForMediaObject(mediaForCopy);
		}
		if (!bestURL) {
			SCINotify(identifier, @"No link available", nil, @"error_filled", SCINotificationToneError);
			return YES;
		}

		[UIPasteboard generalPasteboard].string = bestURL.absoluteString ?: @"";
		SCINotify(identifier, SCICopiedDownloadURLTitleForSource(context.source, NO), nil, @"copy_filled", SCINotificationToneForIconResource(@"copy_filled"));
		return YES;
	}

    if ([identifier isEqualToString:kSCIActionCopyMedia]) {
        id mediaForCopy = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
        SCIDownloadSourceSurface surface = [SCIDownloadHelpers sourceSurfaceForActionButtonSource:context.source];
        if ([SCIMediaQualityManager handleCopyActionWithIdentifier:identifier
                                                         presenter:SCIActionContextPresenter(context)
                                                        sourceView:SCIActionContextAnchorView(context)
                                                         mediaObject:mediaForCopy
                                                           photoURL:currentEntry.photoURL
                                                           videoURL:currentEntry.videoURL
                                                    galleryMetadata:meta
                                                      showProgress:shouldNotify
                                                     sourceSurface:surface]) {
            return YES;
        }

        if (!currentURL && !currentEntry.photoURL) {
            SCINotify(identifier, @"Nothing to copy", nil, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
            return YES;
        }

        if (!isVideo) {
            NSData *imageData = currentURL ? [NSData dataWithContentsOfURL:currentURL] : nil;
            UIImage *image = imageData ? [UIImage imageWithData:imageData] : nil;
            if (image) {
                [[UIPasteboard generalPasteboard] setImage:image];
                SCINotify(identifier, @"Copied photo to clipboard", nil, @"copy_filled", SCINotificationToneForIconResource(@"copy_filled"));
            }
            return YES;
        }

        NSData *data = [NSData dataWithContentsOfURL:currentURL];
        if (data) {
            [[UIPasteboard generalPasteboard] setData:data forPasteboardType:@"public.mpeg-4"];
            SCINotify(identifier, @"Copied video to clipboard", nil, @"copy_filled", SCINotificationToneForIconResource(@"copy_filled"));
        } else {
            SCINotify(identifier, @"Nothing to copy", nil, @"error_filled", SCINotificationToneForIconResource(@"error_filled"));
        }
        return YES;
    }

	if ([identifier isEqualToString:kSCIActionExpand]) {
        NSArray<SCIResolvedMediaEntry *> *previewEntries = entries;
        NSArray<SCIResolvedMediaEntry *> *bulkEntries = SCIDownloadableEntries(SCIBulkEntriesForContext(context));
        if (bulkEntries.count > previewEntries.count) {
            previewEntries = bulkEntries;
		}
		NSArray<SCIMediaItem *> *playerItems = SCIPlayerItemsFromEntries(previewEntries, context.source, username, media);
		if (playerItems.count == 0) {
			SCINotify(identifier, @"No media to expand", nil, @"error_filled", SCINotificationToneError);
			return YES;
		}

		NSInteger previewIndex = SCIClampedIndex(SCIResolveCurrentIndexForContext(context), (NSInteger)previewEntries.count);
		NSInteger clampedIndex = SCIClampedIndex(previewIndex, (NSInteger)playerItems.count);
		SCINotify(identifier, @"Expanded media", nil, @"expand", SCINotificationToneForIconResource(@"expand"));
		[SCIFullScreenMediaPlayer showMediaItems:playerItems
                                startingAtIndex:clampedIndex
                                       metadata:meta
                                 playbackSource:SCIPlaybackSourceForActionSource(context.source)
                                     sourceView:context.view
                                     controller:context.controller
                                  pausePlayback:SCIPausePlaybackBlockForContext(context)
                                 resumePlayback:SCIResumePlaybackBlockForContext(context)];
		return YES;
	}

	if ([identifier isEqualToString:kSCIActionViewThumbnail]) {
		BOOL isVideo = currentEntry.videoURL != nil;
		if (isVideo && context.source == SCIActionButtonSourceStories && currentEntry.photoURL) {
			isVideo = ![currentEntry.videoURL isEqual:currentEntry.photoURL];
		}
		if (!isVideo) {
			SCINotify(identifier, @"Thumbnail is only available for videos", nil, @"error_filled", SCINotificationToneError);
			return YES;
		}

		SCIGallerySaveMetadata *thumbnailMeta = [[SCIGallerySaveMetadata alloc] init];
		thumbnailMeta.source = (int16_t)SCIGallerySourceThumbnail;
		thumbnailMeta.sourceUsername = meta.sourceUsername;
        id mediaForThumbnail = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
        NSURL *coverURL = SCICoverURLForMediaObject(mediaForThumbnail);
        if (coverURL) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSData *data = [NSData dataWithContentsOfURL:coverURL];
                UIImage *image = data ? [UIImage imageWithData:data] : nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (image) {
                        [SCIFullScreenMediaPlayer showImage:image
                                                  metadata:thumbnailMeta
                                            playbackSource:SCIPlaybackSourceForActionSource(context.source)
                                                sourceView:context.view
                                                controller:context.controller
                                             pausePlayback:SCIPausePlaybackBlockForContext(context)
                                            resumePlayback:SCIResumePlaybackBlockForContext(context)];
                    } else {
		                SCIShowExtractedVideoCover(currentEntry.videoURL, thumbnailMeta, context);
                    }
                });
            });
        } else {
		    SCIShowExtractedVideoCover(currentEntry.videoURL, thumbnailMeta, context);
        }
		SCINotify(identifier, @"Opened thumbnail", nil, @"photo_gallery", SCINotificationToneForIconResource(@"photo_gallery"));
		return YES;
	}

	if ([identifier isEqualToString:kSCIActionCopyCaption]) {
		NSString *caption = context.captionResolver ? context.captionResolver(context, media, entries, resolvedIndex) : nil;
		if (caption.length == 0) {
			SCINotify(identifier, @"No caption available", nil, @"error_filled", SCINotificationToneError);
			return YES;
		}

		[UIPasteboard generalPasteboard].string = caption;
		SCINotify(identifier, @"Caption copied", nil, @"copy_filled", SCINotificationToneForIconResource(@"copy_filled"));
		return YES;
	}

	if ([identifier isEqualToString:kSCIActionOpenTopicSettings]) {
		NSString *settingsTitle = SCIResolvedSettingsTitleForContext(context);
		if (settingsTitle.length == 0) {
			SCINotify(identifier, @"Settings unavailable", nil, @"error_filled", SCINotificationToneError);
			return YES;
		}

		SCINotify(identifier, @"Opened settings", nil, @"settings", SCINotificationToneForIconResource(@"settings"));
		[SCIUtils showSettingsForTopicTitle:settingsTitle];
		return YES;
	}

	if ([identifier isEqualToString:kSCIActionRepost]) {
		if (context.repostHandler) {
			SCIArmPendingRepostFeedback(context);
		}
		BOOL handled = context.repostHandler ? context.repostHandler(context) : NO;
		if (!handled) {
			SCIConsumePendingRepostFeedback(context.source);
		}
		if (!handled) {
			SCINotify(identifier, @"Repost unavailable", nil, @"error_filled", SCINotificationToneError);
		}
		return YES;
	}

	return NO;
}

static BOOL SCIExecuteToggleStorySeenUserRuleAction(SCIActionButtonContext *context) {
    SCIStoryContext *storyContext = SCIStoryContextForActionButtonContext(context);
    NSString *title = SCIStoryCurrentUserRuleConfirmationTitle(storyContext);
    NSString *message = SCIStoryCurrentUserRuleConfirmationMessage(storyContext);
    if (title.length == 0 || message.length == 0) {
        SCINotify(kSCINotificationStorySeenUserRule, @"Story user not found", nil, @"error_filled", SCINotificationToneError);
        return YES;
    }

    [SCIUtils showConfirmation:^{
        NSString *notificationTitle = nil;
        NSString *notificationSubtitle = nil;
        if (!SCIStoryToggleCurrentUserRule(storyContext, &notificationTitle, &notificationSubtitle)) {
            SCINotify(kSCINotificationStorySeenUserRule, @"Story user not found", nil, @"error_filled", SCINotificationToneError);
            return;
        }
        SCINotify(kSCINotificationStorySeenUserRule, notificationTitle, notificationSubtitle, @"circle_check_filled", SCINotificationToneSuccess);
        [storyContext.overlayView setNeedsLayout];
    } title:title message:message];
    return YES;
}

static BOOL SCIExecuteToggleProfileStorySeenUserRuleAction(SCIActionButtonContext *context) {
    id user = SCIResolveMediaForContext(context);
    NSString *pk = user ? [SCIUtils pkFromIGUser:user] : nil;
    NSString *username = user ? SCIProfileUsername(user) : nil;
    NSString *fullName = user ? SCIProfileFullName(user) : nil;
    NSString *profilePicUrl = user ? sciDirectUserResolverProfilePicURLStringFromUser(user) : nil;
    if (pk.length == 0 || username.length == 0) {
        SCINotify(kSCINotificationProfileStorySeenUserRule, @"User not found", nil, @"error_filled", SCINotificationToneError);
        return YES;
    }

    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"stories_manual_seen"];
    BOOL listed = SCIStoryManualSeenListContainsUser(pk, manualSeenEnabled);
    BOOL applies = manualSeenEnabled ? !listed : listed;

    NSString *title = applies ? @"Start Marking Stories as Seen" : @"Stop Marking Stories as Seen";
    NSString *message = applies
        ? [NSString stringWithFormat:@"Do you want to start marking stories from @%@ as seen?", username]
        : [NSString stringWithFormat:@"Do you want to stop marking stories from @%@ as seen?", username];

    [SCIUtils showConfirmation:^{
        SCIStoryToggleUserRuleForPK(pk, username, fullName, profilePicUrl);
        NSString *notificationTitle = applies
            ? [NSString stringWithFormat:@"Stories seen on for @%@", username]
            : [NSString stringWithFormat:@"Stories seen off for @%@", username];
        SCINotify(kSCINotificationProfileStorySeenUserRule, notificationTitle, nil, @"circle_check_filled", SCINotificationToneSuccess);
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIActionButtonConfigurationDidChangeNotification object:nil];
    } title:title message:message];
    return YES;
}

static BOOL SCIExecuteToggleProfileMessagesSeenUserRuleAction(SCIActionButtonContext *context) {
    id user = SCIResolveMediaForContext(context);
    NSString *pk = user ? [SCIUtils pkFromIGUser:user] : nil;
    NSString *username = user ? SCIProfileUsername(user) : nil;
    NSString *fullName = user ? SCIProfileFullName(user) : nil;
    NSString *profilePicUrl = user ? sciDirectUserResolverProfilePicURLStringFromUser(user) : nil;
    if (pk.length == 0 || username.length == 0) {
        SCINotify(kSCINotificationProfileMessagesSeenUserRule, @"User not found", nil, @"error_filled", SCINotificationToneError);
        return YES;
    }

    BOOL manualSeenEnabled = [SCIUtils getBoolPref:@"msgs_manual_seen"];
    NSDictionary *existingEntry = SCIDirectManualSeenThreadEntryForUserPK(pk, manualSeenEnabled);
    BOOL listed = (existingEntry != nil);
    BOOL applies = manualSeenEnabled ? !listed : listed;

    NSString *title = applies ? @"Start Marking Messages as Seen" : @"Stop Marking Messages as Seen";
    NSString *message = applies
        ? [NSString stringWithFormat:@"Do you want to start marking messages from %@ as seen?", (fullName.length > 0 ? fullName : [@"@" stringByAppendingString:username])]
        : [NSString stringWithFormat:@"Do you want to stop marking messages from %@ as seen?", (fullName.length > 0 ? fullName : [@"@" stringByAppendingString:username])];    [SCIUtils showConfirmation:^{
        if (listed) {
            NSString *threadId = existingEntry[@"threadId"];
            SCIDirectRemoveManualSeenThreadId(threadId, manualSeenEnabled);
            NSString *notificationTitle = [NSString stringWithFormat:@"Messages seen off for %@", (fullName.length > 0 ? fullName : [@"@" stringByAppendingString:username])];
            NSString *notificationSubtitle = SCIDirectManualSeenListTitle(manualSeenEnabled);
            SCINotify(kSCINotificationProfileMessagesSeenUserRule, notificationTitle, notificationSubtitle, @"circle_check_filled", SCINotificationToneSuccess);
            [[NSNotificationCenter defaultCenter] postNotificationName:SCIActionButtonConfigurationDidChangeNotification object:nil];
        } else {
            NSString *encodedRecipients = [[NSString stringWithFormat:@"[%@]", pk] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
            [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                              path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=%@", encodedRecipients]
                                              body:nil
                                         completion:^(NSDictionary *threadResponse, NSError *threadError) {
                NSDictionary *thread = threadResponse[@"thread"];
                NSString *threadId = SCIStringFromValue(thread[@"thread_id"] ?: thread[@"threadId"]);
                if (threadId.length == 0 || threadError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        SCINotify(kSCINotificationProfileMessagesSeenUserRule, @"No 1:1 chat thread found", @"Make sure you have an active chat with this user.", @"error_filled", SCINotificationToneError);
                    });
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSMutableDictionary *usersEntry = [@{
                        @"pk": pk,
                        @"username": username,
                        @"fullName": fullName ?: @"",
                    } mutableCopy];
                    if (profilePicUrl.length > 0) usersEntry[@"profilePicUrl"] = profilePicUrl;
                    
                    SCIDirectAddOrUpdateManualSeenThreadEntry(@{
                        @"threadId": threadId,
                        @"threadName": fullName.length > 0 ? fullName : username,
                        @"isGroup": @(NO),
                        @"users": @[usersEntry.copy],
                    }, manualSeenEnabled);

                    NSString *notificationTitle = [NSString stringWithFormat:@"Messages seen on for %@", (fullName.length > 0 ? fullName : [@"@" stringByAppendingString:username])];
                    NSString *notificationSubtitle = SCIDirectManualSeenListTitle(manualSeenEnabled);
                    SCINotify(kSCINotificationProfileMessagesSeenUserRule, notificationTitle, notificationSubtitle, @"circle_check_filled", SCINotificationToneSuccess);
                    [[NSNotificationCenter defaultCenter] postNotificationName:SCIActionButtonConfigurationDidChangeNotification object:nil];
                });
            }];
        }
    } title:title message:message];
    return YES;
}

static BOOL SCIExecuteStoryMentionsSheetAction(SCIActionButtonContext *context) {
    if (context.source != SCIActionButtonSourceStories || !context.view) {
        SCINotify(kSCINotificationStoryMentionsSheet, @"Story mentions unavailable", nil, @"error_filled", SCINotificationToneError);
        return YES;
    }

    id media = SCIResolveMediaForContext(context);
    if (!SCIStoryMediaHasMentions(media)) {
        SCINotify(kSCINotificationStoryMentionsSheet, @"No mentions found", nil, @"error_filled", SCINotificationToneError);
        return YES;
    }

    SCIPresentStoryMentionsSheet(context.view);
    return YES;
}

BOOL SCIExecuteActionIdentifier(NSString *identifier, SCIActionButtonContext *context, BOOL isDefaultTap) {
	if (identifier.length == 0 || !context) return NO;

    if ([identifier isEqualToString:kSCIActionToggleStorySeenUserRule]) {
        return SCIExecuteToggleStorySeenUserRuleAction(context);
    }
    if ([identifier isEqualToString:kSCIActionToggleProfileStorySeenUserRule]) {
        return SCIExecuteToggleProfileStorySeenUserRuleAction(context);
    }
    if ([identifier isEqualToString:kSCIActionToggleProfileMessagesSeenUserRule]) {
        return SCIExecuteToggleProfileMessagesSeenUserRuleAction(context);
    }
    if ([identifier isEqualToString:kSCIActionStoryMentionsSheet]) {
        return SCIExecuteStoryMentionsSheetAction(context);
    }
    if (context.source == SCIActionButtonSourceProfile && SCIIsProfileCopyActionIdentifier(identifier)) {
        return SCIExecuteProfileCopyAction(identifier, context);
    }
    if ([identifier isEqualToString:kSCIActionOpenTopicSettings]) {
        NSString *settingsTitle = SCIResolvedSettingsTitleForContext(context);
        if (settingsTitle.length == 0) {
            SCINotify(identifier, @"Settings unavailable", nil, @"error_filled", SCINotificationToneError);
            return YES;
        }
        SCINotify(identifier, @"Opened settings", nil, @"settings", SCINotificationToneForIconResource(@"settings"));
        [SCIUtils showSettingsForTopicTitle:settingsTitle];
        return YES;
    }
    if (context.source == SCIActionButtonSourceDirect && [identifier isEqualToString:kSCIActionDeletedMessagesLog]) {
        [SCIDeletedMessagesViewController presentFromViewController:SCIActionContextPresenter(context)];
        return YES;
    }

	id media = SCIResolveMediaForContext(context);
	NSArray<SCIResolvedMediaEntry *> *entries = SCIEntriesFromMedia(media);
    if (SCIIsBulkChildActionIdentifier(identifier)) {
        id bulkMedia = SCIResolveBulkMediaForContext(context);
        NSArray<SCIResolvedMediaEntry *> *bulkEntries = SCIDownloadableEntries(SCIEntriesFromMedia(bulkMedia));
        if (bulkEntries.count > 0) {
            media = bulkMedia ?: media;
            entries = bulkEntries;
        }
    }
	if (entries.count == 0) {
		SCINotify(identifier, @"Media not found", nil, @"error_filled", SCINotificationToneError);
		return NO;
	}

	NSInteger resolvedIndex = SCIClampedIndex(SCIResolveCurrentIndexForContext(context), (NSInteger)entries.count);
	SCIResolvedMediaEntry *currentEntry = entries[resolvedIndex];
    id metadataObject = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;

	NSString *username = (context.source == SCIActionButtonSourceDirect)
		? SCIDirectUsernameFromController(context.controller)
		: SCIUsernameFromMediaObject(media);
    if (context.source == SCIActionButtonSourceInstants) {
        NSString *explicitUsername = SCIUsernameForEntry(currentEntry, nil);
        if (explicitUsername.length > 0) {
            username = explicitUsername;
        }
    }
	if (username.length == 0) username = SCIUsernameFromMediaObject(metadataObject);
	if (username.length == 0) {
		for (SCIResolvedMediaEntry *entry in entries) {
			username = SCIUsernameFromMediaObject(entry.metadataObject ?: entry.mediaObject);
			if (username.length > 0) break;
		}
	}
	if (context.source == SCIActionButtonSourceDirect && username.length > 0) {
		NSString *sessionUsername = SCISessionUsernameFromController(context.controller);
		if (sessionUsername.length > 0 && [username caseInsensitiveCompare:sessionUsername] == NSOrderedSame) {
			username = nil;
		}
	}

	SCIGallerySaveMetadata *meta = SCIGalleryMetadata(context.source, username, metadataObject);
    SCIApplyEntryMetadata(meta, currentEntry);
	if (metadataObject != media && context.source != SCIActionButtonSourceInstants) {
		[SCIGalleryOriginController populateMetadata:meta fromMedia:media];
		if (entries.count > 1) {
			meta.sourceMediaURLString = [SCIUtils appendImgIndex:resolvedIndex toURLString:meta.sourceMediaURLString];
		}
	}

	if (isDefaultTap && !SCIActionIdentifierOpensPreview(identifier)) {
		SCIPausePlaybackForPreviewContext(context);
	}

	return SCIExecuteCommonAction(identifier, context, currentEntry, entries, resolvedIndex, username, meta, media);
}

static BOOL SCIActionButtonLegacyDiagnosticsEnabled(SCIActionButtonSource source) {
	return source == SCIActionButtonSourceFeed && SYSTEM_VERSION_LESS_THAN(@"26.0");
}

UIButton *SCIActionButtonWithTag(UIView *container, NSInteger tag) {
	UIView *existing = [container viewWithTag:tag];
	if ([existing isKindOfClass:[UIButton class]]) {
		return (UIButton *)existing;
	}
	[existing removeFromSuperview];

	SCIActionMenuButton *button = [[SCIActionMenuButton alloc] initWithSymbol:@"" pointSize:24.0 diameter:44.0];
	button.tag = tag;
	button.adjustsImageWhenHighlighted = YES;
	button.showsMenuAsPrimaryAction = NO;
	button.clipsToBounds = NO;
	button.translatesAutoresizingMaskIntoConstraints = YES;
	[container addSubview:button];
	if (SYSTEM_VERSION_LESS_THAN(@"26.0")) {
		SCILog(@"ActionButton", @"Created action button tag=%ld class=%@ container=%@ iOS=%@",
			   (long)tag,
			   NSStringFromClass(button.class),
			   NSStringFromClass(container.class),
			   [UIDevice currentDevice].systemVersion);
	}
	return button;
}

void SCIApplyButtonStyle(UIButton *button, SCIActionButtonSource source) {
	if (!button) return;

	button.tintColor = SCIActionButtonTintForSource(source);
	button.backgroundColor = UIColor.clearColor;
	button.layer.cornerRadius = 0.0;
	button.layer.shadowColor = UIColor.clearColor.CGColor;
	button.layer.shadowOpacity = 0.0;
	button.layer.shadowRadius = 0.0;
	button.layer.shadowOffset = CGSizeZero;
	button.clipsToBounds = NO;

	BOOL isChrome = [button isKindOfClass:[SCIChromeButton class]];
	if (isChrome) {
		SCIChromeButton *chromeButton = (SCIChromeButton *)button;
		chromeButton.iconTint = SCIActionButtonTintForSource(source);
		chromeButton.bubbleColor = UIColor.clearColor;

		// Reset iconView shadow by default
		chromeButton.iconView.layer.shadowColor = UIColor.clearColor.CGColor;
		chromeButton.iconView.layer.shadowOpacity = 0.0;
		chromeButton.iconView.layer.shadowRadius = 0.0;
		chromeButton.iconView.layer.shadowOffset = CGSizeZero;
		chromeButton.iconView.layer.masksToBounds = NO;
	}

	if (source == SCIActionButtonSourceReels) {
		if (isChrome) {
			SCIChromeButton *chromeButton = (SCIChromeButton *)button;
			chromeButton.iconView.layer.shadowColor = [UIColor blackColor].CGColor;
			chromeButton.iconView.layer.shadowOpacity = 0.24;
			chromeButton.iconView.layer.shadowRadius = 1.8;
			chromeButton.iconView.layer.shadowOffset = CGSizeMake(0.0, 1.0);
		} else {
			button.layer.cornerRadius = CGRectGetHeight(button.bounds) / 2.0;
			button.layer.shadowColor = [UIColor blackColor].CGColor;
			button.layer.shadowOpacity = 0.24;
			button.layer.shadowRadius = 1.8;
			button.layer.shadowOffset = CGSizeMake(0.0, 1.0);
		}
	} else if (source == SCIActionButtonSourceStories || source == SCIActionButtonSourceDirect || source == SCIActionButtonSourceInstants) {
		if (isChrome) {
			SCIChromeButton *chromeButton = (SCIChromeButton *)button;
			chromeButton.iconView.layer.shadowColor = [UIColor blackColor].CGColor;
			chromeButton.iconView.layer.shadowOpacity = 0.5;
			chromeButton.iconView.layer.shadowRadius = 2.0;
			chromeButton.iconView.layer.shadowOffset = CGSizeMake(0.0, 2.0);
		} else {
			button.layer.cornerRadius = 8.0;
			button.layer.shadowColor = [UIColor blackColor].CGColor;
			button.layer.shadowOpacity = 0.5;
			button.layer.shadowRadius = 2.0;
			button.layer.shadowOffset = CGSizeMake(0.0, 2.0);
		}
	}
}

BOOL SCIIsDirectVisualViewerAncestor(UIView *view) {
	UIViewController *ancestorController = SCIViewControllerForAncestorView(view);
	return [ancestorController isKindOfClass:NSClassFromString(@"IGDirectVisualMessageViewerController")];
}

SCIActionButtonContext *SCIActionButtonContextFromButton(UIButton *button) {
	id context = objc_getAssociatedObject(button, kSCIActionButtonContextAssocKey);
	return [context isKindOfClass:[SCIActionButtonContext class]] ? context : nil;
}

// Builds the "Bulk" section (Download All / Copy All / Select Media) for a
// carousel, titled "<sectionTitle> · N" with N the carousel item count.
// `sectionTitle`/`sectionIconName`/`collapsible` come from the user-orderable
// Bulk section so it behaves like any other section. Resolved lazily from a
// UIDeferredMenuElement so it reflects the fully-loaded carousel at the moment
// the menu opens, not whatever was available when the button was first
// configured (which is stale on the first story of a reel, etc.). Returns an
// empty array when there is no bulk media.
static NSArray<UIMenuElement *> *SCIBuildBulkMenuChildren(SCIActionButtonConfiguration *configuration,
                                                          SCIActionButtonContext *context,
                                                          NSString *sectionTitle,
                                                          NSString *sectionIconName,
                                                          BOOL collapsible) {
    id bulkMedia = SCIResolveBulkMediaForContext(context);
    NSArray<SCIResolvedMediaEntry *> *bulkEntries = SCIDownloadableEntries(SCIEntriesFromMedia(bulkMedia));
    if (bulkEntries.count <= 1) return @[];

    NSString *bulkUsername = SCIResolvedBulkUsernameForContext(context, bulkEntries, bulkMedia);
    NSArray<NSString *> *configuredBulkDownloadIdentifiers = SCIActionButtonConfiguredBulkDownloadActionsForSource(context.source);
    NSArray<NSString *> *configuredBulkCopyIdentifiers = SCIActionButtonConfiguredBulkCopyActionsForSource(context.source);

    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
    // Each bulk entry sits in its own inline group so they read as separate rows
    // divided by separator lines. Download All / Copy All carry the download / copy
    // icons (not the generic "more" icon).
    UIMenuElement *downloadAll = SCIBulkActionMenuElementForContext(context, bulkEntries, bulkUsername, bulkMedia, configuredBulkDownloadIdentifiers, @"Download All", kSCIActionDownloadAllLibrary);
    if (downloadAll) [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[downloadAll]]];
    UIMenuElement *copyAll = SCIBulkActionMenuElementForContext(context, bulkEntries, bulkUsername, bulkMedia, configuredBulkCopyIdentifiers, @"Copy All", kSCIActionDownloadAllClipboard);
    if (copyAll) [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[copyAll]]];

    // "Select Media" picker — destinations are the configured bulk actions.
    id media = SCIResolveMediaForContext(context);
    NSArray<SCIResolvedMediaEntry *> *entries = SCIEntriesFromMedia(media);
    NSInteger currentIndex = SCIResolveCurrentIndexForContext(context);
    NSMutableArray<SCIBulkSelectionDestination *> *destinations = [NSMutableArray array];
    for (NSString *identifier in SCIConfiguredBulkActionIdentifiersForSource(context.source)) {
        if (SCIIsActionVisible(context, configuration, identifier, media, entries, currentIndex)) {
            [destinations addObject:[SCIBulkSelectionDestination destinationWithIdentifier:identifier
                                                                                     title:SCIActionButtonTitleForIdentifier(identifier)
                                                                                  iconName:SCIActionDescriptorIconName(identifier)]];
        }
    }
    if (destinations.count > 0) {
        UIAction *selectMediaAction = [UIAction actionWithTitle:@"Select Media"
                                                          image:[SCIAssetUtils instagramIconNamed:@"circle_check" pointSize:22.0]
                                                     identifier:nil
                                                        handler:^(__unused UIAction *action) {
            // Re-resolve at tap time as well, in case the carousel changed.
            id tapBulkMedia = SCIResolveBulkMediaForContext(context);
            NSArray<SCIResolvedMediaEntry *> *tapBulkEntries = SCIDownloadableEntries(SCIEntriesFromMedia(tapBulkMedia));
            if (tapBulkEntries.count == 0) return;
            NSString *tapBulkUsername = SCIResolvedBulkUsernameForContext(context, tapBulkEntries, tapBulkMedia);
            NSMutableArray<SCIBulkSelectionItem *> *selectionItems = [NSMutableArray array];
            for (SCIResolvedMediaEntry *entry in tapBulkEntries) {
                [selectionItems addObject:[SCIBulkSelectionItem itemWithThumbnailURL:entry.photoURL ?: entry.videoURL
                                                                             isVideo:(entry.videoURL != nil)]];
            }
            [SCIBulkMediaSelectionViewController presentFromViewController:SCIActionContextPresenter(context)
                                                                    items:selectionItems
                                                             destinations:destinations
                                                               completion:^(NSIndexSet *selectedIndexes, NSString *destinationIdentifier) {
                NSArray<SCIResolvedMediaEntry *> *selectedEntries = [tapBulkEntries objectsAtIndexes:selectedIndexes];
                if (selectedEntries.count == 0) return;
                NSArray<SCIDownloadItemRequest *> *selectedItems = SCIBulkDownloadItemsFromEntries(selectedEntries, context.source, tapBulkUsername, tapBulkMedia);
                UIViewController *presenter = SCIActionContextPresenter(context);
                UIView *anchorView = SCIActionContextAnchorView(context);
                SCIDownloadSourceSurface surface = [SCIDownloadHelpers sourceSurfaceForActionButtonSource:context.source];
                if ([SCIDownloadHelpers performBulkDownloadIdentifier:destinationIdentifier
                                                                items:selectedItems
                                                            presenter:presenter
                                                           anchorView:anchorView
                                                        sourceSurface:surface]) {
                    return;
                }
                if ([destinationIdentifier isEqualToString:kSCIActionDownloadAllLinks]) {
                    NSArray<NSString *> *links = SCIBulkDownloadLinksFromEntries(selectedEntries, tapBulkMedia);
                    if (links.count == 0) {
                        SCINotify(destinationIdentifier, @"No links available", nil, @"error_filled", SCINotificationToneError);
                        return;
                    }
                    [UIPasteboard generalPasteboard].string = [links componentsJoinedByString:@"\n"];
                    SCINotify(destinationIdentifier, SCICopiedDownloadURLTitleForSource(context.source, YES), [NSString stringWithFormat:@"%lu item%@", (unsigned long)links.count, links.count == 1 ? @"" : @"s"], @"copy_filled", SCINotificationToneForIconResource(@"copy_filled"));
                }
            }];
        }];
        [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[selectMediaAction]]];
    }

    if (children.count == 0) return @[];
    // Present the bulk actions as their own section, styled like the other
    // collapsible sections. Title carries the carousel item count.
    NSString *baseTitle = sectionTitle.length > 0 ? sectionTitle : @"Bulk";
    NSString *title = [NSString stringWithFormat:@"%@ · %lu", baseTitle, (unsigned long)bulkEntries.count];
    UIImage *bulkIcon = [[[SCIAssetUtils instagramIconNamed:(sectionIconName.length > 0 ? sectionIconName : @"carousel") pointSize:22.0] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] imageWithTintColor:[UIColor labelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIMenuElement *section = collapsible
        ? SCISubmenuOrSingleElement(title, bulkIcon, children)
        : [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:children];
    return section ? @[ section ] : @[];
}

void SCIConfigureActionButton(UIButton *button, SCIActionButtonContext *context) {
	if (!button || !context) return;
	BOOL legacyDiagnostics = SCIActionButtonLegacyDiagnosticsEnabled(context.source);
	if (legacyDiagnostics) {
		SCILog(@"ActionButton", @"Configuring feed action button class=%@ view=%@ iOS=%@",
			   NSStringFromClass(button.class),
			   NSStringFromClass(context.view.class),
			   [UIDevice currentDevice].systemVersion);
	}

    if (!objc_getAssociatedObject(button, kSCIActionButtonConfigurationObserverAssocKey)) {
        __weak UIButton *weakObservedButton = button;
        id token = [[NSNotificationCenter defaultCenter] addObserverForName:SCIActionButtonConfigurationDidChangeNotification
                                                                      object:nil
                                                                       queue:nil
                                                                  usingBlock:^(__unused NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIButton *strongButton = weakObservedButton;
                SCIActionButtonContext *storedContext = SCIActionButtonContextFromButton(strongButton);
                if (!strongButton || !storedContext) return;
                objc_setAssociatedObject(strongButton, kSCIActionButtonMenuSignatureAssocKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
                SCIConfigureActionButton(strongButton, storedContext);
            });
        }];
        objc_setAssociatedObject(button, kSCIActionButtonConfigurationObserverAssocKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

	id media = SCIResolveMediaForContext(context);
	NSArray<SCIResolvedMediaEntry *> *entries = SCIEntriesFromMedia(media);
	NSInteger currentIndex = SCIResolveCurrentIndexForContext(context);
    SCIResolvedMediaEntry *currentEntry = nil;
    if (entries.count > 0) {
        currentEntry = entries[SCIClampedIndex(currentIndex, (NSInteger)entries.count)];
	}
	NSArray<NSString *> *visibleActions = SCIVisibleActionsForContext(context, media, entries, currentIndex);
	if (legacyDiagnostics) {
		SCILog(@"ActionButton", @"Feed action button resolved visibleActions=%lu entries=%lu currentIndex=%ld",
			   (unsigned long)visibleActions.count,
			   (unsigned long)entries.count,
			   (long)currentIndex);
	}

	if (visibleActions.count == 0) {
		button.hidden = YES;
		button.menu = nil;
		if (legacyDiagnostics) {
			SCILog(@"ActionButton", @"Feed action button hidden: no visible actions");
		}
		return;
	}

	button.hidden = NO;

	NSString *defaultIdentifier = SCIResolvedDefaultActionIdentifier(visibleActions, context.source);
	UIImage *defaultImage = SCIButtonDefaultImage(defaultIdentifier, context.source, context);
	SCISetButtonVisualImage(button, defaultImage, context.source, defaultIdentifier);
	BOOL shouldOpenMenuOnTap = [defaultIdentifier isEqualToString:kSCIActionNone];
	SCIActionButtonConfiguration *configuration = [SCIActionButtonConfiguration configurationForSource:context.source
																						  topicTitle:context.settingsTitle ?: SCIActionButtonTopicTitleForSource(context.source)
																					supportedActions:context.supportedActions ?: SCIActionButtonSupportedActionsForSource(context.source)
																					 defaultSections:SCIActionButtonDefaultSectionsForSource(context.source)];
    id bulkMedia = SCIResolveBulkMediaForContext(context);
    NSArray<SCIResolvedMediaEntry *> *bulkEntries = SCIDownloadableEntries(SCIEntriesFromMedia(bulkMedia));
	NSString *menuSignature = SCIActionButtonMenuSignature(context, configuration, visibleActions, defaultIdentifier, bulkEntries.count);
	NSString *existingSignature = objc_getAssociatedObject(button, kSCIActionButtonMenuSignatureAssocKey);
	if ([existingSignature isEqualToString:menuSignature] && button.menu != nil) {
		button.showsMenuAsPrimaryAction = shouldOpenMenuOnTap;
		objc_setAssociatedObject(button, kSCIActionButtonContextAssocKey, context, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		if (legacyDiagnostics) {
			SCILog(@"ActionButton", @"Feed action button reused menu default=%@ opensMenu=%@",
				   defaultIdentifier ?: @"(nil)",
				   shouldOpenMenuOnTap ? @"YES" : @"NO");
		}
		return;
	}

	__weak UIButton *weakButton = button;
	// No bespoke touch-down haptic: the resolved action emits its own completion haptic
	// (via SCINotify, which already respects general_disable_haptics), and the menu-open
	// (None) path uses the system context-menu haptic. A selection haptic on touch-down
	// stacked a second, wrong-feeling tick on top of those. Clear any stale one left on a
	// reused button by an earlier configure pass.
	UIAction *oldHapticAction = objc_getAssociatedObject(button, kSCIActionButtonHapticActionAssocKey);
	if (oldHapticAction) {
		[button removeAction:oldHapticAction forControlEvents:UIControlEventTouchDown];
		objc_setAssociatedObject(button, kSCIActionButtonHapticActionAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	UIAction *oldTapAction = objc_getAssociatedObject(button, kSCIActionButtonTapActionAssocKey);
	if (oldTapAction) [button removeAction:oldTapAction forControlEvents:UIControlEventTouchUpInside];

	if (shouldOpenMenuOnTap) {
		objc_setAssociatedObject(button, kSCIActionButtonTapActionAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	} else {
		UIAction *newTapAction = [UIAction actionWithHandler:^(__unused UIAction *action) {
			UIButton *strongButton = weakButton;
			SCIActionButtonContext *strongContext = SCIActionButtonContextFromButton(strongButton);
			if (!strongContext) return;

			id tapMedia = SCIResolveMediaForContext(strongContext);
			NSArray<SCIResolvedMediaEntry *> *tapEntries = SCIEntriesFromMedia(tapMedia);
			NSArray<NSString *> *tapVisibleActions = SCIVisibleActionsForContext(strongContext, tapMedia, tapEntries, SCIResolveCurrentIndexForContext(strongContext));
			NSString *tapIdentifier = SCIResolvedDefaultActionIdentifier(tapVisibleActions, strongContext.source);
			SCIExecuteActionIdentifier(tapIdentifier, strongContext, YES);
		}];
		[button addAction:newTapAction forControlEvents:UIControlEventTouchUpInside];
		objc_setAssociatedObject(button, kSCIActionButtonTapActionAssocKey, newTapAction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	NSMutableArray<UIMenuElement *> *menuElements = [NSMutableArray array];
	// Iterate the configured section order. Non-bulk sections render from their
	// visible (enabled) actions; the "bulk" section renders the derived carousel
	// actions lazily so it tracks the live carousel — both honor the user's order.
	NSArray<SCIActionMenuSection *> *visibleSectionsList = [configuration visibleSections];
	NSMutableDictionary<NSString *, SCIActionMenuSection *> *visibleSectionsByID = [NSMutableDictionary dictionary];
	for (SCIActionMenuSection *visibleSection in visibleSectionsList) {
		if (visibleSection.identifier) visibleSectionsByID[visibleSection.identifier] = visibleSection;
	}
	BOOL firstGroup = YES;
	for (SCIActionMenuSection *orderedSection in configuration.sections) {
		if ([orderedSection.identifier isEqualToString:@"bulk"]) {
			NSString *bulkTitle = orderedSection.title;
			NSString *bulkIconName = orderedSection.iconName;
			BOOL bulkCollapsible = orderedSection.collapsible;
			UIDeferredMenuElement *bulkDeferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
				completion(SCIBuildBulkMenuChildren(configuration, context, bulkTitle, bulkIconName, bulkCollapsible));
			}];
			if (!firstGroup) {
				[menuElements addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[]]];
			}
			[menuElements addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[ bulkDeferred ]]];
			firstGroup = NO;
			continue;
		}
		SCIActionMenuSection *group = visibleSectionsByID[orderedSection.identifier];
		if (!group) continue;
		NSString *title = group.title;
		NSArray<NSString *> *identifiers = group.actions;
		if (![identifiers isKindOfClass:[NSArray class]] || identifiers.count == 0) continue;

		NSMutableArray<UIMenuElement *> *groupElements = [NSMutableArray array];
		UIMenuElement *profileCopyInfoElement = nil; // divided from the rest of Copy by a separator line
		for (NSString *identifier in identifiers) {
			if (![visibleActions containsObject:identifier]) continue;

            if (context.source == SCIActionButtonSourceProfile && [identifier isEqualToString:kSCIActionProfileCopyInfo]) {
                NSMutableArray<UIMenuElement *> *copyChildren = [NSMutableArray array];
                for (NSString *copyIdentifier in SCIProfileConfiguredCopyInfoActions()) {
                    [copyChildren addObject:[UIAction actionWithTitle:SCIActionButtonTitleForIdentifier(copyIdentifier)
                                                                image:SCIActionButtonMenuIconForContext(copyIdentifier, context, 22.0)
                                                           identifier:nil
                                                              handler:^(__unused UIAction *action) {
                        UIButton *strongButton = weakButton;
                        if (strongButton) {
                            objc_setAssociatedObject(strongButton, kSCIActionButtonLastMenuActionAssocKey, copyIdentifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
                        }
                        SCIExecuteActionIdentifier(copyIdentifier, context, NO);
                    }]];
                }
                profileCopyInfoElement = SCISubmenuOrSingleElement(SCIActionButtonDisplayTitleForContext(identifier, context, currentEntry),
                                                                   SCIActionButtonMenuIconForContext(identifier, context, 22.0),
                                                                   copyChildren);
            } else {
                UIAction *menuAction = [UIAction actionWithTitle:SCIActionButtonDisplayTitleForContext(identifier, context, currentEntry)
                                                           image:SCIActionButtonMenuIconForContext(identifier, context, 22.0)
                                                      identifier:nil
                                                         handler:^(__unused UIAction *action) {
                    UIButton *strongButton = weakButton;
                    if (strongButton) {
                        objc_setAssociatedObject(strongButton, kSCIActionButtonLastMenuActionAssocKey, identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
                    }
                    SCIExecuteActionIdentifier(identifier, context, NO);
                }];
                [groupElements addObject:menuAction];
            }
		}

        // On profile, divide the "Copy Info" submenu from the rest of the Copy
        // section with a separator line (two inline groups).
        if (profileCopyInfoElement) {
            if (groupElements.count > 0) {
                UIMenu *restGroup = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:[groupElements copy]];
                UIMenu *infoGroup = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[profileCopyInfoElement]];
                [groupElements removeAllObjects];
                [groupElements addObject:restGroup];
                [groupElements addObject:infoGroup];
            } else {
                [groupElements addObject:profileCopyInfoElement];
            }
        }

        if (groupElements.count == 0) continue;
		if (!firstGroup) {
			[menuElements addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[]]];
		}
		if (group.collapsible && groupElements.count > 1) {
			UIImage *sectionImage = nil;
			if (group.iconName.length > 0) {
				sectionImage = [[[SCIAssetUtils instagramIconNamed:group.iconName pointSize:22.0] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] imageWithTintColor:[UIColor labelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
			}
			UIMenu *submenu = [UIMenu menuWithTitle:title ?: @""
											 image:sectionImage
										identifier:nil
										   options:0
										  children:groupElements];
			[menuElements addObject:[UIMenu menuWithTitle:@""
													image:nil
											   identifier:nil
												  options:UIMenuOptionsDisplayInline
												 children:@[submenu]]];
		} else {
			[menuElements addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:groupElements]];
		}
		firstGroup = NO;
	}

    if (context.source == SCIActionButtonSourceProfile) {
        UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
            id freshMedia = SCIResolveMediaForContext(context);
            completion(SCIProfileInfoMenuElements(freshMedia));
        }];
        [menuElements addObject:[UIMenu menuWithTitle:@""
                                                image:nil
                                            identifier:nil
                                                options:UIMenuOptionsDisplayInline
                                                children:@[deferred]]];
    }

	if (menuElements.count == 0) {
		for (NSString *identifier in visibleActions) {
			[menuElements addObject:[UIAction actionWithTitle:SCIActionButtonDisplayTitleForContext(identifier, context, currentEntry)
														image:SCIActionButtonMenuIconForContext(identifier, context, 22.0)
												   identifier:nil
													  handler:^(__unused UIAction *action) {
				UIButton *strongButton = weakButton;
				if (strongButton) {
					objc_setAssociatedObject(strongButton, kSCIActionButtonLastMenuActionAssocKey, identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
				}
				SCIExecuteActionIdentifier(identifier, context, NO);
			}]];
		}
	}

    UIMenu *fullMenu = [UIMenu menuWithTitle:@"" children:menuElements];
    button.menu = fullMenu;
	button.showsMenuAsPrimaryAction = shouldOpenMenuOnTap;
	objc_setAssociatedObject(button, kSCIActionButtonContextAssocKey, context, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(button, kSCIActionButtonMenuSignatureAssocKey, menuSignature, OBJC_ASSOCIATION_COPY_NONATOMIC);
	if (legacyDiagnostics) {
		SCILog(@"ActionButton", @"Feed action button menu complete elements=%lu default=%@ opensMenu=%@",
			   (unsigned long)menuElements.count,
			   defaultIdentifier ?: @"(nil)",
			   shouldOpenMenuOnTap ? @"YES" : @"NO");
	}
}

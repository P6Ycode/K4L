#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "ActionButtonCore.h"
#import "SCIActionButtonConfiguration.h"
#import "SCIActionDescriptor.h"
#import "../../Downloader/Download.h"
#import "../../Downloader/BulkDownload.h"
#import "../../InstagramHeaders.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../../Settings/SCIPreferences.h"
#import "../MediaDownload/SCIMediaQualityManager.h"
#import "../MediaPreview/SCIFullScreenMediaPlayer.h"
#import "../MediaPreview/SCIMediaItem.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGalleryOriginController.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../Audio/SCIAudioDownloadCoordinator.h"
#import "../Audio/SCIAudioItem.h"
#import "../Stories/SCIStoryContext.h"
#import "../UI/SCINotificationCenter.h"
#import "../UI/SCIChrome.h"

NSString * const kSCIActionNone = @"none";
NSString * const kSCIActionDownloadLibrary = @"download_library";
NSString * const kSCIActionDownloadShare = @"download_share";
NSString * const kSCIActionCopyDownloadLink = @"copy_download_link";
NSString * const kSCIActionCopyMedia = @"copy_media";
NSString * const kSCIActionDownloadGallery = @"download_gallery";
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
NSString * const kSCIActionRepost = @"repost";
NSString * const kSCIActionToggleStorySeenUserRule = @"toggle_story_seen_user_rule";
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
		videoExts = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"avi", @"webm", @"hevc"]];
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
	return [NSString stringWithFormat:@"%@_action_btn_default_action", SCIActionButtonTopicKeyForSource(source)];
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
    return nil;
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

static NSArray<UIMenuElement *> *SCIProfileInfoMenuElements(id user) {
    if (!user) return @[];

    NSMutableArray<UIMenuElement *> *infoItems = [NSMutableArray array];
    NSString *privacyText = SCIProfilePrivacyText(user);
    if (privacyText.length > 0) {
        [infoItems addObject:SCIProfileDisabledInfoAction(privacyText, [privacyText containsString:@"Private"] ? @"lock" : @"unlock")];
    }

    NSString *followers = SCIProfileInfoString(SCIProfileNumberValue(SCIKVCObject(user, @"followerCount")));
    if (followers.length > 0) {
        [infoItems addObject:SCIProfileDisabledInfoAction([NSString stringWithFormat:@"Followers: %@", followers], @"users")];
    }

    NSString *following = SCIProfileInfoString(SCIProfileNumberValue(SCIKVCObject(user, @"followingCount")));
    if (following.length > 0) {
        [infoItems addObject:SCIProfileDisabledInfoAction([NSString stringWithFormat:@"Following: %@", following], @"users")];
    }

    return infoItems;
}

static NSString *SCIProfileInfoSignature(id user) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *privacy = SCIProfilePrivacyText(user);
    if (privacy.length > 0) [parts addObject:privacy];
    NSString *followers = SCIProfileInfoString(SCIProfileNumberValue(SCIKVCObject(user, @"followerCount")));
    if (followers.length > 0) [parts addObject:[NSString stringWithFormat:@"followers:%@", followers]];
    NSString *following = SCIProfileInfoString(SCIProfileNumberValue(SCIKVCObject(user, @"followingCount")));
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
        id value = SCIObjectForSelector(media, selectorName);
        if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) return YES;
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

static void SCIPlayActionButtonTapHaptic(void) {
	UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
	[feedback selectionChanged];
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
    if (instantsURL) {
        SCIResolvedMediaEntry *entry = [[SCIResolvedMediaEntry alloc] init];
        entry.mediaObject = mediaObject;
        entry.metadataObject = mediaObject;
        if (SCIIsVideoExtension(instantsURL.pathExtension)) {
            entry.videoURL = instantsURL;
        } else {
            entry.photoURL = instantsURL;
        }
        return entry;
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

static NSArray<SCIResolvedMediaEntry *> *SCIEntriesFromMedia(id media) {
	if (!media) return @[];

	NSMutableArray<SCIResolvedMediaEntry *> *entries = [NSMutableArray array];

    SCIResolvedMediaEntry *directEntry = SCIEntryFromMediaObject(media);
    if (directEntry) {
        return @[directEntry];
    }

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

	NSArray *items = SCIArrayFromCollection(SCIObjectForSelector(media, @"items"));
	if (items.count == 0) items = SCIArrayFromCollection(SCIKVCObject(media, @"items"));

    if (items.count == 0) {
        for (NSString *selectorName in @[@"carouselMedia", @"carouselChildren", @"children", @"carousel_media"]) {
            items = SCIArrayFromCollection(SCIObjectForSelector(media, selectorName));
            if (items.count == 0) {
                items = SCIArrayFromCollection(SCIKVCObject(media, selectorName));
            }
            if (items.count > 0) {
                break;
            }
        }
    }

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

	for (SCIResolvedMediaEntry *entry in entries) {
		NSURL *url = entry.videoURL ?: entry.photoURL;
		if (!url) continue;
        id metadataObject = entry.metadataObject ?: entry.mediaObject ?: media;

		SCIMediaItem *item = [SCIMediaItem itemWithFileURL:url];
		item.mediaType = entry.videoURL ? SCIMediaItemTypeVideo : SCIMediaItemTypeImage;
		item.gallerySaveSource = SCIGallerySourceForActionSource(source);
		item.galleryMetadata = SCIGalleryMetadata(source, username, metadataObject);
        item.sourceMediaObject = metadataObject;
		if (username.length > 0) item.title = username;
		[items addObject:item];
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
        if ([identifier isEqualToString:kSCIActionDownloadShare]) {
            width = height = 38.0;
        } else if ([identifier isEqualToString:kSCIActionNone] ||
                   [identifier isEqualToString:kSCIActionViewThumbnail] ||
                   [identifier isEqualToString:kSCIActionDownloadGallery] ||
                   [identifier isEqualToString:kSCIActionCopyMedia]) {
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

static NSArray<SCIBulkDownloadItem *> *SCIBulkDownloadItemsFromEntries(NSArray<SCIResolvedMediaEntry *> *entries,
                                                                       SCIActionButtonSource source,
                                                                       NSString *username,
                                                                       id media) {
    NSMutableArray<SCIBulkDownloadItem *> *items = [NSMutableArray array];
    for (SCIResolvedMediaEntry *entry in entries) {
        NSURL *url = entry.videoURL ?: entry.photoURL;
        if (!url) continue;
        BOOL isVideo = (entry.videoURL != nil);
        id metadataObject = entry.metadataObject ?: entry.mediaObject ?: media;
        SCIGallerySaveMetadata *meta = SCIGalleryMetadata(source, username, metadataObject);
        NSString *linkString = SCIBestDownloadURLForMediaObject(metadataObject).absoluteString ?: url.absoluteString;
        [items addObject:[SCIBulkDownloadItem itemWithURL:url
                                            fileExtension:SCIExtensionForURL(url, isVideo)
                                                  isVideo:isVideo
                                                 metadata:meta
                                               linkString:linkString]];
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

static UIMenuElement *SCIBulkActionMenuElementForContext(SCIActionButtonContext *context,
                                                         NSArray<SCIResolvedMediaEntry *> *entries,
                                                         NSString *username,
                                                         id media,
                                                         NSArray<NSString *> *configuredIdentifiers,
                                                         NSString *title,
                                                         NSString *iconIdentifier) {
    UIMenu *menu = SCIBulkActionMenuForContext(context, entries, username, media, configuredIdentifiers);
    if (!menu) return nil;
    return [UIMenu menuWithTitle:title ?: @""
                           image:SCIActionButtonMenuIconForContext(iconIdentifier ?: kSCIActionDownloadAll, context, 22.0)
                      identifier:nil
                         options:0
                        children:menu.children];
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

    return entry.videoURL != nil;
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
    if ([identifier isEqualToString:kSCIActionStoryMentionsSheet]) {
        return context.source == SCIActionButtonSourceStories && SCIStoryMediaHasMentions(media);
    }
    if (context.source == SCIActionButtonSourceProfile && [identifier isEqualToString:kSCIActionProfileCopyInfo]) {
        return media != nil;
    }
    if (context.source == SCIActionButtonSourceProfile && [identifier isEqualToString:kSCIActionOpenTopicSettings]) {
        return SCIResolvedSettingsTitleForContext(context).length > 0;
    }

    if (entries.count == 0) return NO;

	NSInteger idx = SCIClampedIndex(currentIndex, (NSInteger)entries.count);
	SCIResolvedMediaEntry *currentEntry = entries[idx];
	NSURL *currentURL = currentEntry.videoURL ?: currentEntry.photoURL;

	if ([identifier isEqualToString:kSCIActionViewThumbnail]) {
		return currentEntry.videoURL != nil;
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
        if (SCIDownloadableEntries(entries).count <= 1) return NO;
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
											  NSString *defaultIdentifier) {
    NSString *dynamicStoryRuleTitle = [visibleActions containsObject:kSCIActionToggleStorySeenUserRule]
        ? SCIStoryCurrentUserRuleActionTitle(SCIStoryContextForActionButtonContext(context))
        : @"";
    NSString *profileInfoSignature = (context.source == SCIActionButtonSourceProfile)
        ? SCIProfileInfoSignature(SCIResolveMediaForContext(context))
        : @"";
	return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@",
			SCIActionButtonTopicKeyForSource(context.source),
			defaultIdentifier ?: @"",
			[visibleActions componentsJoinedByString:@","],
            dynamicStoryRuleTitle ?: @"",
            profileInfoSignature ?: @"",
			configuration.dictionaryRepresentation.description ?: @""];
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

    NSArray<SCIBulkDownloadItem *> *bulkItems = SCIBulkDownloadItemsFromEntries(downloadableEntries, context.source, username, media);
    UIViewController *presenter = SCIActionContextPresenter(context);
    UIView *anchorView = SCIActionContextAnchorView(context);

    if ([identifier isEqualToString:kSCIActionDownloadAllLibrary]) {
        [SCIBulkDownloadCoordinator performOperation:SCIBulkDownloadOperationSaveToPhotos
                                               items:bulkItems
                                    actionIdentifier:identifier
                                           presenter:presenter
                                          anchorView:anchorView];
        return YES;
    }
    if ([identifier isEqualToString:kSCIActionDownloadAllShare]) {
        [SCIBulkDownloadCoordinator performOperation:SCIBulkDownloadOperationShare
                                               items:bulkItems
                                    actionIdentifier:identifier
                                           presenter:presenter
                                          anchorView:anchorView];
        return YES;
    }
    if ([identifier isEqualToString:kSCIActionDownloadAllGallery]) {
        [SCIBulkDownloadCoordinator performOperation:SCIBulkDownloadOperationSaveToGallery
                                               items:bulkItems
                                    actionIdentifier:identifier
                                           presenter:presenter
                                          anchorView:anchorView];
        return YES;
    }
    if ([identifier isEqualToString:kSCIActionDownloadAllClipboard]) {
        [SCIBulkDownloadCoordinator performOperation:SCIBulkDownloadOperationCopyMedia
                                               items:bulkItems
                                    actionIdentifier:identifier
                                           presenter:presenter
                                          anchorView:anchorView];
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
            audioAction = SCIAudioActionShare;
        }
        [SCIAudioDownloadCoordinator performAction:audioAction
                                             item:audioItem
                                        presenter:SCIActionContextPresenter(context)
                                       sourceView:SCIActionContextAnchorView(context)
                                         metadata:meta
                           notificationIdentifier:identifier];
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
                           notificationIdentifier:identifier];
        return YES;
    }

	if ([identifier isEqualToString:kSCIActionDownloadLibrary] ||
		[identifier isEqualToString:kSCIActionDownloadShare] ||
		[identifier isEqualToString:kSCIActionDownloadGallery]) {
		if (!currentURL) {
			SCINotify(identifier, @"No downloadable media", nil, @"error_filled", SCINotificationToneError);
			return YES;
		}

		DownloadAction action = saveToPhotos;
		if ([identifier isEqualToString:kSCIActionDownloadShare]) action = share;
		else if ([identifier isEqualToString:kSCIActionDownloadGallery]) action = saveToGallery;

        id mediaForDownload = currentEntry.metadataObject ?: currentEntry.mediaObject ?: media;
        UIViewController *presenter = SCIActionContextPresenter(context);
        UIView *anchorView = SCIActionContextAnchorView(context);
        if ([SCIMediaQualityManager handleDownloadAction:action
                                             identifier:identifier
                                              presenter:presenter
                                             sourceView:anchorView
                                              mediaObject:mediaForDownload
                                                photoURL:currentEntry.photoURL
                                                videoURL:currentEntry.videoURL
                                         galleryMetadata:meta
                                           showProgress:shouldNotify]) {
            return YES;
        }

        SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:shouldNotify];
        delegate.notificationIdentifier = identifier;
        delegate.pendingGallerySaveMetadata = meta;
        [delegate downloadFileWithURL:currentURL fileExtension:SCIExtensionForURL(currentURL, isVideo) hudLabel:nil];
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
        if ([SCIMediaQualityManager handleCopyActionWithIdentifier:identifier
                                                         presenter:SCIActionContextPresenter(context)
                                                        sourceView:SCIActionContextAnchorView(context)
                                                         mediaObject:mediaForCopy
                                                           photoURL:currentEntry.photoURL
                                                           videoURL:currentEntry.videoURL
                                                      showProgress:shouldNotify]) {
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
		if (!currentEntry.videoURL) {
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
        NSString *explicitUsername = SCIStringFromValue(SCIObjectForSelector(metadataObject, @"sourceUsername") ?: SCIKVCObject(metadataObject, @"sourceUsername"));
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
	NSString *menuSignature = SCIActionButtonMenuSignature(context, configuration, visibleActions, defaultIdentifier);
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
	UIAction *oldHapticAction = objc_getAssociatedObject(button, kSCIActionButtonHapticActionAssocKey);
	if (oldHapticAction) [button removeAction:oldHapticAction forControlEvents:UIControlEventTouchDown];
	UIAction *newHapticAction = [UIAction actionWithHandler:^(__unused UIAction *action) {
		SCIPlayActionButtonTapHaptic();
	}];
	[button addAction:newHapticAction forControlEvents:UIControlEventTouchDown];
	objc_setAssociatedObject(button, kSCIActionButtonHapticActionAssocKey, newHapticAction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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

    NSArray<NSString *> *configuredBulkDownloadIdentifiers = SCIActionButtonConfiguredBulkDownloadActionsForSource(context.source);
    NSArray<NSString *> *configuredBulkCopyIdentifiers = SCIActionButtonConfiguredBulkCopyActionsForSource(context.source);
    BOOL hasBulkMedia = (SCIDownloadableEntries(entries).count > 1);
    NSString *bulkUsername = hasBulkMedia ? SCIResolvedBulkUsernameForContext(context, entries, media) : nil;
	NSMutableArray<UIMenuElement *> *menuElements = [NSMutableArray array];
	NSArray<SCIActionMenuSection *> *menuSections = [configuration visibleSections];
	BOOL firstGroup = YES;
	for (SCIActionMenuSection *group in menuSections) {
		NSString *title = group.title;
		NSArray<NSString *> *identifiers = group.actions;
		if (![identifiers isKindOfClass:[NSArray class]] || identifiers.count == 0) continue;

		NSMutableArray<UIMenuElement *> *groupElements = [NSMutableArray array];
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
                [groupElements addObject:[UIMenu menuWithTitle:SCIActionButtonDisplayTitleForContext(identifier, context, currentEntry)
                                                         image:SCIActionButtonMenuIconForContext(identifier, context, 22.0)
                                                    identifier:nil
                                                       options:0
                                                      children:copyChildren]];
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

        if (groupElements.count == 0) continue;
        if (hasBulkMedia && [group.identifier isEqualToString:@"download"]) {
            UIMenuElement *bulkElement = SCIBulkActionMenuElementForContext(context, entries, bulkUsername, media, configuredBulkDownloadIdentifiers, @"Download All", kSCIActionDownloadAll);
            if (bulkElement) {
                NSArray<UIMenuElement *> *nonBulkElements = [groupElements copy];
                [groupElements removeAllObjects];
                
                UIMenu *nonBulkInlineGroup = [UIMenu menuWithTitle:@""
                                                            image:nil
                                                       identifier:nil
                                                          options:UIMenuOptionsDisplayInline
                                                         children:nonBulkElements];
                [groupElements addObject:nonBulkInlineGroup];
                [groupElements addObject:bulkElement];
            }
        } else if (hasBulkMedia && [group.identifier isEqualToString:@"copy"]) {
            UIMenuElement *bulkElement = SCIBulkActionMenuElementForContext(context, entries, bulkUsername, media, configuredBulkCopyIdentifiers, @"Copy All", kSCIActionDownloadAll);
            if (bulkElement) {
                NSArray<UIMenuElement *> *nonBulkElements = [groupElements copy];
                [groupElements removeAllObjects];
                
                UIMenu *nonBulkInlineGroup = [UIMenu menuWithTitle:@""
                                                            image:nil
                                                       identifier:nil
                                                          options:UIMenuOptionsDisplayInline
                                                         children:nonBulkElements];
                [groupElements addObject:nonBulkInlineGroup];
                [groupElements addObject:bulkElement];
            }
        }
		if (!firstGroup) {
			[menuElements addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[]]];
		}
		if (group.collapsible) {
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
        NSArray<UIMenuElement *> *profileInfoItems = SCIProfileInfoMenuElements(media);
        if (profileInfoItems.count > 0) {
            [menuElements addObject:[UIMenu menuWithTitle:@""
                                                    image:nil
                                               identifier:nil
                                                  options:UIMenuOptionsDisplayInline
                                                 children:profileInfoItems]];
        }
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

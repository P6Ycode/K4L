#import <UIKit/UIKit.h>

#import "../Shared/ActionButton/ActionButtonCore.h"
#import "../Shared/ActionButton/SPKActionMenuSection.h"
#import "SPKSetting.h"

NS_ASSUME_NONNULL_BEGIN

NSDictionary *SPKTopicSection(NSString *header, NSArray *rows, NSString *_Nullable footer);
FOUNDATION_EXPORT CGFloat const SPKSettingsCellIconPointSize;
UIImage *SPKSettingsIcon(NSString *name);
UIImage *SPKSettingsSystemIcon(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight);
SPKSetting *SPKSettingApplyIconTint(SPKSetting *setting, UIColor *_Nullable tintColor);
SPKSetting *SPKSettingApplySelectedMenuIcon(SPKSetting *setting, UIImage *_Nullable fallbackIcon);
SPKSetting *SPKTopicNavigationSetting(NSString *title, NSString *iconName, CGFloat iconSize, NSArray *sections);
SPKSetting *SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSource source);
SPKSetting *SPKActionButtonConfigurationNavigationSetting(SPKActionButtonSource source, NSString *topicTitle, NSArray<NSString *> *supportedActions, NSArray<SPKActionMenuSection *> *defaultSections);
UIMenu *SPKReelsTapControlMenu(void);
UIMenu *SPKMainFeedModeMenu(void);
UIMenu *SPKNavigationIconOrderingMenu(void);
UIMenu *SPKLaunchTabMenu(void);
UIMenu *SPKSwipeBetweenTabsMenu(void);
UIMenu *SPKLiquidGlassTabBarStateMenu(void);
UIMenu *SPKSwipeCloseCommentsDirectionMenu(void);
UIMenu *SPKCacheAutoClearMenu(void);
UIMenu *SPKNotificationProgressSubtitleStyleMenu(void);
UIMenu *SPKNotificationPillPositionMenu(void);
UIMenu *SPKMediaVideoQualityMenu(void);
UIMenu *SPKMediaPhotoQualityMenu(void);
UIMenu *SPKGalleryShortcutTargetMenu(void);

NS_ASSUME_NONNULL_END

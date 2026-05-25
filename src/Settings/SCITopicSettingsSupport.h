#import <UIKit/UIKit.h>

#import "SCISetting.h"
#import "../Shared/ActionButton/ActionButtonCore.h"
#import "../Shared/ActionButton/SCIActionMenuSection.h"

NS_ASSUME_NONNULL_BEGIN

NSDictionary *SCITopicSection(NSString *header, NSArray *rows, NSString * _Nullable footer);
FOUNDATION_EXPORT CGFloat const SCISettingsCellIconPointSize;
UIImage *SCISettingsIcon(NSString *name);
UIImage *SCISettingsSystemIcon(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight);
SCISetting *SCISettingApplyIconTint(SCISetting *setting, UIColor * _Nullable tintColor);
SCISetting *SCISettingApplySelectedMenuIcon(SCISetting *setting, UIImage * _Nullable fallbackIcon);
SCISetting *SCITopicNavigationSetting(NSString *title, NSString *iconName, CGFloat iconSize, NSArray *sections);
UIMenu *SCIActionButtonDefaultActionMenu(NSString *defaultsKey, NSString *topicTitle, NSArray<NSString *> *supportedActions);
SCISetting *SCIActionButtonConfigurationNavigationSetting(SCIActionButtonSource source, NSString *topicTitle, NSArray<NSString *> *supportedActions, NSArray<SCIActionMenuSection *> *defaultSections);
UIMenu *SCIReelsTapControlMenu(void);
UIMenu *SCINavigationIconOrderingMenu(void);
UIMenu *SCISwipeBetweenTabsMenu(void);
UIMenu *SCISwipeCloseCommentsDirectionMenu(void);
UIMenu *SCICacheAutoClearMenu(void);
UIMenu *SCINotificationProgressSubtitleStyleMenu(void);
UIMenu *SCIMediaVideoQualityMenu(void);
UIMenu *SCIMediaPhotoQualityMenu(void);
UIMenu *SCIGalleryShortcutTargetMenu(void);
NSArray *SCIDevExampleSections(void);

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT CGFloat const SCIMediaChromeTopBarContentHeight;
FOUNDATION_EXPORT CGFloat const SCIMediaChromeBottomBarHeight;
FOUNDATION_EXPORT CGFloat const SCIMediaChromeFloatingBottomBarHeight;
FOUNDATION_EXPORT CGFloat const SCIMediaChromeFloatingBottomBarBottomMargin;

UIBlurEffect *SCIMediaChromeBlurEffect(void);
void SCIApplyMediaChromeNavigationBar(UINavigationBar *bar);

UILabel *SCIMediaChromeTitleLabel(NSString *text);
UIImage *SCIMediaChromeTopIcon(NSString *resourceName);
UIImage *SCIMediaChromeBottomIcon(NSString *resourceName);
UIImage *SCIMediaChromeTopBarIcon(NSString *resourceName);
UIBarButtonItem *SCIMediaChromeTopBarButtonItem(NSString *resourceName, id target, SEL action);
UIBarButtonItem *SCIMediaChromeTopBarButtonItemWithTint(NSString *resourceName, id target, SEL action, UIColor *_Nullable tintColor, NSString *_Nullable accessibilityLabel);
// Top-bar button styled like the others but backed by a UIButton that opens
// `menu` as its primary action (single tap), matching the gallery chrome.
UIBarButtonItem *SCIMediaChromeTopBarMenuButtonItem(NSString *resourceName, UIMenu *menu, NSString *_Nullable accessibilityLabel);
void SCIMediaChromeSetLeadingTopBarItems(UINavigationItem *navigationItem, NSArray<UIBarButtonItem *> *items);
void SCIMediaChromeSetTrailingTopBarItems(UINavigationItem *navigationItem, NSArray<UIBarButtonItem *> *items);

UIView *SCIMediaChromeInstallBottomBar(UIView *hostView);
UIButton *SCIMediaChromeBottomButton(NSString *resourceName, NSString *accessibilityLabel);
UIStackView *SCIMediaChromeInstallBottomRow(UIView *bottomBar, NSArray<UIView *> *row);

NS_ASSUME_NONNULL_END

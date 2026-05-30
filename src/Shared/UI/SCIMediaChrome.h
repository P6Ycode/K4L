#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT CGFloat const SCIMediaChromeTopBarContentHeight;

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

// Bottom toolbar. These build a native UIToolbar (driven through the hosting
// UINavigationController) instead of a hand-positioned floating view. On iOS 26
// the system renders it as a Liquid Glass pill and positions it correctly on
// every device; on earlier systems it is a standard translucent bottom bar.

/// Normalized, template-rendered icon sized for bottom toolbar buttons.
UIImage *SCIMediaChromeBottomBarIcon(NSString *resourceName);

/// Creates a bar button item for the bottom toolbar. `target`/`action` may be
/// nil when the item is driven purely by a menu assigned later.
UIBarButtonItem *SCIMediaChromeBottomBarButtonItem(NSString *resourceName, NSString *accessibilityLabel, id _Nullable target, SEL _Nullable action);

/// Wraps content items with spacers to satisfy Liquid Glass grouping rules.
/// iOS 26: keeps the items adjacent inside a single centered glass capsule.
/// iOS <= 18: distributes the items evenly across a standard bottom bar.
NSArray<UIBarButtonItem *> *SCIMediaChromeBottomToolbarItems(NSArray<UIBarButtonItem *> *contentItems);

/// Like SCIMediaChromeBottomToolbarItems, but breaks `trailingItems` out into a
/// separate glass capsule (iOS 26). Both groups stay centered together with a
/// fixed gap splitting the capsule between them. On iOS <= 18 every item is
/// distributed evenly across the standard bottom bar.
NSArray<UIBarButtonItem *> *SCIMediaChromeBottomToolbarItemsWithTrailingGroup(NSArray<UIBarButtonItem *> *primaryItems, NSArray<UIBarButtonItem *> *trailingItems);

/// Applies media-chrome styling (tint, dark appearance) to a bottom toolbar.
void SCIMediaChromeConfigureBottomToolbar(UIToolbar *toolbar);

/// Toggles a translucent material backing on the navigation bar and bottom
/// toolbar. Use when content scrolls/zooms behind the bars so they stay legible.
/// No-op on iOS 26+, where Liquid Glass already adapts automatically.
void SCIMediaChromeSetBarsMaterialActive(UINavigationController *navigationController, BOOL active);

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT CGFloat const SPKMediaChromeTopBarContentHeight;

UIBlurEffect *SPKMediaChromeBlurEffect(void);
void SPKApplyMediaChromeNavigationBar(UINavigationBar *bar);

/// Shared navigation controller for Sparkle's modal stacks (settings, gallery,
/// downloads, etc.). Applies the media-chrome navigation bar styling (custom
/// back chevron everywhere, neutral non-blue tint and scroll-driven material on
/// iOS 18 and lower) and a title-less back button, so every Sparkle top bar is
/// consistent. Liquid Glass is left to the system on iOS 26+.
@interface SPKChromeNavigationController : UINavigationController
@end

UILabel *SPKMediaChromeTitleLabel(NSString *text);
UIImage *SPKMediaChromeTopIcon(NSString *resourceName);
UIImage *SPKMediaChromeBottomIcon(NSString *resourceName);
UIImage *SPKMediaChromeTopBarIcon(NSString *resourceName);
UIBarButtonItem *SPKMediaChromeTopBarButtonItem(NSString *resourceName, id target, SEL action);
UIBarButtonItem *SPKMediaChromeTopBarButtonItemWithTint(NSString *resourceName, id target, SEL action,
                                                        UIColor *_Nullable tintColor,
                                                        NSString *_Nullable accessibilityLabel);
/// Same as WithTint, but lets the caller pick the bar-button style. Use
/// `UIBarButtonItemStyleDone` for a prominent/emphasized button (rendered as a
/// prominent glass capsule on iOS 26 and bold on earlier systems); others should
/// stay `UIBarButtonItemStylePlain`.
UIBarButtonItem *SPKMediaChromeTopBarButtonItemWithStyle(NSString *resourceName, id target, SEL action,
                                                         UIBarButtonItemStyle style,
                                                         UIColor *_Nullable tintColor,
                                                         NSString *_Nullable accessibilityLabel);
// Top-bar button styled like the others but backed by a UIButton that opens
// `menu` as its primary action (single tap), matching the gallery chrome.
UIBarButtonItem *SPKMediaChromeTopBarMenuButtonItem(NSString *resourceName, UIMenu *menu, NSString *_Nullable accessibilityLabel);
/// Same as the menu button above, but with a caller-supplied tint (e.g. IG blue
/// for a prominent "Done"-equivalent menu button).
UIBarButtonItem *SPKMediaChromeTopBarMenuButtonItemWithTint(NSString *resourceName, UIMenu *menu, UIColor *_Nullable tintColor, NSString *_Nullable accessibilityLabel);
/// A real (non custom-view) bar button item that opens `menu` on tap and honors
/// `style` — use `UIBarButtonItemStyleDone` so a menu-backed Done matches a plain
/// Done button (prominent glass on iOS 26). Doesn't support forced menu ordering.
UIBarButtonItem *SPKMediaChromeTopBarMenuBarButtonItemWithStyle(NSString *resourceName, UIMenu *menu, UIBarButtonItemStyle style, UIColor *_Nullable tintColor, NSString *_Nullable accessibilityLabel);
void SPKMediaChromeSetLeadingTopBarItems(UINavigationItem *navigationItem, NSArray<UIBarButtonItem *> *items);
void SPKMediaChromeSetTrailingTopBarItems(UINavigationItem *navigationItem, NSArray<UIBarButtonItem *> *items);

// Bottom toolbar. These build a native UIToolbar (driven through the hosting
// UINavigationController) instead of a hand-positioned floating view. On iOS 26
// the system renders it as a Liquid Glass pill and positions it correctly on
// every device; on earlier systems it is a standard translucent bottom bar.

/// Normalized, template-rendered icon sized for bottom toolbar buttons.
UIImage *SPKMediaChromeBottomBarIcon(NSString *resourceName);

/// Creates a bar button item for the bottom toolbar. `target`/`action` may be
/// nil when the item is driven purely by a menu assigned later.
UIBarButtonItem *SPKMediaChromeBottomBarButtonItem(NSString *resourceName, NSString *accessibilityLabel, id _Nullable target, SEL _Nullable action);

/// Wraps content items with spacers to satisfy Liquid Glass grouping rules.
/// iOS 26: keeps the items adjacent inside a single centered glass capsule.
/// iOS <= 18: distributes the items evenly across a standard bottom bar.
NSArray<UIBarButtonItem *> *SPKMediaChromeBottomToolbarItems(NSArray<UIBarButtonItem *> *contentItems);

/// Like SPKMediaChromeBottomToolbarItems, but breaks `trailingItems` out into a
/// separate glass capsule (iOS 26). Both groups stay centered together with a
/// fixed gap splitting the capsule between them. On iOS <= 18 every item is
/// distributed evenly across the standard bottom bar.
NSArray<UIBarButtonItem *> *SPKMediaChromeBottomToolbarItemsWithTrailingGroup(NSArray<UIBarButtonItem *> *primaryItems, NSArray<UIBarButtonItem *> *trailingItems);

/// Applies media-chrome styling (tint, dark appearance) to a bottom toolbar.
void SPKMediaChromeConfigureBottomToolbar(UIToolbar *toolbar);

/// Toggles a translucent material backing on the navigation bar and bottom
/// toolbar. Use when content scrolls/zooms behind the bars so they stay legible.
/// No-op on iOS 26+, where Liquid Glass already adapts automatically.
void SPKMediaChromeSetBarsMaterialActive(UINavigationController *navigationController, BOOL active);

NS_ASSUME_NONNULL_END

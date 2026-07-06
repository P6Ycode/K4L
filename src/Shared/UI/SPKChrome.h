// Capture-aware chrome primitives. SPKChromeCanvas handles redaction via
// the UITextField secure-canvas technique; SPKChromeButton / SPKChromeLabel
// own the full visible hierarchy so IG's liquid glass can't wrap them.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted by the settings toggle so live instances can refresh `secureTextEntry`.
FOUNDATION_EXPORT NSNotificationName const SPKHideUIOnCapturePreferenceDidChangeNotification;

// MARK: - SPKChromeCanvas

@interface SPKChromeCanvas : UIView
@property (nonatomic, readonly) UIView *contentContainer;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// YES if `field` is the secure-canvas helper owned by SPKChromeCanvas.
/// Used by the Instants screenshot bypass to skip our own redaction fields.
BOOL SPKChromeCanvasOwnsSecureField(UITextField *field);

#ifdef __cplusplus
}
#endif

// MARK: - SPKChromeButton

@interface SPKChromeButton : UIButton
- (instancetype)initWithSymbol:(NSString *)symbol
                     pointSize:(CGFloat)pointSize
                      diameter:(CGFloat)diameter NS_DESIGNATED_INITIALIZER;

@property (nonatomic, assign, readonly) CGFloat diameter;
@property (nonatomic, assign) CGSize customSize;
@property (nonatomic, assign) UIOffset iconOffset;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, assign) CGFloat symbolPointSize;
@property (nonatomic, copy) UIColor *iconTint;
@property (nonatomic, copy) UIColor *bubbleColor;
/// `symbolName` is SF-only. For IG-styled glyphs use `setIconResource:` or
/// assign `iconView.image` directly with a baked image.
@property (nonatomic, strong, readonly) UIImageView *iconView;

/// IG-styled glyph via `+[SPKAssetUtils instagramIconNamed:]`. Clears `symbolName`.
- (void)setIconResource:(NSString *)resourceName pointSize:(CGFloat)pointSize;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end

#ifdef __cplusplus
extern "C" {
#endif

// Bar button item whose customView is an SPKChromeButton. `outButton` yields
// the inner button for menu/tint/etc.
UIBarButtonItem *SPKChromeBarButtonItem(NSString *symbol,
                                        CGFloat pointSize,
                                        id _Nullable target,
                                        SEL _Nullable action,
                                        SPKChromeButton *_Nullable *_Nullable outButton);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

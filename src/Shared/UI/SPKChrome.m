#import "SPKChrome.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import <objc/runtime.h>

NSNotificationName const SPKHideUIOnCapturePreferenceDidChangeNotification = @"SPKHideUIOnCapturePreferenceDidChangeNotification";

static char kSPKChromeOwnedSecureFieldKey;

BOOL SPKChromeCanvasOwnsSecureField(UITextField *field) {
    if (!field)
        return NO;
    return objc_getAssociatedObject(field, &kSPKChromeOwnedSecureFieldKey) != nil;
}

static void spkPinEdges(UIView *view, UIView *host) {
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:host.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
    ]];
}

static UIView *spkFindCanvasDeep(UIView *root, NSInteger depth) {
    if (!root || depth > 4)
        return nil;

    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) containsString:@"CanvasView"])
            return subview;

        UIView *found = spkFindCanvasDeep(subview, depth + 1);
        if (found)
            return found;
    }

    return nil;
}

@interface SPKChromeCanvas ()
@property (nonatomic, strong) UITextField *secureField;
@property (nonatomic, strong, nullable) UIView *canvas;
@end

@implementation SPKChromeCanvas

+ (NSHashTable<SPKChromeCanvas *> *)instances {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSHashTable weakObjectsHashTable];
    });
    return table;
}

+ (void)ensureObserverInstalled {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:SPKHideUIOnCapturePreferenceDidChangeNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *note) {
                                                          for (SPKChromeCanvas *canvas in [SPKChromeCanvas instances]) {
                                                              [canvas applyPref];
                                                          }
                                                      }];
    });
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [SPKChromeCanvas ensureObserverInstalled];

        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.clipsToBounds = NO;

        _secureField = [UITextField new];
        // Tag so the Instants screenshot bypass leaves our own redaction alone.
        objc_setAssociatedObject(_secureField, &kSPKChromeOwnedSecureFieldKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        _secureField.userInteractionEnabled = NO;
        _secureField.alpha = 1.0;
        _secureField.translatesAutoresizingMaskIntoConstraints = NO;
        _secureField.autocorrectionType = UITextAutocorrectionTypeNo;
        _secureField.spellCheckingType = UITextSpellCheckingTypeNo;
        _secureField.smartDashesType = UITextSmartDashesTypeNo;
        _secureField.smartQuotesType = UITextSmartQuotesTypeNo;
        _secureField.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
        _secureField.autocapitalizationType = UITextAutocapitalizationTypeNone;

        [self applyPref];
        [[SPKChromeCanvas instances] addObject:self];
        [self attachCanvasIfPossible];
    }

    return self;
}

- (UIView *)contentContainer {
    return _canvas ?: self;
}

- (void)setUserInteractionEnabled:(BOOL)userInteractionEnabled {
    [super setUserInteractionEnabled:userInteractionEnabled];
    _canvas.userInteractionEnabled = userInteractionEnabled;
}

- (void)applyPref {
    BOOL enabled = [SPKUtils getBoolPref:@"interface_hide_ui_on_capture"];
    if (_secureField.secureTextEntry != enabled) {
        _secureField.secureTextEntry = enabled;
        [self setNeedsLayout];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self attachCanvasIfPossible];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self attachCanvasIfPossible];
}

- (void)attachCanvasIfPossible {
    if (_canvas.superview == self)
        return;

    // Force the secure field to lay out so iOS materialises the CanvasView.
    [_secureField layoutIfNeeded];

    UIView *canvas = spkFindCanvasDeep(_secureField, 0);
    if (!canvas)
        return;

    NSMutableArray<UIView *> *stashedViews = [NSMutableArray array];
    for (UIView *subview in self.subviews) {
        if (subview != canvas)
            [stashedViews addObject:subview];
    }

    // Steal the CanvasView from the text field and pin it edge-to-edge.
    [canvas removeFromSuperview];
    canvas.translatesAutoresizingMaskIntoConstraints = NO;
    canvas.userInteractionEnabled = self.userInteractionEnabled;
    canvas.clipsToBounds = NO;
    [self insertSubview:canvas atIndex:0];
    spkPinEdges(canvas, self);

    _canvas = canvas;

    for (UIView *view in stashedViews) {
        [view removeFromSuperview];
        [canvas addSubview:view];
    }
}

@end

@interface SPKChromeButton () {
    NSLayoutConstraint *_widthConstraint;
    NSLayoutConstraint *_heightConstraint;
    NSLayoutConstraint *_centerXConstraint;
    NSLayoutConstraint *_centerYConstraint;
    CGSize _customSize;
    UIOffset _iconOffset;
}
@property (nonatomic, strong) SPKChromeCanvas *chromeCanvas;
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong, readwrite) UIImageView *iconView;
@end

@implementation SPKChromeButton

- (instancetype)initWithSymbol:(NSString *)symbol pointSize:(CGFloat)pointSize diameter:(CGFloat)diameter {
    self = [super initWithFrame:CGRectMake(0.0, 0.0, diameter, diameter)];

    if (self) {
        _diameter = diameter;
        _symbolName = symbol.copy;
        _symbolPointSize = pointSize;
        _iconTint = UIColor.whiteColor;
        _bubbleColor = [UIColor colorWithWhite:0.0 alpha:0.4];

        [self buildChrome];
    }

    return self;
}

- (void)buildChrome {
    self.adjustsImageWhenHighlighted = NO;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _chromeCanvas = [SPKChromeCanvas new];
    _chromeCanvas.userInteractionEnabled = NO;
    [self addSubview:_chromeCanvas];
    spkPinEdges(_chromeCanvas, self);

    _bubbleView = [UIView new];
    _bubbleView.userInteractionEnabled = NO;
    _bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
    _bubbleView.backgroundColor = _bubbleColor;
    _bubbleView.layer.cornerRadius = _diameter / 2.0;
    _bubbleView.clipsToBounds = YES;

    _iconView = [UIImageView new];
    _iconView.userInteractionEnabled = NO;
    _iconView.contentMode = UIViewContentModeCenter;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.tintColor = _iconTint;

    [self reloadIcon];

    UIView *host = _chromeCanvas.contentContainer;
    [host addSubview:_bubbleView];
    [host addSubview:_iconView];

    spkPinEdges(_bubbleView, host);

    _widthConstraint = [self.widthAnchor constraintEqualToConstant:_diameter];
    _heightConstraint = [self.heightAnchor constraintEqualToConstant:_diameter];
    _centerXConstraint = [_iconView.centerXAnchor constraintEqualToAnchor:host.centerXAnchor constant:_iconOffset.horizontal];
    _centerYConstraint = [_iconView.centerYAnchor constraintEqualToAnchor:host.centerYAnchor constant:_iconOffset.vertical];

    [NSLayoutConstraint activateConstraints:@[
        _widthConstraint,
        _heightConstraint,
        _centerXConstraint,
        _centerYConstraint
    ]];
}

- (CGSize)intrinsicContentSize {
    if (_customSize.width > 0.0 && _customSize.height > 0.0) {
        return _customSize;
    }
    return CGSizeMake(_diameter, _diameter);
}

- (CGSize)customSize {
    return _customSize;
}

- (void)setCustomSize:(CGSize)customSize {
    _customSize = customSize;
    if (_widthConstraint) {
        _widthConstraint.constant = customSize.width;
    }
    if (_heightConstraint) {
        _heightConstraint.constant = customSize.height;
    }
    [self invalidateIntrinsicContentSize];
}

- (UIOffset)iconOffset {
    return _iconOffset;
}

- (void)setIconOffset:(UIOffset)iconOffset {
    _iconOffset = iconOffset;
    if (_centerXConstraint) {
        _centerXConstraint.constant = iconOffset.horizontal;
    }
    if (_centerYConstraint) {
        _centerYConstraint.constant = iconOffset.vertical;
    }
    [self setNeedsLayout];
}

- (void)setSymbolName:(NSString *)symbolName {
    _symbolName = symbolName.copy;
    [self reloadIcon];
}

- (void)setSymbolPointSize:(CGFloat)symbolPointSize {
    _symbolPointSize = symbolPointSize;
    [self reloadIcon];
}

- (void)setIconTint:(UIColor *)iconTint {
    _iconTint = iconTint;
    _iconView.tintColor = iconTint;
}

- (void)setBubbleColor:(UIColor *)bubbleColor {
    _bubbleColor = bubbleColor;
    _bubbleView.backgroundColor = bubbleColor;
}

- (void)reloadIcon {
    // Empty symbolName → leave iconView.image alone (caller may have set a
    // direct image via setIconResource:).
    if (!_symbolName.length)
        return;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:_symbolPointSize weight:UIImageSymbolWeightSemibold];
    _iconView.image = [UIImage systemImageNamed:_symbolName withConfiguration:config];
}

- (void)setIconResource:(NSString *)resourceName pointSize:(CGFloat)pointSize {
    _symbolName = nil;
    _iconView.image = resourceName.length
                          ? [SPKAssetUtils instagramIconNamed:resourceName pointSize:pointSize renderingMode:UIImageRenderingModeAlwaysTemplate]
                          : nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) / 2.0;
    if (_bubbleView.layer.cornerRadius != radius)
        _bubbleView.layer.cornerRadius = radius;

    UIView *host = _chromeCanvas.contentContainer;
    if (host.layer.shadowOpacity > 0.0) {
        host.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:host.bounds cornerRadius:host.layer.cornerRadius].CGPath;
    } else {
        host.layer.shadowPath = nil;
    }

    if (self.layer.shadowOpacity > 0.0) {
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.layer.cornerRadius].CGPath;
    } else {
        self.layer.shadowPath = nil;
    }
}

@end

UIBarButtonItem *SPKChromeBarButtonItem(NSString *symbol, CGFloat pointSize, id target, SEL action, SPKChromeButton **outButton) {
    SPKChromeButton *button = [[SPKChromeButton alloc] initWithSymbol:symbol pointSize:pointSize diameter:44.0];
    button.iconOffset = UIOffsetMake(-2.0, 0.0);
    button.bubbleColor = UIColor.clearColor;

    if (target && action) {
        [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    }

    if (outButton)
        *outButton = button;
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

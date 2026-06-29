#import "SPKDeletedMessagesAvatarView.h"
#import "SPKDeletedMessagesAvatarCache.h"
#import "../../../Utils.h"
#import "../../../AssetUtils.h"

@interface SPKDeletedMessagesAvatarView ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *placeholderView;
@property (nonatomic, copy) NSString *currentPK;
// Default placeholder fills ~72% of the circle; the group glyph is pinned to its
// native 24pt so a small asset isn't upscaled.
@property (nonatomic, strong) NSLayoutConstraint *placeholderW;
@property (nonatomic, strong) NSLayoutConstraint *placeholderH;
@property (nonatomic, strong) NSLayoutConstraint *placeholderFixedW;
@property (nonatomic, strong) NSLayoutConstraint *placeholderFixedH;
@end

@implementation SPKDeletedMessagesAvatarView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.backgroundColor = [SPKUtils SPKColor_InstagramTertiaryBackground];

        _placeholderView = [UIImageView new];
        _placeholderView.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderView.contentMode = UIViewContentModeScaleAspectFit;
        _placeholderView.tintColor = [SPKUtils SPKColor_InstagramSecondaryText];
        _placeholderView.image = [SPKAssetUtils instagramIconNamed:@"user_circle" pointSize:44.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        [self addSubview:_placeholderView];

        _imageView = [UIImageView new];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _imageView.hidden = YES;
        [self addSubview:_imageView];

        _placeholderW = [_placeholderView.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.72];
        _placeholderH = [_placeholderView.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.72];
        _placeholderFixedW = [_placeholderView.widthAnchor constraintEqualToConstant:24.0];
        _placeholderFixedH = [_placeholderView.heightAnchor constraintEqualToConstant:24.0];
        _placeholderW.active = YES;
        _placeholderH.active = YES;

        [NSLayoutConstraint activateConstraints:@[
            [_imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_placeholderView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_placeholderView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.width / 2.0;
}

// Toggle the placeholder between the default ~72%-of-circle sizing and a fixed
// native 24pt (group glyph — avoid upscaling a small asset).
- (void)setPlaceholderFixed24:(BOOL)fixed {
    self.placeholderW.active = !fixed;
    self.placeholderH.active = !fixed;
    self.placeholderFixedW.active = fixed;
    self.placeholderFixedH.active = fixed;
}

- (void)prepareForReuse {
    self.currentPK = nil;
    self.imageView.image = nil;
    self.imageView.hidden = YES;
    self.placeholderView.hidden = NO;
    [self setPlaceholderFixed24:NO];
    self.placeholderView.image = [SPKAssetUtils instagramIconNamed:@"user_circle" pointSize:44.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (void)configureAsGroupWithThreadId:(NSString *)threadId photoURL:(NSString *)photoURL {
    // Filesystem-safe cache key (the cache only sanitizes "/", so avoid ":").
    NSString *cacheKey = threadId.length ? [@"grp_" stringByAppendingString:threadId] : nil;
    self.currentPK = cacheKey;

    // Native 24pt group glyph placeholder (don't upscale the small asset).
    UIImage *glyph = nil;
    for (NSString *name in @[@"group", @"people", @"members"]) {
        glyph = [SPKAssetUtils instagramIconNamed:name pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        if (glyph) break;
    }
    self.placeholderView.image = glyph ?: [SPKAssetUtils instagramIconNamed:@"user_circle" pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    [self setPlaceholderFixed24:YES];
    self.imageView.hidden = YES;
    self.placeholderView.hidden = NO;

    if (!photoURL.length || !cacheKey.length) return;   // no custom photo — keep glyph

    UIImage *warm = [[SPKDeletedMessagesAvatarCache shared] cachedImageForPK:cacheKey];
    if (warm) { [self applyImage:warm]; return; }

    __weak typeof(self) weakSelf = self;
    NSString *requested = cacheKey;
    [[SPKDeletedMessagesAvatarCache shared] avatarForPK:cacheKey urlString:photoURL completion:^(UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !image) return;
        if (![strongSelf.currentPK isEqualToString:requested]) return;
        [strongSelf applyImage:image];
    }];
}

- (void)configureWithPK:(NSString *)pk urlString:(NSString *)urlString {
    self.currentPK = pk;
    [self setPlaceholderFixed24:NO];
    self.placeholderView.image = [SPKAssetUtils instagramIconNamed:@"user_circle" pointSize:44.0 renderingMode:UIImageRenderingModeAlwaysTemplate];

    UIImage *warm = [[SPKDeletedMessagesAvatarCache shared] cachedImageForPK:pk];
    if (warm) {
        [self applyImage:warm];
        return;
    }

    self.imageView.hidden = YES;
    self.placeholderView.hidden = NO;

    __weak typeof(self) weakSelf = self;
    NSString *requestedPK = pk;
    [[SPKDeletedMessagesAvatarCache shared] avatarForPK:pk urlString:urlString completion:^(UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !image) return;
        // Guard against cell reuse — only apply if the view still wants this PK.
        if (![strongSelf.currentPK isEqualToString:requestedPK]) return;
        [strongSelf applyImage:image];
    }];
}

- (void)applyImage:(UIImage *)image {
    self.imageView.image = image;
    self.imageView.hidden = NO;
    self.placeholderView.hidden = YES;
}

@end

#import "SPKProfileAnalyzerAvatarView.h"
#import "SPKProfileAnalyzerAvatarCache.h"
#import "../../../Utils.h"
#import "../../../AssetUtils.h"

@interface SPKProfileAnalyzerAvatarView ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *placeholderView;
@property (nonatomic, copy) NSString *currentPK;
@end

@implementation SPKProfileAnalyzerAvatarView

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

        [NSLayoutConstraint activateConstraints:@[
            [_imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_placeholderView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_placeholderView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_placeholderView.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.72],
            [_placeholderView.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.72],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.width / 2.0;
}

- (void)prepareForReuse {
    self.currentPK = nil;
    self.imageView.image = nil;
    self.imageView.hidden = YES;
    self.placeholderView.hidden = NO;
}

- (void)configureWithPK:(NSString *)pk urlString:(NSString *)urlString {
    self.currentPK = pk;

    UIImage *warm = [[SPKProfileAnalyzerAvatarCache shared] cachedImageForPK:pk];
    if (warm) {
        [self applyImage:warm];
        return;
    }

    self.imageView.hidden = YES;
    self.placeholderView.hidden = NO;

    __weak typeof(self) weakSelf = self;
    NSString *requestedPK = pk;
    [[SPKProfileAnalyzerAvatarCache shared] avatarForPK:pk urlString:urlString completion:^(UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !image) return;
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

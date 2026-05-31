#import "SCIGalleryGridCell.h"
#import "SCIGalleryFile.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"

@interface SCIGalleryGridCell ()

@property (nonatomic, strong) SCIGalleryFile *file;
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) CAGradientLayer *bottomScrim;
@property (nonatomic, strong) CAGradientLayer *topScrim;
@property (nonatomic, strong) UIImageView *sourceBadge;
@property (nonatomic, strong) UIView *sourceBadgeBackground;
@property (nonatomic, strong) UIImageView *videoBadge;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIImageView *favoriteBadge;
@property (nonatomic, strong) UIImageView *selectionBadge;
@property (nonatomic, strong) NSLayoutConstraint *favoriteTrailingConstraint;

@end

@implementation SCIGalleryGridCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.clipsToBounds = YES;
        self.contentView.layer.cornerRadius = 6.0;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];

        _thumbnailView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnailView.clipsToBounds = YES;
        [self.contentView addSubview:_thumbnailView];

        // Bottom gradient scrim so the video glyph / duration stay legible over
        // bright thumbnails. Sits above the thumbnail, below the badges.
        _bottomScrim = [CAGradientLayer layer];
        _bottomScrim.colors = @[(id)[UIColor clearColor].CGColor,
                                (id)[[UIColor blackColor] colorWithAlphaComponent:0.55].CGColor];
        _bottomScrim.startPoint = CGPointMake(0.5, 0.45);
        _bottomScrim.endPoint = CGPointMake(0.5, 1.0);
        _bottomScrim.hidden = YES;
        [self.contentView.layer addSublayer:_bottomScrim];

        // Top gradient scrim keeps the source badge / favorite legible.
        _topScrim = [CAGradientLayer layer];
        _topScrim.colors = @[(id)[[UIColor blackColor] colorWithAlphaComponent:0.45].CGColor,
                             (id)[UIColor clearColor].CGColor];
        _topScrim.startPoint = CGPointMake(0.5, 0.0);
        _topScrim.endPoint = CGPointMake(0.5, 0.55);
        _topScrim.hidden = YES;
        [self.contentView.layer addSublayer:_topScrim];

        // Source-type badge (top-left): dark rounded chip + glyph.
        _sourceBadgeBackground = [[UIView alloc] initWithFrame:CGRectZero];
        _sourceBadgeBackground.translatesAutoresizingMaskIntoConstraints = NO;
        _sourceBadgeBackground.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        _sourceBadgeBackground.layer.cornerRadius = 10.0;
        _sourceBadgeBackground.layer.cornerCurve = kCACornerCurveContinuous;
        _sourceBadgeBackground.hidden = YES;
        [self.contentView addSubview:_sourceBadgeBackground];

        _sourceBadge = [[UIImageView alloc] initWithFrame:CGRectZero];
        _sourceBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _sourceBadge.tintColor = [UIColor whiteColor];
        _sourceBadge.contentMode = UIViewContentModeScaleAspectFit;
        [_sourceBadgeBackground addSubview:_sourceBadge];

        _videoBadge = [[UIImageView alloc] initWithFrame:CGRectZero];
        _videoBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _videoBadge.image = [SCIAssetUtils instagramIconNamed:@"video_filled" pointSize:13.0];
        _videoBadge.tintColor = [UIColor whiteColor];
        _videoBadge.contentMode = UIViewContentModeScaleAspectFit;
        _videoBadge.hidden = YES;
        [self.contentView addSubview:_videoBadge];

        _durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _durationLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        _durationLabel.textColor = [UIColor whiteColor];
        _durationLabel.textAlignment = NSTextAlignmentRight;
        _durationLabel.hidden = YES;
        [self.contentView addSubview:_durationLabel];

        _usernameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _usernameLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        _usernameLabel.textColor = [UIColor whiteColor];
        _usernameLabel.textAlignment = NSTextAlignmentLeft;
        _usernameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _usernameLabel.hidden = YES;
        [_usernameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_usernameLabel];

        _favoriteBadge = [[UIImageView alloc] initWithFrame:CGRectZero];
        _favoriteBadge.translatesAutoresizingMaskIntoConstraints = NO;
        UIImage *favImg = [SCIAssetUtils instagramIconNamed:@"heart_filled" pointSize:16.0];
        _favoriteBadge.image = favImg;
        _favoriteBadge.contentMode = UIViewContentModeScaleAspectFit;
        _favoriteBadge.tintColor = [SCIUtils SCIColor_InstagramFavorite];
        _favoriteBadge.hidden = YES;
        [self.contentView addSubview:_favoriteBadge];

        _selectionBadge = [[UIImageView alloc] initWithFrame:CGRectZero];
        _selectionBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _selectionBadge.contentMode = UIViewContentModeScaleAspectFit;
        _selectionBadge.tintColor = [UIColor whiteColor];
        _selectionBadge.hidden = YES;
        [self.contentView addSubview:_selectionBadge];

        _favoriteTrailingConstraint = [_favoriteBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6];

        [NSLayoutConstraint activateConstraints:@[
            [_thumbnailView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_thumbnailView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_thumbnailView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_thumbnailView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

            // Source badge (top-left).
            [_sourceBadgeBackground.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6],
            [_sourceBadgeBackground.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_sourceBadgeBackground.widthAnchor constraintEqualToConstant:20],
            [_sourceBadgeBackground.heightAnchor constraintEqualToConstant:20],
            [_sourceBadge.centerXAnchor constraintEqualToAnchor:_sourceBadgeBackground.centerXAnchor],
            [_sourceBadge.centerYAnchor constraintEqualToAnchor:_sourceBadgeBackground.centerYAnchor],
            [_sourceBadge.widthAnchor constraintEqualToConstant:13],
            [_sourceBadge.heightAnchor constraintEqualToConstant:13],

            // Video glyph + duration (bottom-right).
            [_durationLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6],
            [_durationLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],

            [_videoBadge.trailingAnchor constraintEqualToAnchor:_durationLabel.leadingAnchor constant:-4],
            [_videoBadge.centerYAnchor constraintEqualToAnchor:_durationLabel.centerYAnchor],
            [_videoBadge.widthAnchor constraintEqualToConstant:14],
            [_videoBadge.heightAnchor constraintEqualToConstant:14],

            // Username caption (bottom-left), kept clear of the video/duration.
            [_usernameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6],
            [_usernameLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            [_usernameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_videoBadge.leadingAnchor constant:-6],

            [_favoriteBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_favoriteBadge.widthAnchor constraintEqualToConstant:16],
            [_favoriteBadge.heightAnchor constraintEqualToConstant:16],

            [_selectionBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_selectionBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6],
            [_selectionBadge.widthAnchor constraintEqualToConstant:20],
            [_selectionBadge.heightAnchor constraintEqualToConstant:20],

            _favoriteTrailingConstraint,
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // Bottom scrim spans the lower third of the cell.
    CGFloat bottomHeight = MAX(28.0, height * 0.34);
    self.bottomScrim.frame = CGRectMake(0.0, height - bottomHeight, width, bottomHeight);
    // Top scrim spans the upper quarter.
    CGFloat topHeight = MAX(24.0, height * 0.26);
    self.topScrim.frame = CGRectMake(0.0, 0.0, width, topHeight);
    [CATransaction commit];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.file = nil;
    self.thumbnailView.image = nil;
    self.videoBadge.hidden = YES;
    self.durationLabel.hidden = YES;
    self.durationLabel.text = nil;
    self.usernameLabel.hidden = YES;
    self.usernameLabel.text = nil;
    self.sourceBadgeBackground.hidden = YES;
    self.sourceBadge.image = nil;
    self.bottomScrim.hidden = YES;
    self.topScrim.hidden = YES;
    self.favoriteBadge.hidden = YES;
    self.selectionBadge.hidden = YES;
    self.selectionBadge.image = nil;
    self.selectionBadge.alpha = 0.0;
    self.favoriteTrailingConstraint.constant = -6;
}

static NSString *SCIGalleryGridFormatDuration(double seconds) {
    if (seconds <= 0.0 || !isfinite(seconds)) return nil;
    NSInteger total = (NSInteger)llround(seconds);
    NSInteger h = total / 3600;
    NSInteger m = (total % 3600) / 60;
    NSInteger s = total % 60;
    if (h > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

- (UIImage *)selectionBadgeImageSelected:(BOOL)selected {
    NSString *resourceName = selected ? @"circle_check_filled" : @"circle";
    return [SCIAssetUtils instagramIconNamed:resourceName pointSize:20.0];
}

- (void)configureWithGalleryFile:(SCIGalleryFile *)file
                 selectionMode:(BOOL)selectionMode
                      selected:(BOOL)selected {
    [self configureWithGalleryFile:file
                     selectionMode:selectionMode
                          selected:selected
                       showsSource:NO
                     showsUsername:NO];
}

- (void)configureWithGalleryFile:(SCIGalleryFile *)file
                 selectionMode:(BOOL)selectionMode
                      selected:(BOOL)selected
                    showsSource:(BOOL)showsSource
                  showsUsername:(BOOL)showsUsername {
    self.file = file;
    UIImage *thumb = [SCIGalleryFile loadThumbnailForFile:file];
    if (thumb) {
        self.thumbnailView.image = thumb;
    } else {
        self.thumbnailView.image = nil;
        __weak typeof(self) weakSelf = self;
        [SCIGalleryFile generateThumbnailForFile:file completion:^(BOOL success) {
            if (success && weakSelf && weakSelf.file == file) {
                UIImage *newThumb = [UIImage imageWithContentsOfFile:[file thumbnailPath]];
                if (newThumb) {
                    weakSelf.thumbnailView.image = newThumb;
                }
            }
        }];
    }

    BOOL isVideo = (file.mediaType == SCIGalleryMediaTypeVideo);
    BOOL isAudio = (file.mediaType == SCIGalleryMediaTypeAudio);
    BOOL hasTypeBadge = isVideo || isAudio;
    self.videoBadge.image = [SCIAssetUtils instagramIconNamed:(isAudio ? @"audio" : @"video_filled") pointSize:13.0];
    self.videoBadge.hidden = !hasTypeBadge;

    NSString *durationText = hasTypeBadge ? SCIGalleryGridFormatDuration(file.durationSeconds) : nil;
    self.durationLabel.text = durationText;
    self.durationLabel.hidden = (durationText == nil);

    // Source-type badge (top-left).
    if (showsSource) {
        NSString *symbol = [SCIGalleryFile symbolNameForSource:(SCIGallerySource)file.source];
        UIImage *icon = [SCIAssetUtils instagramIconNamed:symbol pointSize:13.0];
        self.sourceBadge.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.sourceBadgeBackground.hidden = (icon == nil);
    } else {
        self.sourceBadge.image = nil;
        self.sourceBadgeBackground.hidden = YES;
    }

    // Username caption (bottom-left), truncated to fit.
    NSString *username = file.sourceUsername.length > 0 ? file.sourceUsername : nil;
    if (showsUsername && username) {
        self.usernameLabel.text = [NSString stringWithFormat:@"@%@", username];
        self.usernameLabel.hidden = NO;
    } else {
        self.usernameLabel.text = nil;
        self.usernameLabel.hidden = YES;
    }

    // Scrims only when there is overlay content to keep legible.
    BOOL hasBottomOverlay = hasTypeBadge || (showsUsername && username != nil);
    self.bottomScrim.hidden = !hasBottomOverlay;
    self.topScrim.hidden = !(showsSource && !self.sourceBadgeBackground.hidden);

    self.favoriteBadge.hidden = !file.isFavorite;

    [self setSelectionMode:selectionMode selected:selected animated:NO];
}

- (void)setSelectionMode:(BOOL)selectionMode selected:(BOOL)selected animated:(BOOL)animated {
    self.selectionBadge.image = selectionMode ? [self selectionBadgeImageSelected:selected] : nil;
    if (selectionMode) {
        self.selectionBadge.hidden = NO;
    }
    self.favoriteTrailingConstraint.constant = selectionMode ? -30.0 : -6.0;

    void (^applyState)(void) = ^{
        self.selectionBadge.alpha = selectionMode ? 1.0 : 0.0;
        [self.contentView layoutIfNeeded];
    };
    void (^finishState)(void) = ^{
        self.selectionBadge.hidden = !selectionMode;
    };

    if (animated) {
        [UIView animateWithDuration:0.22
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:applyState
                         completion:^(__unused BOOL finished) {
            finishState();
        }];
    } else {
        applyState();
        finishState();
    }
}

@end

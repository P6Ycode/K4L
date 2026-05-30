#import "SCIDeletedMessagesSenderCell.h"
#import "SCIDeletedMessagesAvatarView.h"
#import "SCIDeletedMessagesDate.h"
#import "../../../Utils.h"
#import "../../../AssetUtils.h"

NSString *const SCIDeletedMessagesSenderCellReuseID = @"SCIDeletedMessagesSenderCell";

static CGFloat const kSCIAvatarSize = 52.0;

static NSString *SCIDeletedMessagesSenderPreview(SCIDeletedMessageGroup *group);

@interface SCIDeletedMessagesSenderCell ()
@property (nonatomic, strong) SCIDeletedMessagesAvatarView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *pinBadge;
@property (nonatomic, strong) UIImageView *previewIcon;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIStackView *previewRow;
@end

@implementation SCIDeletedMessagesSenderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
        self.selectedBackgroundView = [UIView new];
        self.selectedBackgroundView.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];

        _avatarView = [[SCIDeletedMessagesAvatarView alloc] initWithFrame:CGRectZero];
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_avatarView];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        _nameLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
        [_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        _pinBadge = [UIImageView new];
        _pinBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _pinBadge.contentMode = UIViewContentModeScaleAspectFit;
        _pinBadge.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
        _pinBadge.image = [SCIAssetUtils instagramIconNamed:@"pin_filled" pointSize:12.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        _pinBadge.hidden = YES;
        [_pinBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _pinBadge]];
        nameRow.translatesAutoresizingMaskIntoConstraints = NO;
        nameRow.axis = UILayoutConstraintAxisHorizontal;
        nameRow.alignment = UIStackViewAlignmentCenter;
        nameRow.spacing = 5.0;
        [self.contentView addSubview:nameRow];

        _previewIcon = [UIImageView new];
        _previewIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _previewIcon.contentMode = UIViewContentModeScaleAspectFit;
        _previewIcon.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
        [_previewIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [NSLayoutConstraint activateConstraints:@[
            [_previewIcon.widthAnchor constraintEqualToConstant:14.0],
            [_previewIcon.heightAnchor constraintEqualToConstant:14.0],
        ]];

        _previewLabel = [UILabel new];
        _previewLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _previewLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
        _previewLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];

        _previewRow = [[UIStackView alloc] initWithArrangedSubviews:@[_previewIcon, _previewLabel]];
        _previewRow.translatesAutoresizingMaskIntoConstraints = NO;
        _previewRow.axis = UILayoutConstraintAxisHorizontal;
        _previewRow.alignment = UIStackViewAlignmentCenter;
        _previewRow.spacing = 5.0;
        [self.contentView addSubview:_previewRow];

        _timeLabel = [UILabel new];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _timeLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
        _timeLabel.textColor = [SCIUtils SCIColor_InstagramTertiaryText];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [_timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_timeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatarView.widthAnchor constraintEqualToConstant:kSCIAvatarSize],
            [_avatarView.heightAnchor constraintEqualToConstant:kSCIAvatarSize],

            [nameRow.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12.0],
            [nameRow.topAnchor constraintEqualToAnchor:_avatarView.topAnchor constant:4.0],
            [nameRow.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8.0],

            [_previewRow.leadingAnchor constraintEqualToAnchor:nameRow.leadingAnchor],
            [_previewRow.topAnchor constraintEqualToAnchor:nameRow.bottomAnchor constant:3.0],
            [_previewRow.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8.0],

            [_timeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_timeLabel.topAnchor constraintEqualToAnchor:nameRow.topAnchor],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.avatarView prepareForReuse];
}

- (void)configureWithGroup:(SCIDeletedMessageGroup *)group {
    NSString *name = group.senderUsername.length ? [@"@" stringByAppendingString:group.senderUsername]
                                                 : (group.senderFullName.length ? group.senderFullName : @"Unknown user");
    self.nameLabel.text = name;
    self.pinBadge.hidden = !group.isPinned;

    SCIDeletedMessage *latest = group.latest;
    self.previewIcon.image = [SCIAssetUtils instagramIconNamed:SCIDeletedMessageKindSymbolFilled(latest.kind, YES)
                                                      pointSize:14.0
                                                  renderingMode:UIImageRenderingModeAlwaysTemplate];
    self.previewLabel.text = SCIDeletedMessagesSenderPreview(group);
    self.timeLabel.text = [SCIDeletedMessagesDate stringForDate:group.lastDeletedAt];

    self.avatarView.alpha = group.isBlocked ? 0.4 : 1.0;
    self.nameLabel.alpha = group.isBlocked ? 0.5 : 1.0;
    self.previewRow.alpha = group.isBlocked ? 0.5 : 1.0;

    [self.avatarView configureWithPK:group.senderPk urlString:group.senderProfilePicURL];
}

// Latest message preview: text body when present, otherwise a kind label plus
// a count suffix when the sender has more than one unsent message.
static NSString *SCIDeletedMessagesSenderPreview(SCIDeletedMessageGroup *group) {
    SCIDeletedMessage *latest = group.latest;
    NSString *body = nil;
    if (latest.text.length) body = latest.text;
    else if (latest.previewText.length) body = latest.previewText;
    else body = SCIDeletedMessageKindLocalizedName(latest.kind);

    body = [body stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

    if (group.count > 1) {
        return [NSString stringWithFormat:@"%@  ·  %lu unsent", body, (unsigned long)group.count];
    }
    return body;
}

@end

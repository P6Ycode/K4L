#import "SPKGalleryImportMetadataFormViewController.h"

#import "../../Utils.h"
#import "SPKGalleryFile.h"
#import "SPKGalleryOriginController.h"
#import "SPKGallerySaveMetadata.h"

typedef NS_ENUM(NSInteger, SPKGalleryImportFormRow) {
    SPKGalleryImportFormRowDisplayName = 0,
    SPKGalleryImportFormRowFileStem,
    SPKGalleryImportFormRowSource,
    SPKGalleryImportFormRowUsername,
    SPKGalleryImportFormRowUserPK,
    SPKGalleryImportFormRowProfileURL,
    SPKGalleryImportFormRowMediaPK,
    SPKGalleryImportFormRowMediaCode,
    SPKGalleryImportFormRowMediaURL,
    SPKGalleryImportFormRowPixelWidth,
    SPKGalleryImportFormRowPixelHeight,
    SPKGalleryImportFormRowDuration,
    SPKGalleryImportFormRowGallerySortDate,
    SPKGalleryImportFormRowCount
};

static NSString *SPKFormFormattedGallerySortDate(NSDate *_Nullable date) {
    if (!date) {
        return @"";
    }
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateStyle = NSDateFormatterMediumStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
    });
    return [fmt stringFromDate:date];
}

static NSDate *_Nullable SPKFormParsedGallerySortDate(NSString *raw) {
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) {
        return nil;
    }
    static NSArray<NSDateFormatter *> *formatters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *patterns = @[
            @"yyyy-MM-dd HH:mm:ss",
            @"yyyy-MM-dd HH:mm",
            @"yyyy-MM-dd",
            @"yyyyMMddHHmmss",
            @"yyyyMMddHHmm",
            @"yyyyMMdd",
        ];
        NSMutableArray<NSDateFormatter *> *a = [NSMutableArray array];
        for (NSString *pat in patterns) {
            NSDateFormatter *f = [[NSDateFormatter alloc] init];
            f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            f.timeZone = [NSTimeZone localTimeZone];
            f.dateFormat = pat;
            [a addObject:f];
        }
        formatters = a;
    });
    for (NSDateFormatter *f in formatters) {
        NSDate *d = [f dateFromString:s];
        if (d) {
            return d;
        }
    }
    return nil;
}

@interface SPKGalleryImportMetadataFormViewController () <UITextFieldDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UITextField *> *textFields;
@property (nonatomic, strong) UIButton *sourceMenuButton;
@end

@implementation SPKGalleryImportMetadataFormViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SPKUtils SPKColor_InstagramSeparator];
    self.textFields = [NSMutableDictionary dictionary];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return SPKGalleryImportFormRowCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [self titleForRow:(SPKGalleryImportFormRow)section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (self.footerStemExplanation.length > 0 && section == SPKGalleryImportFormRowFileStem) {
        return self.footerStemExplanation;
    }
    return [self footerTextForRow:(SPKGalleryImportFormRow)section];
}

- (NSString *)titleForRow:(SPKGalleryImportFormRow)row {
    switch (row) {
    case SPKGalleryImportFormRowDisplayName:
        return @"Display name";
    case SPKGalleryImportFormRowFileStem:
        return @"File name key";
    case SPKGalleryImportFormRowSource:
        return @"Source";
    case SPKGalleryImportFormRowUsername:
        return @"Username";
    case SPKGalleryImportFormRowUserPK:
        return @"User id (pk)";
    case SPKGalleryImportFormRowProfileURL:
        return @"Profile URL";
    case SPKGalleryImportFormRowMediaPK:
        return @"Media id (pk)";
    case SPKGalleryImportFormRowMediaCode:
        return @"Shortcode";
    case SPKGalleryImportFormRowMediaURL:
        return @"Permalink URL";
    case SPKGalleryImportFormRowPixelWidth:
        return @"Width (px)";
    case SPKGalleryImportFormRowPixelHeight:
        return @"Height (px)";
    case SPKGalleryImportFormRowDuration:
        return @"Duration (seconds)";
    case SPKGalleryImportFormRowGallerySortDate:
        return @"Gallery date";
    default:
        return @"";
    }
}

- (NSString *)footerTextForRow:(SPKGalleryImportFormRow)row {
    switch (row) {
    case SPKGalleryImportFormRowDisplayName:
        return @"Optional label shown in the gallery list instead of the file name.";
    case SPKGalleryImportFormRowFileStem:
        return @"Used only in the saved filename when the imported name is useless (UUID, generic export). Not Instagram’s shortcode — use Shortcode below for posts.";
    case SPKGalleryImportFormRowSource:
        return @"Feed, Story, Reels, etc. Story builds /stories/<user>/<media id>/. Reels opens shortcode as /reel/...; Feed uses /p/... when building a link.";
    case SPKGalleryImportFormRowUsername:
        return @"Account handle without @. Used for Open profile and, if Profile URL is empty, to fill an instagram:// profile link. Required to open a Story.";
    case SPKGalleryImportFormRowUserPK:
        return @"Numeric Instagram user id when you have it (some tweaks export this).";
    case SPKGalleryImportFormRowProfileURL:
        return @"https or instagram:// profile link. Open profile uses this or Username.";
    case SPKGalleryImportFormRowMediaPK:
        return @"Numeric media id. For posts/reels it's converted to a shortcode when no permalink/shortcode is set; for Stories it forms /stories/<user>/<media id>/.";
    case SPKGalleryImportFormRowMediaCode:
        return @"The code in the URL (e.g. ABCde123). With Permalink empty, Open original can build https://instagram.com/p/ or /reel/ from Source + shortcode.";
    case SPKGalleryImportFormRowMediaURL:
        return @"Full post URL (https or instagram://). Prefer this when you copied a share link from Instagram.";
    case SPKGalleryImportFormRowPixelWidth:
    case SPKGalleryImportFormRowPixelHeight:
        return @"Leave empty to detect from the file. Override only if probing is wrong.";
    case SPKGalleryImportFormRowDuration:
        return @"Video length in seconds. Leave empty to probe; override for broken files.";
    case SPKGalleryImportFormRowGallerySortDate:
        return @"Used for the gallery “downloaded” line and sorting. In tweak-style names, we prefer a leading epoch token (save-time), and fall back to trailing compact digits when needed. Clear to use the device import time.";
    default:
        return @"";
    }
}

- (NSString *)stringValueForRow:(SPKGalleryImportFormRow)row {
    SPKGallerySaveMetadata *m = self.metadata;
    switch (row) {
    case SPKGalleryImportFormRowDisplayName:
        return m.customName ?: @"";
    case SPKGalleryImportFormRowFileStem:
        return m.importFileNameStem ?: @"";
    case SPKGalleryImportFormRowUsername:
        return m.sourceUsername ?: @"";
    case SPKGalleryImportFormRowUserPK:
        return m.sourceUserPK ?: @"";
    case SPKGalleryImportFormRowProfileURL:
        return m.sourceProfileURLString ?: @"";
    case SPKGalleryImportFormRowMediaPK:
        return m.sourceMediaPK ?: @"";
    case SPKGalleryImportFormRowMediaCode:
        return m.sourceMediaCode ?: @"";
    case SPKGalleryImportFormRowMediaURL:
        return m.sourceMediaURLString ?: @"";
    case SPKGalleryImportFormRowPixelWidth:
        return m.pixelWidth > 0 ? [NSString stringWithFormat:@"%d", (int)m.pixelWidth] : @"";
    case SPKGalleryImportFormRowPixelHeight:
        return m.pixelHeight > 0 ? [NSString stringWithFormat:@"%d", (int)m.pixelHeight] : @"";
    case SPKGalleryImportFormRowDuration:
        return m.durationSeconds > 0.05 ? [NSString stringWithFormat:@"%.3f", m.durationSeconds] : @"";
    case SPKGalleryImportFormRowGallerySortDate:
        return SPKFormFormattedGallerySortDate(m.importCapturedDate);
    default:
        return @"";
    }
}

- (void)applyString:(NSString *)value forRow:(SPKGalleryImportFormRow)row {
    NSString *t = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    SPKGallerySaveMetadata *m = self.metadata;
    switch (row) {
    case SPKGalleryImportFormRowDisplayName:
        m.customName = t.length ? t : nil;
        break;
    case SPKGalleryImportFormRowFileStem:
        m.importFileNameStem = t.length ? t : nil;
        break;
    case SPKGalleryImportFormRowUsername: {
        m.sourceUsername = t.length ? t : nil;
        if (t.length > 0) {
            [SPKGalleryOriginController populateProfileMetadata:m username:t user:nil];
        }
        break;
    }
    case SPKGalleryImportFormRowUserPK:
        m.sourceUserPK = t.length ? t : nil;
        break;
    case SPKGalleryImportFormRowProfileURL:
        m.sourceProfileURLString = t.length ? t : nil;
        break;
    case SPKGalleryImportFormRowMediaPK:
        m.sourceMediaPK = t.length ? t : nil;
        break;
    case SPKGalleryImportFormRowMediaCode:
        m.sourceMediaCode = t.length ? t : nil;
        break;
    case SPKGalleryImportFormRowMediaURL:
        m.sourceMediaURLString = t.length ? t : nil;
        break;
    case SPKGalleryImportFormRowPixelWidth:
        m.pixelWidth = t.length ? (int32_t)[t intValue] : 0;
        break;
    case SPKGalleryImportFormRowPixelHeight:
        m.pixelHeight = t.length ? (int32_t)[t intValue] : 0;
        break;
    case SPKGalleryImportFormRowDuration:
        m.durationSeconds = t.length ? [t doubleValue] : 0;
        break;
    case SPKGalleryImportFormRowGallerySortDate:
        m.importCapturedDate = t.length ? SPKFormParsedGallerySortDate(t) : nil;
        break;
    default:
        break;
    }
}

- (UIMenu *)menuForSourceSelection {
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    NSArray<NSNumber *> *sources = @[
        @(SPKGallerySourceFeed), @(SPKGallerySourceStories), @(SPKGallerySourceReels),
        @(SPKGallerySourceProfile), @(SPKGallerySourceDMs), @(SPKGallerySourceThumbnail),
        @(SPKGallerySourceInstants), @(SPKGallerySourceAudioPage), @(SPKGallerySourceComments),
        @(SPKGallerySourceOther)
    ];
    for (NSNumber *num in sources) {
        SPKGallerySource src = (SPKGallerySource)num.intValue;
        NSString *title = [SPKGalleryFile labelForSource:src];
        BOOL checked = ((SPKGallerySource)self.metadata.source == src);
        UIAction *a = [UIAction actionWithTitle:title
                                          image:nil
                                     identifier:nil
                                        handler:^(__unused UIAction *action) {
                                            self.metadata.source = (int16_t)src;
                                            [self.sourceMenuButton setTitle:[SPKGalleryFile labelForSource:src] forState:UIControlStateNormal];
                                            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SPKGalleryImportFormRowSource] withRowAnimation:UITableViewRowAnimationNone];
                                        }];
        a.state = checked ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:a];
    }
    return [UIMenu menuWithTitle:@"" children:actions];
}

- (UITableViewCell *)sourceSelectionCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:[SPKGalleryFile labelForSource:(SPKGallerySource)self.metadata.source] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [btn setTitleColor:[SPKUtils SPKColor_InstagramPrimaryText] forState:UIControlStateNormal];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    btn.menu = [self menuForSourceSelection];
    btn.showsMenuAsPrimaryAction = YES;
    self.sourceMenuButton = btn;

    [cell.contentView addSubview:btn];
    UILayoutGuide *g = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [btn.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [btn.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [btn.topAnchor constraintEqualToAnchor:g.topAnchor],
        [btn.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];

    return cell;
}

- (UITableViewCell *)textFieldCellForSection:(NSInteger)section row:(SPKGalleryImportFormRow)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectZero];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    tf.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    tf.text = [self stringValueForRow:row];
    tf.placeholder = @"Optional";
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    tf.delegate = self;
    tf.tag = row;
    tf.userInteractionEnabled = YES;

    if (row == SPKGalleryImportFormRowPixelWidth || row == SPKGalleryImportFormRowPixelHeight) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
    } else if (row == SPKGalleryImportFormRowDuration) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    } else if (row == SPKGalleryImportFormRowProfileURL || row == SPKGalleryImportFormRowMediaURL) {
        tf.keyboardType = UIKeyboardTypeURL;
    } else if (row == SPKGalleryImportFormRowGallerySortDate) {
        tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        tf.placeholder = @"e.g. yyyy-MM-dd HH:mm or yyyyMMddHHmmss";
    } else {
        tf.keyboardType = UIKeyboardTypeDefault;
    }

    [cell.contentView addSubview:tf];
    self.textFields[@(section)] = tf;

    UILayoutGuide *g = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [tf.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [tf.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [tf.topAnchor constraintEqualToAnchor:g.topAnchor
                                     constant:4],
        [tf.bottomAnchor constraintEqualToAnchor:g.bottomAnchor
                                        constant:-4],
        [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    SPKGalleryImportFormRow row = (SPKGalleryImportFormRow)indexPath.section;
    if (row == SPKGalleryImportFormRowSource) {
        return [self sourceSelectionCell];
    }
    return [self textFieldCellForSection:indexPath.section row:row];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [self applyString:textField.text forRow:(SPKGalleryImportFormRow)textField.tag];
}

@end

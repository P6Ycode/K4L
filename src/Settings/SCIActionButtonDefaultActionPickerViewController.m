#import "SCIActionButtonDefaultActionPickerViewController.h"

#import "SCIPreferences.h"
#import "SCITopicSettingsSupport.h"
#import "../AssetUtils.h"
#import "../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../Shared/ActionButton/SCIActionDescriptor.h"
#import "../Utils.h"

static NSString * const kSCIActionDefaultPickerCellIdentifier = @"SCIActionDefaultPickerCell";

static NSString *SCIActionButtonDefaultActionKeyForSource(SCIActionButtonSource source) {
    return SCIPrefActionButtonDefaultActionKey(SCIActionButtonTopicKeyForSource(source));
}

static NSDictionary<NSString *, NSString *> *SCIProfileLegacyDefaultActionMap(void) {
    return @{
        @"copy_info": kSCIActionProfileCopyInfo,
        @"view_picture": kSCIActionExpand,
        @"share_picture": kSCIActionDownloadShare,
        @"save_picture_gallery": kSCIActionDownloadGallery,
        @"profile_settings": kSCIActionOpenTopicSettings
    };
}

NSString *SCIActionButtonDefaultActionIdentifierForSource(SCIActionButtonSource source) {
    NSArray<NSString *> *supportedActions = SCIActionButtonSupportedActionsForSource(source);
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:SCIActionButtonDefaultActionKeyForSource(source)];
    if (source == SCIActionButtonSourceProfile && saved.length > 0) {
        saved = SCIProfileLegacyDefaultActionMap()[saved] ?: saved;
    }

    if ([saved isEqualToString:kSCIActionNone]) return kSCIActionNone;
    if ([supportedActions containsObject:saved]) return saved;
    if (saved.length > 0 || source == SCIActionButtonSourceProfile) return kSCIActionNone;
    if ([supportedActions containsObject:kSCIActionDownloadLibrary]) return kSCIActionDownloadLibrary;
    return supportedActions.firstObject ?: kSCIActionNone;
}

NSString *SCIActionButtonDefaultActionTitleForSource(SCIActionButtonSource source) {
    NSString *identifier = SCIActionButtonDefaultActionIdentifierForSource(source);
    if ([identifier isEqualToString:kSCIActionNone]) return @"None";
    return SCIActionDescriptorDisplayTitle(identifier, SCIActionButtonTopicTitleForSource(source));
}

NSString *SCIActionButtonDefaultActionIconNameForSource(SCIActionButtonSource source) {
    NSString *identifier = SCIActionButtonDefaultActionIdentifierForSource(source);
    return [identifier isEqualToString:kSCIActionNone] ? @"action" : SCIActionDescriptorIconName(identifier);
}

static NSArray<NSDictionary *> *SCIActionButtonDefaultActionSections(SCIActionButtonSource source) {
    NSArray<NSString *> *supportedActions = SCIActionButtonSupportedActionsForSource(source);
    NSArray<NSDictionary *> *groups = @[
        @{@"title": @"Downloads", @"actions": @[kSCIActionDownloadLibrary, kSCIActionDownloadShare, kSCIActionDownloadGallery]},
        @{@"title": @"Audio", @"actions": @[kSCIActionDownloadAudio, kSCIActionDownloadAudioShare, kSCIActionDownloadAudioGallery, kSCIActionPlayAudio, kSCIActionCopyAudioURL]},
        @{@"title": @"Media", @"actions": @[kSCIActionExpand, kSCIActionViewThumbnail]},
        @{@"title": @"Copy", @"actions": @[kSCIActionCopyDownloadLink, kSCIActionCopyMedia, kSCIActionCopyCaption, kSCIActionProfileCopyInfo]},
        @{@"title": @"Other", @"actions": @[kSCIActionOpenTopicSettings, kSCIActionRepost, kSCIActionStoryMentionsSheet, kSCIActionToggleStorySeenUserRule, kSCIActionDeletedMessagesLog, kSCIActionNone]}
    ];

    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];
    for (NSDictionary *group in groups) {
        NSMutableArray<NSString *> *actions = [NSMutableArray array];
        for (NSString *identifier in group[@"actions"]) {
            if ([identifier isEqualToString:kSCIActionNone] || [supportedActions containsObject:identifier]) {
                [actions addObject:identifier];
            }
        }
        if (actions.count > 0) {
            [sections addObject:@{@"title": group[@"title"], @"actions": [actions copy]}];
        }
    }
    return [sections copy];
}

@interface SCIActionButtonDefaultActionPickerViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) SCIActionButtonSource source;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;

@end

@implementation SCIActionButtonDefaultActionPickerViewController

- (UIView *)selectionBackgroundView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
    return view;
}

- (instancetype)initWithSource:(SCIActionButtonSource)source {
    self = [super init];
    if (self) {
        _source = source;
        _sections = SCIActionButtonDefaultActionSections(source);
        self.title = @"Default Tap Action";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    self.tableView.tintColor = [SCIUtils SCIColor_Primary];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kSCIActionDefaultPickerCellIdentifier];
    [self.view addSubview:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section][@"actions"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"title"];
}

- (NSString *)identifierAtIndexPath:(NSIndexPath *)indexPath {
    return self.sections[indexPath.section][@"actions"][indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSCIActionDefaultPickerCellIdentifier forIndexPath:indexPath];
    UIListContentConfiguration *config = cell.defaultContentConfiguration;
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    BOOL isNone = [identifier isEqualToString:kSCIActionNone];

    cell.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    cell.tintColor = [SCIUtils SCIColor_Primary];
    cell.selectedBackgroundView = [self selectionBackgroundView];
    config.text = isNone ? @"None" : SCIActionDescriptorDisplayTitle(identifier, SCIActionButtonTopicTitleForSource(self.source));
    config.textProperties.color = [SCIUtils SCIColor_InstagramPrimaryText];
    config.image = SCISettingsIcon(isNone ? @"action" : SCIActionDescriptorIconName(identifier));
    config.imageProperties.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];

    if ([identifier isEqualToString:SCIActionButtonDefaultActionIdentifierForSource(self.source)]) {
        UIImageView *checkmarkView = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"circle_check_filled"]];
        checkmarkView.tintColor = [SCIUtils SCIColor_Primary];
        cell.accessoryView = checkmarkView;
    } else {
        cell.accessoryView = nil;
    }

    cell.contentConfiguration = config;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:SCIActionButtonDefaultActionKeyForSource(self.source)];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIActionButtonConfigurationDidChangeNotification object:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.navigationController popViewControllerAnimated:YES];
}

@end

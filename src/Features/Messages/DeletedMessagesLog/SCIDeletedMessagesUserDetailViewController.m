#import "SCIDeletedMessagesUserDetailViewController.h"

#import "SCIDeletedMessagesChipBar.h"
#import "SCIDeletedMessagesDate.h"
#import "SCIDeletedMessagesFilter.h"
#import "SCIDeletedMessagesStorage.h"
#import "../../../Utils.h"
#import "../../../AssetUtils.h"
#import "../../../Shared/UI/SCIMediaChrome.h"
#import "../../../Shared/UI/SCIIGAlertPresenter.h"

@interface SCIDeletedMessagesUserDetailViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, SCIDeletedMessagesChipBarDelegate>
@property (nonatomic, strong) SCIDeletedMessageGroup *group;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) SCIDeletedMessagesChipBar *chipBar;
@property (nonatomic, strong) SCIDeletedMessagesFilter *filter;
@property (nonatomic, copy) NSArray<SCIDeletedMessage *> *messages;
@property (nonatomic, copy) NSArray<SCIDeletedMessage *> *visibleMessages;
@end

@implementation SCIDeletedMessagesUserDetailViewController

- (instancetype)initWithGroup:(SCIDeletedMessageGroup *)group ownerPK:(NSString *)ownerPK {
    if ((self = [super init])) {
        _group = group;
        _ownerPK = ownerPK.length ? [ownerPK copy] : @"anon";
        _filter = [SCIDeletedMessagesFilter new];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.group.senderUsername.length ? [@"@" stringByAppendingString:self.group.senderUsername] : @"Deleted Messages";
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];

    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithImage:SCIMediaChromeTopBarIcon(@"more")
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:nil
                                                                 action:nil];
    moreItem.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    moreItem.menu = [self moreMenu];
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[moreItem]);

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search messages";
    [self.searchController.searchBar setImage:[SCIAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                            forSearchBarIcon:UISearchBarIconSearch
                                       state:UIControlStateNormal];
    self.navigationItem.searchController = self.searchController;

    self.chipBar = [[SCIDeletedMessagesChipBar alloc] initWithFrame:CGRectZero];
    self.chipBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipBar.delegate = self;
    [self.chipBar setItems:@[@"All", @"Text", @"Photo", @"Video", @"Voice", @"GIF", @"Sticker", @"Share", @"Link"]
                   symbols:@[@"grid", @"text", @"photo", @"video", @"microphone", @"gif", @"sticker", @"share", @"link"]];
    [self.view addSubview:self.chipBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    self.tableView.rowHeight = 64.0;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.chipBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.chipBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.chipBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.chipBar.bottomAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:SCIDeletedMessagesDidChangeNotification object:nil];
    [self reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadData {
    self.messages = [SCIDeletedMessagesStorage messagesForSenderPK:self.group.senderPk ownerPK:self.ownerPK];
    [self applyFilter];
    [self rebuildMenus];
}

- (void)applyFilter {
    self.visibleMessages = [self.filter apply:self.messages ?: @[]];
    [self.tableView reloadData];
}

- (void)rebuildMenus {
    NSArray<UIBarButtonItem *> *items = self.navigationItem.rightBarButtonItems;
    if (items.count >= 1) items[0].menu = [self moreMenu];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.filter.searchText = searchController.searchBar.text;
    [self applyFilter];
}

#pragma mark - Chip Bar

- (void)chipBar:(SCIDeletedMessagesChipBar *)bar didSelectIndex:(NSInteger)index {
    [self.filter clearKinds];
    if (index > 0) {
        [self.filter toggleKind:(SCIDeletedMessageKind)index];
    }
    [self applyFilter];
}

#pragma mark - Menus

- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;

    UIAction *pinAction = [UIAction actionWithTitle:(self.group.isPinned ? @"Unpin Sender" : @"Pin Sender")
                                              image:[SCIAssetUtils instagramIconNamed:(self.group.isPinned ? @"pin_filled" : @"pin") pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                         identifier:nil
                                            handler:^(__unused UIAction *a) {
        [SCIDeletedMessagesStorage setSenderPinned:!weakSelf.group.isPinned senderPK:weakSelf.group.senderPk ownerPK:weakSelf.ownerPK];
        weakSelf.group.isPinned = !weakSelf.group.isPinned;
        [weakSelf rebuildMenus];
    }];

    UIAction *blockAction = [UIAction actionWithTitle:(self.group.isBlocked ? @"Unblock Sender" : @"Block Sender")
                                               image:[SCIAssetUtils instagramIconNamed:@"block" pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                          identifier:nil
                                             handler:^(__unused UIAction *a) {
        [SCIDeletedMessagesStorage setSenderBlocked:!weakSelf.group.isBlocked senderPK:weakSelf.group.senderPk ownerPK:weakSelf.ownerPK];
        weakSelf.group.isBlocked = !weakSelf.group.isBlocked;
        [weakSelf rebuildMenus];
    }];

    UIAction *deleteAction = [UIAction actionWithTitle:@"Delete Sender Log"
                                                image:[SCIAssetUtils instagramIconNamed:@"trash" pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                           identifier:nil
                                              handler:^(__unused UIAction *a) {
        [SCIIGAlertPresenter presentAlertFromViewController:weakSelf
                                                      title:@"Delete sender log?"
                                                    message:[NSString stringWithFormat:@"This removes all logged messages from %@.", weakSelf.group.senderUsername.length ? [@"@" stringByAppendingString:weakSelf.group.senderUsername] : @"this sender"]
                                                    actions:@[
            [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
            [SCIIGAlertAction actionWithTitle:@"Delete" style:SCIIGAlertActionStyleDestructive handler:^{
                [SCIDeletedMessagesStorage deleteMessagesForSenderPK:weakSelf.group.senderPk ownerPK:weakSelf.ownerPK];
                [weakSelf.navigationController popViewControllerAnimated:YES];
            }],
        ]];
    }];
    deleteAction.attributes = UIMenuElementAttributesDestructive;

    UIMenu *destructiveSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[deleteAction]];

    return [UIMenu menuWithTitle:@"" children:@[pinAction, blockAction, destructiveSection]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleMessages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"message"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"message"];
    SCIDeletedMessage *message = self.visibleMessages[indexPath.row];
    NSString *title = message.text.length ? message.text : (message.previewText.length ? message.previewText : SCIDeletedMessageKindLocalizedName(message.kind));
    cell.textLabel.text = title;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", SCIDeletedMessageKindLocalizedName(message.kind), [SCIDeletedMessagesDate stringForDate:(message.deletedAt ?: message.capturedAt ?: message.sentAt)]];
    cell.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    cell.selectedBackgroundView = [UIView new];
    cell.selectedBackgroundView.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
    cell.textLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    cell.detailTextLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    UIImage *thumb = [self thumbnailForMessage:message];
    if (thumb) {
        cell.imageView.image = thumb;
        cell.imageView.layer.cornerRadius = 6.0;
        cell.imageView.clipsToBounds = YES;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        cell.imageView.tintColor = nil;
    } else {
        cell.imageView.layer.cornerRadius = 0.0;
        cell.imageView.clipsToBounds = NO;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        cell.imageView.image = [SCIAssetUtils instagramIconNamed:SCIDeletedMessageKindSymbol(message.kind) pointSize:24.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        cell.imageView.tintColor = [SCIUtils SCIColor_InstagramSecondaryText];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (UIImage *)thumbnailForMessage:(SCIDeletedMessage *)message {
    NSString *path = [SCIDeletedMessagesStorage absolutePathForRelativePath:(message.thumbnailPath ?: message.mediaPath) ownerPK:self.ownerPK];
    if (!path.length || ![NSFileManager.defaultManager fileExistsAtPath:path]) return nil;
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(34.0, 34.0) format:format];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0.0, 0.0, 34.0, 34.0)];
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCIDeletedMessage *message = self.visibleMessages[indexPath.row];
    if (message.text.length || message.previewText.length) {
        UIPasteboard.generalPasteboard.string = message.text ?: message.previewText;
        SCINotify(kSCINotificationUnsentMessage, @"Copied to clipboard", nil, @"circle_check_filled", SCINotificationToneSuccess);
    }
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    SCIDeletedMessage *message = self.visibleMessages[indexPath.row];
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        return [weakSelf contextMenuForMessage:message];
    }];
}

- (UIMenu *)contextMenuForMessage:(SCIDeletedMessage *)message {
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];

    if (message.text.length || message.previewText.length) {
        UIAction *copyAction = [UIAction actionWithTitle:@"Copy Text"
                                                  image:[SCIAssetUtils instagramIconNamed:@"copy" pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                             identifier:nil
                                                handler:^(__unused UIAction *a) {
            UIPasteboard.generalPasteboard.string = message.text ?: message.previewText;
        }];
        [children addObject:copyAction];
    }

    NSURL *mediaURL = [self localOrRemoteURLForMessage:message];
    if (mediaURL) {
        UIAction *shareAction = [UIAction actionWithTitle:@"Share"
                                                   image:[SCIAssetUtils instagramIconNamed:@"share" pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                              identifier:nil
                                                 handler:^(__unused UIAction *a) {
            UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[mediaURL] applicationActivities:nil];
            [weakSelf presentViewController:vc animated:YES completion:nil];
        }];
        [children addObject:shareAction];

        if (![mediaURL isFileURL]) {
            UIAction *copyLinkAction = [UIAction actionWithTitle:@"Copy Link"
                                                          image:[SCIAssetUtils instagramIconNamed:@"link" pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                                     identifier:nil
                                                        handler:^(__unused UIAction *a) {
                UIPasteboard.generalPasteboard.string = mediaURL.absoluteString;
            }];
            [children addObject:copyLinkAction];
        }
    }

    UIAction *deleteAction = [UIAction actionWithTitle:@"Delete"
                                                image:[SCIAssetUtils instagramIconNamed:@"trash" pointSize:16.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                           identifier:nil
                                              handler:^(__unused UIAction *a) {
        [SCIDeletedMessagesStorage deleteMessageId:message.messageId forOwnerPK:weakSelf.ownerPK];
    }];
    deleteAction.attributes = UIMenuElementAttributesDestructive;

    UIMenu *destructiveSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[deleteAction]];
    [children addObject:destructiveSection];

    return [UIMenu menuWithTitle:@"" children:children];
}

- (NSURL *)localOrRemoteURLForMessage:(SCIDeletedMessage *)message {
    NSString *path = [SCIDeletedMessagesStorage absolutePathForRelativePath:(message.mediaPath ?: message.thumbnailPath) ownerPK:self.ownerPK];
    if (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]) return [NSURL fileURLWithPath:path];
    if (message.mediaURL.length) return [NSURL URLWithString:message.mediaURL];
    if (message.thumbnailURL.length) return [NSURL URLWithString:message.thumbnailURL];
    return nil;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIDeletedMessage *message = self.visibleMessages[indexPath.row];
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [SCIDeletedMessagesStorage deleteMessageId:message.messageId forOwnerPK:self.ownerPK];
        completionHandler(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

@end

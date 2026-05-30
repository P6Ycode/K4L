#import "SCIDeletedMessagesUserDetailViewController.h"

#import "SCIDeletedMessageBubbleCell.h"
#import "SCIDeletedMessagesChipBar.h"
#import "SCIDeletedMessagesDate.h"
#import "SCIDeletedMessagesFilter.h"
#import "SCIDeletedMessagesStorage.h"
#import "../../../Utils.h"
#import "../../../AssetUtils.h"
#import "../../../Shared/UI/SCIMediaChrome.h"
#import "../../../Shared/UI/SCIIGAlertPresenter.h"
#import "../../../Shared/MediaPreview/SCIFullScreenMediaPlayer.h"

@interface SCIDeletedMessagesUserDetailViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, SCIDeletedMessagesChipBarDelegate, SCIDeletedMessageBubbleCellDelegate>
@property (nonatomic, strong) SCIDeletedMessageGroup *group;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) SCIDeletedMessagesChipBar *chipBar;
@property (nonatomic, strong) NSLayoutConstraint *chipBarHeight;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyStateIcon;
@property (nonatomic, strong) UILabel *emptyStateTitle;
@property (nonatomic, strong) UILabel *emptyStateSubtitle;
@property (nonatomic, strong) SCIDeletedMessagesFilter *filter;
@property (nonatomic, copy) NSArray<SCIDeletedMessage *> *messages;
@property (nonatomic, copy) NSArray<SCIDeletedMessage *> *visibleMessages;
@property (nonatomic, copy, nullable) NSString *threadId;   // resolved from the group's messages
@property (nonatomic, assign) BOOL shouldScrollToBottomOnReload;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;
@property (nonatomic, strong) dispatch_queue_t thumbnailQueue;
@end

@implementation SCIDeletedMessagesUserDetailViewController

// Chip filter columns — see SCIDeletedMessagesViewController for the rationale.
static NSArray<NSString *> *SCIDMDetailChipTitles(void) {
    return @[@"Text", @"Photo", @"Video", @"Voice", @"GIF", @"Sticker", @"Share", @"Link", @"Reaction"];
}
static NSArray<NSString *> *SCIDMDetailChipSymbols(void) {
    return @[@"text", @"photo", @"video", @"voice", @"gif", @"sticker", @"share", @"link", @"reactions"];
}
static NSArray<NSString *> *SCIDMDetailChipSelectedSymbols(void) {
    return @[@"text", @"photo_filled", @"video_filled", @"voice_filled", @"gif_filled", @"sticker_filled", @"share", @"link", @"reactions"];
}
static SCIDeletedMessageKind SCIDMDetailChipKindForIndex(NSInteger index) {
    switch (index) {
        case 0: return SCIDeletedMessageKindText;
        case 1: return SCIDeletedMessageKindPhoto;
        case 2: return SCIDeletedMessageKindVideo;
        case 3: return SCIDeletedMessageKindVoice;
        case 4: return SCIDeletedMessageKindGif;
        case 5: return SCIDeletedMessageKindSticker;
        case 6: return SCIDeletedMessageKindShare;
        case 7: return SCIDeletedMessageKindLink;
        case 8: return SCIDeletedMessageKindReaction;
        default: return SCIDeletedMessageKindUnknown;
    }
}

- (instancetype)initWithGroup:(SCIDeletedMessageGroup *)group ownerPK:(NSString *)ownerPK {
    if ((self = [super init])) {
        _group = group;
        _ownerPK = ownerPK.length ? [ownerPK copy] : @"anon";
        _filter = [SCIDeletedMessagesFilter new];
        // Default to oldest-first so the chat reads top-to-bottom.
        _filter.sort = SCIDMSortOldest;
        // Resolve the thread this sender's messages belong to so we can show the
        // full conversation (their unsends + your own) in chat order.
        for (SCIDeletedMessage *m in group.messages) {
            if (m.threadId.length) { _threadId = [m.threadId copy]; break; }
        }
        _thumbnailCache = [NSCache new];
        _thumbnailCache.countLimit = 120;
        _thumbnailQueue = dispatch_queue_create("com.scinsta.deletedmessages.detailthumbs", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.group.senderUsername.length ? [@"@" stringByAppendingString:self.group.senderUsername] : @"Deleted Messages";
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];

    UIBarButtonItem *moreItem = SCIMediaChromeTopBarMenuButtonItem(@"more", [self moreMenu], @"More");
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
    [self.chipBar setItems:SCIDMDetailChipTitles() symbols:SCIDMDetailChipSymbols() selectedSymbols:SCIDMDetailChipSelectedSymbols()];
    [self.view addSubview:self.chipBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90.0;
    self.tableView.allowsSelection = NO;
    [self.tableView registerClass:[SCIDeletedMessageBubbleCell class] forCellReuseIdentifier:SCIDeletedMessageBubbleCellReuseID];
    [self.view addSubview:self.tableView];

    [self setupEmptyState];

    self.chipBarHeight = [self.chipBar.heightAnchor constraintEqualToConstant:50.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.chipBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.chipBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.chipBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        self.chipBarHeight,
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.chipBar.bottomAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:SCIDeletedMessagesDidChangeNotification object:nil];
    [self reloadData];
}

- (void)setupEmptyState {
    self.emptyStateView = [UIView new];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateView.hidden = YES;
    [self.view addSubview:self.emptyStateView];

    self.emptyStateIcon = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"comment_empty" pointSize:96.0 renderingMode:UIImageRenderingModeAlwaysTemplate]];
    self.emptyStateIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.emptyStateIcon.tintColor = [SCIUtils SCIColor_InstagramTertiaryText];
    [self.emptyStateView addSubview:self.emptyStateIcon];

    self.emptyStateTitle = [UILabel new];
    self.emptyStateTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateTitle.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    self.emptyStateTitle.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    self.emptyStateTitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateTitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateTitle];

    self.emptyStateSubtitle = [UILabel new];
    self.emptyStateSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateSubtitle.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.emptyStateSubtitle.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    self.emptyStateSubtitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateSubtitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateSubtitle];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30.0],
        [self.emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40.0],
        [self.emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40.0],

        [self.emptyStateIcon.topAnchor constraintEqualToAnchor:self.emptyStateView.topAnchor],
        [self.emptyStateIcon.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
        [self.emptyStateIcon.widthAnchor constraintEqualToConstant:72.0],
        [self.emptyStateIcon.heightAnchor constraintEqualToConstant:72.0],

        [self.emptyStateTitle.topAnchor constraintEqualToAnchor:self.emptyStateIcon.bottomAnchor constant:18.0],
        [self.emptyStateTitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateTitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],

        [self.emptyStateSubtitle.topAnchor constraintEqualToAnchor:self.emptyStateTitle.bottomAnchor constant:6.0],
        [self.emptyStateSubtitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateSubtitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],
        [self.emptyStateSubtitle.bottomAnchor constraintEqualToAnchor:self.emptyStateView.bottomAnchor],
    ]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadData {
    // When the thread is known, show the whole conversation (incoming + your
    // own unsends) in chat order. Otherwise fall back to this sender only.
    if (self.threadId.length) {
        self.messages = [SCIDeletedMessagesStorage messagesForThreadId:self.threadId ownerPK:self.ownerPK];
    } else {
        self.messages = [SCIDeletedMessagesStorage messagesForSenderPK:self.group.senderPk ownerPK:self.ownerPK];
    }
    // A fresh data load should land on the newest message at the bottom.
    self.shouldScrollToBottomOnReload = YES;
    [self applyFilter];
    [self rebuildMenus];
}

- (void)applyFilter {
    self.visibleMessages = [self.filter apply:self.messages ?: @[]];
    [self updateChipBarVisibility];
    [self updateEmptyState];
    [self.tableView reloadData];
    if (self.shouldScrollToBottomOnReload) {
        self.shouldScrollToBottomOnReload = NO;
        [self scrollToBottomAnimated:NO];
    }
}

// Jump to the latest (bottom-most) message, chat-style.
- (void)scrollToBottomAnimated:(BOOL)animated {
    NSInteger count = (NSInteger)self.visibleMessages.count;
    if (count == 0) return;
    // Defer until the table has laid out its rows so the offset is correct with
    // self-sizing cells.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger rows = [self.tableView numberOfRowsInSection:0];
        if (rows == 0) return;
        [self.tableView layoutIfNeeded];
        NSIndexPath *last = [NSIndexPath indexPathForRow:rows - 1 inSection:0];
        [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
    });
}

- (NSUInteger)distinctKindCount {
    NSMutableSet<NSNumber *> *kinds = [NSMutableSet set];
    for (SCIDeletedMessage *message in self.messages) [kinds addObject:@(message.kind)];
    return kinds.count;
}

- (void)updateChipBarVisibility {
    BOOL show = ([self distinctKindCount] >= 2) || [self.filter hasKindFilter];
    BOOL hidden = !show;
    if (self.chipBar.hidden != hidden) {
        self.chipBar.hidden = hidden;
        self.chipBarHeight.constant = hidden ? 0.0 : 50.0;
    }
}

- (void)updateEmptyState {
    BOOL isEmpty = (self.visibleMessages.count == 0);
    self.emptyStateView.hidden = !isEmpty;
    self.tableView.hidden = isEmpty;
    if (!isEmpty) return;

    if (![self.filter isEmpty]) {
        self.emptyStateTitle.text = @"No matches";
        self.emptyStateSubtitle.text = @"No messages match the current filters.";
    } else {
        self.emptyStateTitle.text = @"Nothing here yet";
        self.emptyStateSubtitle.text = @"This sender's unsent messages will show up here.";
    }
}

- (void)rebuildMenus {
    // The more menu is deferred (self-refreshing); nothing to reassign.
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.filter.searchText = searchController.searchBar.text;
    [self applyFilter];
}

#pragma mark - Chip Bar

- (void)chipBar:(SCIDeletedMessagesChipBar *)bar didChangeSelection:(NSSet<NSNumber *> *)selectedIndices {
    [self.filter clearKinds];
    for (NSNumber *index in selectedIndices) {
        SCIDeletedMessageKind kind = SCIDMDetailChipKindForIndex(index.integerValue);
        if (kind != SCIDeletedMessageKindUnknown) [self.filter toggleKind:kind];
    }
    [self applyFilter];
}

#pragma mark - Menus

// The bar button keeps a stable menu whose children are resolved fresh each
// time it opens, so pin/block titles always reflect current state without
// needing to reassign the bar button item's menu.
- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;
    UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion([weakSelf moreMenuElements]);
    }];
    return [UIMenu menuWithTitle:@"" children:@[deferred]];
}

- (NSArray<UIMenuElement *> *)moreMenuElements {
    __weak typeof(self) weakSelf = self;

    UIAction *pinAction = [UIAction actionWithTitle:(self.group.isPinned ? @"Unpin Sender" : @"Pin Sender")
                                              image:[SCIAssetUtils instagramIconNamed:(self.group.isPinned ? @"pin_filled" : @"pin_outline") pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                         identifier:nil
                                            handler:^(__unused UIAction *a) {
        [SCIDeletedMessagesStorage setSenderPinned:!weakSelf.group.isPinned senderPK:weakSelf.group.senderPk ownerPK:weakSelf.ownerPK];
        weakSelf.group.isPinned = !weakSelf.group.isPinned;
    }];

    UIAction *blockAction = [UIAction actionWithTitle:(self.group.isBlocked ? @"Unblock Sender" : @"Block Sender")
                                               image:[SCIAssetUtils instagramIconNamed:self.group.isBlocked ? @"circle" : @"block" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                          identifier:nil
                                             handler:^(__unused UIAction *a) {
        [SCIDeletedMessagesStorage setSenderBlocked:!weakSelf.group.isBlocked senderPK:weakSelf.group.senderPk ownerPK:weakSelf.ownerPK];
        weakSelf.group.isBlocked = !weakSelf.group.isBlocked;
    }];

    UIAction *deleteAction = [UIAction actionWithTitle:@"Delete Sender Log"
                                                image:[SCIAssetUtils instagramIconNamed:@"trash" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
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
    /// TODO: investigate whether native UIMenu destructive tint can be customized. UIMenuElement exposes no supported color API.
    deleteAction.attributes = UIMenuElementAttributesDestructive;

    UIMenu *destructiveSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[deleteAction]];

    return @[pinAction, blockAction, destructiveSection];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleMessages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIDeletedMessageBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:SCIDeletedMessageBubbleCellReuseID forIndexPath:indexPath];
    cell.delegate = self;
    SCIDeletedMessage *message = self.visibleMessages[indexPath.row];

    UIImage *cached = message.messageId.length ? [self.thumbnailCache objectForKey:message.messageId] : nil;
    BOOL outgoing = self.ownerPK.length && [message.senderPk isEqualToString:self.ownerPK];
    [cell configureWithMessage:message thumbnail:cached outgoing:outgoing];
    if (!cached && [self messageHasThumbnail:message]) {
        [self loadThumbnailForMessage:message atIndexPath:indexPath];
    }
    return cell;
}

#pragma mark - Thumbnails

- (BOOL)messageHasThumbnail:(SCIDeletedMessage *)message {
    NSString *rel = message.thumbnailPath ?: message.mediaPath;
    if (!rel.length) return NO;
    NSString *path = [SCIDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:self.ownerPK];
    return (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]);
}

- (void)loadThumbnailForMessage:(SCIDeletedMessage *)message atIndexPath:(NSIndexPath *)indexPath {
    NSString *rel = message.thumbnailPath ?: message.mediaPath;
    NSString *path = [SCIDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:self.ownerPK];
    if (!path.length) return;
    NSString *messageId = message.messageId;

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.thumbnailQueue, ^{
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (!image) return;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (messageId.length) [strongSelf.thumbnailCache setObject:image forKey:messageId];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Update the live cell directly (a row reload can be missed during
            // initial layout before visible rows are registered).
            SCIDeletedMessageBubbleCell *cell = (SCIDeletedMessageBubbleCell *)[strongSelf.tableView cellForRowAtIndexPath:indexPath];
            if ([cell isKindOfClass:[SCIDeletedMessageBubbleCell class]]) {
                [cell applyLoadedThumbnail:image forMessageId:messageId];
            }
        });
    });
}

#pragma mark - Bubble delegate

- (void)bubbleCell:(SCIDeletedMessageBubbleCell *)cell didTapMediaForMessage:(SCIDeletedMessage *)message {
    NSString *rel = message.mediaPath ?: message.thumbnailPath;
    NSString *path = rel.length ? [SCIDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:self.ownerPK] : nil;
    if (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]) {
        // SCIFullScreenMediaPlayer detects audio/video/image by extension and
        // presents the right player — voice notes play here too.
        [SCIFullScreenMediaPlayer showFileURL:[NSURL fileURLWithPath:path]];
        return;
    }
    // Deep-link kinds (share/link) have no local blob — open the URL externally.
    NSString *urlStr = message.mediaURL.length ? message.mediaURL : message.thumbnailURL;
    NSURL *url = urlStr.length ? [NSURL URLWithString:urlStr] : nil;
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

#pragma mark - Context menu

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
                                                  image:[SCIAssetUtils instagramIconNamed:@"copy" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                             identifier:nil
                                                handler:^(__unused UIAction *a) {
            UIPasteboard.generalPasteboard.string = message.text ?: message.previewText;
            SCINotify(kSCINotificationUnsentMessage, @"Copied to clipboard", nil, @"circle_check_filled", SCINotificationToneSuccess);
        }];
        [children addObject:copyAction];
    }

    NSURL *mediaURL = [self localOrRemoteURLForMessage:message];
    if (mediaURL) {
        UIAction *shareAction = [UIAction actionWithTitle:@"Share"
                                                   image:[SCIAssetUtils instagramIconNamed:@"share" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                              identifier:nil
                                                 handler:^(__unused UIAction *a) {
            UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[mediaURL] applicationActivities:nil];
            [weakSelf presentViewController:vc animated:YES completion:nil];
        }];
        [children addObject:shareAction];

        if (![mediaURL isFileURL]) {
            UIAction *copyLinkAction = [UIAction actionWithTitle:@"Copy Link"
                                                          image:[SCIAssetUtils instagramIconNamed:@"link" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                                     identifier:nil
                                                        handler:^(__unused UIAction *a) {
                UIPasteboard.generalPasteboard.string = mediaURL.absoluteString;
                SCINotify(kSCINotificationUnsentMessage, @"Copied link", nil, @"circle_check_filled", SCINotificationToneSuccess);
            }];
            [children addObject:copyLinkAction];
        }
    }

    UIAction *deleteAction = [UIAction actionWithTitle:@"Delete"
                                                image:[SCIAssetUtils instagramIconNamed:@"trash" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate]
                                           identifier:nil
                                              handler:^(__unused UIAction *a) {
        [SCIDeletedMessagesStorage deleteMessageId:message.messageId forOwnerPK:weakSelf.ownerPK];
    }];
    /// TODO: investigate whether native UIMenu destructive tint can be customized. UIMenuElement exposes no supported color API.
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
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [SCIDeletedMessagesStorage deleteMessageId:message.messageId forOwnerPK:self.ownerPK];
        completionHandler(YES);
    }];
    deleteAction.image = [SCIAssetUtils instagramIconNamed:@"trash" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    deleteAction.backgroundColor = [SCIUtils SCIColor_InstagramDestructive];
    deleteAction.accessibilityLabel = @"Delete";
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

@end

#import "SCIDeletedMessagesStorageViewController.h"

#import "SCIDeletedMessagesStorage.h"
#import "SCIDeletedMessagesViewController.h"
#import "../../../Utils.h"
#import "../../../Shared/UI/SCIIGAlertPresenter.h"

@interface SCIDeletedMessagesStorageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, assign) NSUInteger messageCount;
@property (nonatomic, assign) unsigned long long mediaBytes;
@end

@implementation SCIDeletedMessagesStorageViewController

static NSString *SCIDMStorageOwnerPK(void) {
    @try {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            id session = nil;
            @try { session = [window valueForKey:@"userSession"]; } @catch (__unused id e) {}
            id user = nil;
            @try { user = [session valueForKey:@"user"]; } @catch (__unused id e) {}
            for (NSString *key in @[@"pk", @"instagramUserID", @"instagramUserId", @"userID", @"userId"]) {
                id value = nil;
                @try { value = [user valueForKey:key]; } @catch (__unused id e) {}
                if ([value isKindOfClass:NSString.class] && [value length]) return value;
                if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
            }
        }
    } @catch (__unused id e) {}
    NSArray<NSString *> *owners = [SCIDeletedMessagesStorage allOwnerPKs];
    return owners.firstObject ?: @"anon";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Storage";
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:SCIDeletedMessagesDidChangeNotification object:nil];
    [self reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadData {
    self.ownerPK = SCIDMStorageOwnerPK();
    NSArray *messages = [SCIDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK];
    self.messageCount = messages.count;
    self.mediaBytes = [SCIDeletedMessagesStorage mediaSizeBytesForOwnerPK:self.ownerPK];
    [self.tableView reloadData];
}

+ (NSString *)formatBytes:(unsigned long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 2 : 2; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"storage"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"storage"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    cell.selectedBackgroundView = [UIView new];
    cell.selectedBackgroundView.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
    cell.textLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    cell.detailTextLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];
    if (indexPath.section == 0 && indexPath.row == 0) {
        cell.textLabel.text = @"Messages";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.messageCount];
    } else if (indexPath.section == 0) {
        cell.textLabel.text = @"Media";
        cell.detailTextLabel.text = [SCIDeletedMessagesStorageViewController formatBytes:self.mediaBytes];
    } else if (indexPath.row == 0) {
        cell.textLabel.text = @"Clear media files";
        cell.textLabel.textColor = [SCIUtils SCIColor_InstagramDestructive];
        cell.detailTextLabel.text = nil;
    } else {
        cell.textLabel.text = @"Clear deleted message log";
        cell.textLabel.textColor = [SCIUtils SCIColor_InstagramDestructive];
        cell.detailTextLabel.text = nil;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    if (indexPath.row == 0) [self clearMedia];
    else [self clearLog];
}

- (void)clearMedia {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Clear media files?"
                                                message:@"This removes all captured media (photos, videos, voice notes) but keeps the message log."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Clear Media" style:SCIIGAlertActionStyleDestructive handler:^{
            for (SCIDeletedMessage *message in [SCIDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK]) {
                NSString *media = [SCIDeletedMessagesStorage absolutePathForRelativePath:message.mediaPath ownerPK:self.ownerPK];
                NSString *thumb = [SCIDeletedMessagesStorage absolutePathForRelativePath:message.thumbnailPath ownerPK:self.ownerPK];
                if (media.length) [NSFileManager.defaultManager removeItemAtPath:media error:nil];
                if (thumb.length) [NSFileManager.defaultManager removeItemAtPath:thumb error:nil];
                message.mediaPath = nil;
                message.thumbnailPath = nil;
                [SCIDeletedMessagesStorage saveMessage:message forOwnerPK:self.ownerPK];
            }
        }],
    ]];
}

- (void)clearLog {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Clear deleted message log?"
                                                message:@"This removes every logged deleted message and captured media for this account."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Clear" style:SCIIGAlertActionStyleDestructive handler:^{
            [SCIDeletedMessagesStorage resetForOwnerPK:self.ownerPK];
        }],
    ]];
}

@end

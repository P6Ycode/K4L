#import "SCIGalleryFileDetailsViewController.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryCoreDataStack.h"
#import "../Account/SCIAccountManager.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../../Utils.h"

typedef NS_ENUM(NSInteger, SCIDetailsEditRow) {
    SCIDetailsEditRowName = 0,
    SCIDetailsEditRowUsername,
    SCIDetailsEditRowAccount,
    SCIDetailsEditRowDate,
    SCIDetailsEditRowCount,
};

@interface SCIGalleryFileDetailsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) SCIGalleryFile *file;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UIDatePicker *datePicker;
// Pending owner-account selection (applied on save). nil PK = unassigned.
@property (nonatomic, copy, nullable) NSString *selectedOwnerPK;
@property (nonatomic, copy, nullable) NSString *selectedOwnerUsername;
// Read-only (label, value) info pairs.
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *infoRows;
@end

@implementation SCIGalleryFileDetailsViewController

- (instancetype)initWithFile:(SCIGalleryFile *)file {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _file = file;
        _selectedOwnerPK = file.ownerAccountPK.length > 0 ? file.ownerAccountPK : nil;
        _selectedOwnerUsername = file.ownerUsername.length > 0 ? file.ownerUsername : nil;
        [self buildControls];
        [self buildInfoRows];
    }
    return self;
}

- (void)buildControls {
    _nameField = [self editableField];
    _nameField.text = self.file.customName;
    _nameField.placeholder = @"Display name";
    _nameField.autocapitalizationType = UITextAutocapitalizationTypeNone;

    _usernameField = [self editableField];
    _usernameField.text = self.file.sourceUsername;
    _usernameField.placeholder = @"Username";
    _usernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _usernameField.autocorrectionType = UITextAutocorrectionTypeNo;

    _datePicker = [[UIDatePicker alloc] init];
    _datePicker.datePickerMode = UIDatePickerModeDateAndTime;
    _datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    _datePicker.date = self.file.dateAdded ?: [NSDate date];
    _datePicker.tintColor = [SCIUtils SCIColor_InstagramBlue];
}

- (UITextField *)editableField {
    UITextField *field = [[UITextField alloc] init];
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;
    field.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    field.textAlignment = NSTextAlignmentRight;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    return field;
}

- (void)buildInfoRows {
    NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray array];
    NSString *typeName = @"Photo";
    if (self.file.mediaType == SCIGalleryMediaTypeVideo) typeName = @"Video";
    else if (self.file.mediaType == SCIGalleryMediaTypeAudio) typeName = @"Audio";
    [rows addObject:@[@"Type", typeName]];
    if (self.file.pixelWidth > 0 && self.file.pixelHeight > 0) {
        [rows addObject:@[@"Dimensions", [NSString stringWithFormat:@"%d × %d", self.file.pixelWidth, self.file.pixelHeight]]];
    }
    if (self.file.mediaType == SCIGalleryMediaTypeVideo && self.file.durationSeconds > 0) {
        NSInteger total = (NSInteger)llround(self.file.durationSeconds);
        [rows addObject:@[@"Duration", [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)]]];
    }
    if (self.file.fileSize > 0) {
        [rows addObject:@[@"Size", [NSByteCountFormatter stringFromByteCount:self.file.fileSize countStyle:NSByteCountFormatterCountStyleFile]]];
    }
    NSString *folder = self.file.folderPath.length > 0 ? [self.file.folderPath lastPathComponent] : @"Gallery";
    [rows addObject:@[@"Folder", folder]];
    if (self.file.sourceMediaCode.length > 0) {
        [rows addObject:@[@"Media code", self.file.sourceMediaCode]];
    }
    self.infoRows = rows;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Edit Details";
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                          target:self
                                                                                          action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                           target:self
                                                                                           action:@selector(save)];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    [self.view endEditing:YES];
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *username = [self.usernameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.file.customName = name.length > 0 ? name : nil;
    self.file.sourceUsername = username.length > 0 ? username : nil;
    self.file.dateAdded = self.datePicker.date;
    self.file.ownerAccountPK = self.selectedOwnerPK.length > 0 ? self.selectedOwnerPK : nil;
    self.file.ownerUsername = self.selectedOwnerPK.length > 0 ? self.selectedOwnerUsername : nil;
    [[SCIGalleryCoreDataStack shared] saveContext];
    if (self.onSaved) {
        self.onSaved();
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Details" : @"Info";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? SCIDetailsEditRowCount : (NSInteger)self.infoRows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    cell.textLabel.textColor = [SCIUtils SCIColor_InstagramPrimaryText];
    cell.detailTextLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText];

    if (indexPath.section == 0) {
        switch ((SCIDetailsEditRow)indexPath.row) {
            case SCIDetailsEditRowName:
                cell.textLabel.text = @"Name";
                [self embedAccessory:self.nameField inCell:cell];
                break;
            case SCIDetailsEditRowUsername:
                cell.textLabel.text = @"Username";
                [self embedAccessory:self.usernameField inCell:cell];
                break;
            case SCIDetailsEditRowAccount: {
                cell.textLabel.text = @"Account";
                cell.detailTextLabel.text = [self ownerDisplayText];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                UIView *selectedBackground = [[UIView alloc] init];
                selectedBackground.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
                cell.selectedBackgroundView = selectedBackground;
                break;
            }
            case SCIDetailsEditRowDate:
                cell.textLabel.text = @"Date";
                [self embedAccessory:self.datePicker inCell:cell];
                break;
            default:
                break;
        }
    } else {
        NSArray<NSString *> *row = self.infoRows[indexPath.row];
        cell.textLabel.text = row.firstObject;
        cell.detailTextLabel.text = row.lastObject;
    }
    return cell;
}

- (NSString *)ownerDisplayText {
    if (self.selectedOwnerPK.length == 0) return @"Unassigned";
    NSString *username = self.selectedOwnerUsername.length > 0
        ? self.selectedOwnerUsername
        : [SCIAccountManager usernameForPK:self.selectedOwnerPK];
    return username.length > 0 ? [@"@" stringByAppendingString:username] : self.selectedOwnerPK;
}

// Accounts offered in the picker: the roster of seen accounts, plus the file's
// current owner if it isn't in the roster (so an external/edited owner stays
// selectable).
- (NSArray<NSDictionary *> *)pickerAccounts {
    NSMutableArray<NSDictionary *> *accounts = [[SCIAccountManager knownAccounts] mutableCopy];
    BOOL hasSelected = NO;
    for (NSDictionary *account in accounts) {
        if ([account[@"pk"] isEqualToString:self.selectedOwnerPK]) { hasSelected = YES; break; }
    }
    if (self.selectedOwnerPK.length > 0 && !hasSelected) {
        [accounts addObject:@{ @"pk": self.selectedOwnerPK, @"username": self.selectedOwnerUsername ?: @"" }];
    }
    return accounts;
}

- (void)presentAccountPicker {
    __weak typeof(self) weakSelf = self;
    NSMutableArray<SCIIGAlertAction *> *actions = [NSMutableArray array];
    for (NSDictionary *account in [self pickerAccounts]) {
        NSString *pk = account[@"pk"];
        NSString *username = account[@"username"];
        if (![pk isKindOfClass:[NSString class]] || pk.length == 0) continue;
        NSString *title = username.length > 0 ? [@"@" stringByAppendingString:username] : pk;
        [actions addObject:[SCIIGAlertAction actionWithTitle:title style:SCIIGAlertActionStyleDefault handler:^{
            weakSelf.selectedOwnerPK = pk;
            weakSelf.selectedOwnerUsername = username.length > 0 ? username : nil;
            [weakSelf.tableView reloadData];
        }]];
    }
    [actions addObject:[SCIIGAlertAction actionWithTitle:@"Unassigned" style:SCIIGAlertActionStyleDestructive handler:^{
        weakSelf.selectedOwnerPK = nil;
        weakSelf.selectedOwnerUsername = nil;
        [weakSelf.tableView reloadData];
    }]];
    [actions addObject:[SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil]];

    [SCIIGAlertPresenter presentActionSheetFromViewController:self
                                                       title:@"Account"
                                                     message:@"Which account does this file belong to?"
                                                     actions:actions];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && (SCIDetailsEditRow)indexPath.row == SCIDetailsEditRowAccount) {
        [self.view endEditing:YES];
        [self presentAccountPicker];
    }
}

- (void)embedAccessory:(UIView *)view inCell:(UITableViewCell *)cell {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    cell.accessoryView = nil;
    [cell.contentView addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:12],
        [view.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        [view.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
    ]];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

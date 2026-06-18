#import "SCIEditActionsListViewController.h"
#include <UIKit/UIKit.h>

#import "SCIActionSectionEditViewController.h"
#import "SCIBulkActionMenuEditViewController.h"
#import "SCITopicSettingsSupport.h"
#import "../Shared/UI/SCISwitch.h"
#import "../Shared/UI/SCIMediaChrome.h"
#import "../Shared/ActionButton/SCIActionDescriptor.h"
#import "../AssetUtils.h"
#import "../Utils.h"

static char kSCIActionsListSwitchAssocKey;

@interface SCIEditActionsListViewController () <UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate, UITableViewDropDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) SCIActionButtonConfiguration *configuration;
@property (nonatomic, assign) SCIActionButtonSource source;

@end

@implementation SCIEditActionsListViewController

- (UIView *)selectionBackgroundView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
    return view;
}

- (instancetype)initWithSource:(SCIActionButtonSource)source topicTitle:(NSString *)topicTitle {
    self = [super init];
    if (self) {
        _source = source;
        _configuration = [SCIActionButtonConfiguration configurationForSource:source
                                                                   topicTitle:topicTitle
                                                             supportedActions:SCIActionButtonSupportedActionsForSource(source)
                                                              defaultSections:SCIActionButtonDefaultSectionsForSource(source)];
        self.title = @"Configure Actions";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ SCIMediaChromeTopBarButtonItem(@"plus", self, @selector(addSectionTapped)) ]);
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.dragInteractionEnabled = YES;
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    self.tableView.tintColor = [SCIUtils SCIColor_Primary];
    [self.view addSubview:self.tableView];
}

- (NSArray<NSString *> *)bulkEditorKinds {
    // Download All / Copy All are derived from the single-item action config and
    // are no longer separately configurable. Only the profile Copy Info submenu
    // remains editable here.
    NSMutableArray<NSString *> *kinds = [NSMutableArray array];
    if (self.source == SCIActionButtonSourceProfile) {
        [kinds addObject:@"copy_info"];
    }
    return kinds;
}

- (BOOL)hasBulkEditorSection {
    return [self bulkEditorKinds].count > 0;
}

- (NSInteger)bulkEditorSectionIndex {
    return [self hasBulkEditorSection] ? 1 : NSNotFound;
}

- (NSInteger)unassignedSectionIndex {
    return [self hasBulkEditorSection] ? 2 : 1;
}

- (NSInteger)availableSectionIndex {
    return [self hasBulkEditorSection] ? 3 : 2;
}

- (NSString *)bulkEditorKindForRow:(NSInteger)row {
    NSArray<NSString *> *kinds = [self bulkEditorKinds];
    if (row < 0 || row >= (NSInteger)kinds.count) {
        return nil;
    }
    return kinds[row];
}

- (NSString *)bulkEditorTitleForKind:(NSString *)kind {
    if ([kind isEqualToString:@"copy_info"]) {
        return @"Configure Copy Info Menu";
    }
    return @"Configure Menu";
}

- (NSString *)bulkEditorSubtitleForKind:(NSString *)kind {
    (void)kind;
    return nil;
}

- (SCIBulkActionMenuEditViewController *)bulkEditorControllerForKind:(NSString *)kind {
    if ([kind isEqualToString:@"copy_info"]) {
        return [[SCIBulkActionMenuEditViewController alloc] initWithTitle:@"Copy Info Menu"
                                                                   source:self.source
                                                         supportedActions:SCIProfileCopyInfoSupportedActions()
                                                        configuredActions:SCIProfileConfiguredCopyInfoActions()
                                                                   onSave:^(NSArray<NSString *> *actions) {
            SCIProfileSetConfiguredCopyInfoActions(actions);
        }];
    }

    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self hasBulkEditorSection] ? 4 : 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.configuration.sections.count;
    if (section == [self bulkEditorSectionIndex]) return [self bulkEditorKinds].count;
    if (section == [self unassignedSectionIndex]) return self.configuration.unassignedActions.count;
    return self.configuration.supportedActions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Menu Sections";
    if (section == [self bulkEditorSectionIndex]) return @"All Menus";
    if (section == [self unassignedSectionIndex]) return @"Unassigned Actions";
    return @"Available Actions";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Long press and drag to reorder sections.";
    if (section == [self unassignedSectionIndex]) return @"Actions here are supported but do not appear in the runtime menu.";
    if (section == [self availableSectionIndex]) return @"Disabled actions are hidden even if they remain assigned to a section.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    UIListContentConfiguration *config = cell.defaultContentConfiguration;
    cell.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    cell.tintColor = [SCIUtils SCIColor_Primary];
    cell.selectedBackgroundView = [self selectionBackgroundView];
    config.textProperties.color = [SCIUtils SCIColor_InstagramPrimaryText];
    config.secondaryTextProperties.color = [SCIUtils SCIColor_InstagramSecondaryText];

    if (indexPath.section == 0) {
        SCIActionMenuSection *section = self.configuration.sections[indexPath.row];
        config.text = section.title;
        config.secondaryText = section.collapsible ? @"Collapsible" : @"Inline";
        config.image = SCISettingsIcon(section.iconName);
        config.imageProperties.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.showsReorderControl = YES;
    } else if (indexPath.section == [self bulkEditorSectionIndex]) {
        NSString *kind = [self bulkEditorKindForRow:indexPath.row];
        config.text = [self bulkEditorTitleForKind:kind];
        config.secondaryText = [self bulkEditorSubtitleForKind:kind];
        config.image = SCISettingsIcon([kind isEqualToString:@"download"] ? @"download" : @"copy");
        config.imageProperties.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.section == [self unassignedSectionIndex]) {
        NSString *identifier = self.configuration.unassignedActions[indexPath.row];
        config.text = SCIActionDescriptorDisplayTitle(identifier, self.configuration.topicTitle);
        config.image = SCISettingsIcon(SCIActionDescriptorIconName(identifier));
        config.imageProperties.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];
    } else {
        NSString *identifier = self.configuration.supportedActions[indexPath.row];
        config.text = SCIActionDescriptorDisplayTitle(identifier, self.configuration.topicTitle);
        config.image = SCISettingsIcon(SCIActionDescriptorIconName(identifier));
        config.imageProperties.tintColor = [SCIUtils SCIColor_InstagramPrimaryText];

        SCISwitch *toggle = [[SCISwitch alloc] init];
        toggle.on = ![self.configuration.disabledActions containsObject:identifier];
        objc_setAssociatedObject(toggle, &kSCIActionsListSwitchAssocKey, identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [toggle addTarget:self action:@selector(disabledSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    cell.contentConfiguration = config;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0) return @[];
    SCIActionMenuSection *section = self.configuration.sections[indexPath.row];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:[[NSItemProvider alloc] initWithObject:section.identifier]];
    item.localObject = section.identifier;
    return @[item];
}

- (BOOL)tableView:(UITableView *)tableView dragSessionAllowsMoveOperation:(id<UIDragSession>)session {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView dragSessionIsRestrictedToDraggingApplication:(id<UIDragSession>)session {
    return YES;
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
    if (session.localDragSession == nil || destinationIndexPath.section != 0) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *destinationIndexPath = coordinator.destinationIndexPath;
    id<UITableViewDropItem> dropItem = coordinator.items.firstObject;
    NSIndexPath *sourceIndexPath = dropItem.sourceIndexPath;
    if (!destinationIndexPath ||
        !sourceIndexPath ||
        sourceIndexPath.section != 0 ||
        destinationIndexPath.section != 0) return;

    NSInteger rowCount = self.configuration.sections.count;
    NSInteger destinationRow = MIN(MAX(0, destinationIndexPath.row), MAX(0, rowCount - 1));
    NSIndexPath *target = [NSIndexPath indexPathForRow:destinationRow inSection:0];

    [tableView performBatchUpdates:^{
        [self.configuration moveSectionFromIndex:sourceIndexPath.row toIndex:target.row];
        [self.configuration save];
        [tableView moveRowAtIndexPath:sourceIndexPath toIndexPath:target];
    } completion:nil];
    [coordinator dropItem:dropItem.dragItem toRowAtIndexPath:target];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == [self bulkEditorSectionIndex]) {
        NSString *kind = [self bulkEditorKindForRow:indexPath.row];
        UIViewController *controller = [self bulkEditorControllerForKind:kind];
        if (controller) {
            [self.navigationController pushViewController:controller animated:YES];
        }
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    if (indexPath.section == 0) {
        SCIActionMenuSection *section = self.configuration.sections[indexPath.row];
        __weak typeof(self) weakSelf = self;
        SCIActionSectionEditViewController *controller = [[SCIActionSectionEditViewController alloc] initWithConfiguration:self.configuration sectionIdentifier:section.identifier onChange:^{
            [weakSelf.configuration save];
            [weakSelf.tableView reloadData];
        }];
        [self.navigationController pushViewController:controller animated:YES];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (void)removeSectionAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0 || indexPath.row >= (NSInteger)self.configuration.sections.count) return;

    SCIActionMenuSection *section = self.configuration.sections[indexPath.row];
    for (NSString *identifier in section.actions) {
        if (![self.configuration.unassignedActions containsObject:identifier]) {
            [self.configuration.unassignedActions addObject:identifier];
        }
    }
    [self.configuration.sections removeObjectAtIndex:indexPath.row];
    [self.configuration save];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    [self removeSectionAtIndexPath:indexPath];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self tableView:tableView canEditRowAtIndexPath:indexPath]) return nil;

    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [weakSelf removeSectionAtIndexPath:indexPath];
        completionHandler(YES);
    }];
    deleteAction.image = [SCIAssetUtils instagramIconNamed:@"trash" pointSize:22.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    deleteAction.backgroundColor = [SCIUtils SCIColor_InstagramDestructive];
    deleteAction.accessibilityLabel = @"Remove Section";
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

- (void)addSectionTapped {
    SCIActionMenuSection *section = [SCIActionMenuSection sectionWithIdentifier:NSUUID.UUID.UUIDString
                                                                          title:[NSString stringWithFormat:@"Section %lu", (unsigned long)(self.configuration.sections.count + 1)]
                                                                       iconName:@"more"
                                                                    collapsible:YES
                                                                        actions:@[]];
    [self.configuration.sections addObject:section];
    [self.configuration save];
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    SCIActionSectionEditViewController *controller = [[SCIActionSectionEditViewController alloc] initWithConfiguration:self.configuration sectionIdentifier:section.identifier onChange:^{
        [weakSelf.configuration save];
        [weakSelf.tableView reloadData];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)disabledSwitchChanged:(UISwitch *)sender {
    NSString *identifier = objc_getAssociatedObject(sender, &kSCIActionsListSwitchAssocKey);
    if (identifier.length == 0) return;

    if (sender.isOn) {
        [self.configuration.disabledActions removeObject:identifier];
    } else if (![self.configuration.disabledActions containsObject:identifier]) {
        [self.configuration.disabledActions addObject:identifier];
    }
    [self.configuration save];
}

@end

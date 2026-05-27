#import "SCISettingsViewController.h"
#import "../App/SCIStartupHooks.h"
#import "../Shared/ActionButton/ActionButtonCore.h"
#import "../Shared/UI/SCIIGAlertPresenter.h"
#import "../Shared/UI/SCIMediaChrome.h"
#import "../Shared/UI/SCISwitch.h"
#import "SCIPreferenceAvailability.h"
#import "../AssetUtils.h"

static char rowStaticRef[] = "row";
static NSInteger const kSCIUINavigationItemSearchBarPlacementStacked = 2;
static CGFloat const kSCISettingsRemoteImageSize = 45.0;

static NSCache<NSString *, UIImage *> *SCISettingsRemoteImageCache(void) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 64;
    });
    return cache;
}

static double SCINormalizedStepperValue(SCISetting *row, double value) {
    if (!row) return value;

    if (row.max >= row.min) {
        value = MIN(row.max, MAX(row.min, value));
    }

    if (row.step > 0.0) {
        double origin = row.min;
        double stepCount = round((value - origin) / row.step);
        value = origin + (stepCount * row.step);
        if (row.max >= row.min) {
            value = MIN(row.max, MAX(row.min, value));
        }
    }

    double nearestInteger = round(value);
    if (fabs(value - nearestInteger) < 0.0000001) {
        value = nearestInteger;
    }

    return value;
}

@interface SCISettingsViewController () <UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate, UITableViewDropDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *sections;
@property (nonatomic, strong) NSArray *originalSections;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIBarButtonItem *applyRestartItem;
@property (nonatomic) BOOL reduceMargin;
@property (nonatomic) BOOL defersRestartPrompt;
@property (nonatomic) BOOL hasPendingRestartChanges;

@end

///

static UIImage *SCISettingsReorderCompositeImage(UIImage *iconImage, UIColor *tintColor) {
    UIImageSymbolConfiguration *grabberConfig = [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightSemibold];
    UIImage *grabber = [[UIImage systemImageNamed:@"line.3.horizontal" withConfiguration:grabberConfig] imageWithTintColor:[SCIUtils SCIColor_InstagramTertiaryText] renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (!grabber || !iconImage) return iconImage ?: grabber;

    CGFloat spacing = 8.0;
    CGSize size = CGSizeMake(grabber.size.width + spacing + iconImage.size.width,
                             MAX(grabber.size.height, iconImage.size.height));
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        CGFloat grabberY = floor((size.height - grabber.size.height) / 2.0);
        [grabber drawAtPoint:CGPointMake(0.0, grabberY)];

        UIImage *renderedIcon = [iconImage imageWithTintColor:tintColor ?: [SCIUtils SCIColor_InstagramPrimaryText] renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGFloat iconY = floor((size.height - renderedIcon.size.height) / 2.0);
        [renderedIcon drawAtPoint:CGPointMake(grabber.size.width + spacing, iconY)];
    }];
}

static NSMutableArray *SCIMutableSectionsCopy(NSArray *sections) {
    NSMutableArray *mutableSections = [NSMutableArray array];
    for (NSDictionary *section in sections) {
        NSMutableDictionary *mutableSection = [section mutableCopy];
        NSArray *rows = section[@"rows"];
        mutableSection[@"rows"] = rows ? [rows mutableCopy] : [NSMutableArray array];
        [mutableSections addObject:mutableSection];
    }
    return mutableSections;
}

static UIImage *SCISettingsSizedRemoteImage(UIImage *image, BOOL circular) {
    if (!image) return nil;

    CGSize targetSize = CGSizeMake(kSCISettingsRemoteImageSize, kSCISettingsRemoteImageSize);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = UIScreen.mainScreen.scale;

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        CGRect bounds = (CGRect){.origin = CGPointZero, .size = targetSize};
        if (circular) {
            [[UIBezierPath bezierPathWithOvalInRect:bounds] addClip];
        }

        CGFloat scale = MAX(targetSize.width / image.size.width, targetSize.height / image.size.height);
        CGSize drawSize = CGSizeMake(image.size.width * scale, image.size.height * scale);
        CGRect drawRect = CGRectMake((targetSize.width - drawSize.width) / 2.0,
                                     (targetSize.height - drawSize.height) / 2.0,
                                     drawSize.width,
                                     drawSize.height);
        [image drawInRect:drawRect];
    }];
}

static NSString *SCISettingsNormalizedQuery(NSString *query) {
    return [[query ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
}

static BOOL SCISettingsStringMatchesQuery(NSString *string, NSString *query) {
    if (query.length == 0) return YES;
    return [[string ?: @"" lowercaseString] containsString:query];
}

static BOOL SCISettingsRowMatchesQuery(SCISetting *row, NSString *query, NSString *path, NSString *sectionTitle) {
    if (![row isKindOfClass:[SCISetting class]]) return NO;
    return SCISettingsStringMatchesQuery(row.title, query) ||
           SCISettingsStringMatchesQuery(row.subtitle, query) ||
           SCISettingsStringMatchesQuery(path, query) ||
           SCISettingsStringMatchesQuery(sectionTitle, query);
}

@implementation SCISettingsViewController

- (UIView *)selectionBackgroundView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [SCIUtils SCIColor_InstagramPressedBackground];
    return view;
}

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray *)sections reduceMargin:(BOOL)reduceMargin {
    self = [super init];

    if (self) {
        self.title = title;
        self.reduceMargin = reduceMargin;

        // Exclude development cells from release builds
        NSMutableArray *mutableSections = SCIMutableSectionsCopy(sections);

        [mutableSections enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSDictionary *section, NSUInteger index, BOOL *stop) {

            if ([section[@"header"] hasPrefix:@"_"] && [section[@"footer"] hasPrefix:@"_"]) {
                if (![[SCIUtils IGVersionString] isEqualToString:@"0.0.0"]) {
                    [mutableSections removeObjectAtIndex:index];
                }
            }

            else if ([section[@"header"] isEqualToString:@"Experimental"]) {
                if (![[SCIUtils IGVersionString] hasSuffix:@"-dev"]) {
                    [mutableSections removeObjectAtIndex:index];
                }
            }

        }];

        self.originalSections = [mutableSections copy];
        self.sections = mutableSections;
    }


    return self;
}

- (instancetype)init {
    self = [self initWithTitle:[SCITweakSettings title] sections:[SCITweakSettings sections] reduceMargin:YES];
    if (self) {
        self.searchesAllSettings = YES;
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
    self.tableView.dragInteractionEnabled = [self pageAllowsReordering];
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
    self.tableView.backgroundColor = [SCIUtils SCIColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SCIUtils SCIColor_InstagramSeparator];
    self.tableView.tintColor = [SCIUtils SCIColor_Primary];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;

    [self.view addSubview:self.tableView];
    [self setupNavigationItems];
    [self setupSearchController];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setupNavigationItems];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (![[[NSUserDefaults standardUserDefaults] objectForKey:@"app_first_run"] isEqualToString:SCIVersionString]) {
        UIViewController *presenter = self.presentingViewController;
        [SCIIGAlertPresenter presentAlertFromViewController:presenter
                                                      title:@"SCInsta Settings Info"
                                                    message:@"In the future: Hold down on the three lines at the top right of your profile page, to re-open SCInsta settings."
                                                    actions:@[
            [SCIIGAlertAction actionWithTitle:@"I understand!" style:SCIIGAlertActionStyleDefault handler:nil],
        ]];

        // Done with first-time setup for this version
        [[NSUserDefaults standardUserDefaults] setValue:SCIVersionString forKey:@"app_first_run"];
    }
}

- (void)setupNavigationItems {
    BOOL isModalRoot = self.navigationController.presentingViewController &&
                       self.navigationController.viewControllers.firstObject == self;
    NSArray<UIBarButtonItem *> *leadingItems = isModalRoot
        ? @[ SCIMediaChromeTopBarButtonItem(@"xmark", self, @selector(closeTapped)) ]
        : @[];
    SCIMediaChromeSetLeadingTopBarItems(self.navigationItem, leadingItems);

    NSArray<UIBarButtonItem *> *trailingItems = @[];
    if (self.defersRestartPrompt) {
        UIBarButtonItem *applyItem = SCIMediaChromeTopBarButtonItemWithTint(@"check",
                                                                           self,
                                                                           @selector(applyRestartChanges),
                                                                           [SCIUtils SCIColor_InstagramPrimaryText],
                                                                           @"Apply Liquid Glass changes");
        applyItem.enabled = self.hasPendingRestartChanges;
        self.applyRestartItem = applyItem;
        trailingItems = @[ applyItem ];
    } else {
        self.applyRestartItem = nil;
    }
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, trailingItems);
}

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    [self.searchController.searchBar setImage:[SCIAssetUtils instagramIconNamed:@"search" pointSize:18.0] 
                         forSearchBarIcon:UISearchBarIconSearch 
                                    state:UIControlStateNormal];
    self.searchController.searchBar.placeholder = self.searchesAllSettings ? @"Search..." : [NSString stringWithFormat:@"Search %@", self.title ?: @"settings"];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    if (@available(iOS 26.0, *)) {
        @try {
            [self.navigationItem setValue:@(kSCIUINavigationItemSearchBarPlacementStacked) forKey:@"preferredSearchBarPlacement"];
        } @catch (__unused NSException *exception) {
        }
    }
    self.definesPresentationContext = YES;
}

- (void)closeTapped {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

// MARK: - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCISetting *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (!row) return nil;

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    UIListContentConfiguration *cellContentConfig = cell.defaultContentConfiguration;
    cell.backgroundColor = [SCIUtils SCIColor_InstagramSecondaryBackground];
    cell.tintColor = [SCIUtils SCIColor_Primary];
    cell.selectedBackgroundView = [self selectionBackgroundView];
    cellContentConfig.textProperties.color = [SCIUtils SCIColor_InstagramPrimaryText];
    cellContentConfig.secondaryTextProperties.color = [SCIUtils SCIColor_InstagramSecondaryText];
    cellContentConfig.textProperties.numberOfLines = 0;
    cellContentConfig.secondaryTextProperties.numberOfLines = 0;
    cellContentConfig.secondaryTextProperties.lineBreakMode = NSLineBreakByWordWrapping;
    BOOL rowEnabled = (row.userInfo[@"enabled"] ? [row.userInfo[@"enabled"] boolValue] : YES) && SCIPrefIsAvailable(row.defaultsKey);

    cellContentConfig.text = row.title;

    // Subtitle
    if (row.subtitle.length) {
        cellContentConfig.secondaryText = row.subtitle;
        cellContentConfig.textToSecondaryTextVerticalPadding = 4.5;
    }

    // Icon
    UIImage *rowIcon = row.iconProvider ? row.iconProvider() : row.icon;
    if (rowIcon != nil) {
        cellContentConfig.image = rowIcon;
        cellContentConfig.imageProperties.tintColor = row.iconTintColor ?: [SCIUtils SCIColor_InstagramPrimaryText];
    }

    if ([row.userInfo[@"showsReorderGrabber"] boolValue] && rowIcon != nil) {
        UIColor *iconTintColor = row.iconTintColor ?: [SCIUtils SCIColor_InstagramPrimaryText];
        cellContentConfig.image = SCISettingsReorderCompositeImage(rowIcon, iconTintColor);
        cellContentConfig.imageProperties.tintColor = nil;
        cellContentConfig.imageToTextPadding = 12.0;
    }

    // Image url
    if (row.imageUrl != nil) {
        BOOL circular = ![row.userInfo[@"remoteImageCircular"] isEqual:@NO];
        NSString *cacheKey = [NSString stringWithFormat:@"%@|%@", row.imageUrl.absoluteString, circular ? @"circle" : @"square"];
        UIImage *cachedImage = [SCISettingsRemoteImageCache() objectForKey:cacheKey];
        if (cachedImage) {
            cellContentConfig.image = cachedImage;
            cellContentConfig.imageProperties.maximumSize = CGSizeMake(kSCISettingsRemoteImageSize, kSCISettingsRemoteImageSize);
            cellContentConfig.imageProperties.reservedLayoutSize = CGSizeMake(kSCISettingsRemoteImageSize, kSCISettingsRemoteImageSize);
        } else {
            [self loadImageFromURL:row.imageUrl atIndexPath:indexPath forTableView:tableView circular:circular];
        }

        cellContentConfig.imageToTextPadding = 14;
    }

    // Custom Tint Color
    if (row.tintColor != nil && rowEnabled) {
        cellContentConfig.textProperties.color = row.tintColor;
    }

    switch (row.type) {
        case SCITableCellStatic: {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }

        case SCITableCellLink: {
            cellContentConfig.textProperties.color = [SCIUtils SCIColor_Primary];
            cellContentConfig.textProperties.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize
                                                                      weight:UIFontWeightMedium];

            cell.selectionStyle = UITableViewCellSelectionStyleDefault;

            UIImageView *imageView = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"compass"]];
            imageView.tintColor = [SCIUtils SCIColor_InstagramTertiaryText];
            cell.accessoryView = imageView;

            break;
        }

        case SCITableCellSwitch: {
            SCISwitch *toggle = [SCISwitch new];
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            if (row.switchValueProvider) {
                toggle.on = row.switchValueProvider();
            } else if (!SCIPrefIsAvailable(row.defaultsKey)) {
                toggle.on = NO;
            } else {
                id storedValue = [defaults objectForKey:row.defaultsKey];
                NSNumber *defaultValue = row.userInfo[@"defaultValue"];
                toggle.on = storedValue ? [defaults boolForKey:row.defaultsKey] : defaultValue.boolValue;
            }
            if (!row.switchValueProvider && row.mutuallyExclusiveDefaultsKey.length) {
                BOOL otherOn = [SCIUtils getBoolPref:row.mutuallyExclusiveDefaultsKey];
                toggle.enabled = toggle.isOn || !otherOn;
            }
            toggle.enabled = toggle.enabled && rowEnabled;
            if (!rowEnabled) {
                cellContentConfig.textProperties.color = [SCIUtils SCIColor_InstagramSecondaryText];
                cellContentConfig.secondaryTextProperties.color = [SCIUtils SCIColor_InstagramTertiaryText];
            }

            objc_setAssociatedObject(toggle, rowStaticRef, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];

            cell.accessoryView = toggle;
            cell.editingAccessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }

        case SCITableCellStepper: {
            UIStepper *stepper = [UIStepper new];
            stepper.minimumValue = row.min;
            stepper.maximumValue = row.max;
            stepper.stepValue = row.step;
            stepper.value = SCINormalizedStepperValue(row, [[NSUserDefaults standardUserDefaults] doubleForKey:row.defaultsKey]);

            objc_setAssociatedObject(stepper, rowStaticRef, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [stepper addTarget:self
                        action:@selector(stepperChanged:)
              forControlEvents:UIControlEventValueChanged];

            // Template subtitle
            if (row.subtitle.length) {
                cellContentConfig.secondaryText = [self formatString:row.subtitle withValue:stepper.value step:row.step label:row.label singularLabel:row.singularLabel];
            }

            cell.accessoryView = stepper;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }

        case SCITableCellButton: {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }

        case SCITableCellMenu: {
            UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
            [menuButton setTitle:@"•••" forState:UIControlStateNormal];
            menuButton.menu = [row menuForButton:menuButton];
            menuButton.showsMenuAsPrimaryAction = YES;
            menuButton.enabled = rowEnabled;
            menuButton.titleLabel.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize
                                                           weight:UIFontWeightMedium];
            menuButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            [menuButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [menuButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

            UIButtonConfiguration *config = menuButton.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
            config.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
            config.image = [UIImage systemImageNamed:@"chevron.up.chevron.down"];
            config.imagePlacement = NSDirectionalRectEdgeTrailing;
            config.imagePadding = 6.0;
            config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:10.0 weight:UIImageSymbolWeightBold];
            
            menuButton.configuration = config;
            menuButton.tintColor = rowEnabled ? [SCIUtils SCIColor_InstagramSecondaryText] : [SCIUtils SCIColor_InstagramTertiaryText];
            if (!rowEnabled) {
                cellContentConfig.textProperties.color = [SCIUtils SCIColor_InstagramSecondaryText];
                cellContentConfig.secondaryTextProperties.color = [SCIUtils SCIColor_InstagramTertiaryText];
            }

            [menuButton sizeToFit];

            cell.accessoryView = menuButton;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }

        case SCITableCellNavigation: {
            NSString *accessoryText = [row.userInfo[@"accessoryText"] isKindOfClass:[NSString class]] ? row.userInfo[@"accessoryText"] : nil;
            if (rowEnabled && accessoryText.length > 0) {
                cellContentConfig.secondaryText = accessoryText;
                cellContentConfig.prefersSideBySideTextAndSecondaryText = YES;
                cellContentConfig.secondaryTextProperties.color = [SCIUtils SCIColor_InstagramSecondaryText];
                cellContentConfig.secondaryTextProperties.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize
                                                                                   weight:UIFontWeightMedium];
            }
            cell.accessoryType = rowEnabled ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
            if (!rowEnabled) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cellContentConfig.textProperties.color = [SCIUtils SCIColor_InstagramSecondaryText];
                cellContentConfig.secondaryTextProperties.color = [SCIUtils SCIColor_InstagramTertiaryText];
            }
            break;
        }

        case SCITableCellTextField: {
            UITextField *textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 150, 34)];
            textField.textAlignment = NSTextAlignmentRight;
            textField.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightMedium];
            textField.textColor = rowEnabled ? [SCIUtils SCIColor_InstagramPrimaryText] : [SCIUtils SCIColor_InstagramTertiaryText];
            textField.placeholder = row.placeholder;
            textField.keyboardType = row.keyboardType;
            textField.text = [[NSUserDefaults standardUserDefaults] stringForKey:row.defaultsKey];
            textField.enabled = rowEnabled;

            if (!rowEnabled) {
                cellContentConfig.textProperties.color = [SCIUtils SCIColor_InstagramSecondaryText];
            }

            objc_setAssociatedObject(textField, rowStaticRef, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [textField addTarget:self action:@selector(textFieldChanged:) forControlEvents:UIControlEventEditingDidEnd];

            cell.accessoryView = textField;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }

        case SCITableCellValue: {
            cellContentConfig.secondaryText = row.subtitle;
            cellContentConfig.prefersSideBySideTextAndSecondaryText = YES;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
    }

    cell.contentConfiguration = cellContentConfig;
    cell.showsReorderControl = NO;
    cell.shouldIndentWhileEditing = NO;

    return cell;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.sections[section][@"footer"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

// MARK: - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    SCISetting *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (!row) return;
    BOOL rowEnabled = (row.userInfo[@"enabled"] ? [row.userInfo[@"enabled"] boolValue] : YES) && SCIPrefIsAvailable(row.defaultsKey);
    if (!rowEnabled) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    if (row.type == SCITableCellLink) {
        [[UIApplication sharedApplication] openURL:row.url options:@{} completionHandler:nil];
    }
    else if (row.type == SCITableCellButton) {
        if (row.action != nil) {
            row.action();
        }
    }
    else if (row.type == SCITableCellNavigation) {
        if (row.navSections.count > 0) {
            UIViewController *vc = [[SCISettingsViewController alloc] initWithTitle:row.title sections:row.navSections reduceMargin:NO];
            ((SCISettingsViewController *)vc).defersRestartPrompt = [row.userInfo[@"deferRestartPrompt"] boolValue];
            vc.title = row.title;
            [self.navigationController pushViewController:vc animated:YES];
        }
        else if (row.navViewController) {
            [self.navigationController pushViewController:row.navViewController animated:YES];
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isSearching]) return NO;
    return [self.sections[indexPath.section][@"allowsReordering"] boolValue];
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (sourceIndexPath.section != proposedDestinationIndexPath.section) {
        NSInteger rowCount = [self.sections[sourceIndexPath.section][@"rows"] count];
        NSInteger targetRow = MIN(MAX(0, proposedDestinationIndexPath.row), MAX(0, rowCount - 1));
        return [NSIndexPath indexPathForRow:targetRow inSection:sourceIndexPath.section];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray *rows = self.sections[sourceIndexPath.section][@"rows"];
    if (![rows isKindOfClass:[NSMutableArray class]]) return;

    SCISetting *row = rows[sourceIndexPath.row];
    [rows removeObjectAtIndex:sourceIndexPath.row];
    [rows insertObject:row atIndex:destinationIndexPath.row];

    NSString *reorderDefaultsKey = self.sections[sourceIndexPath.section][@"reorderDefaultsKey"];
    if (reorderDefaultsKey.length > 0) {
        NSMutableArray<NSString *> *order = [NSMutableArray array];
        for (SCISetting *candidate in rows) {
            NSString *identifier = candidate.userInfo[@"actionIdentifier"];
            if (identifier.length > 0) [order addObject:identifier];
        }
        [[NSUserDefaults standardUserDefaults] setObject:[order copy] forKey:reorderDefaultsKey];
    }
    self.originalSections = [self.sections copy];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
    if (![self tableView:tableView canMoveRowAtIndexPath:indexPath]) {
        return @[];
    }

    SCISetting *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSString *identifier = row.userInfo[@"actionIdentifier"] ?: row.title ?: @"action";
    NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:identifier];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
    item.localObject = row;
    return @[item];
}

- (BOOL)tableView:(UITableView *)tableView dragSessionAllowsMoveOperation:(id<UIDragSession>)session {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView dragSessionIsRestrictedToDraggingApplication:(id<UIDragSession>)session {
    return YES;
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
    if (session.localDragSession == nil || destinationIndexPath == nil) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }
    if (![self.sections[destinationIndexPath.section][@"allowsReordering"] boolValue]) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *destinationIndexPath = coordinator.destinationIndexPath;
    if (destinationIndexPath == nil) return;

    id<UITableViewDropItem> dropItem = coordinator.items.firstObject;
    NSIndexPath *sourceIndexPath = dropItem.sourceIndexPath;
    if (sourceIndexPath == nil || sourceIndexPath.section != destinationIndexPath.section) return;
    if (![self tableView:tableView canMoveRowAtIndexPath:sourceIndexPath]) return;

    NSInteger rowCount = [self.sections[sourceIndexPath.section][@"rows"] count];
    NSInteger destinationRow = MIN(MAX(0, destinationIndexPath.row), MAX(0, rowCount - 1));
    NSIndexPath *clampedDestination = [NSIndexPath indexPathForRow:destinationRow inSection:destinationIndexPath.section];

    [tableView performBatchUpdates:^{
        [self tableView:tableView moveRowAtIndexPath:sourceIndexPath toIndexPath:clampedDestination];
        [tableView moveRowAtIndexPath:sourceIndexPath toIndexPath:clampedDestination];
    } completion:nil];

    [coordinator dropItem:dropItem.dragItem toRowAtIndexPath:clampedDestination];
}

// MARK: - Search

- (BOOL)isSearching {
    return self.searchController.isActive && self.searchController.searchBar.text.length > 0;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = SCISettingsNormalizedQuery(searchController.searchBar.text);
    if (query.length == 0) {
        self.sections = SCIMutableSectionsCopy(self.originalSections);
    } else if (self.searchesAllSettings) {
        self.sections = [self searchAllSettingsForQuery:query];
    } else {
        self.sections = [self filterCurrentSettingsForQuery:query];
    }
    self.tableView.dragInteractionEnabled = ![self isSearching] && [self pageAllowsReordering];
    [self.tableView reloadData];
}

- (NSMutableArray *)filterCurrentSettingsForQuery:(NSString *)query {
    NSMutableArray *filteredSections = [NSMutableArray array];
    for (NSDictionary *section in self.originalSections) {
        NSArray *rows = section[@"rows"];
        NSMutableArray *matchedRows = [NSMutableArray array];
        NSString *sectionTitle = section[@"header"];
        for (SCISetting *row in rows) {
            if (SCISettingsRowMatchesQuery(row, query, self.title, sectionTitle)) {
                [matchedRows addObject:row];
            }
        }
        if (matchedRows.count == 0) continue;

        NSMutableDictionary *filteredSection = [section mutableCopy];
        filteredSection[@"rows"] = matchedRows;
        filteredSection[@"allowsReordering"] = @NO;
        [filteredSections addObject:filteredSection];
    }
    return filteredSections;
}

- (NSMutableArray *)searchAllSettingsForQuery:(NSString *)query {
    NSMutableDictionary<NSString *, NSMutableArray<SCISetting *> *> *rowsByPath = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *orderedPaths = [NSMutableArray array];
    [self collectSearchRowsFromSections:self.originalSections
                                   path:self.title ?: @"Settings"
                                  query:query
                             rowsByPath:rowsByPath
                           orderedPaths:orderedPaths];

    NSMutableArray *sections = [NSMutableArray array];
    for (NSString *path in orderedPaths) {
        NSArray *rows = rowsByPath[path];
        if (rows.count == 0) continue;
        [sections addObject:[@{
            @"header": path,
            @"rows": [rows mutableCopy],
            @"allowsReordering": @NO
        } mutableCopy]];
    }
    return sections;
}

- (void)collectSearchRowsFromSections:(NSArray *)sections
                                  path:(NSString *)path
                                 query:(NSString *)query
                            rowsByPath:(NSMutableDictionary<NSString *, NSMutableArray<SCISetting *> *> *)rowsByPath
                          orderedPaths:(NSMutableArray<NSString *> *)orderedPaths {
    for (NSDictionary *section in sections) {
        NSString *sectionTitle = section[@"header"];
        NSString *sectionPath = sectionTitle.length > 0 ? [NSString stringWithFormat:@"%@ / %@", path, sectionTitle] : path;
        for (SCISetting *row in section[@"rows"]) {
            if (![row isKindOfClass:[SCISetting class]]) continue;

            if (SCISettingsRowMatchesQuery(row, query, sectionPath, sectionTitle)) {
                NSMutableArray *rows = rowsByPath[sectionPath];
                if (!rows) {
                    rows = [NSMutableArray array];
                    rowsByPath[sectionPath] = rows;
                    [orderedPaths addObject:sectionPath];
                }
                [rows addObject:row];
            }

            if (row.navSections.count > 0) {
                NSString *childPath = row.title.length > 0 ? [NSString stringWithFormat:@"%@ / %@", path, row.title] : path;
                [self collectSearchRowsFromSections:row.navSections
                                               path:childPath
                                              query:query
                                         rowsByPath:rowsByPath
                                       orderedPaths:orderedPaths];
            }
        }
    }
}

// MARK: - Actions

- (SCISetting *)settingForSender:(id)sender {
    return objc_getAssociatedObject(sender, rowStaticRef);
}

- (void)switchChanged:(UISwitch *)sender {
    SCISetting *row = objc_getAssociatedObject(sender, rowStaticRef);
    if (!row) return;
    if (!SCIPrefIsAvailable(row.defaultsKey)) {
        sender.on = NO;
        return;
    }

    if (row.switchChangeHandler) {
        row.switchChangeHandler(sender.isOn);
        if (row.action) {
            row.action();
        }
        return;
    }

    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:row.defaultsKey];
    if (sender.isOn && row.mutuallyExclusiveDefaultsKey.length) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:row.mutuallyExclusiveDefaultsKey];
    }

    SCILog(@"General", @"Switch changed: %@", sender.isOn ? @"ON" : @"OFF");
    if (sender.isOn) {
        SCIInstallEnabledFeatureHooks();
    }

    if (row.mutuallyExclusiveDefaultsKey.length) {
        [self.tableView reloadData];
    }

    if (row.requiresRestart) {
        if (self.defersRestartPrompt) {
            self.hasPendingRestartChanges = YES;
            self.applyRestartItem.enabled = YES;
        } else {
            [SCIUtils showRestartConfirmation];
        }
    }

    if (row.action) {
        row.action();
    }
}

- (void)textFieldChanged:(UITextField *)sender {
    SCISetting *row = objc_getAssociatedObject(sender, rowStaticRef);
    if (!row) return;

    NSString *value = [sender.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [[NSUserDefaults standardUserDefaults] setObject:value ?: @"" forKey:row.defaultsKey];
}

- (void)applyRestartChanges {
    [SCIUtils showRestartConfirmation];
}

- (void)stepperChanged:(UIStepper *)sender {
    SCISetting *row = objc_getAssociatedObject(sender, rowStaticRef);
    double normalizedValue = SCINormalizedStepperValue(row, sender.value);
    sender.value = normalizedValue;
    [[NSUserDefaults standardUserDefaults] setDouble:normalizedValue forKey:row.defaultsKey];

    SCILog(@"General", @"Stepper changed: %f", normalizedValue);

    [self reloadCellForView:sender];
}

- (void)menuChanged:(UICommand *)command {
    NSDictionary *properties = command.propertyList;

    [[NSUserDefaults standardUserDefaults] setValue:properties[@"value"] forKey:properties[@"defaultsKey"]];
    NSString *defaultsKey = properties[@"defaultsKey"];
    if ([defaultsKey containsString:@"_action_btn"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIActionButtonConfigurationDidChangeNotification object:nil];
    }

    SCILog(@"General", @"Menu changed: %@", command.propertyList[@"value"]);

    [self reloadCellForView:command.sender animated:YES];

    if (properties[@"requiresRestart"]) {
        [SCIUtils showRestartConfirmation];
    }
}

// MARK: - Helper

- (void)replaceSections:(NSArray *)sections {
    self.originalSections = [sections copy] ?: @[];
    self.sections = SCIMutableSectionsCopy(self.originalSections);
    self.tableView.dragInteractionEnabled = ![self isSearching] && [self pageAllowsReordering];
    [self.tableView reloadData];
}

- (NSString *)formatString:(NSString *)template withValue:(double)value step:(double)step label:(NSString *)label singularLabel:(NSString *)singularLabel {
    // Singular or plural labels
    NSString *applicableLabel = fabs(value - 1.0) < 0.00001 ? singularLabel : label;

    // Force value to 0 to prevent it being -0
    if (fabs(value) < 0.00001) {
        value = 0.0;
    }

    // Get correct decimal value based on step value
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = step > 0.0 ? [SCIUtils decimalPlacesInDouble:step] : [SCIUtils decimalPlacesInDouble:value];

    NSString *stringValue = [formatter stringFromNumber:@(value)];

    return [NSString stringWithFormat:template, stringValue, applicableLabel];
}

- (void)reloadCellForView:(UIView *)view animated:(BOOL)animated {
    UITableViewCell *cell = (UITableViewCell *)view.superview;
    while (cell && ![cell isKindOfClass:[UITableViewCell class]]) {
        cell = (UITableViewCell *)cell.superview;
    }
    if (!cell) return;

    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath) return;

    [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                          withRowAnimation:animated ? UITableViewRowAnimationAutomatic : UITableViewRowAnimationNone];
}
- (void)reloadCellForView:(UIView *)view {
    [self reloadCellForView:view animated:NO];
}

- (BOOL)pageAllowsReordering {
    if ([self isSearching]) return NO;
    for (NSDictionary *section in self.sections) {
        if ([section[@"allowsReordering"] boolValue]) {
            return YES;
        }
    }
    return NO;
}

- (void)loadImageFromURL:(NSURL *)url atIndexPath:(NSIndexPath *)indexPath forTableView:(UITableView *)tableView circular:(BOOL)circular
{
    if (!url) return;

    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@", url.absoluteString, circular ? @"circle" : @"square"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
    {
        if (!data || error) return;

        UIImage *image = SCISettingsSizedRemoteImage([UIImage imageWithData:data], circular);
        if (!image) return;
        [SCISettingsRemoteImageCache() setObject:image forKey:cacheKey];

        dispatch_async(dispatch_get_main_queue(), ^{
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            if (!cell) return;

            UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
            config.image = image;
            config.imageProperties.maximumSize = CGSizeMake(kSCISettingsRemoteImageSize, kSCISettingsRemoteImageSize);
            config.imageProperties.reservedLayoutSize = CGSizeMake(kSCISettingsRemoteImageSize, kSCISettingsRemoteImageSize);
            cell.contentConfiguration = config;
        });
    }];

    [task resume];
}

@end

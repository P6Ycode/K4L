#import "SCIGallerySettingsViewController.h"
#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryManager.h"
#import "SCIGalleryLockViewController.h"
#import "SCIGalleryImportViewController.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryCoreDataStack.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../../Utils.h"
#import "../../AssetUtils.h"
#import "../../Settings/SCITopicSettingsSupport.h"

static NSString * const kFavoritesAtTopKey = @"gallery_show_favorites_top";
static NSString * const kGalleryLongPressTabKey = @"gallery_quick_access_tab";
static NSString * const kGalleryQuickAccessDisabledValue = @"none";

@interface SCIGalleryStorageStats : NSObject
@property (nonatomic, assign) NSInteger totalFiles;
@property (nonatomic, assign) NSInteger imageCount;
@property (nonatomic, assign) NSInteger videoCount;
@property (nonatomic, assign) NSInteger audioCount;
@property (nonatomic, assign) long long totalSize;
@end

@implementation SCIGalleryStorageStats
@end

@interface SCIGallerySettingsViewController ()
@property (nonatomic, strong) SCIGalleryStorageStats *stats;
@end

@implementation SCIGallerySettingsViewController

- (instancetype)init {
    return [super initWithTitle:@"Gallery Settings" sections:@[] reduceMargin:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadStats];
    [self rebuildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadStats];
    [self rebuildSections];
}

- (void)reloadStats {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    NSArray<SCIGalleryFile *> *files = [ctx executeFetchRequest:req error:nil] ?: @[];

    SCIGalleryStorageStats *stats = [SCIGalleryStorageStats new];
    for (SCIGalleryFile *file in files) {
        stats.totalFiles += 1;
        stats.totalSize += file.fileSize;
        if (file.mediaType == SCIGalleryMediaTypeAudio) {
            stats.audioCount += 1;
        } else if (file.mediaType == SCIGalleryMediaTypeVideo) {
            stats.videoCount += 1;
        } else {
            stats.imageCount += 1;
        }
    }
    self.stats = stats;
}

- (NSString *)formattedSize:(long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)rebuildSections {
    NSMutableArray *sections = [NSMutableArray array];

    [sections addObject:SCITopicSection(@"Storage", @[
        [SCISetting valueCellWithTitle:@"Total" subtitle:[NSString stringWithFormat:@"%ld files • %@", (long)self.stats.totalFiles, [self formattedSize:self.stats.totalSize]] icon:SCISettingsIcon(@"info")],
        [SCISetting valueCellWithTitle:@"Images" subtitle:[NSString stringWithFormat:@"%ld", (long)self.stats.imageCount] icon:SCISettingsIcon(@"photo")],
        [SCISetting valueCellWithTitle:@"Videos" subtitle:[NSString stringWithFormat:@"%ld", (long)self.stats.videoCount] icon:SCISettingsIcon(@"video")],
        [SCISetting valueCellWithTitle:@"Audio" subtitle:[NSString stringWithFormat:@"%ld", (long)self.stats.audioCount] icon:SCISettingsIcon(@"audio")]
    ], nil)];

    SCISetting *favoritesRow = [SCISetting switchCellWithTitle:@"Show Favorites at Top" icon:SCISettingsIcon(@"heart") defaultsKey:kFavoritesAtTopKey];
    favoritesRow.action = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SCIGalleryFavoritesSortPreferenceChanged" object:nil];
    };
    [sections addObject:SCITopicSection(@"Browsing", @[favoritesRow], @"Pin favorites above other files inside the current sort and folder context.")];

    SCIGalleryManager *mgr = [SCIGalleryManager sharedManager];
    NSMutableArray *lockRows = [NSMutableArray array];

    __weak typeof(self) weakSelf = self;
    SCISetting *lockSwitch = [SCISetting switchCellWithTitle:@"Enable Passcode Lock" icon:SCISettingsIcon(@"lock") defaultsKey:@""];
    lockSwitch.switchValueProvider = ^BOOL{
        return [SCIGalleryManager sharedManager].isLockEnabled;
    };
    lockSwitch.switchChangeHandler = ^(BOOL isOn) {
        [weakSelf handleLockToggleEnabled:isOn];
    };
    [lockRows addObject:lockSwitch];

    if (mgr.isLockEnabled) {
        SCISetting *changePasscode = [SCISetting buttonCellWithTitle:@"Change Passcode" subtitle:nil icon:SCISettingsIcon(@"key") action:^{
            [SCIGalleryLockViewController presentMode:SCIGalleryLockModeChangePasscode
                                 fromViewController:self
                                         completion:^(BOOL success) {}];
        }];
        [lockRows addObject:changePasscode];
    }

    [sections addObject:SCITopicSection(@"Lock", lockRows, @"Lock the Gallery with a passcode or biometrics.")];

    SCISetting *shortcutTarget = SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Quick Gallery Access" icon:SCISettingsIcon(@"circle_off") menu:SCIGalleryShortcutTargetMenu()], SCISettingsIcon(@"circle_off"));

    [sections addObject:SCITopicSection(@"Shortcuts", @[shortcutTarget], @"Choose the tab that opens Gallery on long press. None disables the action.")];

    SCISetting *importRow = [SCISetting buttonCellWithTitle:@"Import from Files…" subtitle:nil icon:SCISettingsIcon(@"arrow_down") action:^{
        SCIGalleryImportViewController *vc = [[SCIGalleryImportViewController alloc] initWithDestinationFolderPath:self.importDestinationFolderPath];
        [self.navigationController pushViewController:vc animated:YES];
    }];
    [sections addObject:SCITopicSection(@"Import", @[importRow], @"Import from the Files app with full editable metadata.")];

    SCISetting *deleteRow = [SCISetting buttonCellWithTitle:@"Delete Files" subtitle:nil icon:SCISettingsIcon(@"trash") action:^{
        SCIGalleryDeleteViewController *vc = [[SCIGalleryDeleteViewController alloc] initWithMode:SCIGalleryDeletePageModeRoot];
        __weak typeof(self) weakSelf = self;
        vc.onDidDelete = ^{
            [weakSelf reloadStats];
            [weakSelf rebuildSections];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SCIGalleryFavoritesSortPreferenceChanged" object:nil];
        };
        [self.navigationController pushViewController:vc animated:YES];
    }];
    deleteRow.tintColor = [UIColor systemRedColor];
    deleteRow.iconTintColor = [UIColor systemRedColor];

    [sections addObject:SCITopicSection(@"Delete", @[deleteRow], nil)];

    [self replaceSections:sections];
}

- (void)handleLockToggleEnabled:(BOOL)enabled {
    SCIGalleryManager *mgr = [SCIGalleryManager sharedManager];
    if (enabled && !mgr.isLockEnabled) {
        __weak typeof(self) weakSelf = self;
        [SCIGalleryLockViewController presentMode:SCIGalleryLockModeSetPasscode
                             fromViewController:self
                                     completion:^(BOOL success) {
            [weakSelf rebuildSections];
        }];
        return;
    }

    if (enabled && mgr.isLockEnabled) {
        [self rebuildSections];
        return;
    }

    if (!enabled && !mgr.isLockEnabled) {
        [self rebuildSections];
        return;
    }

    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Disable Passcode"
                                                message:@"The gallery will no longer require authentication to open."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:^{
        [self rebuildSections];
    }],
        [SCIIGAlertAction actionWithTitle:@"Disable" style:SCIIGAlertActionStyleDestructive handler:^{
        [mgr removePasscode];
        [self rebuildSections];
    }],
    ]];
}

@end

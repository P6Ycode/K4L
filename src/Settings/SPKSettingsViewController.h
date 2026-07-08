#import "../Utils.h"
#import "SPKSetting.h"
#import "TweakSettings.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray *)sections reduceMargin:(BOOL)reduceMargin;
- (instancetype)init;

@property (nonatomic, strong, readonly) UITableView *tableView;
@property (nonatomic, strong, readonly) NSArray *sections;

@property (nonatomic, assign) BOOL searchesAllSettings;

/// Table style for this page. Defaults to UITableViewStyleInsetGrouped; override
/// to return UITableViewStylePlain for a flat, edge-to-edge list.
- (UITableViewStyle)preferredTableViewStyle;

- (void)switchChanged:(UISwitch *)sender;
- (SPKSetting *)settingForSender:(id)sender;
- (void)replaceSections:(NSArray *)sections;

/// Re-evaluate every row's `hiddenProvider` and reload the table. Call after
/// changing state that a row's `hiddenProvider` depends on. No-op while searching.
- (void)rebuildVisibleSections;

@end

NS_ASSUME_NONNULL_END

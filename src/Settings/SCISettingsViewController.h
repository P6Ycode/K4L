#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "TweakSettings.h"
#import "SCISetting.h"
#import "../Utils.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCISettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray *)sections reduceMargin:(BOOL)reduceMargin;
- (instancetype)init;

@property (nonatomic, strong, readonly) UITableView *tableView;
@property (nonatomic, strong, readonly) NSArray *sections;

@property (nonatomic, assign) BOOL searchesAllSettings;

- (void)switchChanged:(UISwitch *)sender;
- (SCISetting *)settingForSender:(id)sender;
- (void)replaceSections:(NSArray *)sections;

@end

NS_ASSUME_NONNULL_END

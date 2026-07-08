#import <UIKit/UIKit.h>

#import "../../Settings/SPKSettingsViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// Read-only gallery settings page: storage stats, lock configuration, clear gallery,
/// delete by type / source.
@interface SPKGallerySettingsViewController : SPKSettingsViewController

+ (NSArray *)searchSections;

@end

NS_ASSUME_NONNULL_END

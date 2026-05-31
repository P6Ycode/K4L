#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class SCISetting;

@interface SCIInstantsSettingsProvider : NSObject
+ (SCISetting *)rootSetting;

/// A standalone Instants settings screen, for presenting outside the main
/// settings tree (e.g. from the Instants gallery-upload sheet).
+ (UIViewController *)makeSettingsViewController;
@end

#import <Foundation/Foundation.h>

@class SPKSetting;

@interface SPKInterfaceSettingsProvider : NSObject
+ (SPKSetting *)rootSetting;
+ (SPKSetting *)experimentalLiquidGlassSetting;
@end

#import <Foundation/Foundation.h>
#import "SPKSetting.h"
#import "../Utils.h"
#import "../Tweak.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPKTweakSettings : NSObject

+ (NSArray *)sections;
+ (NSString *)title;

@end

NS_ASSUME_NONNULL_END

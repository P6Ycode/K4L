#import "SCIProfileAnalyzerSettingsProvider.h"
#import <UIKit/UIKit.h>

#import "../SCITopicSettingsSupport.h"
#import "../SCISetting.h"
#import "../../Utils.h"
#import "../../Features/Profile/ProfileAnalyzer/SCIProfileAnalyzerViewController.h"

@implementation SCIProfileAnalyzerSettingsProvider

+ (SCISetting *)rootSetting {
    // Opens straight into the analyzer dashboard — no intermediate settings page.
    // Track Visits, Visited Profiles, About and Reset all live inside the dashboard.
    SCISetting *setting = [SCISetting navigationCellWithTitle:@"Profile Analyzer"
                                                     subtitle:@""
                                                         icon:SCISettingsIcon(@"profile_analyzer")
                                               viewController:[SCIProfileAnalyzerViewController new]];
    setting.searchKeywords = @"profile analyzer followers following mutual unfollow tracker visited stalkers";
    return SCISettingApplyIconTint(setting, [SCIUtils SCIColor_InstagramPrimaryText]);
}

@end

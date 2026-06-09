#import "SCIDownloadsSettingsProvider.h"
#import <UIKit/UIKit.h>

#import "../SCITopicSettingsSupport.h"
#import "../SCISetting.h"
#import "../../Utils.h"
#import "../../Shared/Downloads/SCIDownloadsHistoryViewController.h"
#import "../../Shared/Downloads/SCIDownloadsSettingsViewController.h"

@implementation SCIDownloadsSettingsProvider

+ (SCISetting *)rootSetting {
    // Opens straight into the download history — the in-screen gear button leads
    // to the download settings. The settings sections are still surfaced to
    // settings search via the provider below.
    SCISetting *setting = [SCISetting navigationCellWithTitle:@"Downloads"
                                                     subtitle:@""
                                                         icon:SCISettingsIcon(@"download")
                                               viewController:[SCIDownloadsHistoryViewController new]];
    setting.searchKeywords = @"downloads history queue retry cancel duplicate parallel concurrent quality encoding ffmpeg audio resolution";
    setting.searchSectionsProvider = ^NSArray *{
        return [SCIDownloadsSettingsViewController searchSections];
    };
    return SCISettingApplyIconTint(setting, [SCIUtils SCIColor_InstagramPrimaryText]);
}

@end

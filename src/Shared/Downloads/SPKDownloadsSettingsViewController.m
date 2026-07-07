#import "SPKDownloadsSettingsViewController.h"

#import "../../App/SPKStartupHooks.h"
#import "../../AssetUtils.h"
#import "../../Settings/SPKSetting.h"
#import "../../Settings/SPKTopicSettingsSupport.h"
#import "../../Utils.h"
#import "../MediaDownload/SPKMediaFFmpeg.h"
#import "../MediaDownload/SPKMediaQualityManager.h"
#import "SPKDownloadTypes.h"

@implementation SPKDownloadsSettingsViewController

+ (UIMenu *)audioPageDefaultActionMenu {
    NSArray<NSDictionary *> *items = @[
        @{@"title" : @"Save Audio to Files", @"value" : @"files", @"icon" : @"audio_download"},
        @{@"title" : @"Share Audio", @"value" : @"share", @"icon" : @"share"},
        @{@"title" : @"Save Audio to Gallery", @"value" : @"gallery", @"icon" : @"sparkle_gallery"},
        @{@"title" : @"Play Audio", @"value" : @"play", @"icon" : @"play"},
        @{@"title" : @"Copy Audio Download URL", @"value" : @"copy_url", @"icon" : @"link"},
        @{@"title" : @"Open Menu", @"value" : @"none", @"icon" : @"action"}
    ];
    NSMutableArray<UICommand *> *commands = [NSMutableArray array];
    for (NSDictionary *item in items) {
        [commands addObject:[UICommand commandWithTitle:item[@"title"]
                                                  image:[SPKAssetUtils instagramIconNamed:item[@"icon"] pointSize:22.0]
                                                 action:@selector(menuChanged:)
                                           propertyList:@{@"defaultsKey" : @"downloads_audio_page_default_action", @"value" : item[@"value"], @"iconName" : item[@"icon"]}]];
    }
    return [UIMenu menuWithChildren:commands];
}

+ (NSArray *)contentSections {
    BOOL ffmpegAvailable = [SPKMediaFFmpeg isAvailable];
    if (!ffmpegAvailable) {
        // No FFmpeg = no DASH merge for ANY account, so this is a hard global
        // constraint, not a per-account choice. Write it globally (direct).
        [[NSUserDefaults standardUserDefaults] setObject:@"high_ignore_dash" forKey:@"downloads_video_quality"];
    }

    SPKSetting *videoQualitySetting = [SPKSetting menuCellWithTitle:@"Default Video Quality"
                                                           subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                           icon:SPKSettingsIcon(@"video")
                                                               menu:SPKMediaVideoQualityMenu()];
    videoQualitySetting.userInfo = @{@"enabled" : @(ffmpegAvailable)};

    SPKSetting *encodingSettings = [SPKSetting navigationCellWithTitle:@"Encoding Settings"
                                                              subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                              icon:SPKSettingsIcon(@"settings")
                                                        viewController:[SPKMediaQualityManager encodingSettingsViewController]];
    encodingSettings.userInfo = @{@"enabled" : @(ffmpegAvailable)};
    encodingSettings.searchSectionsProvider = ^NSArray * {
        return [SPKMediaQualityManager encodingSettingsSearchSections];
    };

    SPKSetting *encodingLogs = [SPKSetting navigationCellWithTitle:@"View Encoding Logs"
                                                          subtitle:@""
                                                              icon:SPKSettingsIcon(@"logs")
                                                    viewController:[SPKMediaFFmpeg logsViewController]];
    encodingLogs.userInfo = @{@"enabled" : @YES};

    NSString *qualityFooter = ffmpegAvailable ? @"\"High\" merges DASH files for best quality. \"Default\" uses ready-to-play files. \"Always Ask\" prompts for selection." : @"FFmpegKit is required for video quality options and encoding features.";

    return @[
        SPKTopicSection(@"Behavior", @[
            [SPKSetting switchCellWithTitle:@"Detect Duplicate Downloads"
                                       icon:SPKSettingsIcon(@"duplicate")
                                defaultsKey:kSPKDownloadDetectDuplicatesKey],
            [SPKSetting stepperCellWithTitle:@"Parallel Downloads"
                                    subtitle:@"%@ concurrent %@"
                                        icon:SPKSettingsIcon(@"parallel")
                                 defaultsKey:kSPKDownloadMaxConcurrentKey
                                         min:1
                                         max:4
                                        step:1
                                       label:@"downloads"
                               singularLabel:@"download"],
            [SPKSetting stepperCellWithTitle:@"History Limit"
                                    subtitle:@"%@ saved %@"
                                        icon:SPKSettingsIcon(@"history")
                                 defaultsKey:kSPKDownloadHistoryLimitKey
                                         min:50
                                         max:1000
                                        step:50
                                       label:@"entries"
                               singularLabel:@"entry"],
        ],
                        @"Duplicate detection runs before downloading. Gallery checks are exact. Photos checks cover media Sparkle saved while tracking is enabled."),
        SPKTopicSection(@"Quality", @[
            [SPKSetting switchCellWithTitle:@"Enhanced Media Resolution"
                                       icon:SPKSettingsIcon(@"hd")
                                defaultsKey:@"downloads_enhanced_media_resolution"],
            [SPKSetting menuCellWithTitle:@"Default Photo Quality"
                                     icon:SPKSettingsIcon(@"photo")
                                     menu:SPKMediaPhotoQualityMenu()],
            videoQualitySetting,
            encodingSettings,
            encodingLogs
        ],
                        qualityFooter),
        [self audioSection]
    ];
}

// The "Audio Downloads" master toggle gates every other audio action tweak-wide.
// The dependent cells stay visible (and keep their stored value) but are disabled
// while the master is off.
+ (NSDictionary *)audioSection {
    BOOL (^audioEnabled)(void) = ^BOOL {
        return [SPKUtils getBoolPref:@"downloads_audio_enabled"];
    };

    SPKSetting *master = [SPKSetting switchCellWithTitle:@"Audio Downloads" icon:SPKSettingsIcon(@"audio_download") defaultsKey:@"downloads_audio_enabled"];
    master.switchChangeHandler = ^(BOOL isOn) {
        [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:SPKEffectivePreferenceKey(@"downloads_audio_enabled")];
        if (isOn)
            SPKInstallEnabledFeatureHooks();
    };
    master.reloadsTableOnSwitchChange = YES; // grey out / re-enable the dependents live

    SPKSetting *pageButton = [SPKSetting switchCellWithTitle:@"Audio Page Button" icon:SPKSettingsIcon(@"audio_page") defaultsKey:@"downloads_audio_page_button"];
    pageButton.enabledProvider = audioEnabled;

    SPKSetting *pageDefault = SPKSettingApplySelectedMenuIcon([SPKSetting menuCellWithTitle:@"Audio Page Default Action" icon:SPKSettingsIcon(@"action") menu:[self audioPageDefaultActionMenu]], SPKSettingsIcon(@"action"));
    pageDefault.enabledProvider = audioEnabled;

    return SPKTopicSection(@"Audio", @[ master, pageButton, pageDefault ],
                           @"Adds audio actions for audio pages and media action buttons.");
}

+ (NSArray *)searchSections {
    return [self contentSections];
}

- (instancetype)init {
    return [super initWithTitle:@"Downloads Settings" sections:[[self class] contentSections] reduceMargin:NO];
}

@end

#import "SCIDownloadsSettingsViewController.h"

#import "SCIDownloadTypes.h"
#import "../MediaDownload/SCIMediaFFmpeg.h"
#import "../MediaDownload/SCIMediaQualityManager.h"
#import "../../Settings/SCITopicSettingsSupport.h"
#import "../../Settings/SCISetting.h"
#import "../../Utils.h"
#import "../../AssetUtils.h"

@implementation SCIDownloadsSettingsViewController

+ (UIMenu *)audioPageDefaultActionMenu {
    NSArray<NSDictionary *> *items = @[
        @{@"title": @"Save to Files", @"value": @"files", @"icon": @"audio_download"},
        @{@"title": @"Share", @"value": @"share", @"icon": @"share"},
        @{@"title": @"Save to Gallery", @"value": @"gallery", @"icon": @"media"},
        @{@"title": @"Play", @"value": @"play", @"icon": @"play"},
        @{@"title": @"Copy Download URL", @"value": @"copy_url", @"icon": @"link"},
        @{@"title": @"None", @"value": @"none", @"icon": @"action"}
    ];
    NSMutableArray<UICommand *> *commands = [NSMutableArray array];
    for (NSDictionary *item in items) {
        [commands addObject:[UICommand commandWithTitle:item[@"title"]
                                                  image:[SCIAssetUtils instagramIconNamed:item[@"icon"] pointSize:22.0]
                                                 action:@selector(menuChanged:)
                                           propertyList:@{@"defaultsKey": @"downloads_audio_page_default_action", @"value": item[@"value"], @"iconName": item[@"icon"]}]];
    }
    return [UIMenu menuWithChildren:commands];
}

+ (NSArray *)contentSections {
    BOOL ffmpegAvailable = [SCIMediaFFmpeg isAvailable];
    if (!ffmpegAvailable) {
        // No FFmpeg = no DASH merge for ANY account, so this is a hard global
        // constraint, not a per-account choice. Write it globally (direct).
        [[NSUserDefaults standardUserDefaults] setObject:@"high_ignore_dash" forKey:@"downloads_video_quality"];
    }

    SCISetting *videoQualitySetting = [SCISetting menuCellWithTitle:@"Default Video Quality"
                                                           subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                               icon:SCISettingsIcon(@"video")
                                                               menu:SCIMediaVideoQualityMenu()];
    videoQualitySetting.userInfo = @{@"enabled": @(ffmpegAvailable)};

    SCISetting *encodingSettings = [SCISetting navigationCellWithTitle:@"Encoding Settings"
                                                              subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                                  icon:SCISettingsIcon(@"settings")
                                                        viewController:[SCIMediaQualityManager encodingSettingsViewController]];
    encodingSettings.userInfo = @{@"enabled": @(ffmpegAvailable)};
    encodingSettings.searchSectionsProvider = ^NSArray *{
        return [SCIMediaQualityManager encodingSettingsSearchSections];
    };

    SCISetting *encodingLogs = [SCISetting navigationCellWithTitle:@"View Encoding Logs"
                                                          subtitle:@""
                                                              icon:SCISettingsIcon(@"logs")
                                                    viewController:[SCIMediaFFmpeg logsViewController]];
    encodingLogs.userInfo = @{@"enabled": @YES};

    NSString *qualityFooter = ffmpegAvailable ? @"\"High\" merges DASH files for best quality. \"Default\" uses ready-to-play files. \"Always Ask\" prompts for selection." : @"FFmpegKit is required for video quality options and encoding features.";

    return @[
        SCITopicSection(@"Behavior", @[
            [SCISetting switchCellWithTitle:@"Detect Duplicate Downloads" icon:SCISettingsIcon(@"duplicate") defaultsKey:kSCIDownloadDetectDuplicatesKey],
            [SCISetting stepperCellWithTitle:@"Parallel Downloads" subtitle:@"%@ concurrent %@" icon:SCISettingsIcon(@"parallel") defaultsKey:kSCIDownloadMaxConcurrentKey min:1 max:4 step:1 label:@"downloads" singularLabel:@"download"],
            [SCISetting stepperCellWithTitle:@"History Limit" subtitle:@"%@ saved %@" icon:SCISettingsIcon(@"history") defaultsKey:kSCIDownloadHistoryLimitKey min:50 max:1000 step:50 label:@"entries" singularLabel:@"entry"],
        ], @"Duplicate detection runs before downloading. Gallery checks are exact. Photos checks cover media SCInsta saved while tracking is enabled."),
        SCITopicSection(@"Quality", @[
            [SCISetting switchCellWithTitle:@"Enhanced Media Resolution" icon:SCISettingsIcon(@"hd") defaultsKey:@"downloads_enhanced_media_resolution"],
            [SCISetting menuCellWithTitle:@"Default Photo Quality" icon:SCISettingsIcon(@"photo") menu:SCIMediaPhotoQualityMenu()],
            videoQualitySetting,
            encodingSettings,
            encodingLogs
        ], qualityFooter),
        SCITopicSection(@"Audio", @[
            [SCISetting switchCellWithTitle:@"Audio Downloads" icon:SCISettingsIcon(@"audio_download") defaultsKey:@"downloads_audio_enabled"],
            [SCISetting switchCellWithTitle:@"Audio Page Button" icon:SCISettingsIcon(@"audio_page") defaultsKey:@"downloads_audio_page_button" requiresRestart:YES],
            SCISettingApplySelectedMenuIcon([SCISetting menuCellWithTitle:@"Audio Page Default Action" icon:SCISettingsIcon(@"action") menu:[self audioPageDefaultActionMenu]], SCISettingsIcon(@"action"))
        ], @"Adds audio actions for audio pages and media action buttons.")
    ];
}

+ (NSArray *)searchSections {
    return [self contentSections];
}

- (instancetype)init {
    return [super initWithTitle:@"Downloads Settings" sections:[[self class] contentSections] reduceMargin:NO];
}

@end

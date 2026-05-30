#import "SCIDeletedMessagesStorageViewController.h"

#import "SCIDeletedMessagesAvatarCache.h"
#import "SCIDeletedMessagesModels.h"
#import "SCIDeletedMessagesStorage.h"
#import "../../../Utils.h"
#import "../../../Shared/UI/SCIIGAlertPresenter.h"
#import "../../../Settings/SCITopicSettingsSupport.h"

@interface SCIDeletedMessagesStorageViewController ()
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, assign) NSUInteger messageCount;
@property (nonatomic, assign) NSUInteger senderCount;
@property (nonatomic, assign) NSUInteger textCount;
@property (nonatomic, assign) NSUInteger mediaCount;
@property (nonatomic, assign) NSUInteger voiceCount;
@property (nonatomic, assign) NSUInteger otherCount;
@property (nonatomic, assign) unsigned long long mediaBytes;
@property (nonatomic, assign) unsigned long long avatarBytes;
@end

@implementation SCIDeletedMessagesStorageViewController

static NSString *SCIDMStorageOwnerPK(void) {
    @try {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            id session = nil;
            @try { session = [window valueForKey:@"userSession"]; } @catch (__unused id e) {}
            id user = nil;
            @try { user = [session valueForKey:@"user"]; } @catch (__unused id e) {}
            for (NSString *key in @[@"pk", @"instagramUserID", @"instagramUserId", @"userID", @"userId"]) {
                id value = nil;
                @try { value = [user valueForKey:key]; } @catch (__unused id e) {}
                if ([value isKindOfClass:NSString.class] && [value length]) return value;
                if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
            }
        }
    } @catch (__unused id e) {}
    NSArray<NSString *> *owners = [SCIDeletedMessagesStorage allOwnerPKs];
    return owners.firstObject ?: @"anon";
}

- (instancetype)init {
    return [super initWithTitle:@"Storage" sections:@[] reduceMargin:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadStatsAndRebuild) name:SCIDeletedMessagesDidChangeNotification object:nil];
    [self reloadStatsAndRebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadStatsAndRebuild];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadStatsAndRebuild {
    [self reloadStats];
    [self rebuildSections];
}

- (void)reloadStats {
    self.ownerPK = SCIDMStorageOwnerPK();
    NSArray<SCIDeletedMessage *> *messages = [SCIDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK];
    self.messageCount = messages.count;

    NSMutableSet<NSString *> *senders = [NSMutableSet set];
    NSUInteger text = 0, media = 0, voice = 0, other = 0;
    for (SCIDeletedMessage *message in messages) {
        if (message.senderPk.length) [senders addObject:message.senderPk];
        switch (message.kind) {
            case SCIDeletedMessageKindText:
                text++; break;
            case SCIDeletedMessageKindPhoto:
            case SCIDeletedMessageKindVideo:
            case SCIDeletedMessageKindGif:
            case SCIDeletedMessageKindSticker:
                media++; break;
            case SCIDeletedMessageKindVoice:
            case SCIDeletedMessageKindAudioShare:
                voice++; break;
            default:
                other++; break;
        }
    }
    self.senderCount = senders.count;
    self.textCount = text;
    self.mediaCount = media;
    self.voiceCount = voice;
    self.otherCount = other;
    self.mediaBytes = [SCIDeletedMessagesStorage mediaSizeBytesForOwnerPK:self.ownerPK];
    self.avatarBytes = [[SCIDeletedMessagesAvatarCache shared] diskSizeBytes];
}

- (NSString *)formattedSize:(unsigned long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)rebuildSections {
    NSMutableArray *sections = [NSMutableArray array];

    unsigned long long totalDisk = self.mediaBytes + self.avatarBytes;
    NSString *overviewSubtitle = [NSString stringWithFormat:@"%lu message%@ • %lu sender%@ • %@",
                                  (unsigned long)self.messageCount, self.messageCount == 1 ? @"" : @"s",
                                  (unsigned long)self.senderCount, self.senderCount == 1 ? @"" : @"s",
                                  [self formattedSize:totalDisk]];

    [sections addObject:SCITopicSection(@"Overview", @[
        [SCISetting valueCellWithTitle:@"Logged" subtitle:overviewSubtitle icon:SCISettingsIcon(@"history")],
    ], nil)];

    NSMutableArray *breakdown = [NSMutableArray array];
    [breakdown addObject:[SCISetting valueCellWithTitle:@"Text" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.textCount] icon:SCISettingsIcon(@"text")]];
    [breakdown addObject:[SCISetting valueCellWithTitle:@"Photos & Videos" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.mediaCount] icon:SCISettingsIcon(@"photo")]];
    [breakdown addObject:[SCISetting valueCellWithTitle:@"Voice & Audio" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.voiceCount] icon:SCISettingsIcon(@"microphone")]];
    if (self.otherCount > 0) {
        [breakdown addObject:[SCISetting valueCellWithTitle:@"Other" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.otherCount] icon:SCISettingsIcon(@"messages")]];
    }
    [sections addObject:SCITopicSection(@"Messages", breakdown, nil)];

    [sections addObject:SCITopicSection(@"Disk Usage", @[
        [SCISetting valueCellWithTitle:@"Captured Media" subtitle:[self formattedSize:self.mediaBytes] icon:SCISettingsIcon(@"media")],
        [SCISetting valueCellWithTitle:@"Profile Pictures" subtitle:[self formattedSize:self.avatarBytes] icon:SCISettingsIcon(@"user_circle")],
    ], @"Captured media and profile pictures are stored on-device for this account. Profile pictures refresh at most once a day.")];

    __weak typeof(self) weakSelf = self;

    SCISetting *clearMedia = [SCISetting buttonCellWithTitle:@"Clear Captured Media" subtitle:nil icon:SCISettingsIcon(@"media") action:^{
        [weakSelf confirmClearMedia];
    }];
    clearMedia.tintColor = [SCIUtils SCIColor_InstagramDestructive];
    clearMedia.iconTintColor = [SCIUtils SCIColor_InstagramDestructive];

    SCISetting *clearLog = [SCISetting buttonCellWithTitle:@"Clear Entire Log" subtitle:nil icon:SCISettingsIcon(@"trash") action:^{
        [weakSelf confirmClearLog];
    }];
    clearLog.tintColor = [SCIUtils SCIColor_InstagramDestructive];
    clearLog.iconTintColor = [SCIUtils SCIColor_InstagramDestructive];

    [sections addObject:SCITopicSection(@"Maintenance", @[clearMedia, clearLog],
                                        @"Clearing captured media keeps the log text but frees disk space. Clearing the log removes everything for this account.")];

    [self replaceSections:sections];
}

#pragma mark - Actions

- (void)confirmClearMedia {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Clear captured media?"
                                                message:@"This removes all captured media (photos, videos, voice notes) but keeps the message log."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Clear Media" style:SCIIGAlertActionStyleDestructive handler:^{
            for (SCIDeletedMessage *message in [SCIDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK]) {
                NSString *media = [SCIDeletedMessagesStorage absolutePathForRelativePath:message.mediaPath ownerPK:self.ownerPK];
                NSString *thumb = [SCIDeletedMessagesStorage absolutePathForRelativePath:message.thumbnailPath ownerPK:self.ownerPK];
                if (media.length) [NSFileManager.defaultManager removeItemAtPath:media error:nil];
                if (thumb.length) [NSFileManager.defaultManager removeItemAtPath:thumb error:nil];
                message.mediaPath = nil;
                message.thumbnailPath = nil;
                [SCIDeletedMessagesStorage saveMessage:message forOwnerPK:self.ownerPK];
            }
            [self reloadStatsAndRebuild];
        }],
    ]];
}

- (void)confirmClearLog {
    [SCIIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"Clear entire log?"
                                                message:@"This removes every logged deleted message, captured media, and cached profile pictures for this account."
                                                actions:@[
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
        [SCIIGAlertAction actionWithTitle:@"Clear" style:SCIIGAlertActionStyleDestructive handler:^{
            [SCIDeletedMessagesStorage resetForOwnerPK:self.ownerPK];
            [[SCIDeletedMessagesAvatarCache shared] purge];
            [self reloadStatsAndRebuild];
        }],
    ]];
}

@end

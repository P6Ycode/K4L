#import "SCITrimEditorViewController.h"
#import "SCITrimScrubberView.h"
#import "../UI/SCIMediaChrome.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"

#import <AVFoundation/AVFoundation.h>

// Player-control glyphs use the host app's own IG assets (video-play-small /
// video-pause) so they match Instagram's player exactly, falling back to known
// ig_icon glyphs if those raster assets are unavailable (see AssetUtils.m).
static UIImage *SCITrimPlayerIcon(NSString *name, CGFloat pointSize) {
    return [SCIAssetUtils instagramIconNamed:name
                                   pointSize:pointSize
                               renderingMode:UIImageRenderingModeAlwaysTemplate];
}

static NSString *SCITrimFormatTime(NSTimeInterval seconds) {
    if (seconds < 0.0 || !isfinite(seconds)) seconds = 0.0;
    NSInteger total = (NSInteger)llround(seconds);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

@interface SCITrimEditorViewController () <SCITrimScrubberViewDelegate>
@property (nonatomic, strong) SCITrimConfiguration *configuration;
@property (nonatomic, strong) AVURLAsset *asset;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) id timeObserver;

@property (nonatomic, strong) UIView *playerContainer;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIView *bottomContent;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) SCITrimScrubberView *scrubber;
@property (nonatomic, strong) UISegmentedControl *modeControl;

@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL playerReady;
@property (nonatomic, assign) BOOL scrubberInteracting;
@property (nonatomic, assign) BOOL finished;
@end

@implementation SCITrimEditorViewController

- (instancetype)initWithConfiguration:(SCITrimConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        self.title = configuration.title.length > 0 ? configuration.title : @"Trim";
    }
    return self;
}

+ (void)presentWithConfiguration:(SCITrimConfiguration *)configuration
                            from:(UIViewController *)presenter
                      completion:(void (^)(SCITrimResult *_Nullable))completion {
    if (!configuration.sourceURL || !presenter) {
        if (completion) completion(nil);
        return;
    }
    SCITrimEditorViewController *editor = [[self alloc] initWithConfiguration:configuration];
    editor.completion = completion;
    // Hosted in a navigation controller so the top bar and bottom toolbar are
    // native components — they render as Liquid Glass on iOS 26 and as standard
    // translucent bars on earlier systems, with no custom material code.
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    // Media editor is always dark (like Photos), so its black background and
    // light controls read correctly regardless of the system appearance — in
    // light mode the label-colored controls would otherwise vanish on black.
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [presenter presentViewController:nav animated:YES completion:nil];
}

- (void)dealloc {
    if (_timeObserver && _player) {
        [_player removeTimeObserver:_timeObserver];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SCIUtils SCIColor_InstagramBackground] ?: [UIColor blackColor];

    [self setupChrome];
    [self setupPlayerContainer];
    [self setupBottomContent];
    [self loadAsset];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    BOOL showToolbar = _configuration.allowsSingleFrame;
    [self.navigationController setToolbarHidden:!showToolbar animated:NO];
    if (showToolbar) {
        SCIMediaChromeConfigureBottomToolbar(self.navigationController.toolbar);
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.playerLayer.frame = self.playerContainer.bounds;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.player pause];
}

#pragma mark - Setup

- (void)setupChrome {
    UIBarButtonItem *cancelItem = SCIMediaChromeTopBarButtonItem(@"close", self, @selector(cancelTapped));
    cancelItem.accessibilityLabel = @"Cancel";

    // When the caller supplies destinations, Done is a menu (pick where to save
    // without dismissing first); otherwise it's a plain confirm.
    UIBarButtonItem *doneItem;
    if (_configuration.doneOptions.count > 0) {
        doneItem = SCIMediaChromeTopBarMenuButtonItem(@"check", [self buildDoneMenu], @"Save");
    } else {
        doneItem = SCIMediaChromeTopBarButtonItem(@"check", self, @selector(doneTapped));
        doneItem.accessibilityLabel = @"Save";
    }
    SCIMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ cancelItem ]);
    SCIMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ doneItem ]);

    // The Trim / Single-Frame picker is the editor's primary mode switch, so it
    // lives in the bottom toolbar (a Liquid Glass capsule on iOS 26). Play/pause
    // is a dedicated button beside the scrubber (Photos-style).
    if (_configuration.allowsSingleFrame) {
        _modeControl = [[UISegmentedControl alloc] initWithItems:@[ @"Trim", @"Single Frame" ]];
        _modeControl.selectedSegmentIndex = 0;
        [_modeControl addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
        UIBarButtonItem *modeItem = [[UIBarButtonItem alloc] initWithCustomView:_modeControl];
        self.toolbarItems = SCIMediaChromeBottomToolbarItems(@[ modeItem ]);
    }
}

- (void)setupPlayerContainer {
    // Photos-style: the video sits in its own pane between the nav bar and the
    // controls — aspect-fit, on black, with nothing overlaid. Bottom is pinned
    // to the controls in setupBottomContent.
    _playerContainer = [[UIView alloc] init];
    _playerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _playerContainer.backgroundColor = [SCIUtils SCIColor_InstagramBackground] ?: [UIColor blackColor];
    [self.view addSubview:_playerContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_playerContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_playerContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_playerContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)setupBottomContent {
    _bottomContent = [[UIView alloc] init];
    _bottomContent.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_bottomContent];

    _timeLabel = [[UILabel alloc] init];
    _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _timeLabel.textColor = [SCIUtils SCIColor_InstagramSecondaryText] ?: [UIColor whiteColor];
    _timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    _timeLabel.textAlignment = NSTextAlignmentCenter;
    [_bottomContent addSubview:_timeLabel];

    // Play/pause to the left of the filmstrip (Photos-style), not overlaid.
    _playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _playPauseButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playPauseButton.tintColor = [SCIUtils SCIColor_InstagramPrimaryText] ?: [UIColor whiteColor];
    [_playPauseButton setImage:SCITrimPlayerIcon(@"video_play", 36.0) forState:UIControlStateNormal];
    [_playPauseButton addTarget:self action:@selector(togglePlayback) forControlEvents:UIControlEventTouchUpInside];
    _playPauseButton.accessibilityLabel = @"Play";
    [_bottomContent addSubview:_playPauseButton];

    _scrubber = [[SCITrimScrubberView alloc] init];
    _scrubber.translatesAutoresizingMaskIntoConstraints = NO;
    _scrubber.minimumDuration = _configuration.minimumDuration;
    _scrubber.delegate = self;
    [_bottomContent addSubview:_scrubber];

    [NSLayoutConstraint activateConstraints:@[
        [_bottomContent.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:14.0],
        [_bottomContent.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-14.0],
        [_bottomContent.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8.0],
        // Video pane fills the gap above the controls.
        [_playerContainer.bottomAnchor constraintEqualToAnchor:_bottomContent.topAnchor constant:-8.0],

        [_timeLabel.topAnchor constraintEqualToAnchor:_bottomContent.topAnchor],
        [_timeLabel.centerXAnchor constraintEqualToAnchor:_bottomContent.centerXAnchor],

        [_playPauseButton.leadingAnchor constraintEqualToAnchor:_bottomContent.leadingAnchor],
        [_playPauseButton.centerYAnchor constraintEqualToAnchor:_scrubber.centerYAnchor],
        [_playPauseButton.widthAnchor constraintEqualToConstant:40.0],
        [_playPauseButton.heightAnchor constraintEqualToConstant:40.0],

        [_scrubber.topAnchor constraintEqualToAnchor:_timeLabel.bottomAnchor constant:10.0],
        [_scrubber.leadingAnchor constraintEqualToAnchor:_playPauseButton.trailingAnchor constant:10.0],
        [_scrubber.trailingAnchor constraintEqualToAnchor:_bottomContent.trailingAnchor],
        [_scrubber.heightAnchor constraintEqualToConstant:52.0],
        [_scrubber.bottomAnchor constraintEqualToAnchor:_bottomContent.bottomAnchor],
    ]];
}

#pragma mark - Asset loading

- (void)loadAsset {
    NSURL *url = _configuration.sourceURL;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    self.asset = asset;

    __weak typeof(self) weakSelf = self;
    [asset loadValuesAsynchronouslyForKeys:@[@"duration", @"tracks"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSError *err = nil;
            AVKeyValueStatus status = [asset statusOfValueForKey:@"duration" error:&err];
            if (status != AVKeyValueStatusLoaded) {
                [strongSelf failWithMessage:@"This video could not be opened for trimming."];
                return;
            }
            [strongSelf configurePlayerAndScrubber];
        });
    }];
}

- (void)configurePlayerAndScrubber {
    NSTimeInterval duration = CMTimeGetSeconds(self.asset.duration);
    if (duration <= 0.0 || !isfinite(duration)) {
        [self failWithMessage:@"This video has no playable duration."];
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:self.asset];
    self.player = [AVPlayer playerWithPlayerItem:item];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;

    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.playerLayer.frame = self.playerContainer.bounds;
    [self.playerContainer.layer insertSublayer:self.playerLayer atIndex:0];

    self.scrubber.duration = duration;
    [self.scrubber setStartTime:0.0 endTime:duration];
    self.scrubber.playheadTime = 0.0;
    [self.scrubber loadThumbnailsForAsset:self.asset];

    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 30)
                                                                  queue:dispatch_get_main_queue()
                                                             usingBlock:^(CMTime time) {
        [weakSelf playbackTimeChanged:CMTimeGetSeconds(time)];
    }];

    self.playerReady = YES;
    [self updateTimeLabel];
    [self updatePlaybackControls];
}

#pragma mark - Playback

- (void)playbackTimeChanged:(NSTimeInterval)t {
    if (self.scrubberInteracting || self.scrubber.isSingleFrameMode) return;
    self.scrubber.playheadTime = t;
    [self updateTimeLabel];
    // Loop within the selected range.
    if (self.isPlaying && t >= self.scrubber.endTime - 0.03) {
        [self seekToTime:self.scrubber.startTime];
    }
}

- (void)togglePlayback {
    if (self.scrubber.isSingleFrameMode || !self.player) return;
    if (self.isPlaying) {
        [self.player pause];
        self.isPlaying = NO;
    } else {
        NSTimeInterval now = CMTimeGetSeconds(self.player.currentTime);
        if (now < self.scrubber.startTime || now >= self.scrubber.endTime - 0.03) {
            [self seekToTime:self.scrubber.startTime];
        }
        [self.player play];
        self.isPlaying = YES;
    }
    [self updatePlaybackControls];
}

// Swaps the play/pause glyph and disables the control in single-frame mode
// (which has no playback).
- (void)updatePlaybackControls {
    BOOL canPlay = self.playerReady && !self.scrubber.isSingleFrameMode;
    [self.playPauseButton setImage:SCITrimPlayerIcon(self.isPlaying ? @"video_pause" : @"video_play", 36.0)
                          forState:UIControlStateNormal];
    self.playPauseButton.accessibilityLabel = self.isPlaying ? @"Pause" : @"Play";
    self.playPauseButton.enabled = canPlay;
    self.playPauseButton.alpha = canPlay ? 1.0 : 0.35;
}

- (void)seekToTime:(NSTimeInterval)t {
    CMTime cm = CMTimeMakeWithSeconds(t, 600);
    [self.player seekToTime:cm toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

#pragma mark - Mode

- (void)modeChanged {
    BOOL single = (self.modeControl.selectedSegmentIndex == 1);
    if (single) {
        [self.player pause];
        self.isPlaying = NO;
        self.scrubber.singleFrameMode = YES;
        [self seekToTime:self.scrubber.frameTime];
    } else {
        self.scrubber.singleFrameMode = NO;
        [self seekToTime:self.scrubber.startTime];
    }
    [self updatePlaybackControls];
    [self updateTimeLabel];
}

- (void)updateTimeLabel {
    if (self.scrubber.isSingleFrameMode) {
        self.timeLabel.text = [NSString stringWithFormat:@"Frame • %@", SCITrimFormatTime(self.scrubber.frameTime)];
        return;
    }
    NSTimeInterval dur = self.scrubber.endTime - self.scrubber.startTime;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ – %@  •  %.1fs",
                           SCITrimFormatTime(self.scrubber.startTime),
                           SCITrimFormatTime(self.scrubber.endTime),
                           dur];
}

#pragma mark - SCITrimScrubberViewDelegate

- (void)trimScrubberDidBeginInteraction:(SCITrimScrubberView *)scrubber {
    self.scrubberInteracting = YES;
    if (self.isPlaying) {
        [self.player pause];
        self.isPlaying = NO;
        [self updatePlaybackControls];
    }
}

- (void)trimScrubber:(SCITrimScrubberView *)scrubber didChangeStartTime:(NSTimeInterval)startTime {
    [self seekToTime:startTime];
    [self updateTimeLabel];
}

- (void)trimScrubber:(SCITrimScrubberView *)scrubber didChangeEndTime:(NSTimeInterval)endTime {
    [self seekToTime:endTime];
    [self updateTimeLabel];
}

- (void)trimScrubber:(SCITrimScrubberView *)scrubber didScrubToTime:(NSTimeInterval)time {
    [self seekToTime:time];
    [self updateTimeLabel];
}

- (void)trimScrubberDidEndInteraction:(SCITrimScrubberView *)scrubber {
    self.scrubberInteracting = NO;
}

#pragma mark - Actions

- (void)cancelTapped {
    [self.player pause];
    [self finishWithResult:nil];
}

// Confirming returns the trim parameters and dismisses immediately — the actual
// render runs in the background (with a progress pill) from the caller's save
// coordinator, so the app stays usable and the editor never blocks behind a
// full-screen overlay.
- (UIMenu *)buildDoneMenu {
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (SCITrimDoneOption *option in self.configuration.doneOptions) {
        UIImage *image = option.iconName.length > 0
            ? [SCIAssetUtils instagramIconNamed:option.iconName pointSize:22.0]
            : nil;
        UIAction *action = [UIAction actionWithTitle:option.title
                                               image:image
                                          identifier:nil
                                             handler:^(__unused UIAction *a) {
            [weakSelf finishWithDestinationTag:option.identifier];
        }];
        [children addObject:action];
    }
    return [UIMenu menuWithTitle:@"" children:children];
}

- (void)doneTapped {
    [self finishWithDestinationTag:nil];
}

- (void)finishWithDestinationTag:(NSString *)destinationTag {
    [self.player pause];
    self.isPlaying = NO;

    SCITrimResult *result;
    if (self.scrubber.isSingleFrameMode) {
        result = [SCITrimResult requestWithMode:SCITrimResultModeSingleFrame
                                      sourceURL:self.configuration.sourceURL
                                   startSeconds:self.scrubber.frameTime
                                durationSeconds:0.0];
    } else {
        result = [SCITrimResult requestWithMode:SCITrimResultModeTrimmedVideo
                                      sourceURL:self.configuration.sourceURL
                                   startSeconds:self.scrubber.startTime
                                durationSeconds:(self.scrubber.endTime - self.scrubber.startTime)];
    }
    result.destinationTag = destinationTag;
    [self finishWithResult:result];
}

#pragma mark - Finish

- (void)failWithMessage:(NSString *)message {
    SCINotify(@"sci.trim.editor", @"Trim failed", message, @"error_filled", SCINotificationToneError);
}

- (void)finishWithResult:(SCITrimResult *)result {
    if (self.finished) return;
    self.finished = YES;
    void (^completion)(SCITrimResult *_Nullable) = self.completion;
    id<SCITrimEditorDelegate> delegate = self.delegate;
    __weak typeof(self) weakSelf = self;
    [self dismissViewControllerAnimated:YES completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (result) {
            if ([delegate respondsToSelector:@selector(trimEditor:didFinishWithResult:)]) {
                [delegate trimEditor:strongSelf didFinishWithResult:result];
            }
        } else {
            if ([delegate respondsToSelector:@selector(trimEditorDidCancel:)]) {
                [delegate trimEditorDidCancel:strongSelf];
            }
        }
        if (completion) completion(result);
    }];
}

@end

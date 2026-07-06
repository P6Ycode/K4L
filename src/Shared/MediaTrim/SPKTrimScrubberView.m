#import "SPKTrimScrubberView.h"
#import "../../Utils.h"

static CGFloat const kSPKTrimHandleWidth = 18.0;
static CGFloat const kSPKTrimBorderThickness = 3.0;
static CGFloat const kSPKTrimGrabThreshold = 36.0;
static NSInteger const kSPKTrimThumbnailCount = 16;
static CGFloat const kSPKTrimCornerRadius = 8.0;

typedef NS_ENUM(NSInteger, SPKTrimDragTarget) {
    SPKTrimDragTargetNone = 0,
    SPKTrimDragTargetLeftHandle,
    SPKTrimDragTargetRightHandle,
    SPKTrimDragTargetPlayhead,
};

static NSInteger const kSPKTrimWaveformBars = 96;

#pragma mark - Waveform view

// Draws a vertically-centered bar waveform from normalized (0..1) peak samples.
// Lives inside the track container in place of the filmstrip for audio trims.
@interface SPKTrimWaveformView : UIView
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *samples;
@end

@implementation SPKTrimWaveformView

- (void)setSamples:(NSArray<NSNumber *> *)samples {
    _samples = [samples copy];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    NSArray<NSNumber *> *samples = self.samples;
    if (samples.count == 0)
        return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx)
        return;
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.92 alpha:1.0].CGColor);

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    NSInteger n = (NSInteger)samples.count;
    CGFloat step = w / (CGFloat)n;
    CGFloat barW = MAX(1.0, step - 1.5);
    CGFloat maxBarH = MAX(2.0, h - 6.0);

    for (NSInteger i = 0; i < n; i++) {
        CGFloat amp = MAX(0.0, MIN(1.0, samples[i].doubleValue));
        CGFloat barH = MAX(2.0, amp * maxBarH);
        CGFloat x = i * step + (step - barW) / 2.0;
        CGFloat y = (h - barH) / 2.0;
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, barW, barH)
                                                        cornerRadius:barW / 2.0];
        [path fill];
    }
}

@end

// Samples an asset's first audio track into `targetCount` normalized peak values
// on a background queue, delivering the result on the main queue (nil on
// failure). Peak-per-bucket keeps transients visible; the whole set is then
// normalized to the loudest bucket so quiet clips still fill the strip.
static void SPKTrimSampleWaveform(AVAsset *asset, NSInteger targetCount,
                                  void (^completion)(NSArray<NSNumber *> *_Nullable)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        void (^finish)(NSArray<NSNumber *> *) = ^(NSArray<NSNumber *> *result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result);
            });
        };

        AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        if (!track) {
            finish(nil);
            return;
        }

        NSError *error = nil;
        AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
        if (!reader) {
            finish(nil);
            return;
        }

        NSDictionary *settings = @{
            AVFormatIDKey : @(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey : @16,
            AVLinearPCMIsBigEndianKey : @NO,
            AVLinearPCMIsFloatKey : @NO,
            AVLinearPCMIsNonInterleaved : @NO,
        };
        AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
        output.alwaysCopiesSampleData = NO;
        if (![reader canAddOutput:output]) {
            finish(nil);
            return;
        }
        [reader addOutput:output];
        if (![reader startReading]) {
            finish(nil);
            return;
        }

        // Estimate total interleaved int16 samples so we can bucket by position.
        double sampleRate = 44100.0;
        UInt32 channels = 1;
        CMFormatDescriptionRef fmt = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
        if (fmt) {
            const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
            if (asbd) {
                if (asbd->mSampleRate > 0)
                    sampleRate = asbd->mSampleRate;
                if (asbd->mChannelsPerFrame > 0)
                    channels = asbd->mChannelsPerFrame;
            }
        }
        double durationSeconds = CMTimeGetSeconds(asset.duration);
        if (!isfinite(durationSeconds) || durationSeconds <= 0)
            durationSeconds = CMTimeGetSeconds(track.timeRange.duration);
        int64_t estTotal = (int64_t)(MAX(0.0, durationSeconds) * sampleRate * channels);
        if (estTotal <= 0)
            estTotal = targetCount; // Avoid divide-by-zero; buckets clamp below.

        NSInteger count = MAX((NSInteger)1, targetCount);
        double *peaks = calloc((size_t)count, sizeof(double));
        if (!peaks) {
            finish(nil);
            return;
        }

        int64_t globalIndex = 0;
        double globalMax = 0.0;
        while (reader.status == AVAssetReaderStatusReading) {
            CMSampleBufferRef sampleBuffer = [output copyNextSampleBuffer];
            if (!sampleBuffer)
                break;
            CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
            if (block) {
                size_t length = CMBlockBufferGetDataLength(block);
                size_t int16Count = length / sizeof(int16_t);
                if (int16Count > 0) {
                    int16_t *data = malloc(length);
                    if (data && CMBlockBufferCopyDataBytes(block, 0, length, data) == kCMBlockBufferNoErr) {
                        for (size_t s = 0; s < int16Count; s++) {
                            double amp = fabs((double)data[s]) / 32768.0;
                            NSInteger bucket = (NSInteger)((globalIndex * count) / estTotal);
                            if (bucket < 0)
                                bucket = 0;
                            if (bucket >= count)
                                bucket = count - 1;
                            if (amp > peaks[bucket])
                                peaks[bucket] = amp;
                            if (amp > globalMax)
                                globalMax = amp;
                            globalIndex++;
                        }
                    }
                    if (data)
                        free(data);
                }
            }
            CMSampleBufferInvalidate(sampleBuffer);
            CFRelease(sampleBuffer);
        }

        if (reader.status == AVAssetReaderStatusFailed || globalMax <= 0.0) {
            free(peaks);
            finish(nil);
            return;
        }

        NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        for (NSInteger i = 0; i < count; i++) {
            // Slight gamma so mid-level detail is visible, then normalize.
            double norm = peaks[i] / globalMax;
            [result addObject:@(pow(norm, 0.8))];
        }
        free(peaks);
        finish(result);
    });
}

@interface SPKTrimScrubberView ()
@property (nonatomic, strong) UIView *filmstripContainer;
@property (nonatomic, strong) SPKTrimWaveformView *waveformView;
@property (nonatomic, strong) NSMutableArray<UIImageView *> *thumbnailViews;
@property (nonatomic, strong) NSMutableArray<UIImage *> *thumbnailImages;

@property (nonatomic, strong) UIView *dimLeftView;
@property (nonatomic, strong) UIView *dimRightView;
@property (nonatomic, strong) UIView *selectionTopBorder;
@property (nonatomic, strong) UIView *selectionBottomBorder;
@property (nonatomic, strong) UIView *leftHandle;
@property (nonatomic, strong) UIView *rightHandle;
@property (nonatomic, strong) UIView *playheadView;
@property (nonatomic, strong) UIView *frameMarkerView;

@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval endTime;
@property (nonatomic, assign) SPKTrimDragTarget dragTarget;
@property (nonatomic, strong) AVAssetImageGenerator *imageGenerator;
@end

@implementation SPKTrimScrubberView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _minimumDuration = 0.3;
        _thumbnailViews = [NSMutableArray array];
        _thumbnailImages = [NSMutableArray array];
        [self setupViews];
        [self setupGestures];
    }
    return self;
}

- (void)setupViews {
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;

    _filmstripContainer = [[UIView alloc] init];
    _filmstripContainer.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    _filmstripContainer.clipsToBounds = YES;
    _filmstripContainer.layer.cornerRadius = kSPKTrimCornerRadius;
    _filmstripContainer.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_filmstripContainer];

    // Waveform for audio trims; hidden until loadWaveformForAsset: switches modes.
    _waveformView = [[SPKTrimWaveformView alloc] init];
    _waveformView.backgroundColor = [UIColor clearColor];
    _waveformView.userInteractionEnabled = NO;
    _waveformView.hidden = YES;
    [_filmstripContainer addSubview:_waveformView];

    UIColor *dimColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    _dimLeftView = [[UIView alloc] init];
    _dimLeftView.backgroundColor = dimColor;
    _dimLeftView.userInteractionEnabled = NO;
    [self addSubview:_dimLeftView];

    _dimRightView = [[UIView alloc] init];
    _dimRightView.backgroundColor = dimColor;
    _dimRightView.userInteractionEnabled = NO;
    [self addSubview:_dimRightView];

    // Two-tone: white selection chrome over the darkened filmstrip, with dark
    // detail lines on the handles/marker. Avoids the blue accent except where IG
    // itself uses it.
    UIColor *accent = [UIColor whiteColor];

    _selectionTopBorder = [[UIView alloc] init];
    _selectionTopBorder.backgroundColor = accent;
    _selectionTopBorder.userInteractionEnabled = NO;
    [self addSubview:_selectionTopBorder];

    _selectionBottomBorder = [[UIView alloc] init];
    _selectionBottomBorder.backgroundColor = accent;
    _selectionBottomBorder.userInteractionEnabled = NO;
    [self addSubview:_selectionBottomBorder];

    _leftHandle = [self makeHandleWithAccent:accent];
    [self addSubview:_leftHandle];
    _rightHandle = [self makeHandleWithAccent:accent];
    [self addSubview:_rightHandle];

    _playheadView = [[UIView alloc] init];
    _playheadView.backgroundColor = [UIColor whiteColor];
    _playheadView.userInteractionEnabled = NO;
    _playheadView.layer.cornerRadius = 1.5;
    _playheadView.layer.shadowColor = [UIColor blackColor].CGColor;
    _playheadView.layer.shadowOpacity = 0.4;
    _playheadView.layer.shadowRadius = 2.0;
    _playheadView.layer.shadowOffset = CGSizeZero;
    [self addSubview:_playheadView];

    // Single-frame marker: a rounded pill with a vertical line. Hidden until
    // single-frame mode is enabled.
    _frameMarkerView = [[UIView alloc] init];
    _frameMarkerView.backgroundColor = accent;
    _frameMarkerView.userInteractionEnabled = NO;
    _frameMarkerView.layer.cornerRadius = 5.0;
    _frameMarkerView.hidden = YES;
    UIView *markerLine = [[UIView alloc] init];
    markerLine.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    markerLine.tag = 7001;
    [_frameMarkerView addSubview:markerLine];
    [self addSubview:_frameMarkerView];
}

- (UIView *)makeHandleWithAccent:(UIColor *)accent {
    UIView *handle = [[UIView alloc] init];
    handle.backgroundColor = accent;
    handle.layer.cornerRadius = kSPKTrimCornerRadius;
    handle.layer.cornerCurve = kCACornerCurveContinuous;
    // A short dark grip line centered in the (white) handle.
    UIView *grip = [[UIView alloc] init];
    grip.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    grip.layer.cornerRadius = 1.0;
    grip.tag = 7002;
    [handle addSubview:grip];
    return handle;
}

- (void)setupGestures {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self addGestureRecognizer:tap];
}

#pragma mark - Public

- (void)setDuration:(NSTimeInterval)duration {
    _duration = MAX(duration, 0.0);
    if (_endTime <= 0.0 || _endTime > _duration) {
        _startTime = 0.0;
        _endTime = _duration;
    }
    [self setNeedsLayout];
}

- (void)setStartTime:(NSTimeInterval)start endTime:(NSTimeInterval)end {
    _startTime = MAX(0.0, MIN(start, _duration));
    _endTime = MAX(_startTime, MIN(end, _duration));
    [self setNeedsLayout];
}

- (NSTimeInterval)frameTime {
    return _playheadTime;
}

- (void)setPlayheadTime:(NSTimeInterval)playheadTime {
    _playheadTime = MAX(0.0, MIN(playheadTime, _duration));
    [self layoutPlayhead];
}

- (void)setFrameOnlyMode:(BOOL)frameOnlyMode {
    if (_frameOnlyMode == frameOnlyMode)
        return;
    _frameOnlyMode = frameOnlyMode;
    if (frameOnlyMode) {
        // Snap the frame marker into the current selection if outside it.
        if (_playheadTime < _startTime || _playheadTime > _endTime) {
            _playheadTime = _startTime;
        }
    }
    [self updateControlVisibility];
    [self setNeedsLayout];
}

- (void)updateControlVisibility {
    BOOL frameOnly = _frameOnlyMode;
    _dimLeftView.hidden = frameOnly;
    _dimRightView.hidden = frameOnly;
    _selectionTopBorder.hidden = frameOnly;
    _selectionBottomBorder.hidden = frameOnly;
    _leftHandle.hidden = frameOnly;
    _rightHandle.hidden = frameOnly;
    _playheadView.hidden = frameOnly;
    _frameMarkerView.hidden = !frameOnly;
}

#pragma mark - Waveform

- (void)setWaveformMode:(BOOL)waveformMode {
    if (_waveformMode == waveformMode)
        return;
    _waveformMode = waveformMode;
    _waveformView.hidden = !waveformMode;
    for (UIImageView *iv in self.thumbnailViews) {
        iv.hidden = waveformMode;
    }
    [self setNeedsLayout];
}

- (void)loadWaveformForAsset:(AVAsset *)asset {
    if (!asset)
        return;
    self.waveformMode = YES;
    __weak typeof(self) weakSelf = self;
    SPKTrimSampleWaveform(asset, kSPKTrimWaveformBars, ^(NSArray<NSNumber *> *samples) {
        weakSelf.waveformView.samples = samples;
    });
}

#pragma mark - Thumbnails

- (void)loadThumbnailsForAsset:(AVAsset *)asset {
    if (!asset)
        return;
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.requestedTimeToleranceBefore = kCMTimePositiveInfinity;
    generator.requestedTimeToleranceAfter = kCMTimePositiveInfinity;
    CGFloat scale = UIScreen.mainScreen.scale;
    generator.maximumSize = CGSizeMake(120.0 * scale, 120.0 * scale);
    self.imageGenerator = generator;

    CMTime assetDuration = asset.duration;
    NSTimeInterval total = CMTimeGetSeconds(assetDuration);
    if (total <= 0.0 || !isfinite(total))
        return;

    NSMutableArray<NSValue *> *times = [NSMutableArray array];
    for (NSInteger i = 0; i < kSPKTrimThumbnailCount; i++) {
        NSTimeInterval t = (total * (i + 0.5)) / kSPKTrimThumbnailCount;
        [times addObject:[NSValue valueWithCMTime:CMTimeMakeWithSeconds(t, 600)]];
        [self.thumbnailImages addObject:(id)[NSNull null]];
    }

    __weak typeof(self) weakSelf = self;
    [generator generateCGImagesAsynchronouslyForTimes:times
                                    completionHandler:^(CMTime requestedTime, CGImageRef _Nullable image,
                                                        CMTime actualTime, AVAssetImageGeneratorResult result,
                                                        NSError *_Nullable error) {
                                        if (result != AVAssetImageGeneratorSucceeded || !image)
                                            return;
                                        // Derive the slot from the requested time — the generator does not
                                        // guarantee completion order, so we can't rely on a running counter.
                                        NSTimeInterval requested = CMTimeGetSeconds(requestedTime);
                                        NSInteger slot = (NSInteger)floor((requested * kSPKTrimThumbnailCount) / total);
                                        slot = MAX(0, MIN(slot, kSPKTrimThumbnailCount - 1));
                                        UIImage *uiImage = [UIImage imageWithCGImage:image];
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            __strong typeof(weakSelf) strongSelf = weakSelf;
                                            if (!strongSelf || slot >= strongSelf.thumbnailImages.count)
                                                return;
                                            strongSelf.thumbnailImages[slot] = uiImage;
                                            [strongSelf applyThumbnailImageAtSlot:slot image:uiImage];
                                        });
                                    }];
}

- (void)applyThumbnailImageAtSlot:(NSInteger)slot image:(UIImage *)image {
    if (slot < self.thumbnailViews.count) {
        UIImageView *iv = self.thumbnailViews[slot];
        iv.image = image;
        iv.alpha = 0.0;
        [UIView animateWithDuration:0.2
                         animations:^{
                             iv.alpha = 1.0;
                         }];
    }
}

- (void)ensureThumbnailViews {
    NSInteger count = self.thumbnailImages.count > 0 ? self.thumbnailImages.count : 0;
    while (self.thumbnailViews.count < count) {
        UIImageView *iv = [[UIImageView alloc] init];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.userInteractionEnabled = NO;
        id existing = self.thumbnailImages[self.thumbnailViews.count];
        if ([existing isKindOfClass:[UIImage class]]) {
            iv.image = existing;
        }
        [self.filmstripContainer addSubview:iv];
        [self.thumbnailViews addObject:iv];
    }
}

#pragma mark - Layout

// The filmstrip is inset by one handle-width on each side so the drag handles
// live in the side gutters (outside the video frames), not overlapping them.
// All time<->x math runs through this content rect, so the playhead stays within
// the selection and never merges with a handle's edge.
- (CGFloat)contentOriginX {
    return kSPKTrimHandleWidth;
}

- (CGFloat)contentWidth {
    return MAX(0.0, self.bounds.size.width - 2.0 * kSPKTrimHandleWidth);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    _filmstripContainer.frame = CGRectMake([self contentOriginX], 0, [self contentWidth], h);

    if (_waveformMode) {
        // Fills the track container's local space (0..contentWidth).
        _waveformView.frame = _filmstripContainer.bounds;
    } else {
        [self ensureThumbnailViews];
        NSInteger count = self.thumbnailViews.count;
        if (count > 0) {
            // Thumbnails are children of the filmstrip container, so they lay out
            // in its local space (0..contentWidth).
            CGFloat slotWidth = [self contentWidth] / count;
            for (NSInteger i = 0; i < count; i++) {
                self.thumbnailViews[i].frame = CGRectMake(floor(i * slotWidth), 0,
                                                          ceil(slotWidth) + 1.0, h);
            }
        }
    }

    [self layoutSelection];
    [self layoutPlayhead];
}

- (CGFloat)xForTime:(NSTimeInterval)t {
    if (_duration <= 0.0)
        return [self contentOriginX];
    return [self contentOriginX] + (t / _duration) * [self contentWidth];
}

- (NSTimeInterval)timeForX:(CGFloat)x {
    CGFloat w = [self contentWidth];
    if (w <= 0.0)
        return 0.0;
    CGFloat clamped = MAX(0.0, MIN(x - [self contentOriginX], w));
    return (clamped / w) * _duration;
}

- (void)layoutSelection {
    CGFloat h = self.bounds.size.height;
    CGFloat startX = [self xForTime:_startTime];
    CGFloat endX = [self xForTime:_endTime];
    CGFloat contentLeft = [self contentOriginX];
    CGFloat contentRight = contentLeft + [self contentWidth];

    // Dim only the trimmed-away parts of the filmstrip (between the content edge
    // and the selection), never the gutters.
    _dimLeftView.frame = CGRectMake(contentLeft, 0, MAX(0, startX - contentLeft), h);
    _dimRightView.frame = CGRectMake(endX, 0, MAX(0, contentRight - endX), h);

    _selectionTopBorder.frame = CGRectMake(startX, 0, MAX(0, endX - startX), kSPKTrimBorderThickness);
    _selectionBottomBorder.frame = CGRectMake(startX, h - kSPKTrimBorderThickness, MAX(0, endX - startX), kSPKTrimBorderThickness);

    // Handles sit just outside the selection, in the gutters at full extent.
    _leftHandle.frame = CGRectMake(startX - kSPKTrimHandleWidth, 0, kSPKTrimHandleWidth, h);
    _rightHandle.frame = CGRectMake(endX, 0, kSPKTrimHandleWidth, h);

    [self layoutGripInHandle:_leftHandle];
    [self layoutGripInHandle:_rightHandle];
}

- (void)layoutGripInHandle:(UIView *)handle {
    UIView *grip = [handle viewWithTag:7002];
    CGFloat gripH = handle.bounds.size.height * 0.34;
    grip.frame = CGRectMake((handle.bounds.size.width - 2.0) / 2.0,
                            (handle.bounds.size.height - gripH) / 2.0, 2.0, gripH);
}

- (void)layoutPlayhead {
    CGFloat h = self.bounds.size.height;
    if (_frameOnlyMode) {
        CGFloat x = [self xForTime:_playheadTime];
        CGFloat markerW = 12.0;
        _frameMarkerView.frame = CGRectMake(x - markerW / 2.0, -3.0, markerW, h + 6.0);
        UIView *line = [_frameMarkerView viewWithTag:7001];
        line.frame = CGRectMake((markerW - 2.0) / 2.0, 6.0, 2.0, h - 6.0);
        return;
    }
    CGFloat x = [self xForTime:_playheadTime];
    _playheadView.frame = CGRectMake(x - 1.0, -2.0, 2.0, h + 4.0);
}

#pragma mark - Gestures

- (void)handleTap:(UITapGestureRecognizer *)tap {
    CGPoint p = [tap locationInView:self];
    NSTimeInterval t = [self timeForX:p.x];
    if (!_frameOnlyMode) {
        t = MAX(_startTime, MIN(t, _endTime));
    }
    self.playheadTime = t;
    if ([self.delegate respondsToSelector:@selector(trimScrubber:didScrubToTime:)]) {
        [self.delegate trimScrubber:self didScrubToTime:t];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint p = [pan locationInView:self];

    if (pan.state == UIGestureRecognizerStateBegan) {
        _dragTarget = [self dragTargetForPoint:p];
        if ([self.delegate respondsToSelector:@selector(trimScrubberDidBeginInteraction:)]) {
            [self.delegate trimScrubberDidBeginInteraction:self];
        }
    }

    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        [self applyDragAtPoint:p];
    }

    if (pan.state == UIGestureRecognizerStateEnded ||
        pan.state == UIGestureRecognizerStateCancelled ||
        pan.state == UIGestureRecognizerStateFailed) {
        _dragTarget = SPKTrimDragTargetNone;
        if ([self.delegate respondsToSelector:@selector(trimScrubberDidEndInteraction:)]) {
            [self.delegate trimScrubberDidEndInteraction:self];
        }
    }
}

- (SPKTrimDragTarget)dragTargetForPoint:(CGPoint)p {
    if (_frameOnlyMode) {
        return SPKTrimDragTargetPlayhead;
    }
    CGFloat startX = [self xForTime:_startTime];
    CGFloat endX = [self xForTime:_endTime];
    CGFloat distLeft = fabs(p.x - startX);
    CGFloat distRight = fabs(p.x - endX);

    if (distLeft <= kSPKTrimGrabThreshold || distRight <= kSPKTrimGrabThreshold) {
        return (distLeft <= distRight) ? SPKTrimDragTargetLeftHandle : SPKTrimDragTargetRightHandle;
    }
    if (p.x > startX && p.x < endX) {
        return SPKTrimDragTargetPlayhead;
    }
    // Outside selection: grab the nearer handle so it extends toward the touch.
    return (p.x <= startX) ? SPKTrimDragTargetLeftHandle : SPKTrimDragTargetRightHandle;
}

- (void)applyDragAtPoint:(CGPoint)p {
    NSTimeInterval t = [self timeForX:p.x];
    switch (_dragTarget) {
    case SPKTrimDragTargetLeftHandle: {
        NSTimeInterval maxStart = MAX(0.0, _endTime - _minimumDuration);
        _startTime = MAX(0.0, MIN(t, maxStart));
        _playheadTime = _startTime;
        [self layoutSelection];
        [self layoutPlayhead];
        if ([self.delegate respondsToSelector:@selector(trimScrubber:didChangeStartTime:)]) {
            [self.delegate trimScrubber:self didChangeStartTime:_startTime];
        }
        break;
    }
    case SPKTrimDragTargetRightHandle: {
        NSTimeInterval minEnd = MIN(_duration, _startTime + _minimumDuration);
        _endTime = MIN(_duration, MAX(t, minEnd));
        _playheadTime = _endTime;
        [self layoutSelection];
        [self layoutPlayhead];
        if ([self.delegate respondsToSelector:@selector(trimScrubber:didChangeEndTime:)]) {
            [self.delegate trimScrubber:self didChangeEndTime:_endTime];
        }
        break;
    }
    case SPKTrimDragTargetPlayhead: {
        if (!_frameOnlyMode) {
            t = MAX(_startTime, MIN(t, _endTime));
        }
        self.playheadTime = t;
        if ([self.delegate respondsToSelector:@selector(trimScrubber:didScrubToTime:)]) {
            [self.delegate trimScrubber:self didScrubToTime:t];
        }
        break;
    }
    case SPKTrimDragTargetNone:
        break;
    }
}

@end

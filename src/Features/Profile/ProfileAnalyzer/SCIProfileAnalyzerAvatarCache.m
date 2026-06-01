#import "SCIProfileAnalyzerAvatarCache.h"
#import "SCIProfileAnalyzerStorage.h"

static NSTimeInterval const kSCIPAAvatarTTL = 24 * 60 * 60; // refresh at most once per day
static CGFloat const kSCIPAAvatarPixelSize = 120.0;         // stored square size

static UIImage *SCIPAAvatarSquareImage(UIImage *image);

@interface SCIProfileAnalyzerAvatarCache ()
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *memoryCache;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableSet<NSString *> *inflight;
@end

@implementation SCIProfileAnalyzerAvatarCache

+ (instancetype)shared {
    static SCIProfileAnalyzerAvatarCache *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SCIProfileAnalyzerAvatarCache new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _memoryCache = [NSCache new];
        // Tuned for long analyzer lists — smaller limits evict visible rows
        // mid-scroll so revisits show grey placeholders.
        _memoryCache.countLimit = 512;
        _ioQueue = dispatch_queue_create("com.scinsta.profileanalyzer.avatars", DISPATCH_QUEUE_SERIAL);
        _inflight = [NSMutableSet set];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 20;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

#pragma mark - Paths

static NSString *SCIPAAvatarDir(void) {
    NSString *root = [SCIProfileAnalyzerStorage storageRootPath];
    NSString *dir = [root stringByAppendingPathComponent:@"avatars"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *SCIPAAvatarPathForPK(NSString *pk) {
    NSString *safe = [pk stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    if (!safe.length) safe = @"anon";
    return [SCIPAAvatarDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", safe]];
}

#pragma mark - Public

- (UIImage *)cachedImageForPK:(NSString *)pk {
    if (!pk.length) return nil;
    return [self.memoryCache objectForKey:pk];
}

- (void)avatarForPK:(NSString *)pk
          urlString:(NSString *)urlString
         completion:(void (^)(UIImage *_Nullable))completion {
    if (!pk.length) {
        if (completion) completion(nil);
        return;
    }

    UIImage *warm = [self.memoryCache objectForKey:pk];
    if (warm) {
        if (completion) completion(warm);
        return;
    }

    dispatch_async(self.ioQueue, ^{
        NSString *path = SCIPAAvatarPathForPK(pk);
        NSFileManager *fm = [NSFileManager defaultManager];
        UIImage *diskImage = nil;
        BOOL stale = YES;

        if ([fm fileExistsAtPath:path]) {
            diskImage = [UIImage imageWithContentsOfFile:path];
            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
            NSDate *modified = attrs[NSFileModificationDate];
            if (modified) stale = (-[modified timeIntervalSinceNow] > kSCIPAAvatarTTL);
        }

        if (diskImage) {
            [self.memoryCache setObject:diskImage forKey:pk];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(diskImage); });
        }

        // Fetch from network only when missing or stale, and only with a URL.
        BOOL needsFetch = (!diskImage || stale) && urlString.length > 0;
        if (!needsFetch) {
            if (!diskImage) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil); });
            }
            return;
        }

        @synchronized (self.inflight) {
            if ([self.inflight containsObject:pk]) return; // a refresh is already running
            [self.inflight addObject:pk];
        }

        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            @synchronized (self.inflight) { [self.inflight removeObject:pk]; }
            return;
        }

        __weak typeof(self) weakSelf = self;
        BOOL hadDiskImage = (diskImage != nil);
        [[self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            @synchronized (strongSelf.inflight) { [strongSelf.inflight removeObject:pk]; }
            if (err || !data.length) return;
            UIImage *raw = [UIImage imageWithData:data];
            if (!raw) return;
            UIImage *square = SCIPAAvatarSquareImage(raw);
            if (!square) return;

            [strongSelf.memoryCache setObject:square forKey:pk];
            dispatch_async(strongSelf.ioQueue, ^{
                NSData *jpeg = UIImageJPEGRepresentation(square, 0.9);
                if (jpeg.length) [jpeg writeToFile:SCIPAAvatarPathForPK(pk) atomically:YES];
            });
            // Only call back with the network image if we didn't already serve a
            // disk copy (avoids a visible flicker when the stale image was good).
            if (!hadDiskImage) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(square); });
            }
        }] resume];
    });
}

- (void)purge {
    [self.memoryCache removeAllObjects];
    dispatch_async(self.ioQueue, ^{
        [[NSFileManager defaultManager] removeItemAtPath:SCIPAAvatarDir() error:nil];
    });
}

- (unsigned long long)diskSizeBytes {
    NSString *dir = SCIPAAvatarDir();
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
    unsigned long long total = 0;
    for (NSString *name in en) {
        NSDictionary *attrs = [en fileAttributes];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            total += [attrs[NSFileSize] unsignedLongLongValue];
        }
        (void)name;
    }
    return total;
}

#pragma mark - Helpers

// Center-crop to a square and downscale so we don't store full-res CDN images.
static UIImage *SCIPAAvatarSquareImage(UIImage *image) {
    if (!image) return nil;
    CGFloat side = MIN(image.size.width, image.size.height);
    if (side <= 0) return nil;
    CGRect crop = CGRectMake((image.size.width - side) / 2.0,
                             (image.size.height - side) / 2.0,
                             side, side);

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    format.opaque = YES;
    CGSize target = CGSizeMake(kSCIPAAvatarPixelSize, kSCIPAAvatarPixelSize);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
        CGImageRef cg = CGImageCreateWithImageInRect(image.CGImage, crop);
        if (cg) {
            UIImage *cropped = [UIImage imageWithCGImage:cg scale:image.scale orientation:image.imageOrientation];
            CGImageRelease(cg);
            [cropped drawInRect:CGRectMake(0, 0, target.width, target.height)];
        } else {
            [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
        }
    }];
}

@end

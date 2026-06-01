#import "SCIGalleryPaths.h"
#import "../SCIStoragePaths.h"
#import "../../Utils.h"

static NSString *_galleryDirectory;
static NSString *_galleryMediaDirectory;
static NSString *_galleryThumbnailsDirectory;

@implementation SCIGalleryPaths

+ (NSString *)galleryDirectory {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _galleryDirectory = [SCIStoragePaths galleryDirectory];
        [self ensureDirectoryExists:_galleryDirectory];
    });
    return _galleryDirectory;
}

+ (NSString *)galleryMediaDirectory {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _galleryMediaDirectory = [[self galleryDirectory] stringByAppendingPathComponent:@"Files"];
        [self ensureDirectoryExists:_galleryMediaDirectory];
    });
    return _galleryMediaDirectory;
}

+ (NSString *)galleryThumbnailsDirectory {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _galleryThumbnailsDirectory = [[self galleryDirectory] stringByAppendingPathComponent:@"Thumbnails"];
        [self ensureDirectoryExists:_galleryThumbnailsDirectory];
    });
    return _galleryThumbnailsDirectory;
}

+ (void)ensureDirectoryExists:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        NSError *error;
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            SCILog(@"General", @"[SCInsta Gallery] Failed to create directory %@: %@", path, error);
        }
    }
}

@end

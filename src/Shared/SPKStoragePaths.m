#import "SPKStoragePaths.h"
#import "../Utils.h"

static NSString *SPKDocumentsDirectory(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static BOOL SPKEnsureDirectory(NSString *path) {
    if (!path.length) return NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDirectory]) return isDirectory;

    NSError *error = nil;
    BOOL created = [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
    if (!created) SPKWarnLog(@"Storage", @"Failed to create directory %@: %@", path, error);
    return created;
}

static NSString *SPKStorageRoot(void) {
    NSString *root = [SPKDocumentsDirectory() stringByAppendingPathComponent:@"Sparkle"];
    SPKEnsureDirectory(root);
    return root;
}

static NSString *SPKStorageFeatureDirectory(NSString *featureName) {
    NSString *directory = [SPKStorageRoot() stringByAppendingPathComponent:featureName];
    SPKEnsureDirectory(directory);
    return directory;
}

@implementation SPKStoragePaths

+ (NSString *)galleryDirectory {
    return SPKStorageFeatureDirectory(@"Gallery");
}

+ (NSString *)deletedMessagesDirectory {
    return SPKStorageFeatureDirectory(@"DeletedMessages");
}

+ (NSString *)deletedMessagesPendingDirectory {
    return SPKStorageFeatureDirectory(@"DeletedMessagesPending");
}

+ (NSString *)profileAnalyzerDirectory {
    return SPKStorageFeatureDirectory(@"ProfileAnalyzer");
}

+ (NSString *)downloadsDirectory {
    return SPKStorageFeatureDirectory(@"Downloads");
}

@end

#import "SCIStoragePaths.h"
#import "../Utils.h"

static NSString *SCIDocumentsDirectory(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static BOOL SCIEnsureDirectory(NSString *path) {
    if (!path.length) return NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDirectory]) return isDirectory;

    NSError *error = nil;
    BOOL created = [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
    if (!created) SCIWarnLog(@"Storage", @"Failed to create directory %@: %@", path, error);
    return created;
}

static NSString *SCIStorageRoot(void) {
    NSString *root = [SCIDocumentsDirectory() stringByAppendingPathComponent:@"SCInsta"];
    SCIEnsureDirectory(root);
    return root;
}

static NSString *SCIStorageFeatureDirectory(NSString *featureName) {
    NSString *directory = [SCIStorageRoot() stringByAppendingPathComponent:featureName];
    SCIEnsureDirectory(directory);
    return directory;
}

@implementation SCIStoragePaths

+ (NSString *)scinstaDocumentsDirectory {
    return SCIStorageRoot();
}

+ (NSString *)galleryDirectory {
    return SCIStorageFeatureDirectory(@"Gallery");
}

+ (NSString *)deletedMessagesDirectory {
    return SCIStorageFeatureDirectory(@"DeletedMessages");
}

+ (NSString *)deletedMessagesPendingDirectory {
    return SCIStorageFeatureDirectory(@"DeletedMessagesPending");
}

+ (NSString *)profileAnalyzerDirectory {
    return SCIStorageFeatureDirectory(@"ProfileAnalyzer");
}

+ (NSString *)downloadsDirectory {
    return SCIStorageFeatureDirectory(@"Downloads");
}

@end

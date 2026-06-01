#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIStoragePaths : NSObject

+ (NSString *)scinstaDocumentsDirectory;
+ (NSString *)galleryDirectory;
+ (NSString *)deletedMessagesDirectory;
+ (NSString *)profileAnalyzerDirectory;

@end

NS_ASSUME_NONNULL_END

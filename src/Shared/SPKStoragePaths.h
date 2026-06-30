#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKStoragePaths : NSObject

+ (NSString *)galleryDirectory;
+ (NSString *)deletedMessagesDirectory;
+ (NSString *)deletedMessagesPendingDirectory;
+ (NSString *)profileAnalyzerDirectory;
+ (NSString *)downloadsDirectory;

@end

NS_ASSUME_NONNULL_END

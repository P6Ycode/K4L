#import <Foundation/Foundation.h>

#import "SCIDownloadTypes.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^SCIDownloadTransferProgressBlock)(int64_t bytesWritten, int64_t totalBytesExpected, double progress);
typedef void (^SCIDownloadTransferCompletionBlock)(NSString * _Nullable stagedPath, NSError * _Nullable error);

@interface SCIDownloadTransfer : NSObject

- (void)downloadURL:(NSURL *)url
         mediaKind:(SCIDownloadMediaKind)mediaKind
      fileExtension:(nullable NSString *)fileExtension
         stagingDir:(NSString *)stagingDir
             itemID:(NSString *)itemID
           progress:(nullable SCIDownloadTransferProgressBlock)progress
         completion:(SCIDownloadTransferCompletionBlock)completion;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import "../InstagramHeaders.h"
#import "../Utils.h"

#import "Manager.h"
#import "../Shared/UI/SCINotificationCenter.h"
#import "../Shared/MediaPreview/SCIFullScreenMediaPlayer.h"

@class SCIGallerySaveMetadata;
@class SCIGalleryFile;

typedef void (^SCIDownloadCompletionBlock)(NSURL * _Nullable fileURL, NSError * _Nullable error);
typedef void (^SCIDownloadCustomStartBlock)(void);

@interface SCIDownloadDelegate : NSObject <SCIDownloadDelegateProtocol>

typedef NS_ENUM(NSUInteger, DownloadAction) {
    share,
    saveToPhotos,
    saveToGallery,
    downloadOnly
};
@property (nonatomic, readonly) DownloadAction action;
@property (nonatomic, readonly) BOOL showProgress;

@property (nonatomic, strong) SCIDownloadManager *downloadManager;
@property (nonatomic, strong) SCINotificationPillView *progressView;
@property (nonatomic, copy, nullable) NSString *notificationIdentifier;
/// Set immediately before `downloadFileWithURL:` to name and annotate the completed file; consumed when the download finishes.
@property (nonatomic, strong, nullable) SCIGallerySaveMetadata *pendingGallerySaveMetadata;
@property (nonatomic, copy, nullable) SCIDownloadCompletionBlock completionBlock;
@property (nonatomic, copy, nullable) dispatch_block_t customCancelHandler;
@property (nonatomic, assign) BOOL duplicatePreflightApproved;
@property (nonatomic, copy, nullable) NSString *queueActionID;
@property (nonatomic, copy, nullable) NSString *queueJobID;
@property (nonatomic, copy, nullable) NSString *queueParentJobID;
@property (nonatomic, assign) BOOL queuedDownloadStarted;
@property (nonatomic, assign) BOOL retainedForOperation;
@property (nonatomic, assign) BOOL queueHistoryHidden;
/// The caller owns queue settlement. Used by grouped carousel children so the slot includes destination saving.
@property (nonatomic, assign) BOOL queueSettleExternally;

- (instancetype)initWithAction:(DownloadAction)action showProgress:(BOOL)showProgress;

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel;
- (void)startDownloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(nullable NSString *)hudLabel;
- (void)enqueueCustomOperationWithTitle:(NSString *)title
                                 detail:(nullable NSString *)detail
                             descriptor:(nullable NSDictionary *)descriptor
                                  start:(SCIDownloadCustomStartBlock)start;
- (void)beginCustomProgressWithTitle:(nullable NSString *)title subtitle:(nullable NSString *)subtitle;
- (void)updateCustomProgress:(float)progress title:(nullable NSString *)title subtitle:(nullable NSString *)subtitle;
- (void)updateCustomProgress:(float)progress
                        title:(nullable NSString *)title
                     subtitle:(nullable NSString *)subtitle
                 bytesWritten:(int64_t)bytesWritten
           totalBytesExpected:(int64_t)totalBytesExpected;
- (void)showCustomErrorWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle;
- (void)finishWithLocalFileURL:(NSURL *)fileURL;
- (void)cancelCustomOperation;

+ (BOOL)isVideoFileAtURL:(NSURL *)fileURL;
+ (BOOL)isAudioFileAtURL:(NSURL *)fileURL;
+ (nullable SCIGallerySaveMetadata *)metadataFromDescriptor:(NSDictionary *)descriptor;
+ (void)saveFileURLToPhotos:(NSURL *)fileURL completion:(void(^)(BOOL success, NSError * _Nullable error))completion;
+ (void)saveFileURLToPhotos:(NSURL *)fileURL
                   metadata:(nullable SCIGallerySaveMetadata *)metadata
                 completion:(void(^)(BOOL success, NSError * _Nullable error))completion;
+ (nullable SCIGalleryFile *)saveFileURLToGallery:(NSURL *)fileURL
                                         metadata:(nullable SCIGallerySaveMetadata *)metadata
                                            error:(NSError **)error;

@end

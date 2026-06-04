#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "../Downloads/SCIDownloadTypes.h"

@class SCIGallerySaveMetadata;

NS_ASSUME_NONNULL_BEGIN

@interface SCIMediaQualityManager : NSObject

+ (BOOL)handleDownloadDestination:(SCIDownloadDestination)destination
                       identifier:(NSString *)identifier
                        presenter:(nullable UIViewController *)presenter
                       sourceView:(nullable UIView *)sourceView
                      mediaObject:(nullable id)mediaObject
                         photoURL:(nullable NSURL *)photoURL
                         videoURL:(nullable NSURL *)videoURL
                  galleryMetadata:
                      (nullable SCIGallerySaveMetadata *)galleryMetadata
                     showProgress:(BOOL)showProgress
                    sourceSurface:(NSInteger)sourceSurface;

+ (BOOL)handleCopyActionWithIdentifier:(NSString *)identifier
                             presenter:(nullable UIViewController *)presenter
                            sourceView:(nullable UIView *)sourceView
                           mediaObject:(nullable id)mediaObject
                              photoURL:(nullable NSURL *)photoURL
                              videoURL:(nullable NSURL *)videoURL
                       galleryMetadata:
                           (nullable SCIGallerySaveMetadata *)galleryMetadata
                          showProgress:(BOOL)showProgress
                         sourceSurface:(NSInteger)sourceSurface;

+ (UIViewController *)encodingSettingsViewController;
+ (NSArray *)encodingSettingsSearchSections;

/// DASH / FFmpeg pipeline (download + merge). `optionKind` uses
/// SCIMediaOptionKind values from SCIMediaQualityManager.m.
+ (void)
    runDashDownloadWithPrimaryURL:(NSURL *)primaryURL
                     secondaryURL:(nullable NSURL *)secondaryURL
                       optionKind:(NSInteger)optionKind
                         basename:(NSString *)basename
                         duration:(double)duration
                            width:(NSInteger)width
                           height:(NSInteger)height
                    sourceBitrate:(NSInteger)bandwidth
                        extension:(NSString *)extension
                         progress:(void (^)(float progress,
                                            NSString *_Nullable stageTitle,
                                            int64_t bytesWritten,
                                            int64_t totalBytesExpected))progress
                          failure:(void (^)(NSString *title,
                                            NSString *message))failure
                          success:(void (^)(NSURL *outputURL))success
                        cancelOut:
                            (void (^)(dispatch_block_t _Nullable cancelBlock))
                                cancelOut;

@end

NS_ASSUME_NONNULL_END

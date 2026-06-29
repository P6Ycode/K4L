#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKAudioDMUploadCoordinator : NSObject

+ (BOOL)senderTargetSupportsAudioUpload:(nullable id)senderTarget;
+ (void)presentUploadPickerForSenderTarget:(id)senderTarget
                                 presenter:(UIViewController *)presenter
                                sourceView:(nullable UIView *)sourceView;

@end

NS_ASSUME_NONNULL_END

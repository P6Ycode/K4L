#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKSettingsTransferManager : NSObject

+ (instancetype)sharedManager;
- (void)exportFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery includeDeletedMessages:(BOOL)includeDeletedMessages includeProfileAnalyzer:(BOOL)includeProfileAnalyzer;
- (void)importFromController:(UIViewController *)controller includeSettings:(BOOL)includeSettings includeGallery:(BOOL)includeGallery includeDeletedMessages:(BOOL)includeDeletedMessages includeProfileAnalyzer:(BOOL)includeProfileAnalyzer;
- (void)resetAllSettingsFromController:(UIViewController *)controller;

@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>

@class SCIGalleryFile;

NS_ASSUME_NONNULL_BEGIN

typedef void (^SCIGalleryPickerCompletion)(NSArray<SCIGalleryFile *> *selectedFiles);

@interface SCIGalleryPickerViewController : UIViewController

+ (BOOL)hasSelectableFilesForAllowedMediaTypes:(nullable NSSet<NSNumber *> *)allowedMediaTypes;

+ (void)presentFromViewController:(UIViewController *)presenter
                            title:(nullable NSString *)title
                allowedMediaTypes:(nullable NSSet<NSNumber *> *)allowedMediaTypes
          allowsMultipleSelection:(BOOL)allowsMultipleSelection
                       completion:(SCIGalleryPickerCompletion)completion;

- (instancetype)initWithTitle:(nullable NSString *)title
            allowedMediaTypes:(nullable NSSet<NSNumber *> *)allowedMediaTypes
      allowsMultipleSelection:(BOOL)allowsMultipleSelection
                   completion:(SCIGalleryPickerCompletion)completion;

- (instancetype)initWithFolderPath:(nullable NSString *)folderPath
                              title:(nullable NSString *)title
                  allowedMediaTypes:(nullable NSSet<NSNumber *> *)allowedMediaTypes
            allowsMultipleSelection:(BOOL)allowsMultipleSelection
                         completion:(SCIGalleryPickerCompletion)completion;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Crop-rectangle aspect behaviour for the photo editor.
typedef NS_ENUM(NSInteger, SPKPhotoEditorAspectMode) {
    /// A single fixed 1:1 crop, no ratio picker (Instants positioning).
    SPKPhotoEditorAspectModeLockedSquare = 0,
    /// Freeform + ratio presets (Original / 1:1 / 4:5 / 16:9) for general editing.
    SPKPhotoEditorAspectModeFreeform = 1,
};

/// Configures a photo editor instance. Instants uses `lockedSquareConfiguration`;
/// the Gallery uses `freeformConfiguration`.
@interface SPKPhotoEditorConfiguration : NSObject
@property (nonatomic, assign) SPKPhotoEditorAspectMode aspectMode;
/// Title of the confirm button (e.g. "Use" for Instants, "Done" for Gallery).
@property (nonatomic, copy) NSString *confirmButtonTitle;

+ (instancetype)lockedSquareConfiguration;   // confirm = "Use"
+ (instancetype)freeformConfiguration;       // confirm = "Done"
@end

/// A self-contained, full-screen photo editor: pan/zoom crop with a selectable
/// aspect (freeform + ratio presets), plus 90° rotate and horizontal flip.
/// Generalized from the original Instants square cropper so it can be reused by
/// the Gallery and the trim editor's Frame Only output.
@interface SPKPhotoEditorViewController : UIViewController
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, strong) SPKPhotoEditorConfiguration *configuration;
/// Called with the edited image when the user confirms. Not called on cancel.
@property (nonatomic, copy) void (^completion)(UIImage *image);

/// Presents the editor wrapped in a dark, full-screen navigation controller
/// (matching the trim editor's chrome — native top bar renders as Liquid Glass on
/// iOS 26). `completion` runs only when the user confirms.
+ (void)presentWithSourceImage:(UIImage *)image
                 configuration:(nullable SPKPhotoEditorConfiguration *)configuration
                          from:(UIViewController *)presenter
                    completion:(void (^)(UIImage *image))completion;
@end

NS_ASSUME_NONNULL_END

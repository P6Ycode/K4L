#import <UIKit/UIKit.h>

@class SCIGalleryFile;

NS_ASSUME_NONNULL_BEGIN

@interface SCIGalleryGridCell : UICollectionViewCell

- (void)configureWithGalleryFile:(SCIGalleryFile *)file
                 selectionMode:(BOOL)selectionMode
                      selected:(BOOL)selected;

/// Extended configuration that can overlay the source-type icon (top-left) and
/// the `@username` caption (bottom-left). `showsUsername` is typically gated on
/// a roomy density (2–3 columns) by the caller.
- (void)configureWithGalleryFile:(SCIGalleryFile *)file
                 selectionMode:(BOOL)selectionMode
                      selected:(BOOL)selected
                    showsSource:(BOOL)showsSource
                  showsUsername:(BOOL)showsUsername;

- (void)setSelectionMode:(BOOL)selectionMode selected:(BOOL)selected animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END

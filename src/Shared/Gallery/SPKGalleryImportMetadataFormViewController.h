#import <UIKit/UIKit.h>

@class SPKGallerySaveMetadata;

NS_ASSUME_NONNULL_BEGIN

/// Full editor for `SPKGallerySaveMetadata` (same fields as saves from Instagram). Mutates the passed object.
@interface SPKGalleryImportMetadataFormViewController : UITableViewController

@property (nonatomic, strong) SPKGallerySaveMetadata *metadata;
@property (nonatomic, copy, nullable) NSString *footerStemExplanation;

@end

NS_ASSUME_NONNULL_END

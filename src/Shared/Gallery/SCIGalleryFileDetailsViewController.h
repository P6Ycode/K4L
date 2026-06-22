#import <UIKit/UIKit.h>

@class SCIGalleryFile;

NS_ASSUME_NONNULL_BEGIN

/// Edit-details form for a vault file: editable display name, source username and
/// date, plus read-only context (type, dimensions, size, folder, media code).
/// Replaces the old single-field "Rename".
@interface SCIGalleryFileDetailsViewController : UITableViewController

- (instancetype)initWithFile:(SCIGalleryFile *)file;

/// Called after the user saves changes (so the presenter can refetch/reload).
@property (nonatomic, copy, nullable) void (^onSaved)(void);

@end

NS_ASSUME_NONNULL_END

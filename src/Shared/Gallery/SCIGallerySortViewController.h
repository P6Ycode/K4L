#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIGallerySortMode) {
    SCIGallerySortModeDateAddedDesc = 0,  // Newest first (default)
    SCIGallerySortModeDateAddedAsc,       // Oldest first
    SCIGallerySortModeNameAsc,            // A→Z
    SCIGallerySortModeNameDesc,           // Z→A
    SCIGallerySortModeSizeDesc,           // Largest first
    SCIGallerySortModeSizeAsc,            // Smallest first
    SCIGallerySortModeTypeAsc,            // Legacy: grouped by media type
    SCIGallerySortModeTypeDesc,           // Legacy: grouped by media type
};

@class SCIGallerySortViewController;

@protocol SCIGallerySortViewControllerDelegate <NSObject>
- (void)sortController:(SCIGallerySortViewController *)controller didSelectSortMode:(SCIGallerySortMode)mode groupByMediaType:(BOOL)groupByMediaType;
@end

@interface SCIGallerySortViewController : UIViewController

@property (nonatomic, weak) id<SCIGallerySortViewControllerDelegate> delegate;
@property (nonatomic, assign) SCIGallerySortMode currentSortMode;
@property (nonatomic, assign) BOOL currentGroupByMediaType;

/// The height the content needs at the given width (excluding the nav bar and
/// bottom safe area), so the presenter can size a single fixed sheet detent to it
/// once — no layout-time detent invalidation (which deadlocks iOS 26).
- (CGFloat)sciContentHeightForWidth:(CGFloat)width;

+ (NSArray<NSSortDescriptor *> *)sortDescriptorsForMode:(SCIGallerySortMode)mode;
+ (NSArray<NSSortDescriptor *> *)sortDescriptorsForMode:(SCIGallerySortMode)mode groupByMediaType:(BOOL)groupByMediaType;
+ (NSString *)labelForMode:(SCIGallerySortMode)mode;

@end

NS_ASSUME_NONNULL_END

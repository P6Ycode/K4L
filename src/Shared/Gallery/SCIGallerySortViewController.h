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

+ (NSArray<NSSortDescriptor *> *)sortDescriptorsForMode:(SCIGallerySortMode)mode;
+ (NSArray<NSSortDescriptor *> *)sortDescriptorsForMode:(SCIGallerySortMode)mode groupByMediaType:(BOOL)groupByMediaType;
+ (NSString *)labelForMode:(SCIGallerySortMode)mode;

@end

NS_ASSUME_NONNULL_END

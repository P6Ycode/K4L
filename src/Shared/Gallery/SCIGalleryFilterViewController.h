#import <UIKit/UIKit.h>
#import "SCIGalleryFile.h"

NS_ASSUME_NONNULL_BEGIN

@class SCIGalleryFilterViewController;

@protocol SCIGalleryFilterViewControllerDelegate <NSObject>
- (void)filterController:(SCIGalleryFilterViewController *)controller
           didApplyTypes:(NSSet<NSNumber *> *)types
                 sources:(NSSet<NSNumber *> *)sources
           favoritesOnly:(BOOL)favoritesOnly
                usernames:(NSSet<NSString *> *)usernames;

- (void)filterControllerDidClear:(SCIGalleryFilterViewController *)controller;
@end

/// Sheet controller for filtering the gallery by type, source and favorites.
///
/// If `filterTypes` is empty, no type filter is applied. Same for `filterSources`.
@interface SCIGalleryFilterViewController : UIViewController

@property (nonatomic, weak) id<SCIGalleryFilterViewControllerDelegate> delegate;

@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterTypes;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterSources;
@property (nonatomic, assign) BOOL filterFavoritesOnly;
@property (nonatomic, strong) NSMutableSet<NSString *> *filterUsernames;
@property (nonatomic, copy) NSArray<NSString *> *availableUsernames;

/// The height the content needs at the given width (excluding the nav bar and
/// bottom safe area), so the presenter can size a single fixed sheet detent to it
/// once — no layout-time detent invalidation (which deadlocks iOS 26).
- (CGFloat)sciContentHeightForWidth:(CGFloat)width;

/// Composes an NSPredicate from the given filters, or nil if no filters are active.
+ (nullable NSPredicate *)predicateForTypes:(NSSet<NSNumber *> *)types
                                    sources:(NSSet<NSNumber *> *)sources
                              favoritesOnly:(BOOL)favoritesOnly
                                   usernames:(NSSet<NSString *> *)usernames
                                 folderPath:(nullable NSString *)folderPath;

/// When `scopeToFolder` is NO, no folder constraint is applied (search/browse
/// across all folders); otherwise behaves like the method above.
+ (nullable NSPredicate *)predicateForTypes:(NSSet<NSNumber *> *)types
                                    sources:(NSSet<NSNumber *> *)sources
                              favoritesOnly:(BOOL)favoritesOnly
                                   usernames:(NSSet<NSString *> *)usernames
                                 folderPath:(nullable NSString *)folderPath
                              scopeToFolder:(BOOL)scopeToFolder;

@end

NS_ASSUME_NONNULL_END

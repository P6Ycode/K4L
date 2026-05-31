#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Shared grid-density configuration used by the gallery, the gallery picker
// (instants / audio upload sheets), and the gallery settings screen so all of
// them stay in sync.

// NSUserDefaults keys.
FOUNDATION_EXPORT NSString * const kSCIGalleryGridColumnsKey;          // NSInteger, persisted column count
FOUNDATION_EXPORT NSString * const kSCIGalleryGridPinchDisabledKey;    // BOOL, YES disables pinch-to-zoom
FOUNDATION_EXPORT NSString * const kSCIGalleryGridShowSourceUsernameDisabledKey; // BOOL, YES hides source icon + username overlays
FOUNDATION_EXPORT NSString * const kSCIGalleryGridControlsChangedNotification;

// Allowed densities and bounds.
FOUNDATION_EXPORT NSInteger const kSCIGalleryGridColumnsDefault;
FOUNDATION_EXPORT NSInteger const kSCIGalleryGridColumnsMin;
FOUNDATION_EXPORT NSInteger const kSCIGalleryGridColumnsMax;

/// The persisted, clamped column count (falls back to the default when unset).
FOUNDATION_EXPORT NSInteger SCIGalleryGridColumns(void);
/// Persists a clamped column count.
FOUNDATION_EXPORT void SCIGalleryGridSetColumns(NSInteger columns);
/// Next density toward larger cells (fewer columns) or smaller cells (more).
FOUNDATION_EXPORT NSInteger SCIGalleryGridColumnsAdjacent(NSInteger columns, BOOL largerCells);

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class SCIInstantsResolvedSnap, SCIInstantsResolverResult;

/// Returns YES if the service cache has at least one pending Instant.
BOOL SCIInstantsHasCachedMedia(void);

/// Returns the count of cached Instants (for button visibility decisions).
NSUInteger SCIInstantsCachedMediaCount(void);

/// Primary resolution entry point. Called at action execution time only.
/// @param header The QuickSnap header view (used to locate stack view for active index).
/// @param reason Debug string: "media", "bulk", or "index".
SCIInstantsResolverResult *SCIInstantsResolveForHeader(UIView *header, NSString *reason);

/// Installs service/listener hooks. Called once at startup.
void SCIInstallInstantsResolverHooks(void);

@interface SCIInstantsResolvedSnap : NSObject
@property (nonatomic, strong) NSURL *scinstaMediaURL;
@property (nonatomic, strong) NSURL *scinstaPhotoURL;
@property (nonatomic, strong) NSURL *scinstaVideoURL;
@property (nonatomic, assign) BOOL scinstaIsVideo;
@property (nonatomic, copy) NSString *sourceUsername;
@property (nonatomic, copy) NSString *sourceMediaPK;
@property (nonatomic, copy) NSString *sourceMediaURLString;
@property (nonatomic, strong) NSDate *importPostedDate;
@property (nonatomic, strong) id backingMedia;
@property (nonatomic, copy) NSString *resolverPath;
@property (nonatomic, copy) NSString *authorResolverPath;
@end

@interface SCIInstantsResolverResult : NSObject
@property (nonatomic, copy) NSArray<SCIInstantsResolvedSnap *> *snaps;
@property (nonatomic, assign) NSInteger activeIndex;
@property (nonatomic, copy) NSString *path;
/// The currently-displayed snap, resolved directly from the active view. This is the
/// source of truth for single-tap downloads and is always correct regardless of whether
/// it could be matched into the bulk `snaps` list (which comes from the full store list).
@property (nonatomic, strong) SCIInstantsResolvedSnap *activeSnap;
@end

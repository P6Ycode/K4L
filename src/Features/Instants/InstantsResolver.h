#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class SPKInstantsResolvedSnap, SPKInstantsResolverResult;

/// Primary resolution entry point. Called at action execution time only.
/// @param header The QuickSnap header view (used to locate stack view for active index).
/// @param reason Debug string: "media", "bulk", or "index".
SPKInstantsResolverResult *SPKInstantsResolveForHeader(UIView *header, NSString *reason);

/// Installs service/listener hooks. Called once at startup.
void SPKInstallInstantsResolverHooks(void);

@interface SPKInstantsResolvedSnap : NSObject
@property (nonatomic, strong) NSURL *sparkleMediaURL;
@property (nonatomic, strong) NSURL *sparklePhotoURL;
@property (nonatomic, strong) NSURL *sparkleVideoURL;
@property (nonatomic, assign) BOOL sparkleIsVideo;
@property (nonatomic, copy) NSString *sourceUsername;
@property (nonatomic, copy) NSString *sourceMediaPK;
@property (nonatomic, copy) NSString *sourceMediaURLString;
@property (nonatomic, strong) NSDate *importPostedDate;
@property (nonatomic, strong) id backingMedia;
@property (nonatomic, copy) NSString *resolverPath;
@property (nonatomic, copy) NSString *authorResolverPath;
@end

@interface SPKInstantsResolverResult : NSObject
@property (nonatomic, copy) NSArray<SPKInstantsResolvedSnap *> *snaps;
@property (nonatomic, assign) NSInteger activeIndex;
@property (nonatomic, copy) NSString *path;
/// The currently-displayed snap, resolved directly from the active view. This is the
/// source of truth for single-tap downloads and is always correct regardless of whether
/// it could be matched into the bulk `snaps` list (which comes from the full store list).
@property (nonatomic, strong) SPKInstantsResolvedSnap *activeSnap;
@end

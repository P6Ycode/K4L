#import <UIKit/UIKit.h>

#import "SCITrimConfiguration.h"
#import "SCITrimResult.h"

NS_ASSUME_NONNULL_BEGIN

@class SCITrimEditorViewController;

@protocol SCITrimEditorDelegate <NSObject>
@optional
- (void)trimEditor:(SCITrimEditorViewController *)editor didFinishWithResult:(SCITrimResult *)result;
- (void)trimEditorDidCancel:(SCITrimEditorViewController *)editor;
@end

/// Full-screen media trim editor: preview + filmstrip scrubber + in/out handles
/// + optional single-frame mode. On confirm it renders a temp file and reports
/// an `SCITrimResult`. The editor never saves — the caller routes the result.
@interface SCITrimEditorViewController : UIViewController

@property (nonatomic, weak) id<SCITrimEditorDelegate> delegate;
@property (nonatomic, copy, nullable) void (^completion)(SCITrimResult *_Nullable result);

- (instancetype)initWithConfiguration:(SCITrimConfiguration *)configuration;

/// Convenience: build, present full-screen from `presenter`, and report the
/// result (nil on cancel) via `completion`.
+ (void)presentWithConfiguration:(SCITrimConfiguration *)configuration
                            from:(UIViewController *)presenter
                      completion:(nullable void (^)(SCITrimResult *_Nullable result))completion;

@end

NS_ASSUME_NONNULL_END

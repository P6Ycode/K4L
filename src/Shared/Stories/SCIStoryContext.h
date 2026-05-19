#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIStoryContext : NSObject
@property (nonatomic, weak, nullable) UIView *overlayView;
@property (nonatomic, weak, nullable) UIViewController *viewerController;
@property (nonatomic, strong, nullable) id sectionController;
@property (nonatomic, strong, nullable) id markSeenTarget;
@property (nonatomic, strong, nullable) id media;
@property (nonatomic, strong, nullable) NSArray *allMedia;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, strong, nullable) NSURL *storyURL;
@end

#ifdef __cplusplus
extern "C" {
#endif

void SCIStorySetActiveOverlay(UIView *_Nullable overlayView);
UIView *_Nullable SCIStoryActiveOverlay(void);
SCIStoryContext *_Nullable SCIStoryContextFromOverlay(UIView *_Nullable overlayView);
SCIStoryContext *_Nullable SCIStoryContextFromView(UIView *_Nullable view);
SCIStoryContext *_Nullable SCIStoryContextFromMedia(id _Nullable media);
BOOL SCIStoryMarkContextAsSeen(SCIStoryContext *_Nullable context);
void SCIStoryAdvanceContextIfNeeded(SCIStoryContext *_Nullable context, NSString *_Nullable advancePrefKey);

NSString *_Nullable SCIStoryUsernameForContext(SCIStoryContext *_Nullable context);
NSURL *_Nullable SCIStoryURLForContext(SCIStoryContext *_Nullable context);
NSString *_Nullable SCIStoryMediaIdentifierForContext(SCIStoryContext *_Nullable context);

BOOL SCIStoryManualSeenAppliesToContext(SCIStoryContext *_Nullable context);
NSArray<NSString *> *SCIStoryManualSeenUserList(BOOL manualSeenEnabled);
void SCIStorySetManualSeenUserList(NSArray<NSString *> *users, BOOL manualSeenEnabled);
BOOL SCIStoryManualSeenListContainsUsername(NSString *_Nullable username, BOOL manualSeenEnabled);
void SCIStoryToggleUsernameForCurrentManualSeenMode(NSString *username);
NSString *SCIStoryManualSeenListTitle(BOOL manualSeenEnabled);
UIViewController *SCIStoryManualSeenListViewController(void);
NSArray *_Nullable SCIStoryAppendCurrentUserMenuItem(NSArray *_Nullable items);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

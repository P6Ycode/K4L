#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIDirectThreadContext : NSObject
@property (nonatomic, copy, nullable) NSString *threadId;
@property (nonatomic, copy, nullable) NSString *threadName;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy) NSArray<NSDictionary *> *users;
@property (nonatomic, copy, nullable) NSString *groupPhotoUrl;
@end

#ifdef __cplusplus
extern "C" {
#endif

SCIDirectThreadContext *_Nullable SCIDirectThreadContextFromSource(id _Nullable source);
SCIDirectThreadContext *_Nullable SCIDirectThreadContextFromInboxViewModel(id _Nullable viewModel);
NSDictionary *_Nullable SCIDirectThreadEntryFromContext(SCIDirectThreadContext *_Nullable context);

void SCIDirectSetActiveThreadContext(SCIDirectThreadContext *_Nullable context);
SCIDirectThreadContext *_Nullable SCIDirectActiveThreadContext(void);

NSArray<NSDictionary *> *SCIDirectManualSeenThreadList(BOOL manualSeenEnabled);
void SCIDirectSetManualSeenThreadList(NSArray<NSDictionary *> *threads, BOOL manualSeenEnabled);
BOOL SCIDirectManualSeenListContainsThreadId(NSString *_Nullable threadId, BOOL manualSeenEnabled);
void SCIDirectAddOrUpdateManualSeenThreadEntry(NSDictionary *entry, BOOL manualSeenEnabled);
void SCIDirectRemoveManualSeenThreadId(NSString *threadId, BOOL manualSeenEnabled);
NSString *SCIDirectManualSeenListTitle(BOOL manualSeenEnabled);
NSUInteger SCIDirectManualSeenThreadCount(BOOL manualSeenEnabled);
UIViewController *SCIDirectManualSeenListViewController(void);
NSDictionary *_Nullable SCIDirectManualSeenThreadEntryForUserPK(NSString * _Nullable pk, BOOL manualSeenEnabled);

BOOL SCIDirectManualSeenAppliesToSource(id _Nullable source);
BOOL SCIDirectShouldShowSeenButtonForSource(id _Nullable source);
NSString *_Nullable SCIDirectCurrentThreadRuleActionTitle(SCIDirectThreadContext *_Nullable context);
NSString *_Nullable SCIDirectCurrentThreadRuleConfirmationTitle(SCIDirectThreadContext *_Nullable context);
NSString *_Nullable SCIDirectCurrentThreadRuleConfirmationMessage(SCIDirectThreadContext *_Nullable context);
BOOL SCIDirectToggleCurrentThreadRule(SCIDirectThreadContext *_Nullable context, NSString *_Nullable *_Nullable notificationTitle, NSString *_Nullable *_Nullable notificationSubtitle);

extern BOOL SCIDirectSeenDebugPrintEnabled;

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

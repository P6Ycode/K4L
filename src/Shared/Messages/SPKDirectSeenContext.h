#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKDirectThreadContext : NSObject
@property (nonatomic, copy, nullable) NSString *threadId;
@property (nonatomic, copy, nullable) NSString *threadName;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy) NSArray<NSDictionary *> *users;
@property (nonatomic, copy, nullable) NSString *groupPhotoUrl;
@end

#ifdef __cplusplus
extern "C" {
#endif

SPKDirectThreadContext *_Nullable SPKDirectThreadContextFromSource(id _Nullable source);
SPKDirectThreadContext *_Nullable SPKDirectThreadContextFromInboxViewModel(id _Nullable viewModel);
NSDictionary *_Nullable SPKDirectThreadEntryFromContext(SPKDirectThreadContext *_Nullable context);

void SPKDirectSetActiveThreadContext(SPKDirectThreadContext *_Nullable context);
SPKDirectThreadContext *_Nullable SPKDirectActiveThreadContext(void);

NSArray<NSDictionary *> *SPKDirectManualSeenThreadList(BOOL manualSeenEnabled);
void SPKDirectSetManualSeenThreadList(NSArray<NSDictionary *> *threads, BOOL manualSeenEnabled);
BOOL SPKDirectManualSeenListContainsThreadId(NSString *_Nullable threadId, BOOL manualSeenEnabled);
void SPKDirectAddOrUpdateManualSeenThreadEntry(NSDictionary *entry, BOOL manualSeenEnabled);
void SPKDirectRemoveManualSeenThreadId(NSString *threadId, BOOL manualSeenEnabled);
NSString *SPKDirectManualSeenListTitle(BOOL manualSeenEnabled);
NSUInteger SPKDirectManualSeenThreadCount(BOOL manualSeenEnabled);
UIViewController *SPKDirectManualSeenListViewController(void);
NSDictionary *_Nullable SPKDirectManualSeenThreadEntryForUserPK(NSString *_Nullable pk, BOOL manualSeenEnabled);

BOOL SPKDirectManualSeenAppliesToSource(id _Nullable source);
BOOL SPKDirectShouldShowSeenButtonForSource(id _Nullable source);
NSString *_Nullable SPKDirectCurrentThreadRuleActionTitle(SPKDirectThreadContext *_Nullable context);
NSString *_Nullable SPKDirectCurrentThreadRuleConfirmationTitle(SPKDirectThreadContext *_Nullable context);
NSString *_Nullable SPKDirectCurrentThreadRuleConfirmationMessage(SPKDirectThreadContext *_Nullable context);
BOOL SPKDirectToggleCurrentThreadRule(SPKDirectThreadContext *_Nullable context, NSString *_Nullable *_Nullable notificationTitle, NSString *_Nullable *_Nullable notificationSubtitle);

extern BOOL SPKDirectSeenDebugPrintEnabled;

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

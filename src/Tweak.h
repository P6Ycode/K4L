#import <Foundation/Foundation.h>

// * Tweak version *
extern NSString *SPKVersionString;

// Variables that work across features
extern __weak id SPKPendingDirectVisualMessageToMarkSeen;
extern NSString *SPKForcedStorySeenMediaPK;
extern BOOL SPKForceMarkStoryAsSeen;
extern BOOL SPKForceStoryAutoAdvance;

NSString *SPKStoryMediaIdentifier(id media);

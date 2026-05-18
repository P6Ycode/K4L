#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void SCIStabilityGuardBeginLaunch(void);
FOUNDATION_EXPORT void SCIStabilityGuardMarkHooksFinished(void);
FOUNDATION_EXPORT BOOL SCIStabilityGuardIsSafeStartupMode(void);
FOUNDATION_EXPORT void SCIStabilityGuardReset(void);

NS_ASSUME_NONNULL_END

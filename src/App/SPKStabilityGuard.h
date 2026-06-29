#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void SPKStabilityGuardBeginLaunch(void);
FOUNDATION_EXPORT void SPKStabilityGuardMarkHooksFinished(void);
FOUNDATION_EXPORT BOOL SPKStabilityGuardIsSafeStartupMode(void);
FOUNDATION_EXPORT void SPKStabilityGuardReset(void);

NS_ASSUME_NONNULL_END

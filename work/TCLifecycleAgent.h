#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum TCLifecycleDecision {
    TCLifecycleDecisionNone = 0,
    TCLifecycleDecisionLaunch = 1,
    TCLifecycleDecisionTerminate = 2,
} TCLifecycleDecision;

// Pure-C policy: one decision at most for the current WeChat/tool state.
TCLifecycleDecision TCLifecycleDecide(bool wechatRunning,
                                      bool toolRunning,
                                      bool launchInFlight);

#ifdef __cplusplus
}
#endif

#ifdef __OBJC__
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT int TCLifecycleAgentMain(void);
FOUNDATION_EXPORT BOOL TCLifecycleAgentEnabled(void);
FOUNDATION_EXPORT BOOL TCLifecycleAgentRegistered(void);
FOUNDATION_EXPORT BOOL TCLifecycleAgentCanRegister(void);
FOUNDATION_EXPORT NSString *TCLifecycleAgentStatus(void);
FOUNDATION_EXPORT BOOL TCSetLifecycleAgentEnabled(BOOL enabled, NSError **error);
FOUNDATION_EXPORT BOOL TCLifecycleAppIsInstalled(void);
#endif

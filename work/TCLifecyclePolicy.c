#include "TCLifecycleAgent.h"

TCLifecycleDecision TCLifecycleDecide(bool wechatRunning,
                                      bool toolRunning,
                                      bool launchInFlight) {
    if (wechatRunning) {
        return toolRunning ? TCLifecycleDecisionTerminate : TCLifecycleDecisionNone;
    }
    if (!toolRunning && !launchInFlight) return TCLifecycleDecisionLaunch;
    return TCLifecycleDecisionNone;
}

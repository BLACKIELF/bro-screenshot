#include "../../TCLifecycleAgent.h"

#include <assert.h>

int main(void) {
    assert(TCLifecycleDecide(false, false, false) == TCLifecycleDecisionLaunch);
    assert(TCLifecycleDecide(false, false, true) == TCLifecycleDecisionNone);
    assert(TCLifecycleDecide(false, true, false) == TCLifecycleDecisionNone);
    // An outstanding launch request must not trigger a second launch even if
    // the process list has not caught up yet.
    assert(TCLifecycleDecide(false, true, true) == TCLifecycleDecisionNone);
    assert(TCLifecycleDecide(true, false, false) == TCLifecycleDecisionNone);
    // WeChat appearing during an in-flight launch must never launch again.
    assert(TCLifecycleDecide(true, false, true) == TCLifecycleDecisionNone);
    assert(TCLifecycleDecide(true, true, false) == TCLifecycleDecisionTerminate);
    assert(TCLifecycleDecide(true, true, true) == TCLifecycleDecisionTerminate);
    return 0;
}

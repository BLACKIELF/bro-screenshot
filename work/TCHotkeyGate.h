#ifndef TC_HOTKEY_GATE_H
#define TC_HOTKEY_GATE_H
#include <stdbool.h>
// One action per physical press. Completion/cancellation never resets the latch;
// only Carbon's matching release does, so a held key cannot create new workers.
static inline bool TCKeyAction(bool *down, bool pressed) {
    if (!pressed) { *down = false; return false; }
    if (*down) return false;
    *down = true;
    return true;
}
#endif

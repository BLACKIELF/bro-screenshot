#ifndef TC_SESSION_H
#define TC_SESSION_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TCSession TCSession;

/*
 * A session owns one short-lived worker process.  The callback is invoked by
 * the session's monitor thread, never by the caller of TCSessionStart.
 *
 * event is one of:
 *   "spawn"   value is the worker pid
 *   "state"   value is the state byte ('P', 'E', 'S', 'O', 'L', or 'F')
 *   "exit"    value is the normal exit status, or 128 + signal number
 *   "timeout" value is one of the TC_SESSION_TIMEOUT_* constants below
 */
TCSession *TCSessionCreate(const char *exe,
                           const char *fakeMode,
                           void (*onEvent)(const char *, int, void *),
                           void *ctx);
int TCSessionStart(TCSession *session);
void TCSessionCancel(TCSession *session);
int TCSessionIsActive(TCSession *session);
void TCSessionDestroy(TCSession *session);

/* These functions are used only by a worker process. */
int TCWorkerGuardStart(void);
void TCWorkerPulse(char state);
void TCWorkerFinish(int exitCode);
int TCSessionRunFakeWorker(const char *mode);

/* Values delivered with a "timeout" callback. */
enum {
    TC_SESSION_TIMEOUT_HEARTBEAT = 1,
    TC_SESSION_TIMEOUT_PRECAPTURE = 2,
    TC_SESSION_TIMEOUT_CANCEL_KILL = 3
};

/* Fixed descriptors used only across the parent/worker exec boundary. */
enum {
    TC_WORKER_CONTROL_FD = 198,
    TC_WORKER_STATUS_FD = 199
};

/* Stable terminal values used by the native worker. */
enum {
    TC_WORKER_EXIT_SUCCESS = 0,
    TC_WORKER_EXIT_SAVE_SUCCESS = 1,
    TC_WORKER_EXIT_OCR_SUCCESS = 2,
    TC_WORKER_EXIT_CANCELLED = 10,
    TC_WORKER_EXIT_SAVE_CANCELLED = 11,
    TC_WORKER_EXIT_OCR_EMPTY = 12,
    TC_WORKER_EXIT_NO_PERMISSION = 20,
    TC_WORKER_EXIT_ABI_FAILURE = 21,
    TC_WORKER_EXIT_CAPTURE_FAILURE = 22,
    TC_WORKER_EXIT_NATIVE_START_FAILURE = 23,
    TC_WORKER_EXIT_ENCODING_FAILURE = 24,
    TC_WORKER_EXIT_LONG_CAPTURE_FAILURE = 25,
    TC_WORKER_EXIT_EXCEPTION = 26,
    TC_WORKER_EXIT_PROCESSING_TIMEOUT = 27,
    TC_WORKER_EXIT_SAVE_FAILURE = 28,
    TC_WORKER_EXIT_OCR_FAILURE = 29,
    TC_WORKER_EXIT_GUARD_FAILURE = 30,
    TC_WORKER_EXIT_PIN_SUCCESS = 31
};

#ifdef __cplusplus
}
#endif

#endif /* TC_SESSION_H */

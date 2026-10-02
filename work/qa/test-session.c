#define _POSIX_C_SOURCE 200809L

#include "../TCSession.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

typedef struct {
    pthread_mutex_t lock;
    int spawn_count;
    int state_count;
    int exit_count;
    int timeout_count;
    int last_pid;
    int last_exit;
    int last_timeout;
    char states[256];
    size_t state_length;
    pthread_t callback_thread;
    bool callback_thread_seen;
} EventLog;

static int64_t monotonic_millis(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void sleep_millis(int milliseconds) {
    struct timespec request = {
        .tv_sec = milliseconds / 1000,
        .tv_nsec = (long)(milliseconds % 1000) * 1000000L
    };
    while (nanosleep(&request, &request) != 0 && errno == EINTR) {}
}

static void event_callback(const char *event, int value, void *context) {
    EventLog *log = (EventLog *)context;
    pthread_mutex_lock(&log->lock);
    log->callback_thread = pthread_self();
    log->callback_thread_seen = true;
    if (strcmp(event, "spawn") == 0) {
        log->spawn_count++;
        log->last_pid = value;
    } else if (strcmp(event, "state") == 0) {
        log->state_count++;
        if (log->state_length + 1 < sizeof(log->states)) {
            log->states[log->state_length++] = (char)value;
            log->states[log->state_length] = '\0';
        }
    } else if (strcmp(event, "timeout") == 0) {
        log->timeout_count++;
        log->last_timeout = value;
    } else if (strcmp(event, "exit") == 0) {
        log->exit_count++;
        log->last_exit = value;
    }
    pthread_mutex_unlock(&log->lock);
}

static void event_log_init(EventLog *log) {
    memset(log, 0, sizeof(*log));
    (void)pthread_mutex_init(&log->lock, NULL);
}

static void event_log_destroy(EventLog *log) {
    (void)pthread_mutex_destroy(&log->lock);
}

static bool wait_for_exit(EventLog *log, int timeout_ms) {
    int64_t deadline = monotonic_millis() + timeout_ms;
    for (;;) {
        pthread_mutex_lock(&log->lock);
        bool done = log->exit_count > 0;
        pthread_mutex_unlock(&log->lock);
        if (done) return true;
        if (monotonic_millis() >= deadline) return false;
        sleep_millis(10);
    }
}

static int log_exit_count(EventLog *log) {
    pthread_mutex_lock(&log->lock);
    int value = log->exit_count;
    pthread_mutex_unlock(&log->lock);
    return value;
}

static bool wait_for_exit_count(EventLog *log, int expected, int timeout_ms) {
    int64_t deadline = monotonic_millis() + timeout_ms;
    for (;;) {
        if (log_exit_count(log) >= expected) return true;
        if (monotonic_millis() >= deadline) return false;
        sleep_millis(10);
    }
}

static bool has_state(EventLog *log, char state);

static bool wait_for_state(EventLog *log, char state, int timeout_ms) {
    int64_t deadline = monotonic_millis() + timeout_ms;
    for (;;) {
        if (has_state(log, state)) return true;
        if (monotonic_millis() >= deadline) return false;
        sleep_millis(10);
    }
}

static bool has_state(EventLog *log, char state) {
    pthread_mutex_lock(&log->lock);
    bool found = strchr(log->states, state) != NULL;
    pthread_mutex_unlock(&log->lock);
    return found;
}

static int log_exit(EventLog *log) {
    pthread_mutex_lock(&log->lock);
    int value = log->last_exit;
    pthread_mutex_unlock(&log->lock);
    return value;
}

static int log_timeout_count(EventLog *log) {
    pthread_mutex_lock(&log->lock);
    int value = log->timeout_count;
    pthread_mutex_unlock(&log->lock);
    return value;
}

static int log_spawn_count(EventLog *log) {
    pthread_mutex_lock(&log->lock);
    int value = log->spawn_count;
    pthread_mutex_unlock(&log->lock);
    return value;
}

static bool log_callback_on_other_thread(EventLog *log) {
    pthread_mutex_lock(&log->lock);
    bool value = log->callback_thread_seen && !pthread_equal(log->callback_thread, pthread_self());
    pthread_mutex_unlock(&log->lock);
    return value;
}

static int check(bool condition, const char *message) {
    if (condition) return 0;
    fprintf(stderr, "FAIL: %s\n", message);
    return 1;
}

static bool same_signal_mask(const sigset_t *left, const sigset_t *right) {
#ifdef NSIG
    for (int signal_number = 1; signal_number < NSIG; signal_number++) {
        int left_member = sigismember(left, signal_number);
        int right_member = sigismember(right, signal_number);
        if (left_member != right_member) return false;
    }
#else
    if (sigismember(left, SIGPIPE) != sigismember(right, SIGPIPE)) return false;
#endif
    return true;
}

static bool same_sigpipe_action(const struct sigaction *left,
                                const struct sigaction *right) {
    return left->sa_handler == right->sa_handler &&
           left->sa_flags == right->sa_flags &&
           same_signal_mask(&left->sa_mask, &right->sa_mask);
}

static int run_success(const char *exe) {
    EventLog log;
    event_log_init(&log);
    TCSession *session = TCSessionCreate(exe, "success", event_callback, &log);
    if (check(session != NULL, "create success session") != 0) return 1;
    if (check(TCSessionStart(session) == 0, "start success worker") != 0) {
        TCSessionDestroy(session); return 1;
    }
    int result = 0;
    result |= check(TCSessionStart(session) != 0, "reject duplicate start while active");
    result |= check(wait_for_exit(&log, 2000), "success worker exits");
    result |= check(log_exit(&log) == TC_WORKER_EXIT_SUCCESS, "success exit code");
    result |= check(log_spawn_count(&log) == 1, "spawn callback");
    result |= check(has_state(&log, 'E') && has_state(&log, 'F'), "editor and finish states");
    result |= check(log_timeout_count(&log) == 0, "success has no timeout");
    result |= check(log_callback_on_other_thread(&log), "callbacks run on monitor thread");
    result |= check(!TCSessionIsActive(session), "success is inactive after reap");
    TCSessionDestroy(session);
    event_log_destroy(&log);
    return result;
}

static int run_cancel(const char *exe) {
    EventLog log;
    event_log_init(&log);
    TCSession *session = TCSessionCreate(exe, "cancel", event_callback, &log);
    if (check(session != NULL, "create cancel session") != 0) return 1;
    int result = check(TCSessionStart(session) == 0, "start cancel worker");
    sleep_millis(120);
    TCSessionCancel(session);
    result |= check(wait_for_exit(&log, 2000), "cancel worker exits");
    result |= check(log_exit(&log) == TC_WORKER_EXIT_CANCELLED, "cancel exit code");
    result |= check(log_timeout_count(&log) == 0, "normal cancel has no forced timeout");
    result |= check(!TCSessionIsActive(session), "cancel is inactive after reap");
    TCSessionDestroy(session);
    event_log_destroy(&log);
    return result;
}

static int run_repeat(const char *exe) {
    EventLog log;
    event_log_init(&log);
    TCSession *session = TCSessionCreate(exe, "success", event_callback, &log);
    if (check(session != NULL, "create repeat session") != 0) return 1;
    int result = 0;
    for (int i = 0; i < 8; i++) {
        result |= check(TCSessionStart(session) == 0, "repeat start");
        result |= check(wait_for_exit_count(&log, i + 1, 2000), "repeat worker exits");
        result |= check(log_exit(&log) == 0, "repeat exit code");
    }
    result |= check(log_spawn_count(&log) == 8, "one spawn callback per repeat");
    result |= check(!TCSessionIsActive(session), "repeat session inactive");
    TCSessionDestroy(session);
    event_log_destroy(&log);
    return result;
}

static int run_exit_mode(const char *exe, const char *mode, int expected, const char *label) {
    EventLog log;
    event_log_init(&log);
    TCSession *session = TCSessionCreate(exe, mode, event_callback, &log);
    int result = check(session != NULL, label);
    if (!session) {
        event_log_destroy(&log);
        return result;
    }
    result |= check(TCSessionStart(session) == 0, "start terminal mode");
    result |= check(wait_for_exit(&log, 2000), "terminal worker exits");
    result |= check(log_exit(&log) == expected, label);
    result |= check(log_timeout_count(&log) == 0, "terminal mode has no timeout");
    TCSessionDestroy(session);
    event_log_destroy(&log);
    return result;
}

static int run_timeout(const char *exe, const char *mode, const char *label) {
    EventLog log;
    event_log_init(&log);
    TCSession *session = TCSessionCreate(exe, mode, event_callback, &log);
    int result = check(session != NULL, label);
    if (!session) {
        event_log_destroy(&log);
        return result;
    }
    result |= check(TCSessionStart(session) == 0, "start timeout worker");
    result |= check(wait_for_exit(&log, 3000), "timeout worker is killed and reaped");
    result |= check(log_timeout_count(&log) == 1, "one timeout callback");
    result |= check(!TCSessionIsActive(session), "timeout session inactive");
    TCSessionDestroy(session);
    event_log_destroy(&log);
    return result;
}

typedef struct {
    int write_fd;
} SpawnPipe;

static void write_spawn_pid(const char *event, int value, void *context) {
    if (strcmp(event, "spawn") != 0) return;
    SpawnPipe *pipe_context = (SpawnPipe *)context;
    ssize_t ignored;
    do {
        ignored = write(pipe_context->write_fd, &value, sizeof(value));
    } while (ignored < 0 && errno == EINTR);
}

static bool wait_until_gone(pid_t pid, int timeout_ms) {
    int64_t deadline = monotonic_millis() + timeout_ms;
    for (;;) {
        if (kill(pid, 0) != 0 && errno == ESRCH) return true;
        if (monotonic_millis() >= deadline) return false;
        sleep_millis(20);
    }
}

static int run_parent_death(const char *exe, bool crash) {
    int pid_pipe[2];
    if (pipe(pid_pipe) != 0) {
        fprintf(stderr, "FAIL: parent death pipe: %s\n", strerror(errno));
        return 1;
    }
    pid_t owner = fork();
    if (owner < 0) {
        close(pid_pipe[0]); close(pid_pipe[1]);
        fprintf(stderr, "FAIL: fork owner: %s\n", strerror(errno));
        return 1;
    }
    if (owner == 0) {
        close(pid_pipe[0]);
        SpawnPipe pipe_context = {.write_fd = pid_pipe[1]};
        TCSession *session = TCSessionCreate(exe, "parent", write_spawn_pid, &pipe_context);
        if (!session || TCSessionStart(session) != 0) _exit(2);
        sleep_millis(120);
        if (crash) raise(SIGKILL);
        _exit(0);
    }
    close(pid_pipe[1]);
    int worker_pid = 0;
    ssize_t bytes;
    do {
        bytes = read(pid_pipe[0], &worker_pid, sizeof(worker_pid));
    } while (bytes < 0 && errno == EINTR);
    close(pid_pipe[0]);
    int owner_status = 0;
    (void)waitpid(owner, &owner_status, 0);
    int result = check(bytes == (ssize_t)sizeof(worker_pid), "parent death spawn pid");
    if (result == 0) {
        result |= check(wait_until_gone((pid_t)worker_pid, 3000),
                         crash ? "worker exits after parent crash" : "worker exits after parent normal exit");
    }
    return result;
}

static int run_closed_reader_cancel_child(const char *exe) {
    /* Keep the legacy spawn path's target descriptors open so this focused
     * regression reaches TCSessionCancel even before the fixed spawn logic. */
    int sentinel_control = open("/dev/null", O_RDWR);
    int sentinel_status = open("/dev/null", O_RDWR);
    if (sentinel_control < 0 || sentinel_status < 0) _exit(2);
    if (sentinel_control != TC_WORKER_CONTROL_FD &&
        (dup2(sentinel_control, TC_WORKER_CONTROL_FD) < 0 || close(sentinel_control) != 0)) _exit(2);
    if (sentinel_status != TC_WORKER_STATUS_FD &&
        (dup2(sentinel_status, TC_WORKER_STATUS_FD) < 0 || close(sentinel_status) != 0)) _exit(2);

    struct sigaction sigpipe_before;
    struct sigaction sigpipe_after;
    sigset_t mask_before;
    sigset_t mask_after;
    if (sigaction(SIGPIPE, NULL, &sigpipe_before) != 0 ||
        pthread_sigmask(SIG_SETMASK, NULL, &mask_before) != 0) {
        _exit(2);
    }
    EventLog log;
    event_log_init(&log);
    TCSession *session = TCSessionCreate(exe, "reader-closed", event_callback, &log);
    if (!session || TCSessionStart(session) != 0) _exit(2);
    if (!wait_for_state(&log, 'E', 1000)) _exit(2);
    TCSessionCancel(session);
    bool exited = wait_for_exit(&log, 3000);
    int exit_value = log_exit(&log);
    int timeout_count = log_timeout_count(&log);
    bool signal_state_unchanged =
        sigaction(SIGPIPE, NULL, &sigpipe_after) == 0 &&
        pthread_sigmask(SIG_SETMASK, NULL, &mask_after) == 0 &&
        same_sigpipe_action(&sigpipe_before, &sigpipe_after) &&
        same_signal_mask(&mask_before, &mask_after);
    TCSessionDestroy(session);
    event_log_destroy(&log);
    _exit(exited && exit_value == 137 && timeout_count == 1 && signal_state_unchanged ? 0 : 3);
}

static int run_closed_reader_cancel(const char *exe) {
    pid_t child = fork();
    if (child < 0) {
        fprintf(stderr, "FAIL: fork SIGPIPE regression: %s\n", strerror(errno));
        return 1;
    }
    if (child == 0) run_closed_reader_cancel_child(exe);

    int status = 0;
    if (waitpid(child, &status, 0) < 0) {
        fprintf(stderr, "FAIL: wait SIGPIPE regression: %s\n", strerror(errno));
        return 1;
    }
    return check(WIFEXITED(status) && WEXITSTATUS(status) == 0,
                 "cancel survives closed worker reader");
}

static int run_fd_collision_child(const char *exe) {
    for (int target = 3; target <= TC_WORKER_CONTROL_FD; target++) {
        int filler = open("/dev/null", O_RDWR);
        if (filler < 0) _exit(2);
        if (filler != target) {
            if (dup2(filler, target) < 0 || close(filler) != 0) _exit(2);
        }
    }
    /* With 3..198 occupied, the first control pipe must use 199 as its read
     * end.  Leaving 199 free constructs the source=target collision. */
    close(TC_WORKER_STATUS_FD);
    int probe = open("/dev/null", O_RDWR);
    if (probe != TC_WORKER_STATUS_FD) _exit(2);
    close(probe);
    int result = run_success(exe);
    char marker = 'x';
    if (result == 0 && write(TC_WORKER_CONTROL_FD, &marker, 1) != 1) result = 4;
    _exit(result == 0 ? 0 : 3);
}

static int run_fd_collision(const char *exe) {
    pid_t child = fork();
    if (child < 0) {
        fprintf(stderr, "FAIL: fork FD collision regression: %s\n", strerror(errno));
        return 1;
    }
    if (child == 0) run_fd_collision_child(exe);

    int status = 0;
    if (waitpid(child, &status, 0) < 0) {
        fprintf(stderr, "FAIL: wait FD collision regression: %s\n", strerror(errno));
        return 1;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "fd-collision child: exited=%d code=%d signal=%d\\n",
                WIFEXITED(status) ? 1 : 0,
                WIFEXITED(status) ? WEXITSTATUS(status) : -1,
                WIFSIGNALED(status) ? WTERMSIG(status) : 0);
    }
    return check(WIFEXITED(status) && WEXITSTATUS(status) == 0,
                 "spawn survives fixed-FD source collision");
}

static int run_fd_sentinels_child(const char *exe) {
    int first = open("/dev/null", O_RDWR);
    int second = open("/dev/null", O_RDWR);
    if (first < 0 || second < 0) _exit(2);
    if (first != TC_WORKER_CONTROL_FD &&
        (dup2(first, TC_WORKER_CONTROL_FD) < 0 || close(first) != 0)) _exit(2);
    if (second != TC_WORKER_STATUS_FD &&
        (dup2(second, TC_WORKER_STATUS_FD) < 0 || close(second) != 0)) _exit(2);

    int result = run_success(exe);
    char marker = 'x';
    if (result == 0 && write(TC_WORKER_CONTROL_FD, &marker, 1) != 1) result = 3;
    if (result == 0 && write(TC_WORKER_STATUS_FD, &marker, 1) != 1) result = 4;
    _exit(result == 0 ? 0 : 5);
}

static int run_fd_sentinels(const char *exe) {
    pid_t child = fork();
    if (child < 0) {
        fprintf(stderr, "FAIL: fork FD sentinel regression: %s\n", strerror(errno));
        return 1;
    }
    if (child == 0) run_fd_sentinels_child(exe);

    int status = 0;
    if (waitpid(child, &status, 0) < 0) {
        fprintf(stderr, "FAIL: wait FD sentinel regression: %s\n", strerror(errno));
        return 1;
    }
    return check(WIFEXITED(status) && WEXITSTATUS(status) == 0,
                 "spawn preserves non-pipe fixed-FD sentinels");
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "--fake-worker") == 0) {
        if (argc > 2 && strcmp(argv[2], "reader-closed") == 0) {
            pid_t owner = getppid();
            TCWorkerPulse('E');
            close(TC_WORKER_CONTROL_FD);
            for (;;) {
                if (getppid() != owner) _exit(0);
                sleep_millis(20);
            }
        }
        return TCSessionRunFakeWorker(argc > 2 ? argv[2] : "success");
    }
    if (argc > 1 && strcmp(argv[1], "--capture-worker") == 0) {
        if (TCWorkerGuardStart() != 0) return TC_WORKER_EXIT_GUARD_FAILURE;
        for (;;) {
            TCWorkerPulse('P');
            sleep_millis(250);
        }
    }

    if (argc < 1) return 2;
    const char *exe = argv[0];
    if (argc > 1 && strcmp(argv[1], "--regression-closed-reader") == 0) {
        return run_closed_reader_cancel(exe);
    }
    if (argc > 1 && strcmp(argv[1], "--regression-fd-collision") == 0) {
        return run_fd_collision(exe);
    }
    int failures = 0;
    failures += run_success(exe);
    failures += run_cancel(exe);
    failures += run_repeat(exe);
    failures += run_exit_mode(exe, "crash", TC_WORKER_EXIT_EXCEPTION, "crash exit code");
    failures += run_exit_mode(exe, "signal-crash", 128 + SIGABRT, "signal crash exit code");
    failures += run_timeout(exe, "hang", "hung main watchdog");
    failures += run_timeout(exe, "stop", "SIGSTOP watchdog");
    failures += run_exit_mode(exe, "no_permission", TC_WORKER_EXIT_NO_PERMISSION, "no permission");
    failures += run_exit_mode(exe, "capture_failure", TC_WORKER_EXIT_CAPTURE_FAILURE, "capture failure");
    failures += run_exit_mode(exe, "healthy-edit", TC_WORKER_EXIT_SUCCESS, "healthy editor heartbeat");
    failures += run_exit_mode(exe, "healthy-save", TC_WORKER_EXIT_SAVE_SUCCESS, "healthy save heartbeat");
    failures += run_exit_mode(exe, "healthy-ocr", TC_WORKER_EXIT_OCR_SUCCESS, "healthy OCR heartbeat");
    failures += run_exit_mode(exe, "healthy-long", TC_WORKER_EXIT_SUCCESS, "healthy long heartbeat");
    failures += run_exit_mode(exe, "healthy-analysis", TC_WORKER_EXIT_CODE_SUCCESS, "healthy analysis heartbeat");
    failures += run_exit_mode(exe, "healthy-mosaic", TC_WORKER_EXIT_SUCCESS, "healthy in-editor mosaic heartbeat");
    failures += run_exit_mode(exe, "healthy-translation", TC_WORKER_EXIT_CODE_SUCCESS, "healthy translation heartbeat");
    failures += run_parent_death(exe, false);
    failures += run_parent_death(exe, true);
    failures += run_closed_reader_cancel(exe);
    failures += run_fd_collision(exe);
    failures += run_fd_sentinels(exe);
    if (failures == 0) {
        puts("PASS session lifecycle: success/cancel/repeat/crash/signal-crash/hang/SIGSTOP/parent death/permission/capture failure/healthy E-S-O-L-A-M-T/closed-reader/FD collision/sentinels");
        return 0;
    }
    fprintf(stderr, "%d session lifecycle checks failed\n", failures);
    return 1;
}

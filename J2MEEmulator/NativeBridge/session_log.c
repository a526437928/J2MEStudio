/* Preserve miniJVM signal handling; capture its own diagnostics per session. */
#include "session_log.h"
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <pthread.h>
#include <errno.h>

static pthread_mutex_t log_lock = PTHREAD_MUTEX_INITIALIZER;
static int saved_out = -1, saved_error = -1;

void studio_log_flush(void) { fflush(stdout); fflush(stderr); }

int studio_log_begin(const char *path) {
    if (pthread_mutex_trylock(&log_lock)) return EBUSY;
    fflush(stdout); fflush(stderr);
    int file = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (file < 0) { int result = errno; pthread_mutex_unlock(&log_lock); return result; }
    saved_out = dup(STDOUT_FILENO); saved_error = dup(STDERR_FILENO);
    if (saved_out < 0 || saved_error < 0 || dup2(file, STDOUT_FILENO) < 0 || dup2(file, STDERR_FILENO) < 0) {
        int result = errno;
        if (saved_out >= 0) { dup2(saved_out, STDOUT_FILENO); close(saved_out); }
        if (saved_error >= 0) { dup2(saved_error, STDERR_FILENO); close(saved_error); }
        saved_out = saved_error = -1; close(file); pthread_mutex_unlock(&log_lock); return result;
    }
    close(file);
    return 0;
}

void studio_log_end(void) {
    if (saved_out < 0) return;
    fflush(stdout); fflush(stderr);
    dup2(saved_out, STDOUT_FILENO); dup2(saved_error, STDERR_FILENO);
    close(saved_out); close(saved_error); saved_out = saved_error = -1;
    pthread_mutex_unlock(&log_lock);
}

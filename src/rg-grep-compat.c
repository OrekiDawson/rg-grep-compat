// rg-grep-compat: GNU grep compatible dispatcher, optionally using ripgrep.
// Copyright (c) 2026 Contributors. MIT license.
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif
#ifndef O_NOFOLLOW
#define O_NOFOLLOW 0
#endif

#define MAX_FAST_FILE (4 * 1024 * 1024)

struct query {
    const char *pattern;
    const char *file;
    bool fixed;
    bool extended;
    bool quiet;
};

static bool trace_enabled(void) {
    const char *x = getenv("RG_GREP_TRACE");
    return x && strcmp(x, "0") != 0 && *x;
}

static void trace_backend(const char *why) {
    if (trace_enabled()) fprintf(stderr, "[rg-grep-compat] %s\n", why);
}

static bool same_inode(const struct stat *a, const struct stat *b) {
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino;
}

// The authoritative fallback is a fixed absolute executable, never PATH=grep.
// This prevents recursion when the dispatcher itself is named "grep".
static const char *gnu_grep_path(void) {
    const char *override = getenv("RG_GREP_GNU_PATH");
    const char *candidates[] = {override, "/usr/bin/grep", "/bin/grep", NULL};
    struct stat self;
    bool know_self = stat("/proc/self/exe", &self) == 0;
    for (size_t i = 0; i < 3; i++) {
        const char *p = candidates[i];
        if (!p || p[0] != '/' || access(p, X_OK) != 0) continue;
        struct stat target;
        if (stat(p, &target) != 0 || !S_ISREG(target.st_mode)) continue;
        if (know_self && same_inode(&self, &target)) continue;
        return p;
    }
    return NULL;
}

static int exec_gnu(const char *reason, int argc, char **argv) {
    const char *gnu = gnu_grep_path();
    if (!gnu) {
        fprintf(stderr, "rg-grep-compat: GNU grep not found; expected /usr/bin/grep or /bin/grep\n");
        return 127;
    }
    trace_backend(reason);
    char **args = calloc((size_t)argc + 1u, sizeof(*args));
    if (!args) {
        perror("rg-grep-compat: calloc");
        return 127;
    }
    args[0] = "grep";
    for (int i = 1; i < argc; i++) args[i] = argv[i];
    execv(gnu, args);
    int saved_errno = errno;
    fprintf(stderr, "rg-grep-compat: cannot exec %s: %s\n", gnu, strerror(saved_errno));
    free(args);
    return 127;
}

// Only a conservative subset is recognized. Anything else is *not* reinterpreted;
// it is forwarded to the authoritative GNU grep binary as-is.
static bool parse_safe_query(int argc, char **argv, struct query *q) {
    memset(q, 0, sizeof(*q));
    bool end_options = false;
    bool pattern_option = false;

    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (!end_options && strcmp(arg, "--") == 0) {
            end_options = true;
            continue;
        }
        if (!end_options && strcmp(arg, "--quiet") == 0) { q->quiet = true; continue; }
        if (!end_options && strcmp(arg, "--fixed-strings") == 0) { q->fixed = true; continue; }
        if (!end_options && strcmp(arg, "--extended-regexp") == 0) { q->extended = true; continue; }
        if (!end_options && strcmp(arg, "--regexp") == 0) {
            if (pattern_option || ++i >= argc) return false;
            q->pattern = argv[i];
            pattern_option = true;
            continue;
        }
        if (!end_options && strncmp(arg, "--regexp=", 9) == 0) {
            if (pattern_option) return false;
            q->pattern = arg + 9;
            pattern_option = true;
            continue;
        }
        if (!end_options && arg[0] == '-' && arg[1] != '\0') {
            for (const char *c = arg + 1; *c; c++) {
                if (*c == 'q') q->quiet = true;
                else if (*c == 'F') q->fixed = true;
                else if (*c == 'E') q->extended = true;
                else if (*c == 'e') {
                    if (pattern_option) return false;
                    if (c[1]) q->pattern = c + 1;
                    else {
                        if (++i >= argc) return false;
                        q->pattern = argv[i];
                    }
                    pattern_option = true;
                    break;
                } else return false;
            }
            continue;
        }
        if (q->pattern == NULL && !pattern_option) q->pattern = arg;
        else if (q->file == NULL) q->file = arg;
        else return false;
    }
    if (!q->quiet || q->pattern == NULL || q->file == NULL) return false;
    if (q->fixed && q->extended) return false; // GNU's last-option-wins; refuse ambiguity.
    if (strcmp(q->file, "-") == 0) return false;
    return true;
}

static bool safe_pattern(const struct query *q) {
    // ASCII-only makes the fast path independent of Unicode/locale semantics.
    const unsigned char *p = (const unsigned char *)q->pattern;
    for (; *p; p++) {
        if (*p < 32 || *p > 126) return false;
        if (!q->fixed && strchr(".[](){}*+?^$|\\", (int)*p) != NULL) return false;
    }
    return true;
}

static bool safe_regular_ascii_file(const char *path) {
    struct stat before;
    // No symlinks, devices, sockets, pipes or implicit recursion in the rg fast path.
    if (lstat(path, &before) != 0 || !S_ISREG(before.st_mode)) return false;
    if (before.st_size < 0 || before.st_size > MAX_FAST_FILE) return false;
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return false;
    struct stat actual;
    bool ok = (fstat(fd, &actual) == 0 && S_ISREG(actual.st_mode) &&
               same_inode(&before, &actual) && actual.st_size == before.st_size);
    unsigned char buffer[16384];
    off_t consumed = 0;
    while (ok) {
        ssize_t n = read(fd, buffer, sizeof(buffer));
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { ok = false; break; }
        if (n == 0) break;
        consumed += n;
        for (ssize_t i = 0; i < n; i++) {
            if (buffer[i] == 0 || buffer[i] >= 128) { ok = false; break; }
        }
    }
    if (ok && consumed != before.st_size) ok = false;
    if (ok) {
        struct stat after;
        ok = fstat(fd, &after) == 0 && same_inode(&before, &after) &&
             after.st_size == before.st_size &&
             after.st_mtim.tv_sec == before.st_mtim.tv_sec &&
             after.st_mtim.tv_nsec == before.st_mtim.tv_nsec;
    }
    close(fd);
    return ok;
}

static const char *ripgrep_path(void) {
    const char *override = getenv("RG_GREP_RG_PATH");
    if (override && override[0] == '/' && access(override, X_OK) == 0) return override;
    if (access("/usr/bin/rg", X_OK) == 0) return "/usr/bin/rg";
    if (access("/bin/rg", X_OK) == 0) return "/bin/rg";
    return NULL;
}

static int run_rg(const struct query *q) {
    const char *rg = ripgrep_path();
    if (!rg) return 2;
    char *args[] = {
        (char *)"rg", (char *)"--no-config", (char *)"--no-ignore",
        (char *)"--hidden", (char *)"--text", (char *)"-F", (char *)"-q",
        (char *)"-e", (char *)q->pattern, (char *)"--", (char *)q->file, NULL
    };
    pid_t pid = fork();
    if (pid < 0) return 2;
    if (pid == 0) {
        execv(rg, args);
        _exit(127);
    }
    int status;
    for (;;) {
        if (waitpid(pid, &status, 0) >= 0) break;
        if (errno == EINTR) continue;
        return 2;
    }
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) {
        int sig = WTERMSIG(status);
        signal(sig, SIG_DFL);
        raise(sig);
        return 128 + sig;
    }
    return 2;
}

int main(int argc, char **argv) {
    const char *mode = getenv("RG_GREP_MODE");
    if (!mode || !*mode || strcmp(mode, "strict") == 0) {
        return exec_gnu("GNU grep (strict mode)", argc, argv);
    }
    if (strcmp(mode, "fast") != 0 && strcmp(mode, "audit") != 0) {
        return exec_gnu("GNU grep (unknown mode)", argc, argv);
    }
    struct query q;
    if (!parse_safe_query(argc, argv, &q) || !safe_pattern(&q) ||
        !safe_regular_ascii_file(q.file) || !ripgrep_path()) {
        return exec_gnu("GNU grep (unsupported/unsafe request)", argc, argv);
    }
    trace_backend("ripgrep (safe fixed-literal quiet fast path)");
    int result = run_rg(&q);
    if (strcmp(mode, "audit") == 0) {
        if (trace_enabled()) fprintf(stderr, "[rg-grep-compat] audit: rg exit=%d, GNU result is authoritative\n", result);
        return exec_gnu("GNU grep (audit comparison)", argc, argv);
    }
    if (result == 0 || result == 1) return result;
    return exec_gnu("GNU grep (ripgrep failed)", argc, argv);
}

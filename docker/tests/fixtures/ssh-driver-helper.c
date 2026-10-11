#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/sched.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static int send_message(const char *path, const char *body) {
    struct sockaddr_un address = {0};
    int descriptor = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (descriptor < 0 || strlen(path) >= sizeof(address.sun_path)) {
        if (descriptor >= 0) close(descriptor);
        return -1;
    }
    address.sun_family = AF_UNIX;
    strcpy(address.sun_path, path);
    ssize_t sent = sendto(descriptor, body, strlen(body), 0,
                          (struct sockaddr *)&address, sizeof(address));
    int saved = errno;
    close(descriptor);
    errno = saved;
    return sent == (ssize_t)strlen(body) ? 0 : -1;
}

static void *waiting_thread(void *unused) {
    (void)unused;
    for (;;) pause();
    return NULL;
}

static int clone_child(void *marker) {
    int descriptor = open((const char *)marker, O_CREAT | O_WRONLY | O_CLOEXEC, 0600);
    if (descriptor >= 0) close(descriptor);
    return 0;
}

static int create_clone(int flags, const char *marker) {
    void *stack = malloc(65536);
    if (!stack) return -1;
    int child = clone(clone_child, (char *)stack + 65536, flags, (void *)marker);
    if (child < 0) return -1;
    int status;
    if (waitpid(child, &status, 0) != child) return -1;
    free(stack);
    return WIFEXITED(status) ? 0 : -1;
}

static int baseline_shared_clone(const char *marker) {
    pid_t worker = fork();
    if (worker < 0) return 104;
    if (worker == 0) {
        if (setpgid(0, 0) || ptrace(PTRACE_TRACEME, 0, NULL, NULL)) _exit(105);
        raise(SIGSTOP);
        _exit(create_clone(CLONE_VM | SIGCHLD, marker) ? 106 : 0);
    }
    int status;
    unsigned long child = 0;
    if (waitpid(worker, &status, 0) != worker || !WIFSTOPPED(status)) return 107;
    if (ptrace(PTRACE_SETOPTIONS, worker, NULL, PTRACE_O_TRACEFORK | PTRACE_O_EXITKILL) ||
        ptrace(PTRACE_CONT, worker, NULL, NULL)) return 108;
    if (waitpid(worker, &status, 0) != worker || (unsigned int)status >> 16 != PTRACE_EVENT_FORK ||
        ptrace(PTRACE_GETEVENTMSG, worker, NULL, &child) || !child) return 109;
    printf("{\"event\":1,\"status\":%d,\"flags\":%d,\"parent\":%d,\"child\":%lu}\n",
           status, CLONE_VM | SIGCHLD, worker, child);
    fflush(stdout);
    kill(-worker, SIGKILL);
    pid_t waited;
    while ((waited = waitpid(-worker, &status, __WALL)) > 0) {
        if (WIFSTOPPED(status)) ptrace(PTRACE_CONT, waited, NULL, SIGKILL);
    }
    return errno == ECHILD ? 0 : 110;
}

int main(int argc, char **argv) {
    if (argc == 3 && (strcmp(argv[1], "setpgid") == 0 || strcmp(argv[1], "setsid") == 0)) {
        long nr = strcmp(argv[1], "setpgid") == 0 ? SYS_setpgid : SYS_setsid;
        pid_t before_group = getpgrp(), before_session = getsid(0);
        long result = syscall(nr, 0L, 0L, 0L, 0L, 0L, 0L);
        if (result < 0) return 114;
        printf("{\"nr\":%ld,\"pid\":%d,\"before_group\":%d,\"before_session\":%d,"
               "\"after_group\":%d,\"after_session\":%d,\"result\":%ld}\n",
               nr, getpid(), before_group, before_session, getpgrp(), getsid(0), result);
        fflush(stdout);
        return clone_child(argv[2]);
    }
#if defined(__x86_64__)
    if (argc == 3 && strcmp(argv[1], "x32") == 0) {
        (void)syscall(0x40000000L | SYS_getpid);
        return clone_child(argv[2]);
    }
    if (argc == 3 && strcmp(argv[1], "i386") == 0) {
        long result;
        __asm__ volatile("int $0x80" : "=a"(result) : "a"(20L) : "memory");
        (void)result;
        return clone_child(argv[2]);
    }
#endif
    if (argc == 3 && strcmp(argv[1], "baseline-shared-clone") == 0) {
        return baseline_shared_clone(argv[2]);
    }
    if (argc == 3 && (strcmp(argv[1], "shared-clone") == 0 ||
                      strcmp(argv[1], "untraced-clone") == 0)) {
        int flags = SIGCHLD | (strcmp(argv[1], "shared-clone") == 0 ? CLONE_VM : CLONE_UNTRACED);
        return create_clone(flags, argv[2]) ? 99 : 0;
    }
    if (argc == 3 && strcmp(argv[1], "clone3") == 0) {
        struct clone_args args = {0};
        args.exit_signal = SIGCHLD;
        long child = syscall(SYS_clone3, &args, sizeof(args));
        if (child == 0) _exit(clone_child(argv[2]));
        if (child < 0) return 102;
        int status;
        return waitpid((int)child, &status, 0) == child ? 0 : 103;
    }
    if (argc == 2 && strcmp(argv[1], "clone") == 0) {
        pthread_t thread;
        if (pthread_create(&thread, NULL, waiting_thread, NULL) != 0) return 91;
        pthread_join(thread, NULL);
        return 92;
    }
    if (argc != 4 || strcmp(argv[1], "cross-exec") != 0) return 93;
    char *end = NULL;
    errno = 0;
    long descriptor = strtol(argv[3], &end, 10);
    if (errno || end == argv[3] || *end || descriptor < 0 || descriptor > INT_MAX) return 94;
    if (send_message(argv[2], "new-epoch-one") != 0) return 95;
    if (close((int)descriptor) != 0) return 96;
    if (send_message(argv[2], "closed-accepted-fd") != 0) return 97;
    return 23;
}

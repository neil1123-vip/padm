#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
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

int main(int argc, char **argv) {
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

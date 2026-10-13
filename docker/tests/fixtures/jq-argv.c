#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

int main(int argc, char **argv) {
    const char *log = getenv("FAKE_SETUP_ARGV_LOG");
    const char *jq = getenv("FAKE_SETUP_REAL_JQ");
    if (!log || !*log || !jq || !*jq) {
        fputs("jq argv fixture requires its log and real executable\n", stderr);
        return 99;
    }
    size_t length = 3;
    for (int index = 1; index < argc; ++index) {
        length += strlen(argv[index]) + 1;
    }
    char *record = malloc(length);
    if (!record) {
        perror("jq argv fixture allocation");
        return 99;
    }
    memcpy(record, "jq", 3);
    size_t offset = 3;
    for (int index = 1; index < argc; ++index) {
        size_t size = strlen(argv[index]) + 1;
        memcpy(record + offset, argv[index], size);
        offset += size;
    }
    int descriptor = open(log, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (descriptor < 0) {
        perror("jq argv fixture log");
        free(record);
        return 99;
    }
    int status;
    do {
        status = flock(descriptor, LOCK_EX);
    } while (status != 0 && errno == EINTR);
    if (status != 0) {
        perror("jq argv fixture lock");
        free(record);
        close(descriptor);
        return 99;
    }
    offset = 0;
    while (offset < length) {
        ssize_t count = write(descriptor, record + offset, length - offset);
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            perror("jq argv fixture write");
            free(record);
            close(descriptor);
            return 99;
        }
        offset += (size_t)count;
    }
    free(record);
    if (close(descriptor) != 0) {
        perror("jq argv fixture close");
        return 99;
    }
    argv[0] = (char *)jq;
    execv(jq, argv);
    perror("jq argv fixture exec");
    return 127;
}

#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <stdint.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

static FILE *source;
static const char *environment_names[] = {
    "PYTHONHOME", "PYTHONPATH", "PYTHONHASHSEED", "PYTHONUTF8", "PYTHONIOENCODING",
    "PYTHONNOUSERSITE", "PYTHONSAFEPATH", "PYTHONWARNINGS", "PYTHONDONTWRITEBYTECODE",
    "PYTHONOPTIMIZE", "PYTHONINSPECT", "PYTHONVERBOSE", "PYTHONDEVMODE",
    "PYTHONPROFILEIMPORTTIME", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ"
};

static void fallback(char **argv) {
    if (fflush(source) || fseek(source, 0, SEEK_SET) ||
        dup2(fileno(source), STDIN_FILENO) < 0) {
        perror("snapshot fallback stdin");
        exit(98);
    }
    fclose(source);
    argv[0] = "python3";
    execv("/usr/bin/python3", argv);
    perror("snapshot fallback python3");
    exit(98);
}

static int transfer(int fd, void *data, size_t size, int writing) {
    char *cursor = data;
    while (size) {
        ssize_t count = writing ? write(fd, cursor, size) : read(fd, cursor, size);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return -1;
        cursor += count;
        size -= (size_t)count;
    }
    return 0;
}

static int send_data(int fd, const void *data, size_t size) {
    uint32_t length = htonl((uint32_t)size);
    return transfer(fd, &length, sizeof(length), 1) ||
        transfer(fd, (void *)data, size, 1);
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    source = tmpfile();
    if (!source) {
        perror("snapshot stdin");
        return 98;
    }
    char body[65536], buffer[8192];
    size_t size = 0, count;
    int oversized = 0;
    while ((count = fread(buffer, 1, sizeof(buffer), stdin)) != 0) {
        if (fwrite(buffer, 1, count, source) != count) return 98;
        if (count > sizeof(body) - size) oversized = 1;
        if (!oversized) {
            memcpy(body + size, buffer, count);
            size += count;
        }
    }
    if (ferror(stdin)) return 98;
    const char *path = getenv("PADM_SNAPSHOT_FORK_SOCKET");
    if (oversized || !path || argc != 8 || strcmp(argv[1], "-")) fallback(argv);
    int connection = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (connection < 0) fallback(argv);
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    struct timeval timeout = {.tv_sec = 5};
    if (strlen(path) >= sizeof(address.sun_path)) fallback(argv);
    strcpy(address.sun_path, path);
    if (setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) ||
        setsockopt(connection, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) ||
        connect(connection, (struct sockaddr *)&address, sizeof(address))) fallback(argv);
    uint32_t arguments = htonl((uint32_t)(argc - 1));
    if (transfer(connection, &arguments, sizeof(arguments), 1)) fallback(argv);
    for (int index = 1; index < argc; ++index) {
        if (send_data(connection, argv[index], strlen(argv[index]))) fallback(argv);
    }
    char *directory = getcwd(NULL, 0);
    if (!directory || send_data(connection, directory, strlen(directory))) fallback(argv);
    free(directory);
    for (int index = 0; index < 2; ++index) {
        struct sigaction disposition;
        if (sigaction(index ? SIGTERM : SIGINT, NULL, &disposition)) fallback(argv);
        char ignored = disposition.sa_handler == SIG_IGN ? '1' : '0';
        if (send_data(connection, &ignored, 1)) fallback(argv);
    }
    for (size_t index = 0; index < sizeof(environment_names) / sizeof(environment_names[0]); ++index) {
        const char *value = getenv(environment_names[index]);
        char present = value ? '1' : '0';
        if (send_data(connection, &present, 1) ||
            send_data(connection, value ? value : "", value ? strlen(value) : 0)) fallback(argv);
    }
    if (send_data(connection, body, size)) fallback(argv);
    uint32_t response[3];
    if (transfer(connection, response, sizeof(response), 0)) fallback(argv);
    for (int index = 0; index < 3; ++index) response[index] = ntohl(response[index]);
    if (response[0] > 255 || response[1] > 16777216 || response[2] > 16777216) fallback(argv);
    size_t total = (size_t)response[1] + response[2];
    char *output = malloc(total ? total : 1);
    if (!output || transfer(connection, output, total, 0)) fallback(argv);
    close(connection);
    /* 完整响应收到后再输出，通信失败回退不能重复输出半个快照。 */
    if (transfer(STDOUT_FILENO, output, response[1], 1) ||
        transfer(STDERR_FILENO, output + response[1], response[2], 1)) {
        free(output);
        return 98;
    }
    free(output);
    fclose(source);
    return (int)response[0];
}

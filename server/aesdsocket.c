#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <syslog.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

#define PORT "9000"
#define DATAFILE "/var/tmp/aesdsocketdata"
#define BACKLOG 10
#define BUFSIZE 1024

static int server_fd = -1;
static int client_fd = -1;
static volatile sig_atomic_t caught_signal = 0;

static void signal_handler(int sig) {
    caught_signal = sig;
}

static void setup_signals(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
}

static void cleanup(void) {
    if (client_fd != -1) {
        close(client_fd);
        client_fd = -1;
    }
    if (server_fd != -1) {
        close(server_fd);
        server_fd = -1;
    }
    unlink(DATAFILE);
    closelog();
}

static int setup_server_socket(void) {
    struct addrinfo hints, *res, *p;
    int yes = 1;
    int fd = -1;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags    = AI_PASSIVE;

    if (getaddrinfo(NULL, PORT, &hints, &res) != 0) {
        syslog(LOG_ERR, "getaddrinfo: %s", strerror(errno));
        return -1;
    }

    for (p = res; p != NULL; p = p->ai_next) {
        fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (fd == -1) continue;

        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

        if (bind(fd, p->ai_addr, p->ai_addrlen) == 0) break;

        close(fd);
        fd = -1;
    }

    freeaddrinfo(res);

    if (fd == -1) {
        syslog(LOG_ERR, "bind failed: %s", strerror(errno));
        return -1;
    }

    if (listen(fd, BACKLOG) == -1) {
        syslog(LOG_ERR, "listen: %s", strerror(errno));
        close(fd);
        return -1;
    }

    return fd;
}

static void daemonize(void) {
    pid_t pid = fork();
    if (pid < 0) {
        syslog(LOG_ERR, "fork failed: %s", strerror(errno));
        exit(EXIT_FAILURE);
    }
    if (pid > 0) {
        exit(EXIT_SUCCESS); /* parent exits */
    }

    if (setsid() == -1) {
        syslog(LOG_ERR, "setsid failed: %s", strerror(errno));
        exit(EXIT_FAILURE);
    }

    /* Redirect stdin/stdout/stderr to /dev/null */
    int devnull = open("/dev/null", O_RDWR);
    if (devnull != -1) {
        dup2(devnull, STDIN_FILENO);
        dup2(devnull, STDOUT_FILENO);
        dup2(devnull, STDERR_FILENO);
        if (devnull > 2) close(devnull);
    }

    chdir("/");
}

static void handle_client(int cfd, const char *client_ip) {
    char buf[BUFSIZE];
    char *packet = NULL;
    size_t packet_len = 0;
    ssize_t nbytes;

    /* Receive data until newline found */
    while ((nbytes = recv(cfd, buf, sizeof(buf), 0)) > 0) {
        char *new_packet = realloc(packet, packet_len + nbytes + 1);
        if (!new_packet) {
            syslog(LOG_ERR, "realloc failed: %s", strerror(errno));
            free(packet);
            return;
        }
        packet = new_packet;
        memcpy(packet + packet_len, buf, nbytes);
        packet_len += nbytes;
        packet[packet_len] = '\0';

        /* Process all complete packets (newline-terminated) */
        char *start = packet;
        char *nl;
        while ((nl = memchr(start, '\n', packet_len - (start - packet))) != NULL) {
            size_t line_len = nl - start + 1;

            /* Append to data file */
            int dfd = open(DATAFILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
            if (dfd == -1) {
                syslog(LOG_ERR, "open %s: %s", DATAFILE, strerror(errno));
                start = nl + 1;
                continue;
            }
            if (write(dfd, start, line_len) == -1) {
                syslog(LOG_ERR, "write: %s", strerror(errno));
            }
            close(dfd);

            /* Send entire file contents back to client */
            dfd = open(DATAFILE, O_RDONLY);
            if (dfd != -1) {
                ssize_t r;
                char fbuf[BUFSIZE];
                while ((r = read(dfd, fbuf, sizeof(fbuf))) > 0) {
                    send(cfd, fbuf, r, 0);
                }
                close(dfd);
            }

            start = nl + 1;
        }

        /* Keep leftover (partial packet) */
        size_t remaining = packet_len - (start - packet);
        if (remaining > 0 && start != packet) {
            memmove(packet, start, remaining);
        }
        packet_len = remaining;
    }

    free(packet);
    syslog(LOG_INFO, "Closed connection from %s", client_ip);
}

int main(int argc, char *argv[]) {
    int daemon_mode = 0;

    openlog("aesdsocket", LOG_PID, LOG_USER);
    setup_signals();

    /* Parse arguments */
    int opt;
    while ((opt = getopt(argc, argv, "d")) != -1) {
        if (opt == 'd') daemon_mode = 1;
    }

    /* Setup server socket before daemonizing so we can detect bind errors */
    server_fd = setup_server_socket();
    if (server_fd == -1) {
        closelog();
        return -1;
    }

    if (daemon_mode) {
        daemonize();
    }

    /* Main accept loop */
    while (!caught_signal) {
        struct sockaddr_storage client_addr;
        socklen_t addr_len = sizeof(client_addr);

        client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &addr_len);
        if (client_fd == -1) {
            if (caught_signal) break;
            if (errno == EINTR) continue;
            syslog(LOG_ERR, "accept: %s", strerror(errno));
            continue;
        }

        /* Get client IP */
        char client_ip[INET6_ADDRSTRLEN];
        if (client_addr.ss_family == AF_INET) {
            struct sockaddr_in *s = (struct sockaddr_in *)&client_addr;
            inet_ntop(AF_INET, &s->sin_addr, client_ip, sizeof(client_ip));
        } else {
            struct sockaddr_in6 *s = (struct sockaddr_in6 *)&client_addr;
            inet_ntop(AF_INET6, &s->sin6_addr, client_ip, sizeof(client_ip));
        }

        syslog(LOG_INFO, "Accepted connection from %s", client_ip);

        handle_client(client_fd, client_ip);

        close(client_fd);
        client_fd = -1;
    }

    if (caught_signal) {
        syslog(LOG_INFO, "Caught signal, exiting");
    }

    cleanup();
    return 0;
}

#include "linux_so_memfd.h"
#if __linux__
#define _GNU_SOURCE
#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>

int ngx_helper_create_memfd_for_so(void* content, uint32_t content_len, const char* dummy_path, char* out_path) {
    int fd = memfd_create(dummy_path, 0);
    if (fd < 0) {
        return -errno;
    }
    while (content_len) {
        int n = write(fd, content, content_len);
        if (n < 0) {
            close(fd);
            return -errno;
        }
        content_len -= n;
        content += n;
    }
    sprintf(out_path, "/proc/%d/fd/%d", getpid(), fd);
    return fd;
}
#else
int ngx_helper_create_memfd_for_so(void* content, uint32_t content_len, const char* dummy_path, char* out_path) {
    return -1;
}
#endif // __linux__

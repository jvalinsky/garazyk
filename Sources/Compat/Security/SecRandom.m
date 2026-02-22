#if !defined(__APPLE__)

#import "SecRandom.h"
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

uint32_t arc4random(void) {
    uint32_t value = 0;
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd >= 0) {
        read(fd, &value, sizeof(value));
        close(fd);
    }
    return value;
}

uint32_t arc4random_uniform(uint32_t upper_bound) {
    if (upper_bound == 0) return 0;
    return arc4random() % upper_bound;
}

void arc4random_buf(void *buf, size_t nbytes) {
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd >= 0) {
        read(fd, buf, nbytes);
        close(fd);
    } else {
        memset(buf, 0, nbytes);
    }
}

int SecRandomCopyBytes(int *drbg, size_t count, void *bytes) {
    (void)drbg;
    arc4random_buf(bytes, count);
    return 0; // errSecSuccess
}

#endif

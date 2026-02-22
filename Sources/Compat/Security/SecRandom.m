/**
 * @file SecRandom.m
 * @brief SecRandomCopyBytes implementation for Linux
 *
 * Provides arc4random_buf and arc4random_uniform implementations
 * for Linux platforms without BSD/macOS functions.
 */

#import "SecRandom.h"
#include <fcntl.h>
#include <unistd.h>

#if !defined(__APPLE__)

// arc4random implementation
uint32_t arc4random(void) {
    uint32_t value;
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd >= 0) {
        read(fd, &value, sizeof(value));
        close(fd);
    }
    return value;
}

// arc4random_uniform implementation
uint32_t arc4random_uniform(uint32_t upper_bound) {
    uint32_t value;
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd >= 0) {
        read(fd, &value, sizeof(value));
        close(fd);
    }
    // Scale to [0, upper_bound) avoiding modulo bias
    return value % upper_bound;
}

#endif

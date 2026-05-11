// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#if !defined(__APPLE__)

#import "SecRandom.h"
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/syscall.h>

// Linux >= 3.17 has getrandom(2); older systems use /dev/urandom fallback
#ifdef SYS_getrandom
#define HAS_GETRANDOM 1
#else
#define HAS_GETRANDOM 0
#endif

// Internal random byte function using getrandom(2) or /dev/urandom
static void _arc4random_buf_impl(void *buf, size_t nbytes) {
    if (nbytes == 0) return;

#if HAS_GETRANDOM
    // Try getrandom(2) first (available on Linux 3.17+)
    while (nbytes > 0) {
        ssize_t result = syscall(SYS_getrandom, buf, nbytes, 0);
        if (result > 0) {
            buf = (char *)buf + result;
            nbytes -= result;
        } else if (errno == EINTR) {
            // Retry on interrupt
            continue;
        } else {
            // getrandom failed, fall back to /dev/urandom
            break;
        }
    }
    if (nbytes == 0) return;
#endif

    // Fallback to /dev/urandom
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) {
        memset(buf, 0, nbytes);
        return;
    }

    while (nbytes > 0) {
        ssize_t result = read(fd, buf, nbytes);
        if (result > 0) {
            buf = (char *)buf + result;
            nbytes -= result;
        } else if (result < 0 && errno == EINTR) {
            // Retry on interrupt
            continue;
        } else {
            // Read failed, zero remaining buffer
            memset(buf, 0, nbytes);
            break;
        }
    }

    close(fd);
}

uint32_t arc4random(void) {
    uint32_t value = 0;
    _arc4random_buf_impl(&value, sizeof(value));
    return value;
}

uint32_t arc4random_uniform(uint32_t upper_bound) {
    if (upper_bound <= 1) {
        return 0;
    }

    // OpenBSD rejection-sampling algorithm to eliminate modulo bias.
    // Compute the largest power-of-2 multiple of upper_bound that fits in uint32_t,
    // then reject values above that limit.
    uint32_t min = -upper_bound % upper_bound;

    uint32_t value;
    do {
        value = arc4random();
    } while (value < min);

    return value % upper_bound;
}

void arc4random_buf(void *buf, size_t nbytes) {
    _arc4random_buf_impl(buf, nbytes);
}

int SecRandomCopyBytes(int *drbg, size_t count, void *bytes) {
    (void)drbg;
    arc4random_buf(bytes, count);
    return 0; // errSecSuccess
}

#endif

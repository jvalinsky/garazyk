#ifndef SecRandom_h
#define SecRandom_h

#include <stdlib.h>

#ifdef __APPLE__
#import <Security/SecRandom.h>
#else

#define kSecRandomDefault 0
#define errSecSuccess 0

static inline int SecRandomCopyBytes(int *drbg, size_t count, void *bytes) {
    (void)drbg;
    arc4random_buf(bytes, count);
    return 0;
}

#endif

#endif /* SecRandom_h */

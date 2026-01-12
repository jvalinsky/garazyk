#ifndef Security_h
#define Security_h

#if defined(__APPLE__)
#import <Security/Security.h>
#else
#include <stdlib.h>

#define kSecRandomDefault 0
#define errSecSuccess 0

static inline int SecRandomCopyBytes(int *drbg, size_t count, void *bytes) {
    (void)drbg;
    arc4random_buf(bytes, count);
    return 0;
}

typedef struct __SecKey *SecKeyRef;

#endif

#endif /* Security_h */

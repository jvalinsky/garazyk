#ifndef CommonDigest_Compat_h
#define CommonDigest_Compat_h

#if defined(__APPLE__)
#include_next <CommonCrypto/CommonDigest.h>
#else

#include <openssl/sha.h>
#include <stdint.h>

#define CC_SHA256_DIGEST_LENGTH SHA256_DIGEST_LENGTH

typedef SHA256_CTX CC_SHA256_CTX;

static inline int CC_SHA256_Init(CC_SHA256_CTX *c) {
    return SHA256_Init(c);
}

static inline int CC_SHA256_Update(CC_SHA256_CTX *c, const void *data, uint32_t len) {
    return SHA256_Update(c, data, len);
}

static inline int CC_SHA256_Final(unsigned char *md, CC_SHA256_CTX *c) {
    return SHA256_Final(md, c);
}

static inline unsigned char *CC_SHA256(const void *data, uint32_t len, unsigned char *md) {
    return SHA256(data, len, md);
}

#endif
#endif

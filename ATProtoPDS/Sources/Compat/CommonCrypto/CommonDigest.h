#ifndef CommonDigest_Compat_h
#define CommonDigest_Compat_h

#if defined(__APPLE__)
#include_next <CommonCrypto/CommonDigest.h>
#else

#include <openssl/evp.h>
#include <stdint.h>

#define CC_SHA256_DIGEST_LENGTH 32 // SHA256_DIGEST_LENGTH might rely on deprecated headers
#define CC_SHA1_DIGEST_LENGTH 20

typedef uint32_t CC_LONG;

typedef struct {
    EVP_MD_CTX *ctx;
} CC_SHA256_CTX;

static inline int CC_SHA256_Init(CC_SHA256_CTX *c) {
    c->ctx = EVP_MD_CTX_new();
    return EVP_DigestInit_ex(c->ctx, EVP_sha256(), NULL);
}

static inline int CC_SHA256_Update(CC_SHA256_CTX *c, const void *data, CC_LONG len) {
    return EVP_DigestUpdate(c->ctx, data, len);
}

static inline int CC_SHA256_Final(unsigned char *md, CC_SHA256_CTX *c) {
    int ret = EVP_DigestFinal_ex(c->ctx, md, NULL);
    EVP_MD_CTX_free(c->ctx);
    return ret;
}

static inline unsigned char *CC_SHA256(const void *data, CC_LONG len, unsigned char *md) {
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_sha256(), NULL);
    EVP_DigestUpdate(ctx, data, len);
    EVP_DigestFinal_ex(ctx, md, NULL);
    EVP_MD_CTX_free(ctx);
    return md;
}


#endif
#endif

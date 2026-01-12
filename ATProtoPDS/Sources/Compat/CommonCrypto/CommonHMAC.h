#ifndef CommonHMAC_Compat_h
#define CommonHMAC_Compat_h

#if defined(__APPLE__)
#include_next <CommonCrypto/CommonHMAC.h>
#else

#include <openssl/hmac.h>

enum {
    kCCHmacAlgSHA256 = 0,
    kCCHmacAlgSHA1 = 1,
};
typedef uint32_t CCHmacAlgorithm;

typedef struct {
    HMAC_CTX *ctx;
} CCHmacContext;

static inline void CCHmacInit(CCHmacContext *ctx, CCHmacAlgorithm alg, const void *key, size_t keyLength) {
    ctx->ctx = HMAC_CTX_new();
    const EVP_MD *md = EVP_sha256(); // Assume SHA256 for now as mapped above
    HMAC_Init_ex(ctx->ctx, key, (int)keyLength, md, NULL);
}

static inline void CCHmacUpdate(CCHmacContext *ctx, const void *data, size_t dataLength) {
    HMAC_Update(ctx->ctx, data, dataLength);
}

static inline void CCHmacFinal(CCHmacContext *ctx, void *macOut) {
    HMAC_Final(ctx->ctx, macOut, NULL);
    HMAC_CTX_free(ctx->ctx);
}

static inline void CCHmac(CCHmacAlgorithm alg, const void *key, size_t keyLength, const void *data, size_t dataLength, void *macOut) {
    const EVP_MD *md = EVP_sha256();
    unsigned int len;
    HMAC(md, key, (int)keyLength, data, dataLength, macOut, &len);
}

#endif
#endif

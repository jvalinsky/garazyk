// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef CommonHMAC_h
#define CommonHMAC_h

#include <CommonCrypto/CommonDigest.h>
#include <openssl/hmac.h>

typedef uint32_t CCHmacAlgorithm;

enum {
    kCCHmacAlgSHA1,
    kCCHmacAlgMD5,
    kCCHmacAlgSHA256,
    kCCHmacAlgSHA384,
    kCCHmacAlgSHA512,
    kCCHmacAlgSHA224
};

static inline void CCHmac(CCHmacAlgorithm algorithm, const void *key, size_t keyLength, const void *data, size_t dataLength, void *macOut) {
    const EVP_MD *md = NULL;
    switch (algorithm) {
        case kCCHmacAlgSHA1: md = EVP_sha1(); break;
        case kCCHmacAlgMD5: md = EVP_md5(); break;
        case kCCHmacAlgSHA256: md = EVP_sha256(); break;
        case kCCHmacAlgSHA384: md = EVP_sha384(); break;
        case kCCHmacAlgSHA512: md = EVP_sha512(); break;
        case kCCHmacAlgSHA224: md = EVP_sha224(); break;
        default: return;
    }
    
    unsigned int len = 0;
    HMAC(md, key, (int)keyLength, (const unsigned char *)data, dataLength, (unsigned char *)macOut, &len);
}

#endif /* CommonHMAC_h */

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef CommonDigest_h
#define CommonDigest_h

#include <stdint.h>
#include <stddef.h>
#include <openssl/sha.h>
#include <openssl/md5.h>

typedef uint32_t CC_LONG;

#define CC_SHA256_DIGEST_LENGTH SHA256_DIGEST_LENGTH
#define CC_SHA1_DIGEST_LENGTH SHA_DIGEST_LENGTH
#define CC_MD5_DIGEST_LENGTH MD5_DIGEST_LENGTH

typedef SHA256_CTX CC_SHA256_CTX;
typedef SHA_CTX CC_SHA1_CTX;
typedef MD5_CTX CC_MD5_CTX;

// One-shot functions
// OpenSSL SHA functions take size_t, CommonCrypto takes CC_LONG (uint32_t)
#define CC_SHA256(data, len, md) SHA256((const unsigned char *)(data), (size_t)(len), (md))
#define CC_SHA1(data, len, md) SHA1((const unsigned char *)(data), (size_t)(len), (md))
#define CC_MD5(data, len, md) MD5((const unsigned char *)(data), (size_t)(len), (md))

// Init/Update/Final macros
#define CC_SHA256_Init(c) SHA256_Init(c)
#define CC_SHA256_Update(c,d,l) SHA256_Update(c,d,l)
#define CC_SHA256_Final(m,c) SHA256_Final(m,c)

#define CC_SHA1_Init(c) SHA1_Init(c)
#define CC_SHA1_Update(c,d,l) SHA1_Update(c,d,l)
#define CC_SHA1_Final(m,c) SHA1_Final(m,c)

#define CC_MD5_Init(c) MD5_Init(c)
#define CC_MD5_Update(c,d,l) MD5_Update(c,d,l)
#define CC_MD5_Final(m,c) MD5_Final(m,c)

#endif /* CommonDigest_h */

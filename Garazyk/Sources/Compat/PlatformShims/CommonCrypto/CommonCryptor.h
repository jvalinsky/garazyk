// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef CommonCryptor_h
#define CommonCryptor_h

#include <stdint.h>
#include <stddef.h>

#if defined(__APPLE__)
#include <CommonCrypto/CommonCryptor.h>
#else

#include <CommonCrypto/CommonKeyDerivation.h>

enum {
    kCCAlgorithmAES128 = 0,
    kCCAlgorithmDES = 1,
    kCCAlgorithm3DES = 2,
    kCCAlgorithmCAST = 3,
    kCCAlgorithmRC4 = 4,
    kCCAlgorithmRC2 = 5,
    kCCAlgorithmBlowfish = 6
};
typedef uint32_t CCAlgorithm;

enum {
    kCCOptionPKCS7Padding = 1,
    kCCOptionECBMode = 2
};
typedef uint32_t CCOptions;

enum {
    kCCEncrypt = 0,
    kCCDecrypt = 1
};

enum {
    kCCBlockSizeAES128 = 16,
    kCCBlockSizeDES = 8,
    kCCBlockSize3DES = 8,
    kCCBlockSizeCAST = 8,
    kCCBlockSizeRC2 = 8,
    kCCBlockSizeBlowfish = 8
};

enum {
    kCCKeySizeAES128 = 16,
    kCCKeySizeAES192 = 24,
    kCCKeySizeAES256 = 32,
    kCCKeySizeDES = 8,
    kCCKeySize3DES = 24,
    kCCKeySizeMinCAST = 5,
    kCCKeySizeMaxCAST = 16,
    kCCKeySizeMinRC4 = 1,
    kCCKeySizeMaxRC4 = 512,
    kCCKeySizeMinRC2 = 1,
    kCCKeySizeMaxRC2 = 128,
    kCCKeySizeMinBlowfish = 8,
    kCCKeySizeMaxBlowfish = 56
};

CCCryptorStatus CCCrypt(
    int op,
    CCAlgorithm alg,
    CCOptions options,
    const void *key,
    size_t keyLength,
    const void *iv,
    const void *dataIn,
    size_t dataInLength,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved);

#endif

#endif /* CommonCryptor_h */

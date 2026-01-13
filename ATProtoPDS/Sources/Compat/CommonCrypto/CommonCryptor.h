// CommonCryptor.h - Linux compatibility shim using OpenSSL
// Provides CCCrypt and related functionality

#ifndef _CC_COMMONCRYPTOR_H_
#define _CC_COMMONCRYPTOR_H_

#include <stdint.h>
#include <stddef.h>

// Include CommonKeyDerivation.h for kCCSuccess etc. to avoid redefinition
#include "CommonKeyDerivation.h"

// CCCryptorStatus type
typedef int32_t CCCryptorStatus;

// CCOperation values
enum {
    kCCEncrypt = 0,
    kCCDecrypt = 1,
};
typedef uint32_t CCOperation;

// CCAlgorithm values
enum {
    kCCAlgorithmAES128 = 0,
    kCCAlgorithmAES = 0,
    kCCAlgorithmDES = 1,
    kCCAlgorithm3DES = 2,
    kCCAlgorithmCAST = 3,
    kCCAlgorithmRC4 = 4,
    kCCAlgorithmRC2 = 5,
    kCCAlgorithmBlowfish = 6,
};
typedef uint32_t CCAlgorithm;

// CCOptions values
enum {
    kCCOptionPKCS7Padding = 0x0001,
    kCCOptionECBMode = 0x0002,
};
typedef uint32_t CCOptions;

// Key sizes
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
    kCCKeySizeMaxBlowfish = 56,
};

// Block sizes
enum {
    kCCBlockSizeAES128 = 16,
    kCCBlockSizeDES = 8,
    kCCBlockSize3DES = 8,
    kCCBlockSizeCAST = 8,
    kCCBlockSizeRC2 = 8,
    kCCBlockSizeBlowfish = 8,
};

/**
 * Stateless symmetric encryption/decryption.
 * 
 * @param op Operation (kCCEncrypt or kCCDecrypt)
 * @param alg Algorithm (only kCCAlgorithmAES128 supported)
 * @param options Options (kCCOptionPKCS7Padding supported)
 * @param key Pointer to key data
 * @param keyLength Length of key in bytes
 * @param iv Initialization vector (can be NULL for ECB)
 * @param dataIn Input data
 * @param dataInLength Length of input data
 * @param dataOut Output buffer
 * @param dataOutAvailable Size of output buffer
 * @param dataOutMoved Receives actual output size
 * @return kCCSuccess on success
 */
CCCryptorStatus CCCrypt(
    CCOperation op,
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

#endif /* _CC_COMMONCRYPTOR_H_ */

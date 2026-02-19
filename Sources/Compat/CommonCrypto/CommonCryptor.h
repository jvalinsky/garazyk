// CommonCryptor compat header for GNUstep/Linux
// Wraps OpenSSL EVP interface
#ifndef COMMON_CRYPTOR_H
#define COMMON_CRYPTOR_H

#if defined(__APPLE__)
#include <CommonCrypto/CommonCryptor.h>
#else

#include <stdint.h>
#include <stddef.h>
#include <openssl/evp.h>
#include <openssl/aes.h>

// Block sizes
#define kCCBlockSizeAES128 16

// Operations
typedef enum {
    kCCEncrypt = 0,
    kCCDecrypt = 1
} CCOperation;

// Algorithms
typedef enum {
    kCCAlgorithmAES128 = 0,
    kCCAlgorithmAES = 0,
    kCCAlgorithm3DES = 1,
    kCCAlgorithmDES = 2,
    kCCAlgorithmRC4 = 3
} CCAlgorithm;

// Options
typedef enum {
    kCCOptionPKCS7Padding = 0x0001,
    kCCOptionECBMode = 0x0002
} CCOptions;

// Error codes
typedef int32_t CCCryptorStatus;
#define kCCSuccess 0
#define kCCParamError -4300
#define kCCBufferTooSmall -4301
#define kCCMemoryFailure -4302
#define kCCAlignmentError -4303
#define kCCDecodeError -4304
#define kCCUnimplemented -4305

// Key sizes
#define kCCKeySizeAES128 16
#define kCCKeySizeAES192 24
#define kCCKeySizeAES256 32

// Simplified CCCrypt implementation using OpenSSL
static inline CCCryptorStatus CCCrypt(
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
    size_t *dataOutMoved)
{
    if (!key || !dataIn || !dataOut) {
        return kCCParamError;
    }
    
    const EVP_CIPHER *cipher = NULL;
    if (alg == kCCAlgorithmAES128 || alg == kCCAlgorithmAES) {
        switch (keyLength) {
            case 16: cipher = EVP_aes_128_cbc(); break;
            case 24: cipher = EVP_aes_192_cbc(); break;
            case 32: cipher = EVP_aes_256_cbc(); break;
            default: return kCCParamError;
        }
    } else {
        return kCCUnimplemented;
    }
    
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return kCCMemoryFailure;
    }
    
    int len = 0;
    int totalLen = 0;
    
    if (EVP_CipherInit_ex(ctx, cipher, NULL, key, iv, (op == kCCEncrypt) ? 1 : 0) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return kCCParamError;
    }
    
    // Handle padding
    if (!(options & kCCOptionPKCS7Padding)) {
        EVP_CIPHER_CTX_set_padding(ctx, 0);
    }
    
    if (EVP_CipherUpdate(ctx, dataOut, &len, dataIn, (int)dataInLength) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return kCCDecodeError;
    }
    totalLen = len;
    
    if (EVP_CipherFinal_ex(ctx, (unsigned char *)dataOut + len, &len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return kCCDecodeError;
    }
    totalLen += len;
    
    EVP_CIPHER_CTX_free(ctx);
    
    if (dataOutMoved) {
        *dataOutMoved = totalLen;
    }
    
    return kCCSuccess;
}

#endif // __APPLE__

#endif // COMMON_CRYPTOR_H

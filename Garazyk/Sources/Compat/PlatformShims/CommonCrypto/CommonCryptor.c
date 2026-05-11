// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#include "CommonCryptor.h"

#if !defined(__APPLE__)

#include <openssl/evp.h>
#include <string.h>

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
    size_t *dataOutMoved)
{
    if (alg != kCCAlgorithmAES128) {
        return kCCUnimplemented;
    }
    
    const EVP_CIPHER *cipher = NULL;
    if (keyLength == 16) {
        cipher = EVP_aes_128_cbc();
    } else if (keyLength == 24) {
        cipher = EVP_aes_192_cbc();
    } else if (keyLength == 32) {
        cipher = EVP_aes_256_cbc();
    } else {
        return kCCParamError;
    }
    
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return kCCMemoryFailure;
    }
    
    int ret = 0;
    int outlen = 0;
    int tmplen = 0;
    
    if (op == kCCEncrypt) {
        ret = EVP_EncryptInit_ex(ctx, cipher, NULL, key, iv);
    } else {
        ret = EVP_DecryptInit_ex(ctx, cipher, NULL, key, iv);
    }
    
    if (ret != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return kCCParamError;
    }
    
    if (!(options & kCCOptionPKCS7Padding)) {
        EVP_CIPHER_CTX_set_padding(ctx, 0);
    }
    
    if (op == kCCEncrypt) {
        ret = EVP_EncryptUpdate(ctx, dataOut, &outlen, dataIn, (int)dataInLength);
        if (ret == 1) {
            ret = EVP_EncryptFinal_ex(ctx, (unsigned char *)dataOut + outlen, &tmplen);
        }
    } else {
        ret = EVP_DecryptUpdate(ctx, dataOut, &outlen, dataIn, (int)dataInLength);
        if (ret == 1) {
            ret = EVP_DecryptFinal_ex(ctx, (unsigned char *)dataOut + outlen, &tmplen);
        }
    }
    
    EVP_CIPHER_CTX_free(ctx);
    
    if (ret != 1) {
        return kCCDecodeError;
    }
    
    if ((size_t)(outlen + tmplen) > dataOutAvailable) {
        return kCCBufferTooSmall;
    }
    
    if (dataOutMoved) {
        *dataOutMoved = outlen + tmplen;
    }
    
    return kCCSuccess;
}

#endif

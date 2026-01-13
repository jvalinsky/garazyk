// CommonCryptor.m - Linux implementation using OpenSSL

#import "CommonCryptor.h"

#if !defined(__APPLE__)

#include <openssl/evp.h>
#include <string.h>

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
    size_t *dataOutMoved) {
    
    // Only support AES for now
    if (alg != kCCAlgorithmAES128 && alg != kCCAlgorithmAES) {
        return kCCParamError;
    }
    
    // Select cipher based on key length
    const EVP_CIPHER *cipher = NULL;
    switch (keyLength) {
        case kCCKeySizeAES128:
            cipher = EVP_aes_128_cbc();
            break;
        case kCCKeySizeAES192:
            cipher = EVP_aes_192_cbc();
            break;
        case kCCKeySizeAES256:
            cipher = EVP_aes_256_cbc();
            break;
        default:
            return kCCParamError;
    }
    
    if (options & kCCOptionECBMode) {
        switch (keyLength) {
            case kCCKeySizeAES128:
                cipher = EVP_aes_128_ecb();
                break;
            case kCCKeySizeAES192:
                cipher = EVP_aes_192_ecb();
                break;
            case kCCKeySizeAES256:
                cipher = EVP_aes_256_ecb();
                break;
        }
    }
    
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return kCCParamError;
    }
    
    int ret;
    if (op == kCCEncrypt) {
        ret = EVP_EncryptInit_ex(ctx, cipher, NULL, key, iv);
    } else {
        ret = EVP_DecryptInit_ex(ctx, cipher, NULL, key, iv);
    }
    
    if (ret != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return kCCParamError;
    }
    
    // Enable/disable padding
    if (options & kCCOptionPKCS7Padding) {
        EVP_CIPHER_CTX_set_padding(ctx, 1);
    } else {
        EVP_CIPHER_CTX_set_padding(ctx, 0);
    }
    
    int outLen = 0;
    int finalLen = 0;
    
    if (op == kCCEncrypt) {
        ret = EVP_EncryptUpdate(ctx, dataOut, &outLen, dataIn, (int)dataInLength);
        if (ret != 1) {
            EVP_CIPHER_CTX_free(ctx);
            return kCCParamError;
        }
        
        ret = EVP_EncryptFinal_ex(ctx, (unsigned char *)dataOut + outLen, &finalLen);
    } else {
        ret = EVP_DecryptUpdate(ctx, dataOut, &outLen, dataIn, (int)dataInLength);
        if (ret != 1) {
            EVP_CIPHER_CTX_free(ctx);
            return kCCParamError;
        }
        
        ret = EVP_DecryptFinal_ex(ctx, (unsigned char *)dataOut + outLen, &finalLen);
    }
    
    EVP_CIPHER_CTX_free(ctx);
    
    if (ret != 1) {
        return kCCParamError;
    }
    
    if (dataOutMoved) {
        *dataOutMoved = outLen + finalLen;
    }
    
    return kCCSuccess;
}

#endif // !__APPLE__

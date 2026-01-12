#ifndef CommonKeyDerivation_h
#define CommonKeyDerivation_h

#if defined(__APPLE__)
#include <CommonCrypto/CommonKeyDerivation.h>
#else
#include <CommonCrypto/CommonDigest.h>
#include <openssl/evp.h>

enum {
    kCCSuccess = 0,
    kCCParamError = -4300,
    kCCBufferTooSmall = -4301,
    kCCMemoryFailure = -4302,
    kCCAlignmentError = -4303,
    kCCDecodeError = -4304,
    kCCUnimplemented = -4305,
    kCCOverflowError = -4306,
    kCCRNGError = -4307
};

enum {
    kCCPBKDF2 = 2
};

enum {
    kCCPRFHmacAlgSHA1 = 1,
    kCCPRFHmacAlgSHA224 = 2,
    kCCPRFHmacAlgSHA256 = 3,
    kCCPRFHmacAlgSHA384 = 4,
    kCCPRFHmacAlgSHA512 = 5
};

typedef uint32_t CCPseudoRandomAlgorithm;

static inline int CCKeyDerivationPBKDF(uint32_t algorithm, const char *password, size_t passwordLen, const unsigned char *salt, size_t saltLen, CCPseudoRandomAlgorithm prf, uint32_t rounds, unsigned char *derivedKey, size_t derivedKeyLen) {
    if (algorithm != kCCPBKDF2) return kCCParamError;
    
    const EVP_MD *md = NULL;
    switch (prf) {
        case kCCPRFHmacAlgSHA1: md = EVP_sha1(); break;
        case kCCPRFHmacAlgSHA224: md = EVP_sha224(); break;
        case kCCPRFHmacAlgSHA256: md = EVP_sha256(); break;
        case kCCPRFHmacAlgSHA384: md = EVP_sha384(); break;
        case kCCPRFHmacAlgSHA512: md = EVP_sha512(); break;
        default: return kCCParamError;
    }
    
    int res = PKCS5_PBKDF2_HMAC(password, (int)passwordLen, salt, (int)saltLen, (int)rounds, md, (int)derivedKeyLen, derivedKey);
    return (res == 1) ? kCCSuccess : kCCMemoryFailure;
}

#endif /* __APPLE__ */

#endif /* CommonKeyDerivation_h */

#ifndef CommonKeyDerivation_h
#define CommonKeyDerivation_h

#include <stdint.h>
#include <openssl/evp.h>
#include <openssl/sha.h>
#include <openssl/hmac.h>

enum {
    kCCPBKDF2 = 2,
};

enum {
    kCCPRFHmacAlgSHA256 = 2,
};

enum {
    kCCSuccess = 0,
    kCCParamError = -4300,
};

typedef uint32_t CCPseudoRandomAlgorithm;

int CCKeyDerivationPBKDF(unsigned int algorithm, const char *password, size_t passwordLen,
                         const uint8_t *salt, size_t saltLen,
                         CCPseudoRandomAlgorithm prf, unsigned int rounds,
                         unsigned char *derivedKey, size_t derivedKeyLen);

#endif /* CommonKeyDerivation_h */

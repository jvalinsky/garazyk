#import "CommonKeyDerivation.h"
#import <openssl/evp.h>

int CCKeyDerivationPBKDF(unsigned int algorithm, const char *password, size_t passwordLen,
                         const uint8_t *salt, size_t saltLen,
                         CCPseudoRandomAlgorithm prf, unsigned int rounds,
                         unsigned char *derivedKey, size_t derivedKeyLen) {
    
    if (algorithm != kCCPBKDF2) {
        return -1; // Only PBKDF2 is supported
    }

    const EVP_MD *md = NULL;
    if (prf == kCCPRFHmacAlgSHA256) {
        md = EVP_sha256();
    } else {
        return -1; // Only SHA256 is supported for now
    }
    
    // PKCS5_PBKDF2_HMAC returns 1 on success
    if (PKCS5_PBKDF2_HMAC(password, (int)passwordLen,
                          salt, (int)saltLen,
                          (int)rounds, md,
                          (int)derivedKeyLen, derivedKey) != 1) {
        return -1;
    }
    
    return 0; // Success
}

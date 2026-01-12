#import "Security.h"

// Constants
const void * kSecAttrKeyType = @"kSecAttrKeyType";
const void * kSecAttrKeyTypeECSECPrimeRandom = @"kSecAttrKeyTypeECSECPrimeRandom";
const void * kSecAttrKeySizeInBits = @"kSecAttrKeySizeInBits";
const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureMessageX962SHA256 = @"kSecKeyAlgorithmECDSASignatureMessageX962SHA256";
const void * kSecRandomDefault = NULL;

int SecRandomCopyBytes(const void *rnd, size_t count, void *bytes) {
    if (RAND_bytes((unsigned char *)bytes, (int)count) == 1) {
        return 0; // Success
    }
    return -1; // Failure
}

SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef attributes, CFErrorRef *error) {
    EVP_PKEY *pkey = NULL;
    EVP_PKEY_CTX *pctx = EVP_PKEY_CTX_new_id(EVP_PKEY_EC, NULL);
    
    if (!pctx) return NULL;
    
    if (EVP_PKEY_keygen_init(pctx) <= 0) {
        EVP_PKEY_CTX_free(pctx);
        return NULL;
    }
    
    if (EVP_PKEY_CTX_set_ec_paramgen_curve_nid(pctx, NID_X9_62_prime256v1) <= 0) {
        EVP_PKEY_CTX_free(pctx);
        return NULL;
    }
    
    if (EVP_PKEY_keygen(pctx, &pkey) <= 0) {
        EVP_PKEY_CTX_free(pctx);
        return NULL;
    }
    
    EVP_PKEY_CTX_free(pctx);
    return pkey;
}

SecKeyRef SecKeyCopyPublicKey(SecKeyRef key) {
    if (!key) return NULL;
    // OpenSSL EVP_PKEY contains both usually, but we can up-ref.
    // Ideally we clone and drop private part, but for now sharing ref is mostly safe for read ops.
    EVP_PKEY_up_ref(key);
    return key; 
}

NSData * SecKeyCopyExternalRepresentation(SecKeyRef key, CFErrorRef *error) {
    if (!key) return nil;
    
    // Export public key to DER/SubjectPublicKeyInfo
    unsigned char *buf = NULL;
    int len = i2d_PUBKEY(key, &buf);
    
    if (len <= 0) return nil;
    
    NSData *data = [NSData dataWithBytes:buf length:len];
    OPENSSL_free(buf);
    return data;
}

SecKeyRef SecKeyCreateWithData(CFDataRef keyData, CFDictionaryRef attributes, CFErrorRef *error) {
    NSData *data = (__bridge NSData *)keyData;
    const unsigned char *p = [data bytes];
    
    EVP_PKEY *key = d2i_PUBKEY(NULL, &p, [data length]);
    return key;
}

BOOL SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef signedData, CFDataRef signature, CFErrorRef *error) {
    if (!key) return NO;
    
    NSData *msg = (__bridge NSData *)signedData;
    NSData *sig = (__bridge NSData *)signature;
    
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx) return NO;
    
    const EVP_MD *md = EVP_sha256(); // Implicit from algorithm constant
    
    if (EVP_DigestVerifyInit(ctx, NULL, md, NULL, key) <= 0) {
        EVP_MD_CTX_free(ctx);
        return NO;
    }
    
    int ret = EVP_DigestVerify(ctx, [sig bytes], [sig length], [msg bytes], [msg length]);
    EVP_MD_CTX_free(ctx);
    
    return (ret == 1);
}

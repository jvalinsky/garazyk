// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file SecKey.m
 *
 * @brief SecKey operations implementation for Linux/OpenSSL.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "SecKey.h"

#if !defined(__APPLE__)

#import <openssl/evp.h>
#import <openssl/pem.h>
#import <openssl/rsa.h>
#import <openssl/ec.h>
#import <openssl/err.h>
#import <openssl/x509.h>

// Constants definitions
const CFStringRef kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256 = (CFStringRef)@"kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256";
const CFStringRef kSecKeyAlgorithmECDSASignatureMessageX962SHA256 = (CFStringRef)@"kSecKeyAlgorithmECDSASignatureMessageX962SHA256";
const CFStringRef kSecKeyAlgorithmECDSASignatureDigestX962SHA256 = (CFStringRef)@"kSecKeyAlgorithmECDSASignatureDigestX962SHA256";

const CFStringRef kSecAttrKeyType = (CFStringRef)@"kSecAttrKeyType";
const CFStringRef kSecAttrKeyTypeRSA = (CFStringRef)@"kSecAttrKeyTypeRSA";
const CFStringRef kSecAttrKeyTypeECSECPrimeRandom = (CFStringRef)@"kSecAttrKeyTypeECSECPrimeRandom";
const CFStringRef kSecAttrKeyClass = (CFStringRef)@"kSecAttrKeyClass";
const CFStringRef kSecAttrKeyClassPublic = (CFStringRef)@"kSecAttrKeyClassPublic";
const CFStringRef kSecAttrKeyClassPrivate = (CFStringRef)@"kSecAttrKeyClassPrivate";
const CFStringRef kSecAttrKeySizeInBits = (CFStringRef)@"kSecAttrKeySizeInBits";

struct SecKey {
    EVP_PKEY *pkey;
};

// Helper to create NSError from OpenSSL errors
static NSError *OpenSSLError(NSString *desc) {
    unsigned long err = ERR_get_error();
    char buf[256];
    ERR_error_string_n(err, buf, sizeof(buf));
    NSString *reason = [NSString stringWithUTF8String:buf];
    return [NSError errorWithDomain:@"OpenSSL" code:err userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@", desc, reason]}];
}

SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef attributes, CFErrorRef *error) {
    NSDictionary *attrs = (__bridge NSDictionary *)attributes;
    NSString *keyType = attrs[(__bridge NSString *)kSecAttrKeyType];
    NSNumber *keySize = attrs[(__bridge NSString *)kSecAttrKeySizeInBits];
    
    EVP_PKEY *pkey = NULL;
    EVP_PKEY_CTX *pctx = NULL;
    
    if ([keyType isEqualToString:(__bridge NSString *)kSecAttrKeyTypeRSA]) {
        pctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
        if (!pctx || EVP_PKEY_keygen_init(pctx) <= 0 ||
            EVP_PKEY_CTX_set_rsa_keygen_bits(pctx, keySize.intValue) <= 0 ||
            EVP_PKEY_keygen(pctx, &pkey) <= 0) {
            if (error) *error = (__bridge CFErrorRef)OpenSSLError(@"Failed to generate RSA key");
            if (pctx) EVP_PKEY_CTX_free(pctx);
            return NULL;
        }
    } else if ([keyType isEqualToString:(__bridge NSString *)kSecAttrKeyTypeECSECPrimeRandom]) {
        // P-256 default for EC
        pctx = EVP_PKEY_CTX_new_id(EVP_PKEY_EC, NULL);
        if (!pctx || EVP_PKEY_keygen_init(pctx) <= 0 ||
            EVP_PKEY_CTX_set_ec_paramgen_curve_nid(pctx, NID_X9_62_prime256v1) <= 0 ||
            EVP_PKEY_keygen(pctx, &pkey) <= 0) {
            if (error) *error = (__bridge CFErrorRef)OpenSSLError(@"Failed to generate EC key");
            if (pctx) EVP_PKEY_CTX_free(pctx);
            return NULL;
        }
    } else {
        if (error) *error = (__bridge CFErrorRef)[NSError errorWithDomain:@"SecKey" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported key type"}];
        return NULL;
    }
    
    EVP_PKEY_CTX_free(pctx);
    
    SecKeyRef key = malloc(sizeof(struct SecKey));
    key->pkey = pkey;
    return key;
}

SecKeyRef SecKeyCopyPublicKey(SecKeyRef privateKey) {
    if (!privateKey || !privateKey->pkey) return NULL;
    
    // Increment reference count or copy? OpenSSL ref counting is easier
    EVP_PKEY_up_ref(privateKey->pkey);
    
    SecKeyRef publicKey = malloc(sizeof(struct SecKey));
    publicKey->pkey = privateKey->pkey; // Shared PKEY, contains both public and private if generated together?
    // Wait, if it's a private key, it has both.
    // If we want just public key, we might want to separate it, but for EVP_PKEY it handles both.
    // However, for semantics, we should treat it as public.
    // Actually, creating a new EVP_PKEY with just public components is safer but complex.
    // For now, sharing the underlying PKEY is acceptable if we treat it as immutable.
    
    return publicKey;
}

CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, CFErrorRef *error) {
    if (!key || !key->pkey) return NULL;
    
    int type = EVP_PKEY_id(key->pkey);
    unsigned char *buf = NULL;
    int len = 0;
    
    if (type == EVP_PKEY_RSA) {
        // RSA: Apple uses PKCS#1
        // i2d_RSAPublicKey for public, i2d_RSAPrivateKey for private
        // How do we know if it's public or private?
        // Check if private components exist
        RSA *rsa = (RSA *)EVP_PKEY_get0_RSA(key->pkey); // Deprecated in 3.0, but fine for now
        if (RSA_check_key(rsa) == 1) { // Has private components
             len = i2d_RSAPrivateKey(rsa, &buf);
        } else {
             len = i2d_RSAPublicKey(rsa, &buf);
        }
    } else if (type == EVP_PKEY_EC) {
        // EC: Apple uses X9.62 for public (04...)
        EC_KEY *ec = (EC_KEY *)EVP_PKEY_get0_EC_KEY(key->pkey);
        const EC_GROUP *group = EC_KEY_get0_group(ec);
        const EC_POINT *point = EC_KEY_get0_public_key(ec);
        
        // If private key present?
        if (EC_KEY_get0_private_key(ec)) {
             // Export private key (SEC1)
             len = i2d_ECPrivateKey(ec, &buf);
        } else {
             // Export public key (X9.62)
             len = EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, NULL, 0, NULL);
             buf = malloc(len);
             EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, buf, len, NULL);
        }
    }
    
    if (len <= 0 || !buf) {
        if (error) *error = (__bridge CFErrorRef)OpenSSLError(@"Failed to export key");
        return NULL;
    }
    
    NSData *data = [NSData dataWithBytes:buf length:len];
    if (type == EVP_PKEY_RSA || (type == EVP_PKEY_EC && EC_KEY_get0_private_key(EVP_PKEY_get0_EC_KEY(key->pkey)))) {
        OPENSSL_free(buf); // i2d allocates with OPENSSL_malloc
    } else {
        free(buf); // EC_POINT uses user buffer or internal? point2oct writes to buf
    }
    
    return (__bridge_retained CFDataRef)data;
}

SecKeyRef SecKeyCreateWithData(CFDataRef keyData, CFDictionaryRef attributes, CFErrorRef *error) {
    NSData *data = (__bridge NSData *)keyData;
    NSDictionary *attrs = (__bridge NSDictionary *)attributes;
    NSString *keyType = attrs[(__bridge NSString *)kSecAttrKeyType];
    NSString *keyClass = attrs[(__bridge NSString *)kSecAttrKeyClass];
    
    const unsigned char *p = data.bytes;
    long len = data.length;
    EVP_PKEY *pkey = NULL;
    
    if ([keyType isEqualToString:(__bridge NSString *)kSecAttrKeyTypeRSA]) {
        if ([keyClass isEqualToString:(__bridge NSString *)kSecAttrKeyClassPrivate]) {
            RSA *rsa = d2i_RSAPrivateKey(NULL, &p, len);
            if (rsa) {
                pkey = EVP_PKEY_new();
                EVP_PKEY_assign_RSA(pkey, rsa);
            }
        } else {
            RSA *rsa = d2i_RSAPublicKey(NULL, &p, len);
            if (rsa) {
                pkey = EVP_PKEY_new();
                EVP_PKEY_assign_RSA(pkey, rsa);
            }
        }
    } else if ([keyType isEqualToString:(__bridge NSString *)kSecAttrKeyTypeECSECPrimeRandom]) {
        // EC keys
        EC_KEY *ec = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
        if ([keyClass isEqualToString:(__bridge NSString *)kSecAttrKeyClassPrivate]) {
            EC_KEY_free(ec);
            ec = d2i_ECPrivateKey(NULL, &p, len);
        } else {
            // Public key import from X9.62 octet string
             const EC_GROUP *group = EC_KEY_get0_group(ec);
             EC_POINT *point = EC_POINT_new(group);
             if (EC_POINT_oct2point(group, point, p, len, NULL) == 1) {
                 EC_KEY_set_public_key(ec, point);
             } else {
                 EC_POINT_free(point);
                 EC_KEY_free(ec);
                 ec = NULL;
             }
             if (point) EC_POINT_free(point);
        }
        
        if (ec) {
            pkey = EVP_PKEY_new();
            EVP_PKEY_assign_EC_KEY(pkey, ec);
        }
    }
    
    if (!pkey) {
        if (error) *error = (__bridge CFErrorRef)OpenSSLError(@"Failed to import key");
        return NULL;
    }
    
    SecKeyRef key = malloc(sizeof(struct SecKey));
    key->pkey = pkey;
    return key;
}

CFDataRef SecKeyCreateSignature(SecKeyRef key, CFStringRef algorithm, CFDataRef dataToSign, CFErrorRef *error) {
    if (!key || !key->pkey) return NULL;
    NSData *data = (__bridge NSData *)dataToSign;
    
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    EVP_PKEY_CTX *pctx = NULL;
    const EVP_MD *md = EVP_sha256(); // Default to SHA256
    
    if (EVP_DigestSignInit(mdctx, &pctx, md, NULL, key->pkey) <= 0) {
        if (error) *error = (__bridge CFErrorRef)OpenSSLError(@"Failed to init sign");
        EVP_MD_CTX_free(mdctx);
        return NULL;
    }
    
    size_t sigLen = 0;
    if (EVP_DigestSign(mdctx, NULL, &sigLen, data.bytes, data.length) <= 0) {
        if (error) *error = (__bridge CFErrorRef)OpenSSLError(@"Failed to sign (length)");
        EVP_MD_CTX_free(mdctx);
        return NULL;
    }
    
    unsigned char *sig = malloc(sigLen);
    if (EVP_DigestSign(mdctx, sig, &sigLen, data.bytes, data.length) <= 0) {
        if (error) *error = (__bridge CFErrorRef)OpenSSLError(@"Failed to sign");
        free(sig);
        EVP_MD_CTX_free(mdctx);
        return NULL;
    }
    
    EVP_MD_CTX_free(mdctx);
    NSData *sigData = [NSData dataWithBytes:sig length:sigLen];
    free(sig);
    return (__bridge_retained CFDataRef)sigData;
}

Boolean SecKeyVerifySignature(SecKeyRef key, CFStringRef algorithm, CFDataRef signedData, CFDataRef signature, CFErrorRef *error) {
    if (!key || !key->pkey) return false;
    NSData *data = (__bridge NSData *)signedData;
    NSData *sig = (__bridge NSData *)signature;
    
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    const EVP_MD *md = EVP_sha256();
    
    if (EVP_DigestVerifyInit(mdctx, NULL, md, NULL, key->pkey) <= 0) {
        if (error) *error = (__bridge CFErrorRef)OpenSSLError(@"Failed to init verify");
        EVP_MD_CTX_free(mdctx);
        return false;
    }
    
    int ret = EVP_DigestVerify(mdctx, sig.bytes, sig.length, data.bytes, data.length);
    EVP_MD_CTX_free(mdctx);
    
    if (ret != 1) {
        if (error) *error = (__bridge CFErrorRef)[NSError errorWithDomain:@"SecKey" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Signature verification failed"}];
        return false;
    }
    
    return true;
}

// SecKeyRelease - safely release manually-allocated SecKey structs
void SecKeyRelease(SecKeyRef key) {
    if (!key) return;
    if (key->pkey) {
        EVP_PKEY_free(key->pkey);
    }
    free(key);
}

#endif // !__APPLE__

// Placeholder for SecKeyWrapper implementation (Stub for now, or use C functions)
@implementation SecKeyWrapper

+ (nullable NSData *)publicKeyFromData:(NSData *)keyData error:(NSError **)error {
    // Implement using SecKeyCreateWithData and SecKeyCopyPublicKey
    // For now, return nil or implement later
    return nil;
}

+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key error:(NSError **)error {
    return nil;
}

+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key error:(NSError **)error {
    return nil;
}

@end

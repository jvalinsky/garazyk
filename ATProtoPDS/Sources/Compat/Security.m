#import "Security/Security.h"

#if !defined(__APPLE__)

#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/err.h>
#include <openssl/pem.h>

const void * kSecAttrKeyType = @"kSecAttrKeyType";
const void * kSecAttrKeyTypeECSECPrimeRandom = @"kSecAttrKeyTypeECSECPrimeRandom";
const void * kSecAttrKeySizeInBits = @"kSecAttrKeySizeInBits";
const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureMessageX962SHA256 = @"kSecKeyAlgorithmECDSASignatureMessageX962SHA256";
const void * kSecAttrKeyClass = @"kSecAttrKeyClass";
const void * kSecAttrKeyClassPrivate = @"kSecAttrKeyClassPrivate";
const void * kSecAttrKeyClassPublic = @"kSecAttrKeyClassPublic";
const void * kSecPrivateKeyAttrs = @"kSecPrivateKeyAttrs";
const void * kSecAttrIsPermanent = @"kSecAttrIsPermanent";
const void * kSecAttrApplicationTag = @"kSecAttrApplicationTag";
const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256 = @"kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256";
const void * kSecAttrKeyTypeRSA = @"kSecAttrKeyTypeRSA";
const void * kSecRandomDefault = NULL;

// Keychain Constants
const void * kSecClass = @"class";
const void * kSecClassGenericPassword = @"genp";
const void * kSecAttrService = @"svce";
const void * kSecAttrAccount = @"acct";
const void * kSecValueData = @"v_Data";
const void * kSecReturnData = @"r_Data";
const void * kSecReturnRef = @"r_Ref";
const void * kSecMatchLimit = @"m_Limit";
const void * kSecMatchLimitOne = @"m_LimitOne";
const void * kSecValueRef = @"v_Ref";
const void * kSecAttrAccessible = @"accessible";
const void * kSecAttrAccessibleAfterFirstUnlock = @"accessible_after_first_unlock";

// ============================================================================
// Keychain Implementation (In-Memory Shim)
// ============================================================================

static NSMutableDictionary *mockKeychainStore = nil;

static void InitMockKeychain(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mockKeychainStore = [NSMutableDictionary new];
    });
}

static NSString *KeychainKey(CFDictionaryRef query) {
    NSDictionary *q = (__bridge NSDictionary *)query;
    NSString *service = q[(__bridge id)kSecAttrService];
    NSString *account = q[(__bridge id)kSecAttrAccount];
    if (service && account) {
        return [NSString stringWithFormat:@"%@:%@", service, account];
    }
    return nil;
}

OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    InitMockKeychain();
    NSDictionary *attrs = (__bridge NSDictionary *)attributes;
    NSString *key = KeychainKey(attributes);
    
    if (!key) return errSecParam;
    
    @synchronized(mockKeychainStore) {
        if (mockKeychainStore[key]) {
            return errSecDuplicateItem;
        }
        
        NSData *data = attrs[(__bridge id)kSecValueData];
        if (data) {
            mockKeychainStore[key] = data;
        }
    }
    return errSecSuccess;
}

OSStatus SecItemDelete(CFDictionaryRef query) {
    InitMockKeychain();
    NSString *key = KeychainKey(query);
    if (!key) return errSecParam;
    
    @synchronized(mockKeychainStore) {
        if (!mockKeychainStore[key]) {
            return errSecItemNotFound;
        }
        [mockKeychainStore removeObjectForKey:key];
    }
    return errSecSuccess;
}

OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    InitMockKeychain();
    NSDictionary *q = (__bridge NSDictionary *)query;
    NSString *key = KeychainKey(query);
    if (!key) return errSecParam;
    
    @synchronized(mockKeychainStore) {
        NSData *data = mockKeychainStore[key];
        if (!data) return errSecItemNotFound;
        
        if (q[(__bridge id)kSecReturnData] && [q[(__bridge id)kSecReturnData] boolValue]) {
            if (result) {
                *result = (__bridge_retained CFTypeRef)[data copy];
            }
        }
    }
    return errSecSuccess;
}

// ============================================================================
// Crypto Implementation
// ============================================================================

SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef attributes, CFErrorRef *error) {
    // Generate EC Key P-256
    EVP_PKEY *pkey = NULL;
    EVP_PKEY_CTX *pctx = EVP_PKEY_CTX_new_id(EVP_PKEY_EC, NULL);
    
    if (!pctx) goto err;
    if (EVP_PKEY_keygen_init(pctx) <= 0) goto err;
    if (EVP_PKEY_CTX_set_ec_paramgen_curve_nid(pctx, NID_X9_62_prime256v1) <= 0) goto err;
    if (EVP_PKEY_keygen(pctx, &pkey) <= 0) goto err;
    
    EVP_PKEY_CTX_free(pctx);
    return pkey;

err:
    if (pctx) EVP_PKEY_CTX_free(pctx);
    if (error) {
        *error = (__bridge CFErrorRef)[NSError errorWithDomain:@"OpenSSL" code:-1 userInfo:nil];
    }
    return NULL;
}

SecKeyRef SecKeyCopyPublicKey(SecKeyRef key) {
    if (!key) return NULL;
    EVP_PKEY_up_ref(key);
    return key;
}

CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, CFErrorRef *error) {
    if (!key) return NULL;
    
    // Export public key as DER
    unsigned char *buf = NULL;
    int len = i2d_PublicKey(key, &buf);
    if (len < 0) return NULL;
    
    NSData *data = [NSData dataWithBytes:buf length:len];
    OPENSSL_free(buf);
    
    return (__bridge_retained CFDataRef)data;
}

// Stub for creating key from data (simplified)
SecKeyRef SecKeyCreateWithData(CFDataRef keyData, CFDictionaryRef attributes, CFErrorRef *error) {
    if (!keyData) return NULL;
    NSData *data = (__bridge NSData *)keyData;
    const unsigned char *p = [data bytes];
    EVP_PKEY *pkey = d2i_PublicKey(EVP_PKEY_EC, NULL, &p, [data length]);
    
    // If EC failed, try RSA?
    if (!pkey) {
        p = [data bytes];
        pkey = d2i_PublicKey(EVP_PKEY_RSA, NULL, &p, [data length]);
    }
    
    return pkey;
}

BOOL SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef signedData, CFDataRef signature, CFErrorRef *error) {
    if (!key) return NO;
    
    // Declarations at top to avoid goto skips
    NSData *msg = (__bridge NSData *)signedData;
    NSData *sig = (__bridge NSData *)signature;
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    const EVP_MD *md = EVP_sha256();
    int result = 0;

    if(!mdctx) return NO;

    if(EVP_DigestVerifyInit(mdctx, NULL, md, NULL, key) > 0) {
        if(EVP_DigestVerifyUpdate(mdctx, [msg bytes], [msg length]) > 0) {
            result = EVP_DigestVerifyFinal(mdctx, [sig bytes], [sig length]);
        }
    }

    EVP_MD_CTX_free(mdctx);
    return (result == 1);
}

CFDataRef SecKeyCreateSignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef dataToSign, CFErrorRef *error) {
    if (!key) return NULL;
    
    NSData *msg = (__bridge NSData *)dataToSign;
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    const EVP_MD *md = EVP_sha256();
    size_t sigLen = 0;
    unsigned char *sig = NULL;
    NSData *resultData = nil;

    if(!mdctx) return NULL;

    if(EVP_DigestSignInit(mdctx, NULL, md, NULL, key) > 0) {
        if(EVP_DigestSignUpdate(mdctx, [msg bytes], [msg length]) > 0) {
             if(EVP_DigestSignFinal(mdctx, NULL, &sigLen) > 0) {
                 sig = OPENSSL_malloc(sigLen);
                 if(sig && EVP_DigestSignFinal(mdctx, sig, &sigLen) > 0) {
                     resultData = [NSData dataWithBytes:sig length:sigLen];
                 }
                 if(sig) OPENSSL_free(sig);
             }
        }
    }
    EVP_MD_CTX_free(mdctx);
    
    if (resultData) {
        return (__bridge_retained CFDataRef)resultData;
    }
    return NULL;
}

int SecRandomCopyBytes(const void *rnd, size_t count, void *bytes) {
    if (RAND_bytes(bytes, (int)count) == 1) {
        return 0; // Success
    }
    return -1; // Fail
}

// Trust Shim (Minimal)
CFIndex SecTrustGetCertificateCount(SecTrustRef trust) { return 0; }
SecCertificateRef SecTrustGetCertificateAtIndex(SecTrustRef trust, CFIndex ix) { return NULL; }
SecKeyRef SecTrustCopyKey(SecTrustRef trust) { return NULL; }
SecPolicyRef SecPolicyCreateBasicX509() { return NULL; }
OSStatus SecTrustCreateWithCertificates(CFTypeRef certificates, CFTypeRef policies, SecTrustRef *trust) { return errSecSuccess; }
OSStatus SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result) { return errSecSuccess; }

// CoreFoundation Shims
void CFRelease(CFTypeRef cf) {
    if (cf) {
        [(id)cf release];
    }
}

void CFRunLoopRun(void) {
    [[NSRunLoop currentRunLoop] run];
}

#endif

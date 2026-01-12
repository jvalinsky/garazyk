#ifndef Security_Compat_h
#define Security_Compat_h

#if !defined(__APPLE__)

#import <Foundation/Foundation.h>
#import <stdint.h>

// Forward declare OpenSSL types
typedef struct evp_pkey_st EVP_PKEY;

// Primitive types
typedef int32_t OSStatus;
typedef long CFIndex;

// CF types
#ifndef CFDictionaryRef
typedef const void * CFDictionaryRef;
#endif

#ifndef CFDataRef
typedef const void * CFDataRef;
#endif

#ifndef CFErrorRef
typedef const void * CFErrorRef;
#endif

#ifndef CFTypeRef
typedef const void * CFTypeRef;
#endif

// Add generic CF functions if missing
void CFRelease(CFTypeRef cf);
CFTypeRef CFRetain(CFTypeRef cf);

#ifndef SecTrustRef
typedef const void * SecTrustRef;
#endif

#ifndef SecCertificateRef
typedef const void * SecCertificateRef;
#endif

#ifndef SecPolicyRef
typedef const void * SecPolicyRef;
#endif

#ifndef SecKeyRef
typedef EVP_PKEY* SecKeyRef;
#endif

// Attribute Constants
extern const void * kSecAttrKeyType;
extern const void * kSecAttrKeyTypeRSA;
extern const void * kSecAttrKeyTypeECSECPrimeRandom;
extern const void * kSecAttrKeySizeInBits;
extern const void * kSecAttrKeyClass;
extern const void * kSecAttrKeyClassPrivate;
extern const void * kSecAttrKeyClassPublic;
extern const void * kSecPrivateKeyAttrs;
extern const void * kSecAttrIsPermanent;
extern const void * kSecAttrApplicationTag;

// Algorithms
typedef const void * SecKeyAlgorithm;
extern const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureMessageX962SHA256;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;

// Error Codes
enum {
    errSecSuccess = 0,
    errSecItemNotFound = -25300,
    errSecAuthFailed = -25293,
    errSecDuplicateItem = -25299,
    errSecParam = -50
};

// Functions
SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef attributes, CFErrorRef *error);
SecKeyRef SecKeyCopyPublicKey(SecKeyRef key);
CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, CFErrorRef *error);
SecKeyRef SecKeyCreateWithData(CFDataRef keyData, CFDictionaryRef attributes, CFErrorRef *error);
BOOL SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef signedData, CFDataRef signature, CFErrorRef *error);
CFDataRef SecKeyCreateSignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef dataToSign, CFErrorRef *error);

// Random
int SecRandomCopyBytes(const void *rnd, size_t count, void *bytes);
extern const void * kSecRandomDefault;

// Keychain Constants
extern const void * kSecClass;
extern const void * kSecClassGenericPassword;
extern const void * kSecAttrService;
extern const void * kSecAttrAccount;
extern const void * kSecValueData;
extern const void * kSecReturnData;
extern const void * kSecMatchLimit;
extern const void * kSecMatchLimitOne;
extern const void * kSecValueRef;
extern const void * kSecAttrAccessible;
extern const void * kSecAttrAccessibleAfterFirstUnlock;

// Keychain Functions
OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result);
OSStatus SecItemDelete(CFDictionaryRef query);
OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result);

// Trust
// SecTrust functions need to be declared
typedef uint32_t SecTrustResultType;

CFIndex SecTrustGetCertificateCount(SecTrustRef trust);
SecCertificateRef SecTrustGetCertificateAtIndex(SecTrustRef trust, CFIndex ix);
// SecTrustCopyKey returns the public key
SecKeyRef SecTrustCopyKey(SecTrustRef trust);
SecPolicyRef SecPolicyCreateBasicX509();
OSStatus SecTrustCreateWithCertificates(CFTypeRef certificates, CFTypeRef policies, SecTrustRef *trust);
OSStatus SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result);

#endif // !defined(__APPLE__)

#endif /* Security_Compat_h */

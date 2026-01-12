#ifndef Security_Compat_h
#define Security_Compat_h

#if !defined(__APPLE__)

#import <Foundation/Foundation.h>
#import <stdint.h>

typedef int32_t OSStatus;
// CFTypeRef is usually id or void* in GNUstep/CoreFoundation. 
// In GNUstep Base, many CF types are toll-free bridged or just typedefs.
// If CFTypeRef is not defined, we can define it.
#if !defined(CFTypeRef)
typedef const void * CFTypeRef;
#endif

// Add specific CF types if needed for stricter typing or just use id/void*
#if !defined(CFDictionaryRef)
typedef const struct __CFDictionary * CFDictionaryRef;
#endif

enum {
    errSecSuccess = 0,
    errSecItemNotFound = -25300,
    errSecAuthFailed = -25293,
    errSecDuplicateItem = -25299
};
/*
 * GNUstep Security Compatibility Shim
 * Maps Apple Security Framework APIs to OpenSSL
 */

typedef EVP_PKEY* SecKeyRef;
// Duplicate definition removed
// typedef const void* CFDictionaryRef; 

typedef const void* CFDataRef;
typedef const void* CFErrorRef;
typedef const void* SecTrustRef; // Added SecTrustRef

// Attribute Constants
extern const void * kSecAttrKeyType;
extern const void * kSecAttrKeyTypeRSA; // Added RSA
extern const void * kSecAttrKeyTypeECSECPrimeRandom;
extern const void * kSecAttrKeySizeInBits;

// Algorithms
typedef const void * SecKeyAlgorithm;
extern const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureMessageX962SHA256;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256; // Added RSA Algo

// Functions
SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef attributes, CFErrorRef *error);
SecKeyRef SecKeyCopyPublicKey(SecKeyRef key);
NSData * SecKeyCopyExternalRepresentation(SecKeyRef key, CFErrorRef *error);
SecKeyRef SecKeyCreateWithData(CFDataRef keyData, CFDictionaryRef attributes, CFErrorRef *error);
BOOL SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef signedData, CFDataRef signature, CFErrorRef *error);

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

#endif // !defined(__APPLE__)

#endif /* Security_Compat_h */

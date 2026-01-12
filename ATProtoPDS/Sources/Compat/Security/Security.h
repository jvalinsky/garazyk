#ifndef Security_Compat_h
#define Security_Compat_h

#if !defined(__APPLE__)

#import <Foundation/Foundation.h>
#include <openssl/evp.h>
#include <openssl/err.h>
#include <openssl/pem.h>

/*
 * GNUstep Security Compatibility Shim
 * Maps Apple Security Framework APIs to OpenSSL
 */

typedef EVP_PKEY* SecKeyRef;
typedef const void* CFDictionaryRef; // Simplified for shim
typedef const void* CFDataRef;
typedef const void* CFErrorRef;

// Attribute Constants
extern const void * kSecAttrKeyType;
extern const void * kSecAttrKeyTypeECSECPrimeRandom;
extern const void * kSecAttrKeySizeInBits;

// Algorithms
typedef const void * SecKeyAlgorithm;
extern const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureMessageX962SHA256;

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

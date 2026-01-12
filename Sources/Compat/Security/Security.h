#ifndef Security_h
#define Security_h

#if defined(__APPLE__)
#import <Security/Security.h>
#else
#include <stdlib.h>
#include <stdint.h>

#define kSecRandomDefault 0
#define errSecSuccess 0

typedef int32_t OSStatus;

typedef struct __CFType *CFTypeRef;
typedef struct __CFDictionary *CFDictionaryRef;
typedef struct __CFString *CFStringRef;
typedef struct __CFData *CFDataRef;
typedef struct __CFBoolean *CFBooleanRef;
typedef struct __CFAllocator *CFAllocatorRef;
typedef struct __CFError *CFErrorRef;

typedef CFTypeRef CFBridgingRelease(CFTypeRef cf);
typedef CFTypeRef CFRetain(CFTypeRef cf);
typedef void CFRelease(CFTypeRef cf);

static inline int SecRandomCopyBytes(int *drbg, size_t count, void *bytes) {
    (void)drbg;
    arc4random_buf(bytes, count);
    return 0;
}

typedef struct __SecKey *SecKeyRef;
typedef SecKeyRef SecKeyRef;
typedef const struct SecKeyAlgorithm *SecKeyAlgorithm;

static inline SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef parameters, OSStatus *error) {
    (void)parameters;
    (void)error;
    return NULL;
}

static inline CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, OSStatus *error) {
    (void)key;
    (void)error;
    return NULL;
}

#define kSecKeyAlgorithmRSASignatureMessagePSSSHA256 ((SecKeyAlgorithm)0)
#define kSecKeyAlgorithmECDSASignatureRFC6979SHA256 ((SecKeyAlgorithm)0)
#define kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256 ((SecKeyAlgorithm)0)

#define kSecAttrKeyType ((CFStringRef)0)
#define kSecAttrKeyTypeRSA ((CFStringRef)1)
#define kSecAttrKeyTypeECSECPrimeRandom ((CFStringRef)2)

#endif

#endif /* Security_h */

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

static inline CFTypeRef CFBridgingRelease(CFTypeRef cf) {
    (void)cf;
    return NULL;
}

static inline CFTypeRef CFRetain(CFTypeRef cf) {
    return cf;
}

static inline void CFRelease(CFTypeRef cf) {
    (void)cf;
}

#define kCFBooleanTrue ((CFBooleanRef)1)
#define kCFBooleanFalse ((CFBooleanRef)0)

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
    return (SecKeyRef)NULL;
}

static inline CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, OSStatus *error) {
    (void)key;
    (void)error;
    return NULL;
}

static inline SecKeyRef SecKeyCopyPublicKey(SecKeyRef key) {
    (void)key;
    return (SecKeyRef)NULL;
}

static inline SecKeyRef SecKeyCreateWithData(CFDataRef keyData, CFDictionaryRef attributes, OSStatus *error) {
    (void)keyData;
    (void)attributes;
    (void)error;
    return (SecKeyRef)NULL;
}

static inline CFDataRef SecKeyCreateSignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef dataToSign, OSStatus *error) {
    (void)key;
    (void)algorithm;
    (void)dataToSign;
    (void)error;
    return NULL;
}

static inline BOOL SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef signedData, CFDataRef signature, OSStatus *error) {
    (void)key;
    (void)algorithm;
    (void)signedData;
    (void)signature;
    (void)error;
    return NO;
}

#define kSecKeyAlgorithmRSASignatureMessagePSSSHA256 ((SecKeyAlgorithm)0)
#define kSecKeyAlgorithmECDSASignatureRFC6979SHA256 ((SecKeyAlgorithm)0)
#define kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256 ((SecKeyAlgorithm)0)
#define kSecKeyAlgorithmECDSASignatureMessageX962SHA256 ((SecKeyAlgorithm)0)

#define kSecAttrKeyType ((CFStringRef)0)
#define kSecAttrKeyTypeRSA ((CFStringRef)1)
#define kSecAttrKeyTypeECSECPrimeRandom ((CFStringRef)2)
#define kSecAttrKeySizeInBits ((CFStringRef)3)
#define kSecAttrKeyClass ((CFStringRef)4)
#define kSecAttrKeyClassPrivate ((CFStringRef)5)
#define kSecAttrKeyClassPublic ((CFStringRef)6)
#define kSecPrivateKeyAttrs ((CFStringRef)7)
#define kSecAttrIsPermanent ((CFStringRef)8)
#define kSecClass ((CFStringRef)9)
#define kSecClassKey ((CFStringRef)10)
#define kSecClassGenericPassword ((CFStringRef)11)
#define errSecItemNotFound (-25300)

#endif

#endif /* Security_h */

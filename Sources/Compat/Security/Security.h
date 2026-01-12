#ifndef Security_h
#define Security_h

#if defined(__APPLE__)
#import <Security/Security.h>
#else
#include <stdlib.h>
#include <stdint.h>

typedef uint8_t UInt8;

#define kSecRandomDefault 0
#define errSecSuccess 0

typedef int32_t OSStatus;

typedef struct __CFType *CFTypeRef;
typedef struct __CFDictionary *CFDictionaryRef;
typedef struct __CFDictionary *CFMutableDictionaryRef;
typedef struct __CFString *CFStringRef;
typedef struct __CFData *CFDataRef;
typedef struct __CFBoolean *CFBooleanRef;
typedef struct __CFAllocator *CFAllocatorRef;
typedef struct __CFError *CFErrorRef;
typedef struct __CFHost *CFHostRef;
typedef struct __CFArray *CFArrayRef;
typedef struct __CFData *CFDataRef;

typedef unsigned char Boolean;

typedef int32_t CFStreamError;
typedef int CFHostInfoType;

#define kCFHostAddresses 0

// CFSwapInt* functions - byte swapping utilities
static inline uint16_t CFSwapInt16BigToHost(uint16_t arg) {
#if defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 8))
    return __builtin_bswap16(arg);
#else
    return ((arg & 0x00FFU) << 8) | ((arg & 0xFF00U) >> 8);
#endif
}

static inline uint32_t CFSwapInt32BigToHost(uint32_t arg) {
    return __builtin_bswap32(arg);
}

static inline uint64_t CFSwapInt64BigToHost(uint64_t arg) {
    return __builtin_bswap64(arg);
}

static inline uint16_t CFSwapInt16HostToBig(uint16_t arg) {
    return CFSwapInt16BigToHost(arg);
}

static inline uint32_t CFSwapInt32HostToBig(uint32_t arg) {
    return CFSwapInt32BigToHost(arg);
}

static inline uint64_t CFSwapInt64HostToBig(uint64_t arg) {
    return CFSwapInt64BigToHost(arg);
}

typedef int64_t CFIndex;
typedef uint64_t CFHashCode;

typedef struct {
    CFIndex version;
    void (*retain)(CFAllocatorRef, const void *);
    void (*release)(CFAllocatorRef, void *);
    CFStringRef (*copyDescription)(const void *);
    bool (*equal)(const void *, const void *);
    CFHashCode (*hash)(const void *);
} CFDictionaryKeyCallBacks;

typedef struct {
    CFIndex version;
    void (*retain)(CFAllocatorRef, const void *);
    void (*release)(CFAllocatorRef, void *);
    CFStringRef (*copyDescription)(const void *);
    bool (*equal)(const void *, const void *);
} CFDictionaryValueCallBacks;

#define kCFAllocatorDefault ((CFAllocatorRef)0)

static const CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks = {0, NULL, NULL, NULL, NULL, NULL};

static inline CFDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef allocator, CFIndex capacity, const CFDictionaryKeyCallBacks *keyCallBacks, const CFDictionaryValueCallBacks *valueCallBacks) {
    (void)allocator;
    (void)capacity;
    (void)keyCallBacks;
    (void)valueCallBacks;
    return (CFDictionaryRef)malloc(sizeof(void *) * 100);
}

static inline void CFDictionarySetValue(CFDictionaryRef theDict, const void *key, const void *value) {
    (void)theDict;
    (void)key;
    (void)value;
}

static inline CFIndex CFDictionaryGetCount(CFDictionaryRef theDict) {
    (void)theDict;
    return 0;
}

static inline const void *CFDictionaryGetValue(CFDictionaryRef theDict, const void *key) {
    (void)theDict;
    (void)key;
    return NULL;
}

static inline void CFDictionaryRemoveValue(CFDictionaryRef theDict, const void *key) {
    (void)theDict;
    (void)key;
}

static inline void CFDictionaryGetKeysAndValues(CFDictionaryRef theDict, const void **keys, const void **values) {
    (void)theDict;
    (void)keys;
    (void)values;
}

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

static inline CFHostRef CFHostCreateWithName(CFAllocatorRef allocator, CFStringRef hostname) {
    (void)allocator;
    (void)hostname;
    return (CFHostRef)malloc(sizeof(void *));
}

static inline Boolean CFHostStartInfoResolution(CFHostRef host, CFHostInfoType info, CFStreamError *error) {
    (void)host;
    (void)info;
    (void)error;
    return false;
}

static inline CFArrayRef CFHostGetAddressing(CFHostRef host, Boolean *hasName) {
    (void)host;
    (void)hasName;
    return (CFArrayRef)malloc(sizeof(void *));
}

static inline CFIndex CFArrayGetCount(CFArrayRef theArray) {
    (void)theArray;
    return 0;
}

static inline const void *CFArrayGetValueAtIndex(CFArrayRef theArray, CFIndex idx) {
    (void)theArray;
    (void)idx;
    return NULL;
}

static inline const UInt8 *CFDataGetBytePtr(CFDataRef theData) {
    (void)theData;
    return NULL;
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
#define kSecAttrService ((CFStringRef)12)
#define kSecAttrAccount ((CFStringRef)13)
#define kSecAttrAccessGroup ((CFStringRef)14)
#define kSecAttrAccessible ((CFStringRef)15)
#define kSecAttrAccessibleAfterFirstUnlock ((CFStringRef)16)
#define kSecReturnRef ((CFStringRef)17)
#define kSecValueRef ((CFStringRef)18)
#define kSecClass ((CFStringRef)9)
#define kSecClassKey ((CFStringRef)10)
#define kSecClassGenericPassword ((CFStringRef)11)
#define errSecItemNotFound (-25300)

static inline OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    (void)query;
    (void)result;
    return errSecItemNotFound;
}

static inline OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    (void)attributes;
    (void)result;
    return errSecSuccess;
}

static inline OSStatus SecItemDelete(CFDictionaryRef query) {
    (void)query;
    return errSecSuccess;
}

#endif

#endif /* Security_h */

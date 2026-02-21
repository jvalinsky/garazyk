#ifndef Security_h
#define Security_h

#if defined(__APPLE__)
#import <Security/Security.h>
#else
#include <stdlib.h>
#include <stdint.h>
#import <Foundation/Foundation.h>

// CF Types and stubs (restored for compatibility)
#ifndef CF_TYPES_DEFINED
#define CF_TYPES_DEFINED
typedef const void *CFTypeRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef struct __CFDictionary *CFMutableDictionaryRef;
typedef const struct __CFString *CFStringRef;
typedef const struct __CFData *CFDataRef;
typedef const struct __CFBoolean *CFBooleanRef;
typedef const struct __CFAllocator *CFAllocatorRef;
typedef const struct __CFError *CFErrorRef;
typedef const struct __CFArray *CFArrayRef;
typedef const struct __CFHost *CFHostRef;
typedef const struct __CFRunLoop *CFRunLoopRef;
typedef const struct __CFRunLoopMode *CFRunLoopModeRef;

typedef int32_t OSStatus;
typedef int32_t CFStreamError;
typedef int CFHostInfoType;
typedef unsigned char Boolean;
typedef int64_t CFIndex;

#define kCFHostAddresses 0
#define kCFAllocatorDefault ((CFAllocatorRef)0)
#define kCFBooleanTrue ((CFBooleanRef)1)
#define kCFBooleanFalse ((CFBooleanRef)0)
#define errSecSuccess 0
#define errSecItemNotFound (-25300)
#endif

// CFHost stubs for HandleResolver.m
static inline CFHostRef CFHostCreateWithName(CFAllocatorRef allocator, CFStringRef hostname) {
    (void)allocator;
    (void)hostname;
    return (CFHostRef)malloc(1);
}

static inline Boolean CFHostStartInfoResolution(CFHostRef host, CFHostInfoType info, CFStreamError *error) {
    (void)host; (void)info; (void)error;
    return false;
}

static inline CFArrayRef CFHostGetAddressing(CFHostRef host, Boolean *hasName) {
    (void)host; (void)hasName;
    return NULL;
}

static inline CFIndex CFArrayGetCount(CFArrayRef theArray) {
    return 0;
}

static inline const void *CFArrayGetValueAtIndex(CFArrayRef theArray, CFIndex idx) {
    return NULL;
}

static inline const uint8_t *CFDataGetBytePtr(CFDataRef theData) {
    return NULL;
}

static inline void CFRelease(CFTypeRef cf) {
    if (cf) free((void*)cf);
}

// Byte swapping
static inline uint32_t CFSwapInt32BigToHost(uint32_t arg) { return ntohl(arg); }
static inline uint16_t CFSwapInt16BigToHost(uint16_t arg) { return ntohs(arg); }

// Import new modular headers
#import "SecRandom.h"
#import "SecKey.h"
#import "SecItem.h"

#endif

#endif /* Security_h */

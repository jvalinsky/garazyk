// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef Security_h
#define Security_h

#if defined(__APPLE__)
#import <Security/Security.h>
#else
#include <stdlib.h>
#include <stdint.h>
#include <arpa/inet.h>

// Import CF types FIRST (no Foundation dependency)
#import "../CoreFoundation/CFTypes.h"

// Then import Foundation for other needs
#import <Foundation/Foundation.h>

// Import CFByteOrder for byte swapping
#import "../CoreFoundation/CFByteOrder.h"

typedef uint8_t UInt8;

// CF Types not yet in CFBase.h
typedef const struct __CFHost *CFHostRef;
typedef const struct __CFRunLoop *CFRunLoopRef;
typedef const struct __CFRunLoopMode *CFRunLoopModeRef;

typedef int32_t OSStatus;
typedef int32_t CFStreamError;
typedef int CFHostInfoType;

// SecKeyAlgorithm is just a CFStringRef
typedef CFStringRef SecKeyAlgorithm;

// CFNumber types
typedef CFIndex CFNumberType;
enum {
    kCFNumberSInt8Type = 1,
    kCFNumberSInt16Type = 2,
    kCFNumberSInt32Type = 3,
    kCFNumberSInt64Type = 4,
    kCFNumberFloat32Type = 5,
    kCFNumberFloat64Type = 6,
    kCFNumberCharType = 7,
    kCFNumberShortType = 8,
    kCFNumberIntType = 9,
    kCFNumberLongType = 10,
    kCFNumberLongLongType = 11,
    kCFNumberFloatType = 12,
    kCFNumberDoubleType = 13,
    kCFNumberCFIndexType = 14,
    kCFNumberNSIntegerType = 15,
    kCFNumberCGFloatType = 16
};
typedef const struct __CFNumber *CFNumberRef;

#define kCFHostAddresses 0
#define errSecSuccess 0
#define errSecItemNotFound (-25300)

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
    if (theArray == NULL) return 0;
    NSArray *arr = (__bridge NSArray *)theArray;
    return [arr count];
}

static inline const void *CFArrayGetValueAtIndex(CFArrayRef theArray, CFIndex idx) {
    if (theArray == NULL) return NULL;
    NSArray *arr = (__bridge NSArray *)theArray;
    return (__bridge const void *)[arr objectAtIndex:idx];
}

static inline const uint8_t *CFDataGetBytePtr(CFDataRef theData) {
    if (theData == NULL) return NULL;
    NSData *data = (__bridge NSData *)theData;
    return [data bytes];
}

static inline CFNumberType CFNumberGetType(CFNumberRef number) {
    (void)number;
    return kCFNumberDoubleType;
}

// Import new modular headers
#import "SecRandom.h"
#import "SecKey.h"
#import "SecItem.h"
#import "SecAccessControl.h"

#endif

#endif /* Security_h */

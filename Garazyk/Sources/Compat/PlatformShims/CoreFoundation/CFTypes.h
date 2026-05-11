// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef CFTypes_h
#define CFTypes_h

// Basic CF types - must be defined before importing Foundation
// to avoid circular dependencies

#include <stdint.h>
#include <stddef.h>

#if defined(__APPLE__)
#include <CoreFoundation/CFBase.h>
#else

// CFIndex type
#ifndef CFIndex
typedef long CFIndex;
#endif

// Boolean type
#ifndef Boolean
typedef unsigned char Boolean;
#endif

// CFTypeID - unique identifier for each CF type
typedef uint64_t CFTypeID;

// CFTypeRef - generic reference to any CF object (toll-free bridged with ARC)
typedef const void *CFTypeRef;

// CFAllocatorRef
typedef const struct __CFAllocator *CFAllocatorRef;

// Core Foundation types (toll-free bridged with Objective-C)
typedef const struct __CFString *CFStringRef;
typedef const struct __CFData *CFDataRef;
typedef const struct __CFArray *CFArrayRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef const struct __CFBoolean *CFBooleanRef;
typedef const struct __CFNumber *CFNumberRef;
typedef const struct __CFError *CFErrorRef;
typedef struct __CFDictionary *CFMutableDictionaryRef;

// CF Bridging macros for ARC
#ifndef CFBridgingRelease
#define CFBridgingRelease(x) ((__bridge_transfer id)(x))
#endif
#ifndef CFBridgingRetain
#define CFBridgingRetain(x) ((__bridge_retained CFTypeRef)(x))
#endif

// CFAllocator constants
#define kCFAllocatorDefault ((CFAllocatorRef)0)
#define kCFAllocatorSystemDefault ((CFAllocatorRef)0)
#define kCFAllocatorMalloc ((CFAllocatorRef)0)
#define kCFAllocatorMallocZone ((CFAllocatorRef)0)
#define kCFAllocatorNull ((CFAllocatorRef)0)

#endif // __APPLE__

#endif /* CFTypes_h */

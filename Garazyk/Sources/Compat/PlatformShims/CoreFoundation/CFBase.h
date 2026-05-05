#ifndef CFBase_h
#define CFBase_h

#include <stdint.h>

#if defined(__APPLE__)
#include <CoreFoundation/CFBase.h>
#else

// Import CFTypes FIRST (no Foundation dependency - defines CFStringRef, etc.)
#include "CFTypes.h"

// Then import Foundation for function implementations
#import <Foundation/Foundation.h>

#include "CFByteOrder.h"

// CFGetTypeID - returns type identifier for a CF object
static inline CFTypeID CFGetTypeID(CFTypeRef cf) {
    if (cf == NULL) return 0;
    
    // For toll-free bridged types, identify by NSObject class
    id obj = (__bridge id)cf;
    
    if ([obj isKindOfClass:[NSNumber class]]) {
        // NSNumber can be CFBoolean or CFNumber
        // CFBoolean is a special case of NSNumber for YES/NO
        NSNumber *num = (NSNumber *)obj;
        const char *type = [num objCType];
        if (type != NULL && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, "c") == 0 || strcmp(type, "B") == 0)) {
            return 3; // CFBoolean type ID
        }
        return 4; // CFNumber type ID
    }
    if ([obj isKindOfClass:[NSString class]]) return 5;  // CFString
    if ([obj isKindOfClass:[NSData class]]) return 6;     // CFData
    if ([obj isKindOfClass:[NSArray class]]) return 7;    // CFArray
    if ([obj isKindOfClass:[NSDictionary class]]) return 8; // CFDictionary
    if ([obj isKindOfClass:[NSDate class]]) return 9;     // CFDate
    if ([obj isKindOfClass:[NSError class]]) return 10;   // CFError
    
    return 0; // Unknown type
}

// CFBoolean type IDs
static inline CFTypeID CFBooleanGetTypeID(void) { return 3; }
static inline CFTypeID CFNumberGetTypeID(void) { return 4; }
static inline CFTypeID CFStringGetTypeID(void) { return 5; }
static inline CFTypeID CFDataGetTypeID(void) { return 6; }
static inline CFTypeID CFArrayGetTypeID(void) { return 7; }
static inline CFTypeID CFDictionaryGetTypeID(void) { return 8; }
static inline CFTypeID CFDateGetTypeID(void) { return 9; }
static inline CFTypeID CFErrorGetTypeID(void) { return 10; }

// CFBoolean constants (toll-free bridged with NSNumber)
extern const CFBooleanRef kCFBooleanTrue;
extern const CFBooleanRef kCFBooleanFalse;

// CFNull type
typedef const struct __CFNull *CFNullRef;
static inline CFTypeID CFNullGetTypeID(void) { return 1; }
extern const CFNullRef kCFNull;

// CFRetain/CFRelease (ARC-compatible - no-op since ARC handles memory)
static inline CFTypeRef CFRetain(CFTypeRef cf) {
    return cf; // ARC handles retention
}

static inline void CFRelease(CFTypeRef cf) {
    // ARC handles release - this is a no-op
    (void)cf;
}

// CFAutorelease - adds object to autorelease pool for deferred release
// Under ARC, explicit -autorelease is forbidden, so use objc_msgSend.
#ifndef __clang_major__
// Fallback for non-clang compilers
static inline CFTypeRef CFAutorelease(CFTypeRef cf) {
    if (cf == NULL) return NULL;
    id obj = (__bridge id)cf;
    return (__bridge CFTypeRef)[obj autorelease];
}
#elif __has_feature(objc_arc)
#include <objc/message.h>
static inline CFTypeRef CFAutorelease(CFTypeRef cf) {
    if (cf == NULL) return NULL;
    id obj = (__bridge id)cf;
    return (__bridge CFTypeRef)objc_msgSend(obj, sel_registerName("autorelease"));
}
#else
static inline CFTypeRef CFAutorelease(CFTypeRef cf) {
    if (cf == NULL) return NULL;
    id obj = (__bridge id)cf;
    return (__bridge CFTypeRef)[obj autorelease];
}
#endif

// CFGetRetainCount (not meaningful under ARC)
static inline CFIndex CFGetRetainCount(CFTypeRef cf) {
    if (cf == NULL) return 0;
    return 1; // ARC doesn't expose actual retain count
}

// CFAllocator constants
#define kCFAllocatorDefault ((CFAllocatorRef)0)
#define kCFAllocatorSystemDefault ((CFAllocatorRef)0)
#define kCFAllocatorMalloc ((CFAllocatorRef)0)
#define kCFAllocatorMallocZone ((CFAllocatorRef)0)
#define kCFAllocatorNull ((CFAllocatorRef)0)

// CFEqual
static inline Boolean CFEqual(CFTypeRef cf1, CFTypeRef cf2) {
    if (cf1 == cf2) return true;
    if (cf1 == NULL || cf2 == NULL) return false;
    id obj1 = (__bridge id)cf1;
    id obj2 = (__bridge id)cf2;
    return [obj1 isEqual:obj2];
}

// CFHash
static inline CFIndex CFHash(CFTypeRef cf) {
    if (cf == NULL) return 0;
    id obj = (__bridge id)cf;
    return [obj hash];
}

// CFCopyDescription
static inline CFStringRef CFCopyDescription(CFTypeRef cf) {
    if (cf == NULL) return (CFStringRef)@"(null)";
    id obj = (__bridge id)cf;
    return (__bridge CFStringRef)[obj description];
}

#endif // __APPLE__

#endif /* CFBase_h */

#ifndef CoreFoundation_h
#define CoreFoundation_h

#if defined(__APPLE__)
#import <CoreFoundation/CoreFoundation.h>
#import <CFNetwork/CFNetwork.h>
#else
// On Linux/GNUstep, we provide compatibility implementations

// Import CF types FIRST (no Foundation dependency - defines CFStringRef, etc.)
#import "CFTypes.h"

// Then import CF base (imports Foundation internally)
#import "CFBase.h"
#import "CFByteOrder.h"

// Then import CFNetwork (depends on CF types and Security)
#import "CFNetwork.h"

// CFRange
typedef struct {
    CFIndex location;
    CFIndex length;
} CFRange;

static inline CFRange CFRangeMake(CFIndex loc, CFIndex len) {
    CFRange r;
    r.location = loc;
    r.length = len;
    return r;
}

#endif

#endif /* CoreFoundation_h */

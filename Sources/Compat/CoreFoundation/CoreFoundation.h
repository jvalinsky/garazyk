#ifndef CoreFoundation_h
#define CoreFoundation_h

#if defined(__APPLE__)
#import <CoreFoundation/CoreFoundation.h>
#import <CFNetwork/CFNetwork.h>
#else
// On Linux/GNUstep, we provide compatibility implementations
#import <Foundation/Foundation.h>
#import "Security/Security.h"
#import "CoreFoundation/CFNetwork.h"

// CFIndex type (if not already defined)
#ifndef CFIndex
typedef long CFIndex;
#endif

#endif

#endif /* CoreFoundation_h */

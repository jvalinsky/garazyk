#ifndef Security_h
#define Security_h

#if defined(__APPLE__)
#import <Security/Security.h>
#else
// GNUstep compatibility - SecKeyRef is just a pointer to an opaque struct
typedef struct __SecKey *SecKeyRef;
#endif

#endif /* Security_h */

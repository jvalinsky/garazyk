#ifndef Security_h
#define Security_h

#ifdef __APPLE__
#import <Security/Security.h>
#else
#import "SecRandom.h"
#endif

#endif /* Security_h */

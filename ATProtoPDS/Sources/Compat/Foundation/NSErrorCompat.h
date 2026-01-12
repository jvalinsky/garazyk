#ifndef NSErrorCompat_h
#define NSErrorCompat_h

#ifdef __APPLE__
#import <Foundation/Foundation.h>
#else
#import <GNUstepBase/NSError+GNUstepBase.h>
#endif

#endif /* NSErrorCompat_h */

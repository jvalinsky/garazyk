// SecItem.h stub for GNUstep/Linux
// Includes the main Security.h which has keychain stubs
#ifndef SEC_ITEM_H
#define SEC_ITEM_H

#if defined(__APPLE__)
#import <Security/SecItem.h>
#else
#import <Security/Security.h>
#endif

#endif // SEC_ITEM_H

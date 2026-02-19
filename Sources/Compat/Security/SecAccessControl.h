// SecAccessControl stub for GNUstep/Linux
#ifndef SEC_ACCESS_CONTROL_H
#define SEC_ACCESS_CONTROL_H

#if defined(__APPLE__)
#import <Security/SecAccessControl.h>
#else

#import <Security/Security.h>

typedef struct __SecAccessControl *SecAccessControlRef;

typedef NS_OPTIONS(CFIndex, SecAccessControlCreateFlags) {
    kSecAccessControlUserPresence = 1 << 0,
    kSecAccessControlBiometryAny = 1 << 1,
    kSecAccessControlBiometryCurrentSet = 1 << 3,
    kSecAccessControlDevicePasscode = 1 << 4,
    kSecAccessControlOr = 1 << 14,
    kSecAccessControlAnd = 1 << 15,
    kSecAccessControlPrivateKeyUsage = 1 << 30,
    kSecAccessControlApplicationPassword = 1 << 31
};

static inline SecAccessControlRef SecAccessControlCreateWithFlags(
    CFAllocatorRef allocator,
    CFTypeRef protection,
    SecAccessControlCreateFlags flags,
    CFErrorRef *error) {
    (void)allocator;
    (void)protection;
    (void)flags;
    (void)error;
    return NULL;
}

#define kSecAttrAccessControl ((CFStringRef)99)
#define kSecUseOperationPrompt ((CFStringRef)100)
#define kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly ((CFStringRef)101)

#endif // __APPLE__

#endif // SEC_ACCESS_CONTROL_H

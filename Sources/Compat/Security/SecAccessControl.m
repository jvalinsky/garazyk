#include "SecAccessControl.h"

#if !defined(__APPLE__)

const CFStringRef kSecAttrAccessibleWhenUnlocked = (CFStringRef)@"kSecAttrAccessibleWhenUnlocked";
const CFStringRef kSecAttrAccessibleAfterFirstUnlock = (CFStringRef)@"kSecAttrAccessibleAfterFirstUnlock";
const CFStringRef kSecAttrAccessibleAlways = (CFStringRef)@"kSecAttrAccessibleAlways";
const CFStringRef kSecAttrAccessibleWhenUnlockedThisDeviceOnly = (CFStringRef)@"kSecAttrAccessibleWhenUnlockedThisDeviceOnly";
const CFStringRef kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly = (CFStringRef)@"kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly";
const CFStringRef kSecAttrAccessibleAlwaysThisDeviceOnly = (CFStringRef)@"kSecAttrAccessibleAlwaysThisDeviceOnly";
const CFStringRef kSecAttrAccessControl = (CFStringRef)@"kSecAttrAccessControl";
const CFStringRef kSecUseAuthenticationContext = (CFStringRef)@"kSecUseAuthenticationContext";

SecAccessControlRef SecAccessControlCreateWithFlags(CFAllocatorRef allocator,
                                                    CFTypeRef protection,
                                                    SecAccessControlCreateFlags flags,
                                                    CFErrorRef *error) {
    // On Linux, return NULL as biometric auth is not available
    if (error) {
        NSError *nsError = [NSError errorWithDomain:@"com.apple.security"
                                              code:-1
                                          userInfo:nil];
        *error = (__bridge_retained CFErrorRef)nsError;
    }
    return NULL;
}

#endif

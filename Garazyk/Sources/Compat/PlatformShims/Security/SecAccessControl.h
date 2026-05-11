// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef SecAccessControl_h
#define SecAccessControl_h

#if defined(__APPLE__)
#import <Security/SecAccessControl.h>
#else

#import <Foundation/Foundation.h>

typedef CFTypeRef SecAccessControlRef;

typedef uint32_t SecAccessControlCreateFlags;

enum {
    kSecAccessControlUserPresence = 1U << 0,
    kSecAccessControlBiometryAny = 1U << 1,
    kSecAccessControlBiometryCurrentSet = 1U << 3,
    kSecAccessControlDevicePasscode = 1U << 4,
    kSecAccessControlWatch = 1U << 5,
    kSecAccessControlOr = 1U << 14,
    kSecAccessControlAnd = 1U << 15,
    kSecAccessControlPrivateKeyUsage = 1U << 16,
    kSecAccessControlApplicationPassword = 1U << 17,
};

static const SecAccessControlCreateFlags kSecAccessControlBiometryAnySet = kSecAccessControlBiometryAny;

extern const CFStringRef kSecAttrAccessibleWhenUnlocked;
extern const CFStringRef kSecAttrAccessibleAfterFirstUnlock;
extern const CFStringRef kSecAttrAccessibleAlways;
extern const CFStringRef kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
extern const CFStringRef kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
extern const CFStringRef kSecAttrAccessibleAlwaysThisDeviceOnly;
extern const CFStringRef kSecAttrAccessControl;
extern const CFStringRef kSecUseAuthenticationContext;

#define errSecDuplicateItem -25299

SecAccessControlRef SecAccessControlCreateWithFlags(CFAllocatorRef allocator,
                                                    CFTypeRef protection,
                                                    SecAccessControlCreateFlags flags,
                                                    CFErrorRef *error);

#endif

#endif /* SecAccessControl_h */

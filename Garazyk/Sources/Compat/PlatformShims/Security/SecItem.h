// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file SecItem.h
 *
 * @brief Keychain items compatibility wrapper.
 *
 * Provides cross-platform wrapper for keychain item operations.
 * On macOS, uses Security framework. On Linux, uses encrypted file store.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef SecItem_h
#define SecItem_h

#import <Foundation/Foundation.h>

#ifdef __APPLE__
#import <Security/Security.h>
#else

// Basic types
typedef CFTypeRef SecKeychainItemRef;
typedef OSStatus SecOSStatus;

// Constants (simplified for Linux)
extern const CFStringRef kSecClass;
extern const CFStringRef kSecClassGenericPassword;
extern const CFStringRef kSecClassInternetPassword;
extern const CFStringRef kSecClassCertificate;
extern const CFStringRef kSecClassKey;
extern const CFStringRef kSecClassIdentity;

extern const CFStringRef kSecAttrService;
extern const CFStringRef kSecAttrAccount;
extern const CFStringRef kSecAttrGeneric;
extern const CFStringRef kSecAttrAccessGroup;
extern const CFStringRef kSecAttrLabel;
extern const CFStringRef kSecAttrComment;
extern const CFStringRef kSecAttrDescription;
extern const CFStringRef kSecAttrType;
extern const CFStringRef kSecAttrCreator;

extern const CFStringRef kSecValueData;
extern const CFStringRef kSecValueRef;
extern const CFStringRef kSecValuePersistentRef;

extern const CFStringRef kSecReturnData;
extern const CFStringRef kSecReturnAttributes;
extern const CFStringRef kSecReturnRef;
extern const CFStringRef kSecReturnPersistentRef;

extern const CFStringRef kSecMatchLimit;
extern const CFStringRef kSecMatchLimitOne;
extern const CFStringRef kSecMatchLimitAll;

extern const CFStringRef kSecAttrAccessible;

// Error codes
#define errSecAuthFailed -25293
#define errSecParam -50
#define errSecNotAvailable -4

// Functions
OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result);
OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result);
OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);
OSStatus SecItemDelete(CFDictionaryRef query);

#endif /* __APPLE__ */

#endif /* SecItem_h */

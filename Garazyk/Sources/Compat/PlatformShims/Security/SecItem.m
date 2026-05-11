// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file SecItem.m
 *
 * @brief SecItem operations implementation for Linux (SQLite-backed persistent store).
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "SecItem.h"
#import "SecItemLinuxStore.h"

#if !defined(__APPLE__)

// Constant definitions
const CFStringRef kSecClass = (CFStringRef)@"kSecClass";
const CFStringRef kSecClassGenericPassword = (CFStringRef)@"kSecClassGenericPassword";
const CFStringRef kSecClassInternetPassword = (CFStringRef)@"kSecClassInternetPassword";
const CFStringRef kSecClassCertificate = (CFStringRef)@"kSecClassCertificate";
const CFStringRef kSecClassKey = (CFStringRef)@"kSecClassKey";
const CFStringRef kSecClassIdentity = (CFStringRef)@"kSecClassIdentity";

const CFStringRef kSecAttrService = (CFStringRef)@"kSecAttrService";
const CFStringRef kSecAttrAccount = (CFStringRef)@"kSecAttrAccount";
const CFStringRef kSecAttrGeneric = (CFStringRef)@"kSecAttrGeneric";
const CFStringRef kSecAttrAccessGroup = (CFStringRef)@"kSecAttrAccessGroup";
const CFStringRef kSecAttrLabel = (CFStringRef)@"kSecAttrLabel";
const CFStringRef kSecAttrComment = (CFStringRef)@"kSecAttrComment";
const CFStringRef kSecAttrDescription = (CFStringRef)@"kSecAttrDescription";
const CFStringRef kSecAttrType = (CFStringRef)@"kSecAttrType";
const CFStringRef kSecAttrCreator = (CFStringRef)@"kSecAttrCreator";
const CFStringRef kSecAttrAccessible = (CFStringRef)@"kSecAttrAccessible";

const CFStringRef kSecValueData = (CFStringRef)@"kSecValueData";
const CFStringRef kSecValueRef = (CFStringRef)@"kSecValueRef";
const CFStringRef kSecValuePersistentRef = (CFStringRef)@"kSecValuePersistentRef";

const CFStringRef kSecReturnData = (CFStringRef)@"kSecReturnData";
const CFStringRef kSecReturnAttributes = (CFStringRef)@"kSecReturnAttributes";
const CFStringRef kSecReturnRef = (CFStringRef)@"kSecReturnRef";
const CFStringRef kSecReturnPersistentRef = (CFStringRef)@"kSecReturnPersistentRef";

const CFStringRef kSecMatchLimit = (CFStringRef)@"kSecMatchLimit";
const CFStringRef kSecMatchLimitOne = (CFStringRef)@"kSecMatchLimitOne";
const CFStringRef kSecMatchLimitAll = (CFStringRef)@"kSecMatchLimitAll";

OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSDictionary *attrs = (__bridge NSDictionary *)attributes;

    NSString *service = attrs[(__bridge NSString *)kSecAttrService];
    NSString *account = attrs[(__bridge NSString *)kSecAttrAccount];

    if (!service || !account) {
        return -50; // errSecParam
    }

    NSError *error = nil;
    BOOL success = [[SecItemLinuxStore sharedStore] addItemWithService:service
                                                               account:account
                                                            attributes:attrs
                                                                 error:&error];
    if (!success) {
        if ([error.domain isEqual:SecItemLinuxStoreErrorDomain] && error.code == -25299) {
            return -25299; // errSecDuplicateItem
        }
        return error ? (OSStatus)error.code : -50;
    }

    return 0; // errSecSuccess
}

OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSDictionary *q = (__bridge NSDictionary *)query;

    NSString *service = q[(__bridge NSString *)kSecAttrService];
    NSString *account = q[(__bridge NSString *)kSecAttrAccount];

    if (!service || !account) {
        return -25300; // errSecItemNotFound
    }

    NSError *error = nil;
    NSDictionary *item = [[SecItemLinuxStore sharedStore] itemWithService:service
                                                                  account:account
                                                                    error:&error];
    if (!item) {
        return -25300; // errSecItemNotFound
    }

    if (result) {
        if ([q[(__bridge NSString *)kSecReturnData] boolValue]) {
            *result = (__bridge_retained CFTypeRef)item[(__bridge NSString *)kSecValueData];
        } else if ([q[(__bridge NSString *)kSecReturnRef] boolValue]) {
            *result = (__bridge_retained CFTypeRef)item;
        } else if ([q[(__bridge NSString *)kSecReturnAttributes] boolValue]) {
            *result = (__bridge_retained CFTypeRef)item;
        } else {
            *result = NULL;
        }
    }

    return 0;
}

OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSDictionary *q = (__bridge NSDictionary *)query;
    NSDictionary *update = (__bridge NSDictionary *)attributesToUpdate;

    NSString *service = q[(__bridge NSString *)kSecAttrService];
    NSString *account = q[(__bridge NSString *)kSecAttrAccount];

    if (!service || !account) return -25300;

    NSError *error = nil;
    BOOL success = [[SecItemLinuxStore sharedStore] updateItemWithService:service
                                                                  account:account
                                                        attributesToUpdate:update
                                                                    error:&error];
    return success ? 0 : -25300; // Return item not found if update fails
}

OSStatus SecItemDelete(CFDictionaryRef query) {
    NSDictionary *q = (__bridge NSDictionary *)query;

    NSString *service = q[(__bridge NSString *)kSecAttrService];
    NSString *account = q[(__bridge NSString *)kSecAttrAccount];

    if (!service || !account) return -25300;

    NSError *error = nil;
    BOOL success = [[SecItemLinuxStore sharedStore] deleteItemWithService:service
                                                                  account:account
                                                                    error:&error];
    return success ? 0 : -25300;
}

#endif

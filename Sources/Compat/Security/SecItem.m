/**
 * @file SecItem.m
 *
 * @brief SecItem operations implementation for Linux (Memory-based stub).
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "SecItem.h"

#if !defined(__APPLE__)

// Simple in-memory keychain for testing/stubbing
static NSMutableDictionary *gKeychain = nil;

static void InitKeychain(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gKeychain = [NSMutableDictionary dictionary];
    });
}

OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    InitKeychain();
    NSDictionary *attrs = (__bridge NSDictionary *)attributes;
    
    // Use kSecAttrService + kSecAttrAccount as key
    NSString *service = attrs[(__bridge NSString *)kSecAttrService];
    NSString *account = attrs[(__bridge NSString *)kSecAttrAccount];
    
    if (!service || !account) {
        return -50; // errSecParam
    }
    
    NSString *key = [NSString stringWithFormat:@"%@:%@", service, account];
    
    @synchronized(gKeychain) {
        if (gKeychain[key]) {
            return -25299; // errSecDuplicateItem
        }
        gKeychain[key] = attrs;
    }
    
    return 0; // errSecSuccess
}

OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    InitKeychain();
    NSDictionary *q = (__bridge NSDictionary *)query;
    
    NSString *service = q[(__bridge NSString *)kSecAttrService];
    NSString *account = q[(__bridge NSString *)kSecAttrAccount];
    
    // Handle kSecClassIdentity or generic queries
    // Simplified: only support service+account lookup
    
    if (!service || !account) {
        return -25300; // errSecItemNotFound
    }
    
    NSString *key = [NSString stringWithFormat:@"%@:%@", service, account];
    NSDictionary *item = nil;
    
    @synchronized(gKeychain) {
        item = gKeychain[key];
    }
    
    if (!item) {
        return -25300; // errSecItemNotFound
    }
    
    if (result) {
        if ([q[(__bridge NSString *)kSecReturnData] boolValue]) {
            *result = (__bridge_retained CFTypeRef)item[(__bridge NSString *)kSecValueData];
        } else if ([q[(__bridge NSString *)kSecReturnRef] boolValue]) {
            // Return persistent ref or object?
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
    InitKeychain();
    NSDictionary *q = (__bridge NSDictionary *)query;
    NSDictionary *update = (__bridge NSDictionary *)attributesToUpdate;
    
    NSString *service = q[(__bridge NSString *)kSecAttrService];
    NSString *account = q[(__bridge NSString *)kSecAttrAccount];
    
    if (!service || !account) return -25300;
    
    NSString *key = [NSString stringWithFormat:@"%@:%@", service, account];
    
    @synchronized(gKeychain) {
        NSMutableDictionary *item = [gKeychain[key] mutableCopy];
        if (!item) return -25300;
        
        [item addEntriesFromDictionary:update];
        gKeychain[key] = item;
    }
    return 0;
}

OSStatus SecItemDelete(CFDictionaryRef query) {
    InitKeychain();
    NSDictionary *q = (__bridge NSDictionary *)query;
    
    NSString *service = q[(__bridge NSString *)kSecAttrService];
    NSString *account = q[(__bridge NSString *)kSecAttrAccount];
    
    if (!service || !account) return -25300;
    
    NSString *key = [NSString stringWithFormat:@"%@:%@", service, account];
    
    @synchronized(gKeychain) {
        if (!gKeychain[key]) return -25300;
        [gKeychain removeObjectForKey:key];
    }
    
    return 0;
}

#endif

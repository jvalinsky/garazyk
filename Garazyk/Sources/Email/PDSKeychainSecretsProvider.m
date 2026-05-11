// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSKeychainSecretsProvider.h"
#import <Security/Security.h>

NSString *const PDSKeychainSecretsProviderErrorDomain = @"PDSKeychainSecretsProviderErrorDomain";

@interface PDSKeychainSecretsProvider ()

@property (nonatomic, copy, readwrite) NSString *service;

@end

@implementation PDSKeychainSecretsProvider

- (instancetype)init {
    return [self initWithService:@"com.atproto.pds.email"];
}

- (instancetype)initWithService:(NSString *)service {
    if (self = [super init]) {
        _service = [service copy];
    }
    return self;
}

- (nullable NSString *)secretForKey:(NSString *)key error:(NSError **)error {
    if (key.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSKeychainSecretsProviderErrorDomain
                                         code:PDSKeychainSecretsProviderErrorInvalidKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Key cannot be empty"}];
        }
        return nil;
    }
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.service,
        (__bridge id)kSecAttrAccount: key,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    
    CFDataRef dataRef = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&dataRef);
    
    if (status == errSecItemNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PDSKeychainSecretsProviderErrorDomain
                                         code:PDSKeychainSecretsProviderErrorItemNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Secret not found for key: %@", key]}];
        }
        return nil;
    }
    
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:PDSKeychainSecretsProviderErrorDomain
                                         code:PDSKeychainSecretsProviderErrorKeychainFailure
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Keychain error %d for key: %@", (int)status, key]}];
        }
        return nil;
    }
    
    NSData *data = (__bridge_transfer NSData *)dataRef;
    NSString *secret = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    return secret;
}

- (BOOL)storeSecret:(NSString *)secret forKey:(NSString *)key error:(NSError **)error {
    if (secret == nil || key == nil) {
        if (error) {
            *error = [NSError errorWithDomain:PDSKeychainSecretsProviderErrorDomain
                                         code:PDSKeychainSecretsProviderErrorInvalidInput
                                     userInfo:@{NSLocalizedDescriptionKey: @"Secret and key cannot be nil"}];
        }
        return NO;
    }
    
    if (key.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSKeychainSecretsProviderErrorDomain
                                         code:PDSKeychainSecretsProviderErrorInvalidInput
                                     userInfo:@{NSLocalizedDescriptionKey: @"Key cannot be empty"}];
        }
        return NO;
    }
    
    [self deleteSecretForKey:key error:NULL];
    
    NSData *secretData = [secret dataUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.service,
        (__bridge id)kSecAttrAccount: key,
        (__bridge id)kSecValueData: secretData
    };
    
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:PDSKeychainSecretsProviderErrorDomain
                                         code:PDSKeychainSecretsProviderErrorStorageFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to store secret for key: %@ (error %d)", key, (int)status]}];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)deleteSecretForKey:(NSString *)key error:(NSError **)error {
    if (key.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSKeychainSecretsProviderErrorDomain
                                         code:PDSKeychainSecretsProviderErrorInvalidKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Key cannot be empty"}];
        }
        return NO;
    }
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.service,
        (__bridge id)kSecAttrAccount: key
    };
    
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    
    if (status == errSecItemNotFound || status == errSecParam) {
        return YES;
    }
    
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:PDSKeychainSecretsProviderErrorDomain
                                         code:PDSKeychainSecretsProviderErrorDeletionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to delete secret for key: %@ (error %d)", key, (int)status]}];
        }
        return NO;
    }
    
    return YES;
}

@end

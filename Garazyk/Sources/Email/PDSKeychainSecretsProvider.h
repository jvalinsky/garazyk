// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSecretsProvider.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error codes returned by keychain-backed secret storage.
 */
typedef NS_ENUM(NSInteger, PDSKeychainSecretsProviderError) {
    /** The requested key is malformed or unsupported. */
    PDSKeychainSecretsProviderErrorInvalidKey = 1,
    /** No keychain item exists for the requested key. */
    PDSKeychainSecretsProviderErrorItemNotFound = 2,
    /** Security.framework returned a keychain failure. */
    PDSKeychainSecretsProviderErrorKeychainFailure = 3,
    /** A required input value was empty or invalid. */
    PDSKeychainSecretsProviderErrorInvalidInput = 4,
    /** The keychain item could not be stored. */
    PDSKeychainSecretsProviderErrorStorageFailed = 5,
    /** The keychain item could not be deleted. */
    PDSKeychainSecretsProviderErrorDeletionFailed = 6
};

/**
 * @abstract Stores provider secrets in the macOS keychain.
 */
@interface PDSKeychainSecretsProvider : NSObject <PDSSecretsProvider>

/** Keychain service name used for secret items. */
@property (nonatomic, copy, readonly) NSString *service;

/** Initializes the provider with a keychain service name. */
- (instancetype)initWithService:(NSString *)service NS_DESIGNATED_INITIALIZER;
/** Initializes the provider with the default keychain service name. */
- (instancetype)init;

/** Stores or replaces a secret for a logical key. */
- (BOOL)storeSecret:(NSString *)secret forKey:(NSString *)key error:(NSError **)error;
/** Deletes a stored secret for a logical key. */
- (BOOL)deleteSecretForKey:(NSString *)key error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

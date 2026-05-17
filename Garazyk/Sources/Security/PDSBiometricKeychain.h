// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PDSBiometricKeychainErrorDomain;

/**
 * @abstract Error codes returned by biometric keychain operations.
 */
typedef NS_ENUM(NSInteger, PDSBiometricKeychainError) {
    /** LocalAuthentication failed or the user did not authorize access. */
    PDSBiometricKeychainErrorAuthFailed = 2000,
    /** Biometric authentication is unavailable on this device. */
    PDSBiometricKeychainErrorBiometryNotAvailable,
    /** Biometric authentication is available but no biometric identity is enrolled. */
    PDSBiometricKeychainErrorBiometryNotEnrolled,
    /** The keychain access-control object could not be created. */
    PDSBiometricKeychainErrorAccessControlCreationFailed,
    /** A key already exists for the requested account. */
    PDSBiometricKeychainErrorKeyAlreadyExists,
    /** No key exists for the requested account. */
    PDSBiometricKeychainErrorKeyNotFound,
    /** Key material could not be encoded for storage. */
    PDSBiometricKeychainErrorEncodingFailed,
    /** Stored key material could not be decoded. */
    PDSBiometricKeychainErrorDecodingFailed,
    /** Stored keys use an older protection policy and must be upgraded. */
    PDSBiometricKeychainErrorUpgradeRequired,
};

/**
 * @abstract Stores account key material in the macOS keychain with optional biometric access control.
 */
@interface PDSBiometricKeychain : NSObject

/** Keychain service name used for stored items. */
@property (nonatomic, copy, readonly) NSString *serviceName;
/** Keychain access group used for stored items, when configured. */
@property (nonatomic, copy, readonly) NSString *accessGroup;
/** Whether stored keys require biometric authentication for retrieval. */
@property (nonatomic, assign, readonly) BOOL useBiometrics;

/**
 * @abstract Returns the process-wide biometric keychain instance.
 */
+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Initializes a keychain wrapper with explicit storage settings.
 * @param serviceName Keychain service name for stored items.
 * @param accessGroup Optional keychain access group.
 * @param useBiometrics YES to require biometric authentication for protected keys.
 * @return An initialized keychain wrapper.
 */
- (instancetype)initWithServiceName:(NSString *)serviceName
                        accessGroup:(nullable NSString *)accessGroup
                      useBiometrics:(BOOL)useBiometrics NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Stores key material for an account.
 * @param keyData Raw key bytes to persist.
 * @param account Account identifier for the keychain item.
 * @param error Receives keychain or encoding failures.
 * @return YES when the key is stored.
 */
- (BOOL)storeKey:(NSData *)keyData
        forAccount:(NSString *)account
             error:(NSError **)error;

/**
 * @abstract Retrieves key material for an account.
 * @param account Account identifier for the keychain item.
 * @param error Receives authentication, keychain, or decoding failures.
 * @return Stored key bytes, or nil when unavailable.
 */
- (nullable NSData *)retrieveKeyForAccount:(NSString *)account
                                     error:(NSError **)error;

/**
 * @abstract Deletes stored key material for an account.
 * @param account Account identifier for the keychain item.
 * @param error Receives keychain deletion failures.
 * @return YES when the key is removed or no longer present.
 */
- (BOOL)deleteKeyForAccount:(NSString *)account
                      error:(NSError **)error;

/**
 * @abstract Checks whether key material exists for an account.
 * @param account Account identifier for the keychain item.
 * @return YES when a matching keychain item exists.
 */
- (BOOL)keyExistsForAccount:(NSString *)account;

/**
 * @abstract Creates a LocalAuthentication context suitable for key retrieval.
 * @param error Receives biometric availability or context creation failures.
 * @return Authentication context, or nil if biometric policy cannot be evaluated.
 */
- (nullable LAContext *)createAuthenticationContextWithError:(NSError **)error;

/**
 * @abstract Upgrades existing keychain items to the current protection policy.
 * @param accounts Account identifiers to migrate.
 * @param error Receives the first migration failure.
 * @return YES when all requested keys are upgraded.
 */
- (BOOL)upgradeExistingKeysWithAccounts:(NSArray<NSString *> *)accounts
                                  error:(NSError **)error;

/**
 * @abstract Returns whether biometric authentication can be used now.
 */
- (BOOL)isBiometryAvailable;

/**
 * @abstract Returns the current biometric type as a display-safe string.
 */
- (nullable NSString *)biometryTypeString;

@end

NS_ASSUME_NONNULL_END

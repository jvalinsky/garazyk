// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PDSBiometricKeychainErrorDomain;

typedef NS_ENUM(NSInteger, PDSBiometricKeychainError) {
    PDSBiometricKeychainErrorAuthFailed = 2000,
    PDSBiometricKeychainErrorBiometryNotAvailable,
    PDSBiometricKeychainErrorBiometryNotEnrolled,
    PDSBiometricKeychainErrorAccessControlCreationFailed,
    PDSBiometricKeychainErrorKeyAlreadyExists,
    PDSBiometricKeychainErrorKeyNotFound,
    PDSBiometricKeychainErrorEncodingFailed,
    PDSBiometricKeychainErrorDecodingFailed,
    PDSBiometricKeychainErrorUpgradeRequired,
};

@interface PDSBiometricKeychain : NSObject

@property (nonatomic, copy, readonly) NSString *serviceName;
@property (nonatomic, copy, readonly) NSString *accessGroup;
@property (nonatomic, assign, readonly) BOOL useBiometrics;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithServiceName:(NSString *)serviceName
                        accessGroup:(nullable NSString *)accessGroup
                      useBiometrics:(BOOL)useBiometrics NS_DESIGNATED_INITIALIZER;

- (BOOL)storeKey:(NSData *)keyData
        forAccount:(NSString *)account
             error:(NSError **)error;

- (nullable NSData *)retrieveKeyForAccount:(NSString *)account
                                     error:(NSError **)error;

- (BOOL)deleteKeyForAccount:(NSString *)account
                      error:(NSError **)error;

- (BOOL)keyExistsForAccount:(NSString *)account;

- (nullable LAContext *)createAuthenticationContextWithError:(NSError **)error;

- (BOOL)upgradeExistingKeysWithAccounts:(NSArray<NSString *> *)accounts
                                  error:(NSError **)error;

- (BOOL)isBiometryAvailable;

- (nullable NSString *)biometryTypeString;

@end

NS_ASSUME_NONNULL_END

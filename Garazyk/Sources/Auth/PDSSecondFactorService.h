// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabaseAccount;
@class PDSServiceDatabases;

extern NSString * const PDSSecondFactorErrorDomain;
extern NSString * const PDSSecondFactorATProtoErrorKey;

/**
 * @abstract Error codes returned by second-factor authentication checks.
 */
typedef NS_ENUM(NSInteger, PDSSecondFactorErrorCode) {
    /** The account requires a second factor before sign-in can complete. */
    PDSSecondFactorErrorRequired = 1,
    /** The supplied second-factor token is invalid. */
    PDSSecondFactorErrorInvalidToken,
    /** The supplied second-factor token has expired. */
    PDSSecondFactorErrorExpiredToken,
    /** Second-factor verification is unavailable. */
    PDSSecondFactorErrorUnavailable,
};

/**
 * @abstract Coordinates WebAuthn second-factor challenges for account sign-in.
 */
@interface PDSSecondFactorService : NSObject

/** Initializes the service with shared databases and expected WebAuthn origin. */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                                  origin:(NSString *)origin;

/** Returns whether an account requires second-factor authentication. */
- (BOOL)accountRequiresSecondFactor:(PDSDatabaseAccount *)account;

/** Verifies a previously issued second-factor token for an account. */
- (BOOL)verifyAuthFactorToken:(nullable NSString *)authFactorToken
                    forAccount:(PDSDatabaseAccount *)account
                         error:(NSError **)error;

/** Starts WebAuthn login for an account and returns challenge parameters. */
- (nullable NSDictionary *)beginWebAuthnLoginForAccount:(PDSDatabaseAccount *)account
                                                  error:(NSError **)error;

/** Completes WebAuthn login and returns an auth-factor token on success. */
- (nullable NSString *)completeWebAuthnLoginWithSessionID:(NSString *)sessionID
                                                assertion:(NSDictionary *)assertion
                                                 forAccount:(PDSDatabaseAccount *)account
                                                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSDatabaseAccount
 * 
 * @abstract Represents a PDS account record in the database.
 * 
 * @discussion This class models account data stored in the database, including
 * identity information (DID, handle, email), credentials (password hash, JWT tokens),
 * and metadata (creation time, invite status).
 * 
 * @see PDSDatabase (Accounts)
 */
/**
 * @abstract Represents an account row stored in the PDS database.
 */
@interface PDSDatabaseAccount : NSObject <PDSDatabaseModel>

/** The decentralized identifier (DID) for this account. */
@property (nonatomic, copy) NSString *did;

/** The handle (username) for this account. */
@property (nonatomic, copy) NSString *handle;

/** Optional email address for password recovery and notifications. */
@property (nonatomic, copy, nullable) NSString *email;

/** Bcrypt hash of the account password. */
@property (nonatomic, copy, nullable) NSData *passwordHash;

/** Salt used for password hashing. */
@property (nonatomic, copy, nullable) NSData *passwordSalt;

/** JWT access token for API authentication. */
@property (nonatomic, copy, nullable) NSData *accessJwt;

/** JWT refresh token for obtaining new access tokens. */
@property (nonatomic, copy, nullable) NSData *refreshJwt;

/** Account status (e.g., "active", "deactivated"). */
@property (nonatomic, copy) NSString *status;

/** Unix timestamp when the account was deactivated. */
@property (nonatomic, assign) NSTimeInterval deactivatedAt;

/** Unix timestamp when the account was created. */
@property (nonatomic, assign) NSTimeInterval createdAt;

/** Unix timestamp when the account was last updated. */
@property (nonatomic, assign) NSTimeInterval updatedAt;

/** Whether invite codes are enabled for this account. */
@property (nonatomic, assign) BOOL inviteEnabled;

/** Whether 2FA (TOTP/Passkey) is enabled. */
@property (nonatomic, assign) BOOL tfaEnabled;

/** Whether WebAuthn is enabled for this account. */
@property (nonatomic, assign) BOOL webauthnEnabled;

/** Encrypted TOTP secret or other 2FA secret data. */
@property (nonatomic, copy, nullable) NSData *tfaSecret;

/** JSON array of hashed recovery codes. */
@property (nonatomic, copy, nullable) NSData *recoveryCodes;

/** Age assurance level. */
@property (nonatomic, copy, nullable) NSString *ageAssurance;

/** Timestamp when age was verified. */
@property (nonatomic, copy, nullable) NSString *ageVerifiedAt;

@end

NS_ASSUME_NONNULL_END

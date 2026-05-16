// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSActorStore+Account.h

 @abstract PDSActorStore category for account-related database operations.

 @discussion Extends PDSActorStore with methods for managing account records
 in the actor's SQLite database. This includes account creation, updates,
 and credential management.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Database/ActorStore/ActorStore.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @category PDSActorStore (Account)

 @abstract Account management methods for PDSActorStore.

 @discussion This category extends PDSActorStore with account-specific database
 operations. Account records store user identity information including:

 - DID and handle
 - Email address
 - Password credentials (hashed)
 - 2FA settings
 - JWT tokens

 All methods in this category should be called within a transaction
 using transactWithBlock:error:.

 @see PDSActorStore
 @see PDSDatabaseAccount
 */
/**
 * @abstract Actor store operations for account records.
 */
@interface PDSActorStore (Account)

- (nullable PDSDatabaseAccount *)getAccountForDid:(NSString *)did error:(NSError * _Nullable * _Nullable)error;
- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError * _Nullable * _Nullable)error;
- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError * _Nullable * _Nullable)error;
- (nullable NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError * _Nullable * _Nullable)error;
- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError * _Nullable * _Nullable)error;

/**
 * @abstract Create account.
 * @param account Account record to persist.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError * _Nullable * _Nullable)error;
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError * _Nullable * _Nullable)error;
- (BOOL)deleteAccount:(NSString *)did error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

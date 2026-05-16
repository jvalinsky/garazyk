// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSAccountRepository.h
 * @abstract Protocol for account data access.
 * @discussion Defines the contract for account persistence operations, decoupling
 * the service layer from concrete database implementations.
 */

#import <Foundation/Foundation.h>
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabaseAccount;

/**
 * @abstract Protocol for account data access operations.
 * @discussion Implementations provide CRUD operations for PDS accounts.
 * The repository pattern abstracts the underlying storage mechanism.
 *
 * Thread Safety: Implementations must be thread-safe for read operations.
 * Write operations should be serialized by the caller.
 */
@protocol PDSAccountRepository <NSObject>

/**
 * @abstract Finds an account by its DID.
 * @param did The decentralized identifier to search for.
 * @param error Receives failure details.
 * @return The account object, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Finds an account by its handle.
 * @param handle The handle (username) to search for.
 * @param error Receives failure details.
 * @return The account object, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)accountForHandle:(NSString *)handle error:(NSError **)error;

/**
 * @abstract Finds an account by its email address.
 * @param email The email address to search for.
 * @param error Receives failure details.
 * @return The account object, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)accountForEmail:(NSString *)email error:(NSError **)error;

/**
 * @abstract Persists a new or updated account.
 * @param account The account object to save.
 * @param error Receives failure details.
 * @return YES if saved successfully, NO otherwise.
 */
- (BOOL)saveAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/**
 * @abstract Deletes an account and its associated data.
 * @param did The DID of the account to delete.
 * @param error Receives failure details.
 * @return YES if deleted successfully, NO otherwise.
 * @warning This operation is irreversible and removes all associated data.
 */
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

/**
 * @abstract Lists accounts with keyset pagination.
 * @param limit Maximum number of accounts to return.
 * @param cursor Exclusive lower bound for pagination (DID string), or nil for first page.
 * @param error Receives failure details.
 * @return An array of account objects, or nil if an error occurred.
 */
- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

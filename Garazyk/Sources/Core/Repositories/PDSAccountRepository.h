// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAccountRepository.h

 @abstract Protocol for account data access.

 @discussion Defines the contract for account persistence operations, decoupling
 the service layer from concrete database implementations. This allows for
 different storage backends (SQLite, in-memory, etc.) without changing
 business logic.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PDSAccountRepository

 @abstract Protocol for account data access operations.

 @discussion Implementations provide CRUD operations for PDS accounts.
 The repository pattern abstracts the underlying storage mechanism,
 allowing the service layer to remain storage-agnostic.

 <b>Implementations:</b>
 - PDSSQLiteAccountRepository: SQLite-backed persistent storage
 - PDSLegacyAccountRepository: Legacy database format support

 <b>Thread Safety:</b> Implementations must be thread-safe for read operations.
 Write operations should be serialized by the caller.

 @see PDSAccountService
 @see PDSDatabaseAccount
 */
@protocol PDSAccountRepository <NSObject>

/*!
 @method accountForDid:error:

 @abstract Finds an account by its DID.

 @param did The decentralized identifier to search for.
 @param error On return, contains an error if the lookup failed.
 @return The account object, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error;

/*!
 @method accountForHandle:error:

 @abstract Finds an account by its handle.

 @param handle The handle (username) to search for (e.g., "alice.bsky.social").
 @param error On return, contains an error if the lookup failed.
 @return The account object, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)accountForHandle:(NSString *)handle error:(NSError **)error;

/*!
 @method accountForEmail:error:

 @abstract Finds an account by its email address.

 @param email The email address to search for.
 @param error On return, contains an error if the lookup failed.
 @return The account object, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)accountForEmail:(NSString *)email error:(NSError **)error;

/*!
 @method saveAccount:error:

 @abstract Persists a new or updated account.

 @param account The account object to save.
 @param error On return, contains an error if the save failed.
 @return YES if the account was saved successfully, NO otherwise.
 */
- (BOOL)saveAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/*!
 @method deleteAccount:error:

 @abstract Deletes an account and its associated data.

 @param did The DID of the account to delete.
 @param error On return, contains an error if the deletion failed.
 @return YES if the account was deleted successfully, NO otherwise.

 @warning This operation is irreversible and removes all associated data.
 */
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

/*!
 @method listAccountsWithLimit:cursor:error:

 @abstract Lists accounts with keyset pagination.

 @param limit Maximum number of accounts to return.
 @param cursor Exclusive lower bound for pagination (DID string), or nil for first page.
 @param error On return, contains an error if the query failed.
 @return An array of account objects, or nil if an error occurred.
 */
- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

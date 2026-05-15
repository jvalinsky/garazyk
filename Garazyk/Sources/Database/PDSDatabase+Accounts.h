// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @category PDSDatabase (Accounts)

 @abstract Account management methods for PDSDatabase.

 @discussion These methods provide CRUD operations for PDS accounts.
 Accounts represent user identities on the PDS and contain authentication
 credentials and metadata.
 */
@interface PDSDatabase (Accounts)

/*!
 @method createAccount:error:

 @abstract Creates a new account in the database.

 @param account The account object containing account details.
 @param error On return, contains an error if the operation failed.
 @return YES if the account was created successfully, NO otherwise.
 */
- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/*!
 @method updateAccount:error:

 @abstract Updates an existing account in the database.

 @param account The account object with updated values.
 @param error On return, contains an error if the operation failed.
 @return YES if the account was updated successfully, NO otherwise.
 */
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/*!
 @method getAccountByDid:error:

 @abstract Retrieves an account by its DID.

 @param did The DID to search for.
 @param error On return, contains an error if the operation failed.
 @return The account object, or nil if not found.
 */
- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error;

/*!
 @method getAccountByHandle:error:

 @abstract Retrieves an account by its handle.

 @param handle The handle to search for (e.g., "alice.test").
 @param error On return, contains an error if the operation failed.
 @return The account object, or nil if not found.
 */
- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error;

/*!
 @method getAccountByEmail:error:

 @abstract Retrieves an account by its email address.

 @param email The email address to search for.
 @param error On return, contains an error if the operation failed.
 @return The account object, or nil if not found.
 */
- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error;

/*!
 @method getAccountByRefreshToken:error:

 @abstract Retrieves an account by its refresh token.

 @param refreshToken The refresh token string to search for.
 @param error On return, contains an error if the operation failed.
 @return The account object, or nil if not found.
 */
- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error;

/*!
 @method getAllAccountsWithError:

 @abstract Retrieves all accounts in the database.

 @param error On return, contains an error if the operation failed.
 @return An array of all account objects.
 */
- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error;

/*!
 @method getAccountsWithLimit:afterDid:error:

 @abstract Retrieves a page of accounts ordered by DID ascending (keyset pagination).

 @param limit Maximum number of accounts to return.
 @param afterDid Exclusive lower bound on DID for the next page, or nil for the first page.
 @param error On return, contains an error if the operation failed.
 @return An array of account objects.
 */
- (NSArray<PDSDatabaseAccount *> *)getAccountsWithLimit:(NSInteger)limit afterDid:(nullable NSString *)afterDid error:(NSError **)error;

/*!
 @method deleteAccount:error:

 @abstract Deletes an account and all associated data.

 @param did The DID of the account to delete.
 @param error On return, contains an error if the operation failed.
 @return YES if the account was deleted successfully, NO otherwise.
 */
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

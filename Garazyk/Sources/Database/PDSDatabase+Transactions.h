// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @category PDSDatabase (Transactions)
 
 @abstract Transaction methods for PDSDatabase.
 
 @discussion These methods support SQLite transactions for atomic operations.
 Use transactions to group multiple operations into a single atomic unit.
 */
@interface PDSDatabase (Transactions)

/*!
 @method beginTransactionWithError:
 
 @abstract Begins a database transaction.
 
 @discussion All subsequent operations will be part of this transaction
 until commit or rollback is called.
 
 @param error On return, contains an error if the operation failed.
 @return YES if the transaction began successfully, NO otherwise.
 */
- (BOOL)beginTransactionWithError:(NSError **)error;

/*!
 @method commitTransactionWithError:
 
 @abstract Commits the current transaction.
 
 @discussion All operations since the last beginTransaction are made permanent.
 
 @param error On return, contains an error if the operation failed.
 @return YES if the transaction committed successfully, NO otherwise.
 */
- (BOOL)commitTransactionWithError:(NSError **)error;

/*!
 @method rollbackTransactionWithError:
 
 @abstract Rolls back the current transaction.
 
 @discussion All operations since the last beginTransaction are discarded.
 
 @param error On return, contains an error if the operation failed.
 @return YES if the transaction rolled back successfully, NO otherwise.
 */
- (BOOL)rollbackTransactionWithError:(NSError **)error;

/*!
 @method transactWithBlock:error:

 @abstract Executes a block within a transaction.

 @discussion Begins a transaction, executes the block, and commits if the block
 returns without error. If the block sets the error pointer or throws an exception,
 the transaction is rolled back.

 @param block The block to execute within the transaction. The block receives an
 error pointer to set if an error occurs.
 @param error On return, contains an error if the transaction failed.
 @return YES if the transaction committed successfully, NO otherwise.
 */
- (BOOL)transactWithBlock:(void (^)(NSError **error))block error:(NSError **)error;

/*!
 @method performTransaction:error:

 @abstract Executes a block within a database transaction.

 @param block The block to execute. If it returns NO, the transaction is rolled back.
 @param error On return, contains an error if the transaction failed.
 @return YES if the transaction was committed, NO otherwise.
 */
- (BOOL)performTransaction:(BOOL (^)(PDSDatabase *db, NSError **error))block error:(NSError **)error;

/*!
 @method expandPlaceholdersForArray:

 @abstract Returns a string of ? placeholders for an array of values.

 @param values The array of values.
 @return A string like "?, ?, ?" or empty if array is empty.
 */
- (NSString *)expandPlaceholdersForArray:(NSArray *)values;

@end

NS_ASSUME_NONNULL_END

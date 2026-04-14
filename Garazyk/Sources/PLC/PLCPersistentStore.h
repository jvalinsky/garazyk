/*!
 @file PLCPersistentStore.h

 @abstract Persistent SQLite storage for PLC operations.

 @discussion Implements the PLCStore protocol using SQLite for production use.
 Stores DID operation history with proper indexing for efficient lookups.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"
#import <sqlite3.h>
#import "PLCStore.h"
#import "PLCOperation.h"

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for PLC persistent store operations. */
extern NSString * const PLCPersistentStoreErrorDomain;

/*!
 @enum PLCPersistentStoreError

 @abstract Error codes for PLC persistent store operations.
 */
typedef NS_ENUM(NSInteger, PLCPersistentStoreError) {
    PLCPersistentStoreErrorNotFound = 2000,
    PLCPersistentStoreErrorAlreadyExists,
    PLCPersistentStoreErrorTransactionRequired,
    PLCPersistentStoreErrorDatabaseClosed,
    PLCPersistentStoreErrorInvalidOperation,
};

/*!
 @class PLCPersistentStore

 @abstract Persistent SQLite storage for PLC operations.

 @discussion Stores DID operation history with proper indexing for efficient
 lookups by DID. Uses WAL mode for concurrent access and prepared statements
 for query optimization.
 */
@interface PLCPersistentStore : NSObject <PLCStore>

/*! Path to the SQLite database file. */
@property (nonatomic, copy, readonly) NSString *dbPath;

/*! Whether the database is currently open. */
@property (nonatomic, assign, readonly, getter=isOpen) BOOL open;

/*! Raw SQLite handle (internal use). */
@property (nonatomic, assign, readonly) sqlite3 *db;

/*! Creates a persistent store at the given path. */
+ (nullable instancetype)storeWithPath:(NSString *)dbPath error:(NSError **)error;

/*! Initializes a store without opening. Call openWithError: to open. */
- (instancetype)initWithPath:(NSString *)dbPath;

/*! Opens the database. */
- (BOOL)openWithError:(NSError **)error;

/*! Closes the database. */
- (void)close;

/*! Gets the operation count for a DID. */
- (NSInteger)operationCountForDid:(NSString *)did error:(NSError **)error;

/*! Deletes all operations for a DID (for tombstoning). */
- (BOOL)deleteOperationsForDid:(NSString *)did error:(NSError **)error;

/*! Transaction queue for thread-safe operations (internal). */
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, readonly) dispatch_queue_t transactionQueue;

/*! Prepare a statement (internal). */
- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

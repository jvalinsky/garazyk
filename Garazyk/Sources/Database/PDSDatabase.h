// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*!
 @header PDSDatabase.h
 @abstract Database layer for ATProto PDS persistence.
 @discussion This header defines the core database interface for persisting
 ATProto data including accounts, repositories, records, blocks, and blobs.
 Uses SQLite for local storage with transactions and migrations.
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

extern NSString * const PDSDatabaseErrorDomain;

/*! Error codes for PDSDatabase. */
typedef NS_ENUM(NSInteger, PDSDatabaseError) {
    PDSDatabaseErrorNotOpen = 1000,
    PDSDatabaseErrorQueryFailed = 1001,
    PDSDatabaseErrorMigrationFailed = 1002,
    PDSDatabaseErrorConstraintViolation = 1003,
    PDSDatabaseErrorNotFound = 1004,
};

/*!
 @class PDSDatabase
 @abstract Manages the PDS SQLite database.
 */
@interface PDSDatabase : NSObject <PDSQueryDatabase>

/*! The URL path to the SQLite database file. */
@property (nonatomic, readonly) NSURL *databaseURL;

/*! YES if the database connection is currently open. */
@property (nonatomic, readonly) BOOL isOpen;

/*!
 @method internalSQLiteHandle
 @abstract Returns the raw sqlite3* handle.
 @discussion INTERNAL USE ONLY. Requires casting to sqlite3*.
 */
- (void *)internalSQLiteHandle;

/*!
 @method init
 @abstract Designated initializer.
 */
- (instancetype)init NS_DESIGNATED_INITIALIZER;

/*!
 @method databaseAtURL:
 
 @abstract Creates a database instance at the specified file path.
 
 @param url The file URL where the SQLite database should be located or created.
 @return An initialized PDSDatabase instance.
 */
+ (instancetype)databaseAtURL:(NSURL *)url;

/*!
 @method openWithError:
 
 @abstract Opens the database connection and runs any pending migrations.
 
 @param error On return, contains an error if the operation failed.
 @return YES if the database opened successfully, NO otherwise.
 */
- (BOOL)openWithError:(NSError **)error;

/*!
 @method close
 
 @abstract Closes the database connection.
 */
- (void)close;

/*!
 @method preparedStatementForQuery:

 @abstract Returns a cached prepared statement for the given SQL query.
 @discussion Uses an LRU cache internally. The caller must finalize the returned
 statement when done.
 */
- (nullable sqlite3_stmt *)preparedStatementForQuery:(NSString *)query;

/*!
 @method executeUnsafeRawSQL:error:
 
 @abstract Executes a raw SQL statement.
 
 @discussion DANGEROUS: Does not support parameter binding. Use only for
 internal schema setup or when the SQL string is a compile-time constant.
 
 @param sql The SQL statement to execute.
 @param error On return, contains an error if the operation failed.
 @return YES if the statement executed successfully, NO otherwise.
 */
/**
 * @abstract Execute unsafe raw sql.
 * @param sql SQL statement to execute.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)executeUnsafeRawSQL:(NSString *)sql error:(NSError **)error;

/*!
 @method executeUnsafeRawQuery:error:
 
 @abstract Executes a SQL query and returns results.
 
 @discussion DANGEROUS: Does not support parameter binding. Prefer
 executeParameterizedQuery:params:error: instead.
 
 @param sql The SQL query to execute.
 @param error On return, contains an error if the query failed.
 @return An array of dictionaries representing query results, or nil on failure.
 */
/**
 * @abstract Execute unsafe raw query.
 * @param sql SQL statement to execute.
 * @param error Receives details when the operation fails.
 * @return The response array, or nil when the request fails.
 */
- (NSArray<NSDictionary *> *)executeUnsafeRawQuery:(NSString *)sql error:(NSError **)error;

/*!
 @method executeParameterizedQuery:params:error:
 
 @abstract Executes a SQL query with parameterized values.
 
 @discussion This is the RECOMMENDED method for executing queries with user-provided
 values. It uses SQLite parameter binding to prevent SQL injection attacks.
 
 @param sql The SQL query with ? placeholders for parameters.
 @param params An array of parameter values to bind to the query.
 @param error On return, contains an error if the query failed.
 @return An array of dictionaries representing query results, or nil on failure.
 */
/**
 * @abstract Execute parameterized query.
 * @param sql SQL statement to execute.
 * @param params Bound SQL parameter values.
 * @param error Receives details when the operation fails.
 * @return The response array, or nil when the request fails.
 */
- (NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql
                                                params:(NSArray *)params
                                                 error:(NSError **)error;

/*!
 @method executeParameterizedQuery:params:modelClass:error:
 @abstract Executes a query and maps results to model objects.
 @param sql The SQL query to execute.
 @param params Array of parameters for placeholders.
 @param modelClass The class of the model to instantiate (must implement PDSDatabaseModel).
 @param error On return, contains an error if the query failed.
 @return An array of model objects, or nil on failure.
 */
- (nullable NSArray *)executeParameterizedQuery:(NSString *)sql
                                         params:(NSArray *)params
                                     modelClass:(Class<PDSDatabaseModel>)modelClass
                                          error:(NSError **)error;

/*!
 @method executeParameterizedUpdate:params:error:
 
 @abstract Executes a parameterized SQL statement (INSERT, UPDATE, DELETE).
 
 @param sql The SQL statement with ? placeholders for parameters.
 @param params An array of parameter values to bind to the statement.
 @param error On return, contains an error if the statement failed.
 @return YES if the statement executed successfully, NO otherwise.
 */
- (BOOL)executeParameterizedUpdate:(NSString *)sql
                            params:(NSArray *)params
                             error:(NSError **)error;

/*!
 @method parameterPlaceholdersForCount:
 @abstract Returns a string of ? placeholders for use in an IN clause.
 @param count Number of placeholders needed.
 @return A string like "?, ?, ?" or empty if count is 0.
 */
- (NSString *)parameterPlaceholdersForCount:(NSUInteger)count;

@end

NS_ASSUME_NONNULL_END

#import "Database/PDSDatabaseAccount.h"
#import "Database/PDSDatabaseRepo.h"
#import "Database/PDSDatabaseRecord.h"
#import "Database/PDSDatabaseBlob.h"
#import "Database/PDSDatabaseBlock.h"

// ── Category imports ─────────────────────────────────────────────────
// Importing here (after @interface) preserves backward compatibility:
// consumers who #import "PDSDatabase.h" still get all category methods.
// The category headers #import this file, but #import's include guards
// prevent recursion.
#import "PDSDatabase+Accounts.h"
#import "PDSDatabase+Transactions.h"
#import "PDSDatabase+Repos.h"
#import "PDSDatabase+Blobs.h"
#import "PDSDatabase+Records.h"
#import "PDSDatabase+Moderation.h"
#import "PDSDatabase+AdminAudit.h"
#import "PDSDatabase+Reports.h"
#import "PDSDatabase+AdminConfig.h"
#import "PDSDatabase+Sessions.h"
#import "PDSDatabase+VideoJobs.h"
#import "PDSDatabase+WebAuthn.h"
#import "PDSDatabase+Blocks.h"
#import "PDSDatabase+OAuthClients.h"


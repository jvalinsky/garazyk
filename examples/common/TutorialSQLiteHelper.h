/*!
 @file TutorialSQLiteHelper.h

 @abstract Thread-safe SQLite wrapper for tutorial examples.

 @discussion Provides a simple SQLite wrapper using a serial dispatch queue
 for thread safety. This is the educational version of the production
 PDSDatabase in Garazyk/Sources/Database/PDSDatabase.h.

 Key concepts:
 - Serial dispatch queue for thread-safe database access
 - Block-based API for safe database operations
 - Automatic database opening/closing
 - Error handling with NSError

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const TutorialSQLiteErrorDomain;

/*!
 @class TutorialSQLiteHelper

 @abstract Thread-safe SQLite wrapper using serial dispatch queue.
 */
@interface TutorialSQLiteHelper : NSObject

/*! The path to the SQLite database file. */
@property (nonatomic, copy, readonly) NSString *databasePath;

/*!
 @method initWithPath:

 @abstract Creates a SQLite helper with a database file path.

 @param path The path to the SQLite database file.
 @return A new helper instance, or nil if the database cannot be opened.
 */
- (nullable instancetype)initWithPath:(NSString *)path;

/*!
 @method executeSync:error:block:

 @abstract Executes a database operation synchronously on the serial queue.

 @discussion The sqlite3 database handle is only accessible inside the block,
 ensuring thread safety. Do NOT retain or use the handle outside the block.

 @param error On failure, contains error details.
 @param block The operation to execute. Receives the sqlite3* handle.
 @return YES if the operation completed, NO on error.
 */
- (BOOL)executeSync:(NSError **)error
             block:(void (^)(sqlite3 *db))block;

/*!
 @method executeQuery:error:block:

 @abstract Executes a query and returns the result.

 @param error On failure, contains error details.
 @param block The query to execute. Receives the sqlite3* handle.
 @return The result returned by the block, or nil on error.
 */
- (nullable id)executeUnsafeRawQuery:(NSError **)error
                        block:(id _Nullable (^)(sqlite3 *db))block;
/*!
 @method executeUpdate:error:sql:

 @abstract Executes a SQL update statement.

 @param error On failure, contains error details.
 @param sql The SQL statement to execute.
 @return YES if successful, NO on error.
 */
- (BOOL)executeUpdate:(NSError **)error
                  sql:(NSString *)sql, ... NS_FORMAT_FUNCTION(2,3);

@end

NS_ASSUME_NONNULL_END

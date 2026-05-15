// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Database/PDSDatabase.h"
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @category PDSDatabase (Private)

 @abstract Private interface for PDSDatabase category files.

 @discussion This header declares private helper methods that category
 implementations need to call. It should only be imported by PDSDatabase
 implementation files (the main .m and category .m files), never by
 external consumers.

 Properties (db, isOpen, dbQueue, etc.) are declared in the class
 extension in PDSDatabase.m and accessed via self.property in category
 files — do NOT re-declare them here.
 */
@interface PDSDatabase (Private)

// ── Properties from class extension (re-declared for category visibility) ──

/*! The SQLite database handle. */
@property (nonatomic, assign, readonly) sqlite3 *db;

/*! Whether the database is currently open. */
@property (nonatomic, readonly) BOOL isOpen;

/*! Executes a block synchronously on the database queue. */
- (void)safeExecuteSync:(void (^)(void))block;

/*! Creates an NSError with a SQLite error message and custom code. */
- (NSError *)errorWithMessage:(const char *)message code:(NSInteger)code;

/*! Creates an NSError with a description string and custom code. */
- (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;

/*! Binds an NSData blob to a prepared statement parameter. */
- (void)bindData:(nullable NSData *)data toStatement:(sqlite3_stmt *)stmt index:(int)index;

/*! Formats an NSDate as an ISO 8601 string. */
- (NSString *)iso8601StringFromDate:(NSDate *)date;

/*! Executes a parameterized query and returns model objects. */
- (nullable NSArray *)executeParameterizedQuery:(NSString *)sql
                                         params:(NSArray *)params
                                     modelClass:(Class)modelClass
                                          error:(NSError **)error;

/*! Reads an account from the current row of a prepared statement. */
- (nullable PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt;

/*! Reads a repo from the current row of a prepared statement. */
- (nullable PDSDatabaseRepo *)repoFromStatement:(sqlite3_stmt *)stmt;

/*! Reads a block from the current row of a prepared statement. */
- (nullable PDSDatabaseBlock *)blockFromStatement:(sqlite3_stmt *)stmt;

/*! Reads a blob from the current row of a prepared statement. */
- (nullable PDSDatabaseBlob *)blobFromStatement:(sqlite3_stmt *)stmt;

/*! Reads a record from the current row of a prepared statement. */
- (nullable PDSDatabaseRecord *)recordFromStatement:(sqlite3_stmt *)stmt;

/*! Parses an ISO 8601 date string into an NSDate. */
- (nullable NSDate *)dateFromISO8601String:(NSString *)string;

/*! Reads a value from a statement column, handling type detection. */
- (nullable id)valueFromStatement:(sqlite3_stmt *)stmt columnIndex:(int)colIndex;

/*! Generates parameter placeholders (?, ?, ...) for a given count. */
- (NSString *)parameterPlaceholdersForCount:(NSUInteger)count;

/*! Expands placeholders for an array of values. */
- (NSString *)expandPlaceholdersForArray:(NSArray *)values;

@end

NS_ASSUME_NONNULL_END

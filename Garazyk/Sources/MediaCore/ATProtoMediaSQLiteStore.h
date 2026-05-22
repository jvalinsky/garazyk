// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMediaSQLiteStore.h

 @abstract Thread-safe SQLite-backed implementation of @c ATProtoMediaJobStore.

 @discussion Uses the unified @c media_jobs table with a @c results_json column
 for domain-specific metadata. Supports WAL mode and connection pooling.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoMediaJobStore.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract SQLite-backed implementation of the media job store.
 */
@interface ATProtoMediaSQLiteStore : NSObject <ATProtoMediaJobStore>

/**
 * @abstract Initializes the store with a database file path.
 *
 * @param path  File system path to the SQLite database file.
 * @param error Receives failure details.
 * @return An initialized store, or nil on failure.
 */
- (nullable instancetype)initWithDatabasePath:(NSString *)path
                                        error:(NSError **)error;

/**
 * @abstract Opens the database connection and creates the schema if needed.
 */
- (BOOL)openDatabaseWithError:(NSError **)error;

/**
 * @abstract Closes the database connection.
 */
- (void)closeDatabase;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoJobStore.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract SQLite-based implementation of the video job store.
 */
@interface JelczDatabase : NSObject <VideoJobStore>

/**
 * @abstract Initializes the database instance.
 * @param path File system path to the SQLite file.
 * @param error Receives failure details.
 * @return An initialized database instance, or nil on failure.
 */
- (nullable instancetype)initWithDatabasePath:(NSString *)path
                                       error:(NSError **)error;

/**
 * @abstract Opens the database connection.
 * @param error Receives failure details.
 * @return YES if successfully opened.
 */
- (BOOL)openDatabaseWithError:(NSError **)error;

/**
 * @abstract Closes the database connection.
 */
- (void)closeDatabase;

/**
 * @abstract Lists video jobs filtered by state.
 * @param state The job state filter, or nil for all.
 * @param limit Pagination limit.
 * @param offset Pagination offset.
 * @param error Receives failure details.
 * @return Array of job dictionaries.
 */
- (NSArray<NSDictionary *> *)listVideoJobsWithState:(nullable NSString *)state
                                               limit:(NSUInteger)limit
                                              offset:(NSUInteger)offset
                                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

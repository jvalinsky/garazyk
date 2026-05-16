// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSSQLiteRecordRepository.h
 * @abstract SQLite implementation of the record repository.
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSRecordRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

/**
 * @abstract SQLite-backed implementation of the record repository.
 */
@interface PDSSQLiteRecordRepository : NSObject <PDSRecordRepository>

/**
 * @abstract Initializes the repository with a database pool.
 * @param databasePool The SQLite database pool for record storage.
 */
- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

@end

NS_ASSUME_NONNULL_END

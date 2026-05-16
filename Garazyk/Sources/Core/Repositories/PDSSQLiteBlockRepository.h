// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSSQLiteBlockRepository.h
 * @abstract SQLite implementation of the block repository.
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSBlockRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

/**
 * @abstract SQLite-backed implementation of the block repository.
 */
@interface PDSSQLiteBlockRepository : NSObject <PDSBlockRepository>

/**
 * @abstract Initializes the repository with a database pool.
 * @param databasePool The SQLite database pool for block storage.
 */
- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

@end

NS_ASSUME_NONNULL_END

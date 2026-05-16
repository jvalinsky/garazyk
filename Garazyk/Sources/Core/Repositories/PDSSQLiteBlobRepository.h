// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSSQLiteBlobRepository.h
 * @abstract SQLite implementation of the blob repository.
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSBlobRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

/**
 * @abstract SQLite-backed implementation of the blob repository.
 */
@interface PDSSQLiteBlobRepository : NSObject <PDSBlobRepository>

/**
 * @abstract Initializes the repository with a database pool.
 * @param databasePool The SQLite database pool for blob storage.
 */
- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

@end

NS_ASSUME_NONNULL_END

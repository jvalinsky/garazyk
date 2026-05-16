// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSSQLiteRepoRepository.h
 * @abstract SQLite implementation of the repository repository.
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSRepoRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

/**
 * @abstract SQLite-backed implementation of the repository repository.
 */
@interface PDSSQLiteRepoRepository : NSObject <PDSRepoRepository>

/**
 * @abstract Initializes the repository with a database pool.
 * @param servicePool The SQLite database pool for repository storage.
 */
- (instancetype)initWithServicePool:(PDSDatabasePool *)servicePool;

@end

NS_ASSUME_NONNULL_END

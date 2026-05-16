// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSSQLiteSessionRepository.h
 * @abstract SQLite implementation of the session repository.
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSSessionRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

/**
 * @abstract SQLite-backed implementation of the session repository.
 */
@interface PDSSQLiteSessionRepository : NSObject <PDSSessionRepository>

/**
 * @abstract Initializes the repository with a database pool.
 * @param servicePool The SQLite database pool for session storage.
 */
- (instancetype)initWithServicePool:(PDSDatabasePool *)servicePool;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSLegacyAccountRepository.h
 * @abstract Adapter class for legacy account storage.
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSAccountRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;

/**
 * @abstract Adapter for legacy account storage backends.
 */
@interface PDSLegacyAccountRepository : NSObject <PDSAccountRepository>

/**
 * @abstract Initializes the repository with service databases.
 * @param serviceDatabases The service database registry.
 * @return An initialized repository instance.
 */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

@end

NS_ASSUME_NONNULL_END

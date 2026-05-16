// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSLegacySessionRepository.h
 * @abstract Adapter for legacy session data.
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSSessionRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;

/**
 * @abstract Adapter for legacy session storage backends.
 */
@interface PDSLegacySessionRepository : NSObject <PDSSessionRepository>

/**
 * @abstract Initializes the repository with service databases.
 * @param serviceDatabases The service database registry.
 * @return An initialized repository instance.
 */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

@end

NS_ASSUME_NONNULL_END

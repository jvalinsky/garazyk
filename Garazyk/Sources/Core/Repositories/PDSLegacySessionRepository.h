// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSLegacySessionRepository.h
 @abstract Adapter for legacy session data.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSSessionRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;

@interface PDSLegacySessionRepository : NSObject <PDSSessionRepository>

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

@end

NS_ASSUME_NONNULL_END

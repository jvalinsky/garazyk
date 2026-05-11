// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSServiceContainer.h
 @abstract Lightweight dependency injection container.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSServiceContainer
 @abstract Manages service and repository lifecycles and provides discovery.
 */
@interface PDSServiceContainer : NSObject

/*! Returns the shared service container. */
+ (instancetype)sharedContainer;

/*! Registers a singleton instance for a protocol. */
- (void)registerInstance:(id)instance forProtocol:(Protocol *)protocol;

/*! Registers a factory block for a protocol. The instance is created lazily. */
- (void)registerFactory:(id (^)(PDSServiceContainer *container))factory forProtocol:(Protocol *)protocol;

/*! Resolves an instance for a protocol. */
- (nullable id)resolveProtocol:(Protocol *)protocol;

/*! Removes all registrations. Useful for testing. */
- (void)reset;

@end

NS_ASSUME_NONNULL_END

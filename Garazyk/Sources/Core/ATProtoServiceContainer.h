// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoServiceContainer.h
 @abstract Lightweight dependency injection container.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ATProtoServiceContainer
 @abstract Manages service and repository lifecycles and provides discovery.
 */
@interface ATProtoServiceContainer : NSObject

/*! Returns the shared service container. */
+ (instancetype)sharedContainer;

/*! Registers a singleton instance for a protocol. */
- (void)registerInstance:(id)instance forProtocol:(Protocol *)protocol;

/*! Registers a factory block for a protocol. The instance is created lazily. */
- (void)registerFactory:(id (^)(ATProtoServiceContainer *container))factory forProtocol:(Protocol *)protocol;

/*! Resolves an instance for a protocol. */
- (nullable id)resolveProtocol:(Protocol *)protocol;

/*! Removes all registrations. Useful for testing. */
- (void)reset;

@end

NS_ASSUME_NONNULL_END

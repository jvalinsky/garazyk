// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSXrpcGermIdentityPack.h

 @abstract XRPC handler registration for Germ AC Protocol identity.

 @discussion Registers com.germnetwork.identity.* XRPC endpoints
 for the Germ Protocol identity layer. Models after Germ's current
 shipping 1:1 E2EE DM product.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class ATProtoXrpcDispatcher;
@class PDSGermIdentityService;
@class PDSChatAuthManager;

NS_ASSUME_NONNULL_BEGIN

@interface PDSXrpcGermIdentityPack : NSObject

/**
 * @abstract Performs the initWithIdentityService operation.
 */
- (instancetype)initWithIdentityService:(PDSGermIdentityService *)identityService
                            authManager:(PDSChatAuthManager *)authManager;

/**
 * @abstract Performs the registerHandlersWithDispatcher operation.
 */
- (void)registerHandlersWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END

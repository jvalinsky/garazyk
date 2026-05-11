// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcGermMailboxPack.h

 @abstract XRPC handler registration for Germ E2EE mailbox transport.

 @discussion Registers com.germnetwork.mailbox.* and
 com.germnetwork.rendezvous.* XRPC endpoints for the Germ Protocol
 E2EE mailbox transport. Models after Germ's current shipping
 1:1 E2EE DM product.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class GermMailboxService;
@class ChatAuthManager;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcGermMailboxPack : NSObject

- (instancetype)initWithMailboxService:(GermMailboxService *)mailboxService
                          authManager:(ChatAuthManager *)authManager;

- (void)registerHandlersWithDispatcher:(XrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcChatBskyActorPack.h

 @abstract XRPC route pack for chat.bsky.actor and chat.bsky.moderation endpoints.
 */

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

@class XrpcDispatcher;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcChatBskyActorPack : NSObject <XrpcRoutePack>

/*! Legacy entry point; builds a minimal services bag from the dispatcher. */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END

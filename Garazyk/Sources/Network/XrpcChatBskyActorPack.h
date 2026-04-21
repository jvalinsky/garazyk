/*!
 @file XrpcChatBskyActorPack.h

 @abstract XRPC route pack for chat.bsky.actor and chat.bsky.moderation endpoints.
 */

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class ChatModerationService;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcChatBskyActorPack : NSObject

/*! Register all chat.bsky.actor and chat.bsky.moderation routes with the dispatcher. */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
         chatModerationService:(nullable ChatModerationService *)chatModerationService;

@end

NS_ASSUME_NONNULL_END

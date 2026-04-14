//
//  XrpcChatBskyConvoPack.h
//  ATProtoPDS
//
//  Namespace pack for chat.bsky.convo.* XRPC endpoints.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcChatBskyConvoPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END

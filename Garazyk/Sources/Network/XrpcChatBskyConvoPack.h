//
//  XrpcChatBskyConvoPack.h
//  ATProtoPDS
//
//  Namespace pack for chat.bsky.convo.* XRPC endpoints.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@protocol PDSQueryDatabase;
@class JWTMinter;
@protocol PDSAdminController;
@class ChatAuthManager;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcChatBskyConvoPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                    jwtMinter:(nullable JWTMinter *)jwtMinter
              adminController:(nullable id<PDSAdminController>)adminController;

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                   authManager:(nullable ChatAuthManager *)authManager;

@end

NS_ASSUME_NONNULL_END

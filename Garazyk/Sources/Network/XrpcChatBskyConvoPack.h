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

NS_ASSUME_NONNULL_BEGIN

@interface XrpcChatBskyConvoPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                    jwtMinter:(JWTMinter *)jwtMinter
              adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END

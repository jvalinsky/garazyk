//
//  XrpcChatBskyGroupPack.h
//  ATProtoPDS
//
//  Namespace pack for chat.bsky.group.* XRPC endpoints.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@protocol PDSQueryDatabase;
@class JWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcChatBskyGroupPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                    jwtMinter:(nullable JWTMinter *)jwtMinter
              adminController:(nullable id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END

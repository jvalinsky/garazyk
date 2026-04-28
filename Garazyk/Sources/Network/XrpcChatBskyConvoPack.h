/*!
 @file XrpcChatBskyConvoPack.h

 @abstract XRPC route pack for chat.bsky.convo.* endpoints.
 */

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@protocol PDSQueryDatabase;
@class JWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcChatBskyConvoPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                      jwtMinter:(nullable JWTMinter *)jwtMinter
                adminController:(nullable id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END

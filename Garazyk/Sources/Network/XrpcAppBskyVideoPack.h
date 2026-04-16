//
//  XrpcAppBskyVideoPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.video.* XRPC endpoints.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSDatabase;
@class PDSServiceDatabases;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyVideoPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                  appViewDatabase:(PDSDatabase *)appViewDatabase
                       jwtMinter:(JWTMinter *)jwtMinter
                 adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END

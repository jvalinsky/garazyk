//
//  XrpcAppBskyFeedPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.feed.* XRPC endpoints.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSDatabase;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 @brief Namespace pack for app.bsky.feed.* endpoints.
 */
@interface XrpcAppBskyFeedPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(PDSDatabase *)appViewDatabase
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END

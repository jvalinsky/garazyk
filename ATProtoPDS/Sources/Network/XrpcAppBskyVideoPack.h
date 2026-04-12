//
//  XrpcAppBskyVideoPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.video.* XRPC endpoints.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyVideoPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END

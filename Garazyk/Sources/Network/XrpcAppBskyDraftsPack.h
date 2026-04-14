//
//  XrpcAppBskyDraftsPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.draft.* XRPC endpoints.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyDraftsPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END

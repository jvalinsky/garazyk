//
//  XrpcAppBskyBookmarksPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.bookmark.* XRPC endpoints.
//

#import <Foundation/Foundation.h>

@class BookmarkService;
@class JWTMinter;
@class XrpcDispatcher;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyBookmarksPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               bookmarkService:(BookmarkService *)bookmarkService
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END

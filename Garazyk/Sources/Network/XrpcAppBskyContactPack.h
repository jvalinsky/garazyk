/*!
 @file XrpcAppBskyContactPack.h

 @abstract XRPC route pack for app.bsky.contact endpoints.
 */

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class ContactService;
@class JWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyContactPack : NSObject

/*! Register all app.bsky.contact routes with the dispatcher. */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 contactService:(ContactService *)contactService
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END

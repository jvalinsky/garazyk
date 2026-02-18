#import <Foundation/Foundation.h>
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSApplication;
@class PDSController;
@class JWTMinter;
@protocol PDSAdminController;

/**
 @header XrpcMethodRegistry.h

 @abstract XRPC method registration utilities.

 @discussion This header defines the XrpcMethodRegistry class for
 registering all standard ATProto XRPC methods with a dispatcher.
 */

/**
 @class XrpcMethodRegistry

 @abstract Registers all ATProto XRPC methods with a dispatcher.

 @discussion XrpcMethodRegistry provides a convenient way to register
 all standard ATProto XRPC method handlers with an XrpcDispatcher.
 */
@interface XrpcMethodRegistry : NSObject

/**
 @brief Register the ATProto XRPC method handlers with the dispatcher.

 @param dispatcher Dispatcher to register methods on.
 @param controller Backend controller that implements the handlers.

 @note This method is provided for backward compatibility. For new code,
 prefer registerMethodsWithDispatcher:application: which uses services directly.
 */
+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller;

/**
 @brief Register the ATProto XRPC method handlers using PDSApplication services.

 @param dispatcher Dispatcher to register methods on.
 @param application The PDSApplication providing services.

 @discussion This method registers XRPC handlers that use the application's
 services directly, without depending on PDSController.
 */
+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                          application:(PDSApplication *)application;

/**
 @brief Extract the authenticated DID from an Authorization header.

 @param authHeader The Authorization header value.
 @param jwtMinter The JWT minter used for token verification.
 @param adminController The admin controller for takedown checks.
 @param request The HTTP request (used for DPoP validation).
 @return The authenticated DID, or nil if authentication fails.
 */
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                      jwtMinter:(JWTMinter *)jwtMinter
                                adminController:(id<PDSAdminController>)adminController
                                        request:(HttpRequest *)request;

/**
 @brief Decode a DID `publicKeyMultibase` string into raw key bytes.

 @param multibase `publicKeyMultibase` value from a DID document.
 @param error Populated when decoding fails.
 @return Raw public key bytes or nil if the string is malformed.
 */
+ (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

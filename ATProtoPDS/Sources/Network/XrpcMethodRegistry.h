#import <Foundation/Foundation.h>
#import "Network/XrpcHandler.h"
#import "App/PDSController.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

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
 It connects each method to the appropriate PDSController handler.
 */
@interface XrpcMethodRegistry : NSObject

/**
 @brief Register the ATProto XRPC method handlers with the dispatcher.
 
 @param dispatcher Dispatcher to register methods on.
 @param controller Backend controller that implements the handlers.
 */
+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller;

/**
 @brief Decode a DID `publicKeyMultibase` string into raw key bytes.
 
 @param multibase `publicKeyMultibase` value from a DID document.
 @param error Populated when decoding fails.
 @return Raw public key bytes or nil if the string is malformed.
 */
+ (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

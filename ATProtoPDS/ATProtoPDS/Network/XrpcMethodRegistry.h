#import <Foundation/Foundation.h>
#import "XrpcHandler.h"
#import "../PDSController.h"
#import "HttpRequest.h"
#import "HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @header XrpcMethodRegistry.h
 
 @abstract XRPC method registration utilities.
 
 @discussion This header defines the XrpcMethodRegistry class for
 registering all standard ATProto XRPC methods with a dispatcher.
 
 @copyright Copyright (c) 2024 Jack Myers
 */

/*!
 @class XrpcMethodRegistry
 
 @abstract Registers all ATProto XRPC methods with a dispatcher.
 
 @discussion XrpcMethodRegistry provides a convenient way to register
 all standard ATProto XRPC method handlers with an XrpcDispatcher.
 It connects each method to the appropriate PDSController handler.
 
 @code
 XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];
 PDSController *controller = [[PDSController alloc] initWithDatabase:db];
 
 [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher
                                       controller:controller];
 @endcode
 */
@interface XrpcMethodRegistry : NSObject

/*!
 @method registerMethodsWithDispatcher:controller:
 
 @abstract Registers all standard XRPC methods with the dispatcher.
 
 @discussion This method registers handlers for all ATProto XRPC methods,
 connecting each to the appropriate method on the PDSController.
 
 @param dispatcher The XrpcDispatcher to register methods with.
 @param controller The PDSController to handle the methods.
 */
+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller;

@end

NS_ASSUME_NONNULL_END

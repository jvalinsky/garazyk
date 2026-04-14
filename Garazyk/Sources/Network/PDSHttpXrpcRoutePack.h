/*!
 @file PDSHttpXrpcRoutePack.h

 @abstract Registers the XRPC transport route pack on an HTTP server.
 */

#import <Foundation/Foundation.h>
#import "Network/PDSHttpRoutePackTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSApplication;
@class PDSController;
@class SubscribeReposHandler;
@class XrpcDispatcher;

@interface PDSHttpXrpcRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                      dispatcher:(nullable XrpcDispatcher *)dispatcher
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller
           subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler
                  setCorsHeaders:(PDSHttpSetCorsHeadersBlock)setCorsHeaders;

@end

NS_ASSUME_NONNULL_END


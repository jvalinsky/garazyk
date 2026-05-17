// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpXrpcRoutePack.h

 @abstract Registers the XRPC transport route pack on an HTTP server.
 */

#import <Foundation/Foundation.h>
#import "Network/ATProtoHttpRoutePackTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSApplication;
@class PDSController;
@class SubscribeReposHandler;
@class XrpcDispatcher;

@interface ATProtoHttpXrpcRoutePack : NSObject

/**
 * @abstract Performs the registerRoutesWithServer operation.
 */
+ (void)registerRoutesWithServer:(HttpServer *)server
                      dispatcher:(nullable XrpcDispatcher *)dispatcher
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller
           subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler
                  setCorsHeaders:(ATProtoHttpSetCorsHeadersBlock)setCorsHeaders;

@end

NS_ASSUME_NONNULL_END


/*!
 @file NodeInfoHandler.h

 @abstract NodeInfo HTTP request handler.

 @discussion Handles NodeInfo discovery and schema endpoint requests.
 Implements singleton pattern following other handlers in the codebase.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class HttpServer;
@class HttpRequest;
@class HttpResponse;
@class PDSController;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class NodeInfoHandler

 @abstract HTTP request handler for NodeInfo endpoints.

 @discussion Handles requests to:
 - /.well-known/nodeinfo (discovery JRD)
 - /nodeinfo/2.0 (schema 2.0)
 - /nodeinfo/2.1 (schema 2.1)
 */
@interface NodeInfoHandler : NSObject

/*! Shared singleton instance. */
+ (instancetype)sharedHandler;

/*!
 @brief Set the server issuer URL for metadata generation.

 @param issuer The issuer URL (e.g., "https://pds.example.com")
 */
- (void)setIssuer:(NSString *)issuer;

/*!
 @brief Set the PDS controller for configuration access.

 @param controller The PDS controller instance.
 */
- (void)setController:(PDSController *)controller;

/*!
 @brief Register NodeInfo routes with the HTTP server.

 @param httpServer The HTTP server to register routes with.
 */
- (void)registerRoutesWithServer:(HttpServer *)httpServer;

/*!
 @brief Handle NodeInfo discovery request.

 @param request The HTTP request.
 @param response The HTTP response to write to.
 */
- (void)handleDiscoveryRequest:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @brief Handle NodeInfo 2.0 schema request.

 @param request The HTTP request.
 @param response The HTTP response to write to.
 */
- (void)handleNodeInfo20Request:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @brief Handle NodeInfo 2.1 schema request.

 @param request The HTTP request.
 @param response The HTTP response to write to.
 */
- (void)handleNodeInfo21Request:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END

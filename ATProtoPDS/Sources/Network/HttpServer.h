#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@class HttpServer;

/*!
 @header HttpServer.h
 
 @abstract HTTP server implementation for the PDS.
 
 @discussion This header defines the HTTP server interface for handling
 incoming requests. The server supports route registration, request/response
 handling, and lifecycle management.
 
 @copyright Copyright (c) 2024 Jack Myers
 */

/*!
 @typedef RequestHandler
 
 @abstract Block type for handling HTTP requests.
 
 @param request The incoming HTTP request.
 @param response The response object to populate.
 */
typedef void (^RequestHandler)(HttpRequest *request, HttpResponse *response);

@protocol PDSNetworkConnection;

/*!
 @typedef WebSocketUpgradeHandler
 
 @abstract Block type for handling WebSocket upgrade requests.
 
 @param request The incoming HTTP request with WebSocket upgrade headers.
 @param connection The underlying network connection to hand off.
 @return YES if the handler accepted the upgrade, NO to reject.
 */
typedef BOOL (^WebSocketUpgradeHandler)(HttpRequest *request, id<PDSNetworkConnection> connection);

/*!
 @class HttpServer
 
 @abstract HTTP server for handling PDS requests.
 
 @discussion HttpServer provides a simple HTTP server implementation
 for the PDS. It supports route registration for different HTTP methods
 and paths, with handlers invoked for matching requests.
 
 @code
 HttpServer *server = [HttpServer serverWithPort:8080];
 
 [server addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *resp) {
     resp.statusCode = 200;
     [resp setBody:@"OK"];
 }];
 
 [server startWithError:nil];
 @endcode
 */
@interface HttpServer : NSObject

/*! The port the server is listening on. */
@property (nonatomic, readonly) NSUInteger port;

/*! YES if the server is currently running. */
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/*! Optional callback invoked for every request received. */
@property (nonatomic, copy, nullable) void (^didReceiveRequest)(HttpRequest *request, HttpResponse *response);

/*!
 @method serverWithPort:
 
 @abstract Creates a server instance for the specified port.
 
 @param port The port to listen on.
 @return A new HttpServer instance.
 */
+ (instancetype)serverWithPort:(NSUInteger)port;

/*!
 @method startWithError:
 
 @abstract Starts the server and begins listening for connections.
 
 @param error On return, contains an error if the server failed to start.
 @return YES if the server started successfully, NO otherwise.
 */
- (BOOL)startWithError:(NSError * _Nullable *)error;

/*!
 @method stop
 
 @abstract Stops the server and closes all connections.
 */
- (void)stop;

/*!
 @method addRoute:path:handler:
 
 @abstract Registers a route handler for a specific method and path.
 
 @param method The HTTP method (GET, POST, etc.).
 @param path The URL path pattern.
 @param handler The handler block to invoke for matching requests.
 */
- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler;

/*!
 @method addHandlerForPath:handler:
 
 @abstract Registers a handler for all methods on a path.
 
 @param path The URL path pattern.
 @param handler The handler block to invoke for matching requests.
 */
- (void)addHandlerForPath:(NSString *)path handler:(RequestHandler)handler;

/*!
 @method setWebSocketUpgradeHandler:forPath:
 
 @abstract Registers a handler for WebSocket upgrade requests on a specific path.
 
 @param handler The handler block to invoke for WebSocket upgrades.
 @param path The URL path to handle WebSocket upgrades on.
 
 @discussion When a request with "Upgrade: websocket" header is received
 for the specified path, the handler will be called with the request
 and the underlying connection. The handler should complete the WebSocket
 handshake and take ownership of the connection.
 */
- (void)setWebSocketUpgradeHandler:(WebSocketUpgradeHandler)handler forPath:(NSString *)path;

/*!
 @method createWebSocketAcceptKeyForKey:
 
 @abstract Creates the Sec-WebSocket-Accept value for a WebSocket handshake.
 
 @param clientKey The Sec-WebSocket-Key from the client request.
 @return The base64-encoded accept key to send in the response.
 */
+ (NSString *)createWebSocketAcceptKeyForKey:(NSString *)clientKey;

/*!
 @method webSocketHandshakeResponseDataForRequest:
 
 @abstract Creates the complete HTTP response data for a WebSocket upgrade.
 
 @param request The WebSocket upgrade request.
 @return The HTTP response data to send to complete the handshake.
 */
+ (NSData *)webSocketHandshakeResponseDataForRequest:(HttpRequest *)request;

@end

NS_ASSUME_NONNULL_END

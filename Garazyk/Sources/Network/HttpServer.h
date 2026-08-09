// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoHttpRequest;
@class ATProtoHttpResponse;
@class ATProtoHttpServer;
/**
 * @abstract Defines the ATProtoNetworkConnection protocol contract.
 */
@protocol ATProtoNetworkConnection;

/*!
 @header ATProtoHttpServer.h
 
 @abstract HTTP server implementation for the PDS.
 
 @discussion This header defines the HTTP server interface for handling
 incoming requests. The server supports route registration, request/response
 handling, and lifecycle management.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

/*!
 
 @abstract Block type for handling HTTP requests.
 
 @param request The incoming HTTP request.
 @param response The response object to populate.
 */
typedef void (^RequestHandler)(ATProtoHttpRequest *request, ATProtoHttpResponse *response);
typedef void (^WebSocketRequestHandler)(ATProtoHttpRequest *request, ATProtoHttpResponse *response, id<ATProtoNetworkConnection> connection);

/*!
 @abstract Default concurrency limit applied when a server is created without an explicit one.
 */
extern const NSUInteger kHttpServerDefaultMaxConcurrentRequests;

/*!
 @class ATProtoHttpServer
 
 @abstract HTTP server for handling PDS requests.
 
 @discussion ATProtoHttpServer provides a simple HTTP server implementation
 for the PDS. It supports route registration for different HTTP methods
 and paths, with handlers invoked for matching requests.
 
 @code
 ATProtoHttpServer *server = [ATProtoHttpServer serverWithPort:8080];
 
 [server addRoute:@"GET" path:@"/health" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *resp) {
     resp.statusCode = 200;
     [resp setBody:@"OK"];
 }];
 
 [server startWithError:nil];
 @endcode
 */
/**
 * @abstract Declares the ATProtoHttpServer public API.
 */
@interface ATProtoHttpServer : NSObject

/*! Optional local host/interface to bind to (nil binds to all interfaces). */
@property (nonatomic, readonly, nullable) NSString *host;

/*! The port the server is listening on. */
@property (atomic, readonly) NSUInteger port;

/*! YES if the server is currently running. */
@property (atomic, readonly, getter=isRunning) BOOL running;

/*! Optional callback invoked for every request received. */
@property (nonatomic, copy, nullable) void (^didReceiveRequest)(ATProtoHttpRequest *request, ATProtoHttpResponse *response);

/*! Maximum number of requests this server dispatches concurrently. */
@property (nonatomic, readonly) NSUInteger maxConcurrentRequests;

/*!
 @method serverWithPort:

 @abstract Creates a server instance for the specified port.

 @param port The port to listen on.
 @return A new ATProtoHttpServer instance.
 */
+ (instancetype)serverWithPort:(NSUInteger)port;

/*!
 @method serverWithHost:port:

 @abstract Creates a server instance bound to a specific local host/interface.

 @param host The local host/interface to bind to (e.g. 127.0.0.1).
 @param port The port to listen on (0 for ephemeral port assignment).
 */
+ (instancetype)serverWithHost:(NSString *)host port:(NSUInteger)port;

/*!
 @method serverWithHost:port:maxConcurrentRequests:

 @abstract Creates a server with an explicit concurrency limit.

 @discussion Request handling is dispatched to the global concurrent queue, and a
 handler that blocks — waiting on an outbound HTTP call, for example — holds a
 global worker for its whole duration. A server whose handlers may block while
 another server in the same process must answer them needs a limit well below the
 default, or the two can together demand more workers than the pool provides.
 Admin UI listeners embedded alongside a service listener are exactly that case.

 @param host The local host/interface to bind to (e.g. 127.0.0.1).
 @param port The port to listen on (0 for ephemeral port assignment).
 @param maxConcurrentRequests Concurrency limit; 0 selects the default.
 */
+ (instancetype)serverWithHost:(nullable NSString *)host
                          port:(NSUInteger)port
         maxConcurrentRequests:(NSUInteger)maxConcurrentRequests;

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
 @method addWebSocketRoute:path:handler:

 @abstract Registers a WebSocket upgrade handler for an exact path.

 @param path The URL path to match for upgrades.
 @param handler The handler invoked after a successful upgrade handshake.
 */
- (void)addWebSocketRoute:(NSString *)path handler:(WebSocketRequestHandler)handler;

@end

NS_ASSUME_NONNULL_END

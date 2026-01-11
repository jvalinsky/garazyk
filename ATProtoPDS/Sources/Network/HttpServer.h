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

@end

NS_ASSUME_NONNULL_END

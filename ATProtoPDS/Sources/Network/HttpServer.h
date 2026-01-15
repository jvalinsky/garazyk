#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@class HttpServer;

/// A block type for handling HTTP requests.
///
/// @param request The incoming HTTP request containing headers, body, and path.
/// @param response The response object used to send the HTTP response back to the client.
typedef void (^RequestHandler)(HttpRequest *request, HttpResponse *response);

/// HttpServer provides a lightweight HTTP server implementation for handling
/// incoming HTTP requests, routing them to appropriate handlers, and managing
/// server lifecycle.
///
/// The server supports route-based request handling where handlers are registered
/// for specific HTTP methods and paths. Each incoming request triggers the
/// registered handler if a matching route is found.
///
/// Example:
/// @code
/// HttpServer *server = [HttpServer serverWithPort:8080];
/// [server addRoute:@"GET" path:@"/api/users" handler:^(HttpRequest *req, HttpResponse *res) {
///     // Handle request
/// }];
/// [server startWithError:nil];
/// @endcode
@interface HttpServer : NSObject

/// The port number the server is listening on. This value is set when the server
/// is initialized and cannot be changed while the server is running.
@property (nonatomic, readonly) uint16_t port;

/// A boolean indicating whether the server is currently running and accepting
/// connections.
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// An optional callback block invoked whenever the server receives a new request.
/// This provides a hook for logging, monitoring, or global request preprocessing.
///
/// @note This block is called before any route-specific handlers.
@property (nonatomic, copy, nullable) void (^didReceiveRequest)(HttpRequest *request, HttpResponse *response);

/// Creates and configures a new HTTP server instance bound to the specified port.
///
/// @param port The port number to listen on (0-65535).
/// @return A newly initialized HttpServer instance.
+ (instancetype)serverWithPort:(uint16_t)port;

/// Starts the HTTP server and begins accepting incoming connections.
///
/// @param error On return, contains an error if the server failed to start.
/// @return YES if the server started successfully, NO otherwise.
- (BOOL)startWithError:(NSError * _Nullable *)error;

/// Stops the HTTP server and closes all active connections.
/// Any pending requests will be aborted.
- (void)stop;

/// Registers a handler for a specific HTTP method and path combination.
///
/// @param method The HTTP method to match (e.g., @"GET", @"POST").
/// @param path The URL path to match (e.g., @"/api/users").
/// @param handler The block to invoke when a matching request is received.
- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler;

/// Registers a handler for any HTTP method at the specified path.
///
/// This is a convenience method that registers handlers for GET, POST, PUT,
/// DELETE, and PATCH methods at the given path.
///
/// @param path The URL path to match.
/// @param handler The block to invoke when a matching request is received.
- (void)addHandlerForPath:(NSString *)path handler:(RequestHandler)handler;

@end

NS_ASSUME_NONNULL_END

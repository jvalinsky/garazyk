/*!
 @file PLCServer.h

 @abstract HTTP server for the PLC directory service.

 @discussion
    Provides an HTTP server that implements the PLC directory API.
    Handles DID resolution, operation submission, and audit log queries.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PLC/PLCStore.h"
#import "PLC/PLCAuditor.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PLCServer

 @abstract HTTP server implementing the PLC directory API.

 @discussion
    Serves the PLC directory API endpoints including:
    - GET /:did - Resolve DID document
    - GET /:did/log - Get audit log
    - POST /:did - Submit operation

    The server validates incoming operations using the PLCAuditor before
    persisting them via the PLCStore.

    Thread Safety: All public methods are thread-safe.
 */
@interface PLCServer : NSObject

/*! The underlying HTTP server instance. */
@property (nonatomic, readonly) HttpServer *httpServer;

/*! The PLC store for operations. */
@property (nonatomic, readonly) id<PLCStore> store;

/*! Admin secret for operator routes. */
@property (nonatomic, readonly, nullable) NSString *adminSecret;

/*!
 @method initWithStore:auditor:port:

 @abstract Initializes the PLC server with dependencies.

 @param store The PLC store for persisting operations.
 @param auditor The auditor for validating operations.
 @param port The TCP port to listen on.

 @return A new PLC server instance.
 */
- (instancetype)initWithStore:(id<PLCStore>)store
                     auditor:(PLCAuditor *)auditor
                        port:(NSUInteger)port;

/*!
 @method initWithStore:auditor:adminSecret:port:

 @abstract Initializes the PLC server with admin auth.

 @param store The PLC store for persisting operations.
 @param auditor The auditor for validating operations.
 @param adminSecret Secret for admin route authentication.

 @return A new PLC server instance.
 */
- (instancetype)initWithStore:(id<PLCStore>)store
                     auditor:(PLCAuditor *)auditor
                adminSecret:(NSString *)adminSecret
                        port:(NSUInteger)port;

/*!
 @method initWithStore:auditor:host:port:

 @abstract Initializes the PLC server with dependencies and a bind host.

 @param store The PLC store for persisting operations.
 @param auditor The auditor for validating operations.
 @param host The host address to bind to (e.g. @"0.0.0.0" for all interfaces).
 @param port The TCP port to listen on.

 @return A new PLC server instance.
 */
- (instancetype)initWithStore:(id<PLCStore>)store
                     auditor:(PLCAuditor *)auditor
                        host:(NSString *)host
                        port:(NSUInteger)port;

/*!
 @method startWithError:

 @abstract Starts the HTTP server.

 @param error On failure, set to an error describing the failure.
 @return YES on success, NO on failure.
 */
- (BOOL)startWithError:(NSError **)error;

/*!
 @method stop

 @abstract Stops the HTTP server.
 */
- (void)stop;

/*!
 @method setCorsHeaders:forRequest:

 @abstract Sets CORS response headers for cross-origin requests.

 @discussion
    Adds Access-Control-Allow-Origin, Allow-Methods, Allow-Headers,
    Max-Age, and Vary headers to the response. Called automatically
    by all PLC route handlers and OPTIONS preflight routes.

 @param response The HTTP response to add CORS headers to.
 @param request The incoming HTTP request (used to read the Origin header).
 */
- (void)setCorsHeaders:(HttpResponse *)response forRequest:(HttpRequest *)request;

@end

NS_ASSUME_NONNULL_END

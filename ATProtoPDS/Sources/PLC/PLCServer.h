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

@end

NS_ASSUME_NONNULL_END

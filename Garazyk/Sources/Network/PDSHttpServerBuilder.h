// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSHttpServerBuilder.h

 @abstract Builder for configuring and creating HTTP server instances.

 @discussion PDSHttpServerBuilder encapsulates HTTP server route configuration,
 extracting this responsibility from PDSController. It configures XRPC handlers,
 OAuth endpoints, explore UI, and other routes in a testable, reusable manner.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSController;
@class PDSApplication;
@class PDSConfiguration;
@class JWTMinter;
@class PDSServiceDatabases;
@class XrpcDispatcher;
@class SubscribeReposHandler;

/*!
 @class PDSHttpServerBuilder

 @abstract Builds and configures HTTP server instances for the PDS.

 @discussion This builder encapsulates the route configuration logic previously
 embedded in PDSController.startServerWithError:. It provides a cleaner separation
 of concerns and enables easier testing of server configuration.

 @code
 PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
 builder.port = 2583;
 builder.controller = controller;
 builder.jwtMinter = minter;
 builder.serviceDatabases = databases;

 NSError *error = nil;
 HttpServer *server = [builder buildWithError:&error];
 if (server) {
     [server startWithError:nil];
 }
 @endcode
 */
@interface PDSHttpServerBuilder : NSObject

#pragma mark - Configuration Properties

/*! Port for the HTTP server (default: 2583). */
@property (nonatomic, assign) NSUInteger port;

/*! Data directory for storing and retrieving files. */
@property (nonatomic, copy, nullable) NSString *dataDirectory;

/*! The PDS controller for handler callbacks (legacy). */
@property (nonatomic, weak, nullable) PDSController *controller;

/*! The PDS application for service-based handlers (preferred). */
@property (nonatomic, weak, nullable) PDSApplication *application;

/*! JWT minter for OAuth handlers. */
@property (nonatomic, strong, nullable) JWTMinter *jwtMinter;

/*! Service databases for OAuth and other handlers. */
@property (nonatomic, strong, nullable) PDSServiceDatabases *serviceDatabases;

/*! XRPC dispatcher for method routing. */
@property (nonatomic, strong, nullable) XrpcDispatcher *xrpcDispatcher;

/*! subscribeRepos handler for main-port WebSocket upgrades. */
@property (nonatomic, strong, nullable) SubscribeReposHandler *subscribeReposHandler;

/*! Issuer URL for NodeInfo (e.g., "https://localhost:2583"). */
@property (nonatomic, copy, nullable) NSString *issuer;

#pragma mark - Feature Flags

/*! Whether to register XRPC routes (default: YES). */
@property (nonatomic, assign) BOOL enableXrpc;

/*! Whether to register OAuth routes (default: YES). */
@property (nonatomic, assign) BOOL enableOAuth;

/*! Whether to register OAuth Demo routes (default: YES). */
@property (nonatomic, assign) BOOL enableOAuthDemo;

/*! Whether to register MST Viewer routes (default: YES). */
@property (nonatomic, assign) BOOL enableMSTViewer;

/*! Whether to register NodeInfo routes (default: YES). */
@property (nonatomic, assign) BOOL enableNodeInfo;

#pragma mark - Initialization

/*!
 @method init

 @abstract Creates a builder with default settings.

 @return An initialized builder with all features enabled.
 */
- (instancetype)init;

/*!
 @method initWithConfiguration:

 @abstract Creates a builder from application configuration.

 @param configuration The PDS configuration to use.
 @return An initialized builder configured from settings.
 */
- (instancetype)initWithConfiguration:(PDSConfiguration *)configuration;

#pragma mark - Building

/*!
 @method buildWithError:

 @abstract Builds and configures an HTTP server.

 @discussion Creates an HttpServer instance and registers all enabled routes
 based on the builder's configuration. The server is returned in a stopped
 state; the caller must start it.

 @param error On return, contains an error if building failed.
 @return A configured HttpServer instance, or nil on failure.
 */
- (nullable HttpServer *)buildWithError:(NSError **)error;

/*!
 @method configureServer:error:

 @abstract Configures an existing HTTP server with routes.

 @discussion Registers all enabled routes on the provided server. Useful when
 the caller needs to create the server themselves (e.g., for testing).

 @param server The HTTP server to configure.
 @param error On return, contains an error if configuration failed.
 @return YES if configuration succeeded, NO otherwise.
 */
- (BOOL)configureServer:(HttpServer *)server error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

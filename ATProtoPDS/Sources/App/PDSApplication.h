/*!
 @file PDSApplication.h
 
 @abstract Main application facade for the ATProto PDS.
 
 @discussion PDSApplication is the new recommended entry point for the PDS.
 It composes all services, controllers, and infrastructure components,
 providing a clean interface for server lifecycle management.
 
 This class replaces PDSController as the primary entry point for new code.
 PDSController remains available for backward compatibility but delegates
 to PDSApplication internally.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSConfiguration;
@class PDSServiceDatabases;
@class PDSDatabasePool;
@class PDSAccountService;
@class PDSRecordService;
@class PDSBlobService;
@class PDSRepositoryService;
@class PDSAdminController;
@class PDSController;
@class JWTMinter;
@class HttpServer;
@class PDSRelayService;
@class SubscribeReposHandler;

@protocol PDSAccountService;
@protocol PDSAdminController;
@protocol PDSEmailProvider;

/*!
 @class PDSApplication

 @abstract Main application facade composing all PDS services.

 @discussion PDSApplication provides a unified entry point for the PDS,
 managing the lifecycle of all components including:
 
 - Database pools (service and user databases)
 - Service layer (account, record, blob, repository)
 - Admin controller (moderation, labeling, takedowns)
 - HTTP server (including WebSocket upgrades for subscribeRepos)
 - JWT minting for authentication

 @code
 // Create and start the application
 PDSApplication *app = [PDSApplication sharedApplication];
 
 NSError *error = nil;
 if (![app startWithError:&error]) {
     NSLog(@"Failed to start: %@", error);
     return;
 }
 
 // Access services directly
 NSDictionary *account = [app.accountService getAccountForDid:@"did:plc:..." error:nil];
 
 // Or use admin controller for administrative operations
 [app.adminController takeDownAccount:@"did:plc:..." reason:@"TOS violation" error:nil];
 
 // Stop when done
 [app stop];
 @endcode
 */
@interface PDSApplication : NSObject

#pragma mark - Singleton

/*!
 @method sharedApplication

 @abstract Returns the shared application instance.

 @discussion Creates the shared instance on first access using default
 configuration from PDSConfiguration.sharedConfiguration.

 @return The shared PDSApplication instance.
 */
+ (instancetype)sharedApplication;

#pragma mark - Initialization

/*!
 @method initWithConfiguration:

 @abstract Initializes the application with the given configuration.

 @param configuration The configuration to use. If nil, uses default configuration.
 @return An initialized PDSApplication instance.
 */
- (instancetype)initWithConfiguration:(nullable PDSConfiguration *)configuration;

- (instancetype)initWithConfiguration:(nullable PDSConfiguration *)configuration dataDirectory:(nullable NSString *)dataDirectory NS_DESIGNATED_INITIALIZER;

/*!
 @method initWithConfiguration:dataDirectory:serviceMaxSize:userDatabaseMaxSize:didCacheMaxSize:sequencerMaxSize:

 @abstract Initializes the application with explicit pool-size composition inputs.

 @discussion This is used by legacy compatibility facades to preserve constructor
 semantics while delegating runtime composition to PDSApplication.
 */
- (instancetype)initWithConfiguration:(nullable PDSConfiguration *)configuration
                        dataDirectory:(nullable NSString *)dataDirectory
                       serviceMaxSize:(NSUInteger)serviceMaxSize
                  userDatabaseMaxSize:(NSUInteger)userDatabaseMaxSize
                      didCacheMaxSize:(NSUInteger)didCacheMaxSize
                    sequencerMaxSize:(NSUInteger)sequencerMaxSize;

/*!
 @method initWithDataDirectory:

 @abstract Initializes the application with a specific data directory.

 @param dataDirectory Path to the data directory for databases and blobs.
 @return An initialized PDSApplication instance.
 */
- (instancetype)initWithDataDirectory:(NSString *)dataDirectory;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Lifecycle

/*!
 @method startWithError:

 @abstract Starts the application servers.

 @discussion Starts the HTTP server for XRPC endpoints. The
 com.atproto.sync.subscribeRepos stream is exposed via WebSocket upgrade
 on the same HTTP port. All services are initialized during init, so this
 method only starts the network listener.

 @param error On return, contains an error if startup failed.
 @return YES if the application started successfully, NO otherwise.
 */
- (BOOL)startWithError:(NSError **)error;

/*!
 @method stop

 @abstract Stops the application and releases resources.

 @discussion Stops all servers, closes database connections, and flushes
 logs. After calling stop, the application can be restarted with startWithError:.
 */
- (void)stop;

/*!
 @property running

 @abstract Whether the application is currently running.
 */
@property (nonatomic, readonly, getter=isRunning) BOOL running;

#pragma mark - Configuration

/*!
 @property configuration

 @abstract The configuration used by this application.
 */
@property (nonatomic, strong, readonly) PDSConfiguration *configuration;

/*!
 @property dataDirectory

 @abstract Path to the data directory.
 */
@property (nonatomic, copy, readonly) NSString *dataDirectory;

/*!
 @property httpPort

 @abstract The HTTP server port (default: 2583).

 @discussion Can be changed before calling startWithError:. After starting,
 reflects the actual port the server is listening on.
 */
@property (nonatomic, assign) NSUInteger httpPort;

/*!
 @property wsPort

 @abstract Compatibility property for subscribeRepos streaming port.

 @discussion subscribeRepos is served via WebSocket upgrade on the HTTP port.
 This property is retained for compatibility and reflects the active HTTP port
 after startup.
 */
@property (nonatomic, assign, readonly) NSUInteger wsPort
    DEPRECATED_MSG_ATTRIBUTE("subscribeRepos uses HTTP port upgrades; use httpPort");

#pragma mark - Infrastructure

/*!
 @property serviceDatabases

 @abstract Service-level database connections.

 @discussion Provides access to the shared service database, DID cache,
 and sequencer databases.
 */
@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;

/*!
 @property userDatabasePool

 @abstract Pool for user-specific (actor) databases.

 @discussion Each user's repository data is stored in a separate database
 managed by this pool.
 */
@property (nonatomic, strong, readonly) PDSDatabasePool *userDatabasePool;

/*!
 @property jwtMinter

 @abstract JWT minter for creating access and refresh tokens.
 */
@property (nonatomic, strong, readonly) JWTMinter *jwtMinter;

/*!
 @property httpServer

 @abstract The HTTP server instance (available after start).
 */
@property (nonatomic, strong, readonly, nullable) HttpServer *httpServer;

/*!
 @property relayService

 @abstract Service for notifying external relays of updates.
 */
@property (nonatomic, strong, readonly) PDSRelayService *relayService;

/*!
 @property subscribeReposHandler

 @abstract Handler for the subscribeRepos firehose.
 */
@property (nonatomic, strong, readonly) SubscribeReposHandler *subscribeReposHandler;

/*!
 @property emailProvider
 
 @abstract The pluggable email provider for sending notifications.
 */
@property (nonatomic, strong, readonly, nullable) id<PDSEmailProvider> emailProvider;

#pragma mark - Services

/*!
 @property accountService

 @abstract Service for account management operations.

 @discussion Provides account creation, authentication, token refresh,
 and account deletion.
 */
@property (nonatomic, strong, readonly) id<PDSAccountService> accountService;

/*!
 @property recordService

 @abstract Service for record CRUD operations.

 @discussion Provides record creation, retrieval, listing, and deletion
 within user repositories.
 */
@property (nonatomic, strong, readonly) PDSRecordService *recordService;

/*!
 @property blobService

 @abstract Service for blob storage operations.

 @discussion Provides blob upload, retrieval, listing, and deletion.
 */
@property (nonatomic, strong, readonly) PDSBlobService *blobService;

/*!
 @property repositoryService

 @abstract Service for repository operations.

 @discussion Provides MST management, commit processing, and repo sync.
 */
@property (nonatomic, strong, readonly) PDSRepositoryService *repositoryService;

#pragma mark - Controllers

/*!
 @property adminController

 @abstract Controller for administrative operations.

 @discussion Provides account takedowns, moderation actions, and labeling.
 */
@property (nonatomic, strong, readonly) id<PDSAdminController> adminController;

#pragma mark - Backward Compatibility

/*!
 @property legacyController

 @abstract The legacy PDSController for backward compatibility.

 @discussion Provides access to a PDSController instance that wraps this
 application. Use this when interfacing with code that expects PDSController.

 @note Prefer using the services directly for new code.
 */
@property (nonatomic, strong, readonly) PDSController *legacyController;

@end

NS_ASSUME_NONNULL_END

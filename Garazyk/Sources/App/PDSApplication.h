// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class ATProtoServiceConfiguration;
@class PDSDatabase;
@class PDSServiceDatabases;
@class PDSDatabasePool;
@class PDSRepositoryService;
@class PDSBlobService;
@class PDSRelayService;
@class PDSController;
@class RateLimiter;
@class JWTMinter;
@class SubscribeReposHandler;
@class PDSRecordService;
@class PDSBlobAuditManager;
@class HttpServer;
/**
 * @abstract Defines the PDSAccountService protocol contract.
 */
@protocol PDSAccountService;
@protocol PDSEmailProvider;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 * PDSApplication is the root object of the PDS server. It initializes and manages
 * the lifecycle of all services.
 */
/**
 * @abstract Declares the PDSApplication public API.
 */
@interface PDSApplication : NSObject

/**
 * Returns the shared application singleton.
 */
+ (instancetype)sharedApplication;

/**
 * Initializes a new PDSApplication with the given data directory.
 * @param dataDirectory Path to the directory where data and configuration are stored.
 */
- (instancetype)initWithDataDirectory:(NSString *)dataDirectory;

/**
 * Initializes a new PDSApplication with an optional configuration.
 */
- (instancetype)initWithConfiguration:(nullable ATProtoServiceConfiguration *)configuration;

/**
 * Initializes a new PDSApplication with configuration and data directory.
 */
- (instancetype)initWithConfiguration:(nullable ATProtoServiceConfiguration *)configuration
                        dataDirectory:(nullable NSString *)dataDirectory;

/**
 * Full initializer for PDSApplication with pool size overrides.
 */
- (instancetype)initWithConfiguration:(nullable ATProtoServiceConfiguration *)configuration
                        dataDirectory:(nullable NSString *)dataDirectory
                       serviceMaxSize:(NSUInteger)serviceMaxSize
                  userDatabaseMaxSize:(NSUInteger)userDatabaseMaxSize
                      didCacheMaxSize:(NSUInteger)didCacheMaxSize
                    sequencerMaxSize:(NSUInteger)sequencerMaxSize;

/**
 * Starts all PDS services.
 * @param error populated if startup fails.
 */
- (BOOL)startWithError:(NSError **)error;

/**
 * Stops all PDS services.
 */
- (void)stop;

/*! Configuration for the application. */
@property (nonatomic, strong, readonly) ATProtoServiceConfiguration *configuration;

/*! The data directory used for storage. */
@property (nonatomic, copy, readonly) NSString *dataDirectory;

/*! Primary database connection. */
@property (nonatomic, strong, readonly) PDSDatabase *database;

/*! Service databases. */
@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;

/*! User database pool. */
@property (nonatomic, strong, readonly) PDSDatabasePool *userDatabasePool;

/*! Blob management service. */
@property (nonatomic, strong, readonly) PDSBlobService *blobService;

/*! Repository management service. */
@property (nonatomic, strong, readonly) PDSRepositoryService *repositoryService;

/*! Account management service. */
@property (nonatomic, strong, readonly) id<PDSAccountService> accountService;

/*! Record management service. */
@property (nonatomic, strong, readonly) PDSRecordService *recordService;

/*! Service for notifying external relays of updates. */
@property (nonatomic, strong, readonly) PDSRelayService *relayService;

/*! Administrative operations controller. */
@property (nonatomic, strong, readonly) id<PDSAdminController> adminController;

/*! Blob audit manager. */
@property (nonatomic, strong, readonly) PDSBlobAuditManager *blobAuditManager;

/*! Email provider. */
@property (nonatomic, strong, readonly, nullable) id<PDSEmailProvider> emailProvider;

/*! The rate limiter for throttling requests. */
@property (nonatomic, strong, readonly) RateLimiter *rateLimiter;

/*! JWT minting for access tokens. */
@property (nonatomic, strong, readonly) JWTMinter *jwtMinter;

/*! Handler for the subscribeRepos firehose. */
@property (nonatomic, strong, readonly) SubscribeReposHandler *subscribeReposHandler;

/*! The HTTP server instance. */
@property (nonatomic, strong, readonly) HttpServer *httpServer;

/*! Port for the HTTP XRPC server (default 2583). */
@property (nonatomic, assign) NSUInteger httpPort;

/*! WebSocket port; mirrors httpPort. */
@property (nonatomic, assign, readonly) NSUInteger wsPort;

/*! Whether the application services are currently running. */
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;

/**
 * A convenience property that returns a legacy PDSController instance.
 *
 * @discussion Provides access to a PDSController instance that wraps this
 * application. Use this when interfacing with code that expects PDSController.
 *
 * @note Prefer using the services directly for new code.
 */
/**
 * @abstract Exposes the legacy controller value.
 */
@property (nonatomic, strong, readonly) PDSController *legacyController;

@end

NS_ASSUME_NONNULL_END

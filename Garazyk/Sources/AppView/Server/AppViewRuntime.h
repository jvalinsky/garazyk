/*!
 @file AppViewRuntime.h

 @abstract Top-level coordinator for the standalone AppView server.

 @discussion AppViewRuntime owns and wires together all three planes:
  - Ingest: AppViewIngestEngine + RelayClient connections
  - Backfill: AppViewBackfillOrchestrator + worker pool
  - Query API: HTTP server with app.bsky.* XRPC routes

 Lifecycle:
  1. loadConfiguration: / loadConfigurationFromEnvironment
  2. startWithError:
  3. (running — ingest events flow, backfill workers execute)
  4. stop

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AppViewConfiguration;
@class AppViewDatabase;

/*!
 @class AppViewRuntime
 
 @abstract Manages the complete AppView server lifecycle.
 */
@interface AppViewRuntime : NSObject

/*! The active configuration. Populated after loadConfiguration*. */
@property (nonatomic, strong, readonly) AppViewConfiguration *configuration;

/*! Returns the AppView database. */
@property (nonatomic, strong, readonly) AppViewDatabase *database;

/*! Returns YES if the runtime is running. */
@property (nonatomic, readonly) BOOL isRunning;

/*!
 @method sharedRuntime

 @abstract Singleton accessor for process-level use (e.g. from `main.m`).
 */
+ (instancetype)sharedRuntime;

/*!
 @method loadConfiguration:error:

 @abstract Load configuration from a TOML/JSON file path.
 Returns NO if the file cannot be read or is invalid.
 */
- (BOOL)loadConfiguration:(NSString *)path error:(NSError **)error;

/*!
 @method loadConfigurationFromEnvironment

 @abstract Load configuration from environment variables.
 */
- (void)loadConfigurationFromEnvironment;

/*!
 @method startWithError:

 @abstract Open the database, run migrations, start all planes.
 Returns NO if startup fails.
 */
- (BOOL)startWithError:(NSError **)error;

/*!
 @method stop

 @abstract Gracefully stop all planes and flush state.
 */
- (void)stop;

@end

NS_ASSUME_NONNULL_END

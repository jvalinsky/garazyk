// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MikrusRuntime.h
 * @abstract Top-level coordinator for the Mikrus link index service.
 */

#import <Foundation/Foundation.h>
#import "AppView/Server/Ingest/AppViewIngestEngine.h"

NS_ASSUME_NONNULL_BEGIN

@class MikrusConfiguration;
@class MikrusDatabase;

/**
 * @abstract Coordinates the initialization and lifecycle of the Mikrus service.
 */
@interface MikrusRuntime : NSObject <AppViewIngestEngineDelegate>

/**
 * @abstract Current service configuration.
 */
@property (nonatomic, strong, readonly) MikrusConfiguration *configuration;

/**
 * @abstract Database handle for the link index.
 */
@property (nonatomic, strong, readonly) MikrusDatabase *database;

/**
 * @abstract Whether the runtime service is actively running.
 */
@property (nonatomic, readonly) BOOL isRunning;

/**
 * @abstract Returns the shared singleton runtime.
 */
+ (instancetype)sharedRuntime;

/**
 * @abstract Loads service configuration from a file path.
 * @param path File path to the configuration.
 * @param error Receives failure details.
 * @return YES if loaded successfully.
 */
- (BOOL)loadConfiguration:(NSString *)path error:(NSError **)error;

/**
 * @abstract Loads configuration from environment variables.
 */
- (void)loadConfigurationFromEnvironment;

/**
 * @abstract Starts the Mikrus runtime service.
 * @param error Receives startup failure details.
 * @return YES if started successfully.
 */
- (BOOL)startWithError:(NSError **)error;

/**
 * @abstract Stops the service runtime.
 */
- (void)stop;

@end

NS_ASSUME_NONNULL_END

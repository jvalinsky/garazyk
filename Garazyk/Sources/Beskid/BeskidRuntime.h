// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file GZBeskidRuntime.h
 * @abstract Top-level coordinator for the Beskid edge record and identity cache.
 */

#import <Foundation/Foundation.h>

#import "Runtime/GZServiceLifecycle.h"

NS_ASSUME_NONNULL_BEGIN

@class GZBeskidConfiguration;
@class GZBeskidDatabase;

/**
 * @abstract Coordinates the initialization and lifecycle of the Beskid service.
 */
@interface GZBeskidRuntime : NSObject <GZServiceRuntimeProtocol>

/**
 * @abstract Current service configuration.
 */
@property (nonatomic, strong, readonly) GZBeskidConfiguration *configuration;

/**
 * @abstract Database handle for the edge cache.
 */
@property (nonatomic, strong, readonly) GZBeskidDatabase *database;

/**
 * @abstract Whether the runtime service is actively running.
 */
@property (nonatomic, readonly) BOOL isRunning;

#pragma mark - Admin UI

/** @abstract Admin UI bind address; 127.0.0.1 by default. */
@property (nonatomic, copy) NSString *adminUIHost;
/** @abstract Admin UI port; 2595 by default. */
@property (nonatomic, assign) NSUInteger adminUIPort;
/** @abstract Admin password; empty disables the embedded admin listener. */
@property (nonatomic, copy) NSString *adminPassword;

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
 * @abstract Starts the Beskid runtime service.
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

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayConfiguration.h

 @abstract Configuration for ATProto Relay (Sync v1.1)

 @discussion
    RelayConfiguration manages settings for the relay including:
    - Upstream PDS URLs to subscribe to
    - Downstream consumer port
    - Event retention window (default 72 hours per Sync v1.1)
    - Validation mode (lenient/strict/log-only)

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Defines RelayValidationMode values exposed by this API.
 */
typedef NS_ENUM(NSInteger, RelayValidationMode) {
    RelayValidationModeLenient,     // Validate but forward all events
    RelayValidationModeStrict,       // Drop events that fail validation
    RelayValidationModeLogOnly      // Validate strictly, log failures, forward anyway (default)
};

/**
 * @abstract Declares the RelayConfiguration public API.
 */
@interface RelayConfiguration : NSObject

/**
 * @abstract Exposes the upstream urls value.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *upstreamURLs;
@property (nonatomic, assign, readonly) uint16_t downstreamPort;
@property (nonatomic, assign, readonly) NSUInteger retentionHours;
@property (nonatomic, assign, readonly) RelayValidationMode validationMode;
@property (nonatomic, assign, readonly) NSUInteger maxDownstreamConnections;
@property (nonatomic, copy, readonly, nullable) NSString *dataDirectory;
@property (nonatomic, copy, readonly, nullable) NSString *adminPassword;
@property (nonatomic, assign, readonly) BOOL logLevelDebug;

/**
 * @abstract Performs the initWithUpstreamURLs operation.
 */
- (instancetype)initWithUpstreamURLs:(NSArray<NSString *> *)upstreamURLs
                    downstreamPort:(uint16_t)port
                     retentionHours:(NSUInteger)hours
                   validationMode:(RelayValidationMode)mode;

/**
 * @abstract Returns the operation result.
 */
- (instancetype)init NS_UNAVAILABLE;
/**
 * @abstract Returns the operation result.
 */
+ (instancetype)configuration NS_UNAVAILABLE;

/**
 * @abstract Performs the configurationFromFile operation.
 */
+ (nullable instancetype)configurationFromFile:(NSString *)path error:(NSError **)error;
/**
 * @abstract Returns the configuration from environment result.
 */
+ (nullable instancetype)configurationFromEnvironment;

@end

NS_ASSUME_NONNULL_END
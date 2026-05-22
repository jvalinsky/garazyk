// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MikrusConfiguration.h
 * @abstract Runtime configuration for the Mikrus link-index service.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Configuration container for Mikrus service parameters.
 */
@interface MikrusConfiguration : NSObject

/** @abstract List of relay URLs. */
@property (nonatomic, strong) NSArray<NSString *> *relayURLs;
/** @abstract Data storage directory path. */
@property (nonatomic, copy) NSString *dataDirectory;
/** @abstract HTTP listening port. */
@property (nonatomic, assign) NSUInteger httpPort;
/** @abstract Interval in milliseconds for cursor checkpoints. */
@property (nonatomic, assign) NSUInteger cursorCheckpointIntervalMs;
/** @abstract Flag to enable or disable ingestion. */
@property (nonatomic, assign) BOOL ingestEnabled;

#pragma mark - Rate Limiting

/** @abstract Enable per-IP rate limiting (default: YES). */
@property (nonatomic, assign) BOOL rateLimitEnabled;
/** @abstract Maximum requests per IP per window (default: 200). */
@property (nonatomic, assign) NSInteger rateLimitIpLimit;
/** @abstract IP rate limit window in seconds (default: 60). */
@property (nonatomic, assign) NSTimeInterval rateLimitIpWindowSeconds;

/**
 * @abstract Returns a default configuration instance.
 */
+ (instancetype)defaultConfiguration;

/**
 * @abstract Populates configuration from environment variables.
 */
+ (instancetype)configurationFromEnvironment;

/**
 * @abstract Loads configuration parameters from a dictionary.
 * @param dictionary The configuration dictionary.
 */
- (void)loadFromDictionary:(NSDictionary *)dictionary;

/**
 * @abstract Validates the current configuration state.
 * @param error Receives failure details.
 * @return YES if valid.
 */
- (BOOL)validate:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

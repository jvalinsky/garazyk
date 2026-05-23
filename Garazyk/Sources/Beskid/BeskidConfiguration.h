// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file BeskidConfiguration.h
 * @abstract Runtime configuration for the Beskid edge-cache service.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Configuration container for Beskid service parameters.
 */
@interface BeskidConfiguration : NSObject

/** @abstract Data storage directory path. */
@property (nonatomic, copy) NSString *dataDirectory;
/** @abstract HTTP listening port. */
@property (nonatomic, assign) NSUInteger httpPort;
/** @abstract Domain name for service proxying (e.g., slingshot.microcosm.blue). */
@property (nonatomic, copy) NSString *domain;
/** @abstract TTL in seconds for cached repo records (default: 3600). */
@property (nonatomic, assign) NSTimeInterval cacheRecordTtlSeconds;
/** @abstract TTL in seconds for cached identities (default: 86400). */
@property (nonatomic, assign) NSTimeInterval cacheIdentityTtlSeconds;

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

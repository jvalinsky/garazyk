// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RateLimiter.h

 @abstract Declares rate-limiting interfaces for request-throttling policy enforcement.

 @discussion Defines APIs and configuration surfaces for evaluating and recording request rates under policy limits. Exposes control primitives used by handlers without embedding endpoint-specific logic.
 */

/**
 * @file RateLimiter.h
 * @brief API rate limiting for PDS operations
 *
 * RateLimiter implements sliding window rate limiting for different resource
 * types (DID-based API calls, IP-based requests, blob uploads). Uses SQLite
 * for persistent rate limit tracking across server restarts.
 *
 * Rate limits prevent abuse by tracking request counts per identifier within
 * time windows (defaults vary by limit type). Limits are configurable per type.
 *
 * Thread-safe through SQLite serialization.
 *
 * @see HttpServer, HttpRequest
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

/**
 * @abstract Rate limit buckets tracked by request identity and resource type.
 */
typedef NS_ENUM(NSInteger, RateLimitType) {
    /** Per-DID API request limit. */
    RateLimitTypeDID,
    /** Per-IP request limit for unauthenticated requests. */
    RateLimitTypeIP,
    /** Per-DID blob upload limit. */
    RateLimitTypeBlob,
    /** Caller-defined bucket for endpoint-specific limits. */
    RateLimitTypeCustom
};

/**
 * @class RateLimitResult
 * @brief Result of a rate limit check operation
 *
 * Contains information about whether the request is allowed and provides
 * data for HTTP headers (X-RateLimit-* headers per RFC 6585).
 */
@interface RateLimitResult : NSObject

/*! Whether the request is allowed (NO if rate limit exceeded) */
@property (nonatomic, assign) BOOL allowed;

/*! Maximum requests allowed in the time window */
@property (nonatomic, assign) NSInteger limit;

/*! Requests remaining in current window */
@property (nonatomic, assign) NSInteger remaining;

/*! Seconds until the rate limit window resets */
@property (nonatomic, assign) NSTimeInterval resetSeconds;

/*! Seconds to wait before retrying (0 if allowed, >0 if denied) */
@property (nonatomic, assign) NSTimeInterval retryAfter;

/**
 * @brief Create a rate limit result
 *
 * @param allowed Whether request is allowed
 * @param limit Maximum requests in window
 * @param remaining Requests remaining
 * @param resetSeconds Time until window reset
 * @param retryAfter Time to wait before retry
 * @return RateLimitResult instance
 */
+ (instancetype)resultAllowed:(BOOL)allowed
                        limit:(NSInteger)limit
                    remaining:(NSInteger)remaining
                  resetSeconds:(NSTimeInterval)resetSeconds
                   retryAfter:(NSTimeInterval)retryAfter;

@end

/**
 * @class RateLimiter
 * @brief Sliding window rate limiter with SQLite persistence
 *
 * Implements rate limiting using a sliding window algorithm. Tracks request
 * timestamps in SQLite database, automatically cleaning old entries.
 *
 * Default Limits:
 * - DID-based API: 5000 requests/hour
 * - IP-based: 100 requests/minute
 * - Blob uploads: 50 requests/hour
 *
 * Limits are configurable per-instance. The shared instance uses in-memory
 * storage for development; production should use database-backed storage.
 *
 * Usage:
 * @code
 * RateLimiter *limiter = [[RateLimiter alloc] initWithDatabasePath:@"rate_limits.db"];
 * limiter.didLimit = 500; // Increase DID limit
 *
 * RateLimitResult *result = [limiter checkRateLimitForDid:@"did:plc:123..."];
 * if (!result.allowed) {
 *     // Return 429 Too Many Requests
 * }
 * @endcode
 *
 * @note Thread-safe through SQLite connection serialization
 */
@interface RateLimiter : NSObject

/*! Maximum API requests per hour per DID (default: 5000) */
@property (nonatomic, assign) NSInteger didLimit;

/*! Time window for DID rate limiting in seconds (default: 3600) */
@property (nonatomic, assign) NSTimeInterval didWindowSeconds;

/*! Maximum API requests per minute per IP address (default: 100) */
@property (nonatomic, assign) NSInteger ipLimit;

/*! Time window for IP rate limiting in seconds (default: 60) */
@property (nonatomic, assign) NSTimeInterval ipWindowSeconds;

/*! Maximum blob uploads per hour per DID (default: 50) */
@property (nonatomic, assign) NSInteger blobLimit;

/*! Time window for blob upload limiting in seconds (default: 3600) */
@property (nonatomic, assign) NSTimeInterval blobWindowSeconds;

/*! Whether rate limiting is enabled (default: YES) */
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

/**
 * @brief Get the singleton rate limiter instance
 *
 * Uses in-memory storage. For production use, create instance with database path.
 *
 * @return Shared RateLimiter instance
 */
+ (instancetype)sharedLimiter;

/**
 * @brief Initialize with persistent SQLite storage
 *
 * @param path Path to SQLite database file, or nil for in-memory storage
 * @return RateLimiter instance
 */
- (instancetype)initWithDatabasePath:(nullable NSString *)path;

/**
 * @brief Reconfigure SQLite database path and reopen lazily on next use
 *
 * Closes any active SQLite handle, updates the configured path, and defers
 * reopening until the next rate-limit check. Pass nil to restore default path
 * resolution behavior.
 *
 * @param path Absolute or relative database file path, or nil
 */
- (void)reconfigureDatabasePath:(nullable NSString *)path;

/**
 * @brief Check rate limit for a DID
 *
 * Records the request timestamp and checks against didLimit/didWindowSeconds.
 *
 * @param did Decentralized identifier to check
 * @return RateLimitResult indicating if request is allowed
 */
- (RateLimitResult *)checkRateLimitForDid:(NSString *)did;

/**
 * @brief Check rate limit for an IP address
 *
 * Used for unauthenticated requests. Checks against ipLimit/ipWindowSeconds.
 *
 * @param ip IP address to check (IPv4 or IPv6)
 * @return RateLimitResult indicating if request is allowed
 */
- (RateLimitResult *)checkRateLimitForIP:(NSString *)ip;

- (RateLimitResult *)checkBlobUploadRateLimitForDid:(NSString *)did;

/**
 * @brief Check a custom rate limit with specific key, limit and window
 *
 * @param key Unique key for the limit
 * @param limit Maximum requests allowed
 * @param windowSeconds Window duration in seconds
 * @return RateLimitResult indicating if request is allowed
 */
- (RateLimitResult *)checkRateLimitForKey:(NSString *)key limit:(NSInteger)limit windowSeconds:(NSTimeInterval)windowSeconds;

/**
 * @brief Generate X-RateLimit-* headers for DID-based limit
 *
 * @param did Decentralized identifier
 * @return Dictionary of header names to values
 */
- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForDid:(NSString *)did;

/**
 * @brief Generate X-RateLimit-* headers for IP-based limit
 *
 * @param ip IP address
 * @return Dictionary of header names to values
 */
- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForIP:(NSString *)ip;

/**
 * @brief Generate X-RateLimit-* headers for blob upload limit
 *
 * @param did Decentralized identifier
 * @return Dictionary of header names to values
 */
- (NSDictionary<NSString *, NSString *> *)blobRateLimitHeadersForDid:(NSString *)did;

/**
 * @brief Apply rate limit headers to HTTP response
 *
 * Automatically selects appropriate rate limit type based on whether DID
 * or IP is provided. Adds X-RateLimit-Limit, X-RateLimit-Remaining,
 * X-RateLimit-Reset headers.
 *
 * @param response Response object to add headers to
 * @param did DID for authenticated requests (may be nil)
 * @param ip IP address for rate limiting (may be nil)
 */
- (void)applyRateLimitHeadersToResponse:(HttpResponse *)response
                                  forDid:(nullable NSString *)did
                                    ip:(nullable NSString *)ip;

/**
 * @brief Get top rate-limited identifiers by request count
 *
 * Queries the rate_limits table for identifiers with the highest request counts
 * in the current window.
 *
 * @param limit Maximum number of results (default: 20)
 * @return Array of dictionaries with keys: identifier, type, requestCount, windowStart
 */
- (NSArray<NSDictionary *> *)getTopLimitedIdentifiers:(NSInteger)limit;

/**
 * @brief Clear rate limit entries for a specific identifier
 *
 * Removes all rate limit entries for the given identifier from the database.
 *
 * @param identifier DID or IP address to clear
 * @param type Rate limit type ("did", "ip", or "blob")
 * @return Number of entries cleared
 */
- (NSInteger)clearRateLimitForIdentifier:(NSString *)identifier type:(NSString *)type;

@end

/**
 * @brief Global control for all rate limiters
 */
FOUNDATION_EXPORT void RateLimiterSetDisabledGlobally(BOOL disabled);
FOUNDATION_EXPORT BOOL RateLimiterIsDisabledGlobally(void);

NS_ASSUME_NONNULL_END

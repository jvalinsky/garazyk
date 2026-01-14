/*!
 @file PDSConfiguration.h

 @abstract Application configuration management.

 @discussion Loads and provides access to PDS configuration from files or
 environment. Includes settings for server, database pools, tokens, and debugging.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for configuration errors. */
extern NSString *const PDSConfigErrorDomain;

/*!
 @enum PDSConfigError

 @abstract Error codes for configuration operations.

 @constant PDSConfigErrorFileNotFound Configuration file not found.
 @constant PDSConfigErrorInvalidFormat Configuration format is invalid.
 @constant PDSConfigErrorMissingValue Required value is missing.
 */
typedef NS_ENUM(NSInteger, PDSConfigError) {
    PDSConfigErrorFileNotFound = 1,
    PDSConfigErrorInvalidFormat = 2,
    PDSConfigErrorMissingValue = 3
};

/*!
 @class PDSConfiguration

 @abstract Application configuration settings.

 @discussion Provides typed access to configuration values for server,
 database, authentication, rate limiting, and debugging.
 */
@interface PDSConfiguration : NSObject

/*! Server host address. */
@property (nonatomic, readonly) NSString *serverHost;

/*! Server port. */
@property (nonatomic, readonly) NSUInteger serverPort;

/*! Path to data directory. */
@property (nonatomic, readonly) NSString *dataDirectory;

/*! PLC directory server URL. */
@property (nonatomic, readonly) NSString *plcURL;

/*! Number of PLC operation retries. */
@property (nonatomic, readonly) NSUInteger plcRetryCount;

/*! Delay between PLC retries in milliseconds. */
@property (nonatomic, readonly) NSUInteger plcRetryDelayMs;

/*! Skip PLC operations (debug mode). */
@property (nonatomic, readonly) BOOL debugSkipPlcOperations;

/*! Enable verbose logging. */
@property (nonatomic, readonly) BOOL debugVerboseLogging;

/*! Use in-memory databases. */
@property (nonatomic, readonly) BOOL debugInMemoryDatabases;

/*! Reset data on startup. */
@property (nonatomic, readonly) BOOL debugResetOnStartup;

/*! Maximum user database pool size. */
@property (nonatomic, readonly) NSUInteger userDatabasePoolMaxSize;

/*! Maximum service database pool size. */
@property (nonatomic, readonly) NSUInteger serviceDatabasePoolMaxSize;

/*! DID cache pool size. */
@property (nonatomic, readonly) NSUInteger didCachePoolMaxSize;

/*! Sequencer pool size. */
@property (nonatomic, readonly) NSUInteger sequencerPoolMaxSize;

/*! Access token TTL in seconds. */
@property (nonatomic, readonly) NSUInteger accessTokenTtlSeconds;

/*! Refresh token TTL in seconds. */
@property (nonatomic, readonly) NSUInteger refreshTokenTtlSeconds;

/*! Whether invite codes are required. */
@property (nonatomic, readonly) BOOL inviteCodeRequired;

/*! Whether rate limiting is enabled. */
@property (nonatomic, readonly) BOOL rateLimitEnabled;

/*! Requests per minute limit. */
@property (nonatomic, readonly) NSUInteger rateLimitRequestsPerMinute;

/*! Burst size for rate limiting. */
@property (nonatomic, readonly) NSUInteger rateLimitBurstSize;

/*! Whether SSL pinning is enabled. */
@property (nonatomic, readonly) BOOL sslPinningEnabled;

/*! Returns the shared configuration. */
+ (nullable instancetype)sharedConfiguration;

/*! Loads configuration from a file path. */
+ (nullable instancetype)configurationWithPath:(NSString *)path error:(NSError **)error;

/*! Loads configuration from a file path. */
- (BOOL)loadFromPath:(NSString *)path error:(NSError **)error;

/*! Returns a string configuration value. */
- (nullable NSString *)stringForKey:(NSString *)key;

/*! Returns an integer configuration value. */
- (NSInteger)integerForKey:(NSString *)key;

/*! Returns a boolean configuration value. */
- (BOOL)boolForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END

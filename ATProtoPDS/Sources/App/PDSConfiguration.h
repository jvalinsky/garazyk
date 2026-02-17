/*!
 @file PDSConfiguration.h

 @abstract Application configuration management.

 @discussion Loads and provides access to PDS configuration from files or
 environment. Includes settings for server, database pools, tokens, and debugging.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Forward declarations for logging types
typedef NS_ENUM(NSInteger, PDSLogLevel);
typedef NS_ENUM(NSInteger, PDSLogFormat);

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
@property (nonatomic, copy) NSString *plcURL;

/*! Number of PLC operation retries. */
@property (nonatomic, assign) NSUInteger plcRetryCount;

/*! Delay between PLC retries in milliseconds. */
@property (nonatomic, assign) NSUInteger plcRetryDelayMs;

/*! Skip PLC operations (debug mode). */
@property (nonatomic, assign) BOOL debugSkipPlcOperations;

/*! Use new repository implementation (Phase 2). */
@property (nonatomic, assign) BOOL useNewRepositoryImplementation;

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

/*! Phone verification provider name (`none`, `mock`, or provider key). */
@property (nonatomic, readonly) NSString *phoneVerificationProvider;

/*! Email provider name (`none`, `mock`, or `smtp`). */
@property (nonatomic, readonly) NSString *emailProviderType;

/*! SMTP server host. */
@property (nonatomic, readonly, nullable) NSString *emailSmtpHost;

/*! SMTP server port. */
@property (nonatomic, readonly) NSUInteger emailSmtpPort;

/*! SMTP username. */
@property (nonatomic, readonly, nullable) NSString *emailSmtpUsername;

/*! SMTP password. */
@property (nonatomic, readonly, nullable) NSString *emailSmtpPassword;

/*! Whether to use TLS for SMTP. */
@property (nonatomic, readonly) BOOL emailSmtpUseTLS;

/*! Whether rate limiting is enabled. */
@property (nonatomic, readonly) BOOL rateLimitEnabled;


/*! Requests per minute limit. */
@property (nonatomic, readonly) NSUInteger rateLimitRequestsPerMinute;

/*! Burst size for rate limiting. */
@property (nonatomic, readonly) NSUInteger rateLimitBurstSize;

/*! DID rate limit (requests per window). */
@property (nonatomic, readonly) NSUInteger rateLimitDidLimit;

/*! DID window size in seconds. */
@property (nonatomic, readonly) NSTimeInterval rateLimitDidWindowSeconds;

/*! IP rate limit (requests per window). */
@property (nonatomic, readonly) NSUInteger rateLimitIpLimit;

/*! IP window size in seconds. */
@property (nonatomic, readonly) NSTimeInterval rateLimitIpWindowSeconds;

/*! Blob upload limit (requests per window). */
@property (nonatomic, readonly) NSUInteger rateLimitBlobLimit;

/*! Blob upload window size in seconds. */
@property (nonatomic, readonly) NSTimeInterval rateLimitBlobWindowSeconds;

/*! Whether SSL pinning is enabled. */
@property (nonatomic, readonly) BOOL sslPinningEnabled;

/*! Path to write log file, or nil to disable file logging. */
@property (nonatomic, readonly, nullable) NSString *logFilePath;

/*! Minimum log level to output. */
@property (nonatomic, readonly) PDSLogLevel logLevel;

/*! Log output format (text, JSON, or both). */
@property (nonatomic, readonly) PDSLogFormat logFormat;

/*! Maximum log file size in bytes before rotation. */
@property (nonatomic, readonly) NSUInteger maxLogFileSize;

/*! Maximum number of rotated log files to keep. */
@property (nonatomic, readonly) NSUInteger maxLogFiles;

/*! If YES, use async logging with background queue. */
@property (nonatomic, readonly) BOOL asyncLogging;

/*! Array of enabled component tags, or nil for all components. */
@property (nonatomic, readonly, nullable) NSArray<NSString *> *enabledComponents;

/*! Whether NodeInfo endpoint is enabled. */
@property (nonatomic, readonly) BOOL nodeinfoEnabled;

/*! NodeInfo software name. */
@property (nonatomic, readonly, nullable) NSString *nodeinfoSoftwareName;

/*! NodeInfo software version. */
@property (nonatomic, readonly, nullable) NSString *nodeinfoSoftwareVersion;

/*! NodeInfo software repository URL. */
@property (nonatomic, readonly, nullable) NSString *nodeinfoRepositoryURL;

/*! NodeInfo software homepage URL. */
@property (nonatomic, readonly, nullable) NSString *nodeinfoHomepageURL;

/*! Whether NodeInfo open registrations field is enabled. */
@property (nonatomic, readonly) BOOL nodeinfoOpenRegistrations;

/*! Whether biometric protection is enabled for signing keys (default: YES). */
@property (nonatomic, assign) BOOL useBiometricProtection;

/*! Whether to use the system Keychain for storing keys (default: YES). */
@property (nonatomic, assign) BOOL useKeychain;

/*! Returns the shared configuration. */
+ (nullable instancetype)sharedConfiguration;

/*!
 @method defaultDataDirectory

 @abstract Returns the default data directory for the PDS.

 @discussion On macOS: ~/Library/Application Support/ATProtoPDS
 On Linux: ~/.local/share/ATProtoPDS

 @return Path to the default data directory.
 */
+ (NSString *)defaultDataDirectory;

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

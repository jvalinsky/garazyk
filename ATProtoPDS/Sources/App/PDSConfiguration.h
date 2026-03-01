/*!
 @file PDSConfiguration.h

 @abstract Application configuration management.

 @discussion Loads and provides access to PDS configuration from files or
 environment. Includes settings for server, database pools, tokens, and debugging.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDataPaths;

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
@property (nonatomic, strong) NSString *issuer;
@property (nonatomic, readonly) NSString *canonicalIssuer;

/*! Server host address. */
@property (nonatomic, readonly) NSString *serverHost;

/*! Server port. */
@property (nonatomic, assign) NSUInteger serverPort;

/*! Path to data directory. */
@property (nonatomic, readonly) NSString *dataDirectory;

/*! Lazily-created path configuration derived from dataDirectory. */
@property (nonatomic, strong, readonly) PDSDataPaths *dataPaths;

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

/*! Available user domains for registration. If nil, defaults to canonical hostname. */
@property (nonatomic, readonly, nullable) NSArray<NSString *> *availableUserDomains;

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

/*! Resend API Key Source (env or keychain). */
@property (nonatomic, readonly) NSString *resendAPIKeySource;

/*! Resend API Key Environment Variable Name. */
@property (nonatomic, readonly) NSString *resendAPIKeyEnvVar;

/*! Resend Keychain Service Name. */
@property (nonatomic, readonly) NSString *resendKeychainService;

/*! Resend Keychain Account Name. */
@property (nonatomic, readonly) NSString *resendKeychainAccount;

/*! Resend From Address. */
@property (nonatomic, readonly, nullable) NSString *resendFromAddress;

/*! Resend API Endpoint (optional override). */
@property (nonatomic, readonly, nullable) NSString *resendAPIEndpoint;

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

/*! URL of the remote AppView for proxying app.bsky.* requests. */
@property (nonatomic, readonly, nullable) NSString *appViewURL;

/*! DID of the remote AppView for service-to-service auth. */
@property (nonatomic, readonly, nullable) NSString *appViewDID;

/*! Whether the local AppView implementation is enabled. Defaults to YES. */
@property (nonatomic, readonly) BOOL localAppViewEnabled;

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

/*! URL for the privacy policy. */
@property (nonatomic, readonly, nullable) NSString *privacyPolicyURL;

/*! URL for the terms of service. */
@property (nonatomic, readonly, nullable) NSString *termsOfServiceURL;

/*! List of relay hostnames to notify on updates. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *crawlRelays;

/*! Whether biometric protection is enabled for signing keys (default: YES). */
@property (nonatomic, assign) BOOL useBiometricProtection;

/*! Whether to use the system Keychain for storing keys (default: YES). */
@property (nonatomic, assign) BOOL useKeychain;

/*! Whether to use the Secure Enclave for hardware-backed keys (default: NO). */
@property (nonatomic, assign) BOOL useSecureEnclave;

/*! Master secret used for encryption at rest. */
@property (nonatomic, copy, nullable) NSString *masterSecret;

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

/*! Returns an array configuration value. */
- (nullable NSArray *)arrayForKey:(NSString *)key;

/*! Returns an integer configuration value. */
- (NSInteger)integerForKey:(NSString *)key;

/*! Returns a boolean configuration value. */
- (BOOL)boolForKey:(NSString *)key;

/*!
 @brief Returns the canonical issuer URL for this configuration.

 @param portHint Optional port override. Pass `0` to use configured/default port.
 @return Canonical issuer URL used by server metadata and token validation.
 */
- (NSString *)canonicalIssuerWithPortHint:(NSUInteger)portHint;

/*!
 @brief Returns the canonical hostname for this PDS instance.

 @return Lowercased hostname derived from issuer or server host.
 */
- (NSString *)canonicalHostname;

@end

NS_ASSUME_NONNULL_END

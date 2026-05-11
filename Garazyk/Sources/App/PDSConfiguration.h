// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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

#pragma mark - Server & Infrastructure

/*! @abstract Server identity (issuer URL). */
@property (nonatomic, strong) NSString *issuer;
@property (nonatomic, readonly) NSString *canonicalIssuer;

/*! @abstract Server host address. */
@property (nonatomic, readonly) NSString *serverHost;

/*! @abstract Server port. */
@property (nonatomic, assign) NSUInteger serverPort;

/*! @abstract PLC directory server URL. */
@property (nonatomic, copy) NSString *plcURL;

/*! @abstract Number of PLC operation retries. */
@property (nonatomic, assign) NSUInteger plcRetryCount;

/*! @abstract Delay between PLC retries in milliseconds. */
@property (nonatomic, assign) NSUInteger plcRetryDelayMs;

/*! @abstract Whether to run as a PLC replica. */
@property (nonatomic, readonly) BOOL plcReplicaEnabled;

/*! @abstract PLC replica upstream URL. */
@property (nonatomic, readonly, nullable) NSString *plcReplicaUpstreamURL;

/*! @abstract PLC replica bind address. */
@property (nonatomic, readonly, nullable) NSString *plcReplicaBindAddress;

/*! @abstract PLC replica data directory path. */
@property (nonatomic, readonly, nullable) NSString *plcReplicaDataDir;

/*! @abstract Use new repository implementation (Phase 2). */
@property (nonatomic, assign) BOOL useNewRepositoryImplementation;

#pragma mark - Data & Paths

/*! @abstract Path to data directory. */
@property (nonatomic, readonly) NSString *dataDirectory;

/*! @abstract Lazily-created path configuration derived from dataDirectory. */
@property (nonatomic, strong, readonly) PDSDataPaths *dataPaths;

/*! @abstract Maximum user database pool size. */
@property (nonatomic, readonly) NSUInteger userDatabasePoolMaxSize;

/*! @abstract Maximum service database pool size. */
@property (nonatomic, readonly) NSUInteger serviceDatabasePoolMaxSize;

/*! @abstract DID cache pool size. */
@property (nonatomic, readonly) NSUInteger didCachePoolMaxSize;

/*! @abstract Sequencer pool size. */
@property (nonatomic, readonly) NSUInteger sequencerPoolMaxSize;

#pragma mark - Authentication & Account

/*! @abstract Access token TTL in seconds. */
@property (nonatomic, readonly) NSUInteger accessTokenTtlSeconds;

/*! @abstract Refresh token TTL in seconds. */
@property (nonatomic, readonly) NSUInteger refreshTokenTtlSeconds;

/*! @abstract Whether invite codes are required for registration. */
@property (nonatomic, readonly) BOOL inviteCodeRequired;

/*! @abstract Whether phone verification is required for registration. */
@property (nonatomic, readonly) BOOL phoneVerificationRequired;

/*! @abstract Whether CAPTCHA verification is required for registration. */
@property (nonatomic, readonly) BOOL captchaRequired;

/*! @abstract CAPTCHA provider name (`none`, `turnstile`, `hcaptcha`). */
@property (nonatomic, readonly) NSString *captchaProvider;

/*! @abstract CAPTCHA site key for client-side rendering. */
@property (nonatomic, readonly, nullable) NSString *captchaSiteKey;

/*! @abstract CAPTCHA secret key for server-side verification. */
@property (nonatomic, readonly, nullable) NSString *captchaSecretKey;

/*! @abstract Whether only OAuth-based registration is allowed (blocks direct API signup). */
@property (nonatomic, readonly) BOOL oauthOnlyRegistration;

/*! @abstract Check whether a named registration gate is enabled in config. */
- (BOOL)isRegistrationGateEnabled:(NSString *)gateIdentifier;

#pragma mark - Provider Configuration

/*!
 @abstract The structured `providers` config section.
 @discussion
    Contains provider-specific configuration keyed by domain:
    "email", "phone_verification", "captcha", etc.
    Values use the `env:VAR_NAME` convention for secrets.
    Takes precedence over legacy top-level config keys.
 */
@property (nonatomic, readonly, nullable) NSDictionary<NSString *, NSDictionary *> *providersConfig;

/*!
 @method providerConfigForKey:
 @abstract Returns the provider config dictionary for a given domain.
 @param key Provider domain key (e.g. "email", "phone_verification", "captcha").
 @return The config dictionary for the domain, or nil if not configured.
 @discussion
    Looks up from the `providers` section first, then falls back to
    legacy top-level config keys for backward compatibility.
 */
- (nullable NSDictionary *)providerConfigForKey:(NSString *)key;

/*!
 @method resolveSecretValue:
 @abstract Resolve a config value that may use the `env:VAR_NAME` convention.
 @param value The config value string. If it starts with "env:", the remainder
    is treated as an environment variable name and its value is returned.
    Otherwise, the value is returned as-is.
 @return The resolved value, or nil if the env var doesn't exist.
 */
- (nullable NSString *)resolveSecretValue:(NSString *)value;

/*! @abstract Available user domains for registration. If nil, defaults to canonical hostname. */
@property (nonatomic, readonly, nullable) NSArray<NSString *> *availableUserDomains;

/*! @abstract Phone verification provider name (`none`, `mock`, or provider key). */
@property (nonatomic, readonly) NSString *phoneVerificationProvider;

#pragma mark - Email & Notifications

/*! @abstract Email provider name (`none`, `mock`, `smtp`, or `resend`). SMTP is configured but not implemented. */
@property (nonatomic, readonly) NSString *emailProviderType;

/*! @abstract SMTP server host. */
@property (nonatomic, readonly, nullable) NSString *emailSmtpHost;

/*! @abstract SMTP server port. */
@property (nonatomic, readonly) NSUInteger emailSmtpPort;

/*! @abstract SMTP username. */
@property (nonatomic, readonly, nullable) NSString *emailSmtpUsername;

/*! @abstract SMTP password. */
@property (nonatomic, readonly, nullable) NSString *emailSmtpPassword;

/*! @abstract Whether to use TLS for SMTP. */
@property (nonatomic, readonly) BOOL emailSmtpUseTLS;

/*! @abstract Resend API Key Source (env or keychain). */
@property (nonatomic, readonly) NSString *resendAPIKeySource;

/*! @abstract Resend API Key Environment Variable Name. */
@property (nonatomic, readonly) NSString *resendAPIKeyEnvVar;

/*! @abstract Resend Keychain Service Name. */
@property (nonatomic, readonly) NSString *resendKeychainService;

/*! @abstract Resend Keychain Account Name. */
@property (nonatomic, readonly) NSString *resendKeychainAccount;

/*! @abstract Resend From Address. */
@property (nonatomic, readonly, nullable) NSString *resendFromAddress;

/*! @abstract Resend API Endpoint (optional override). */
@property (nonatomic, readonly, nullable) NSString *resendAPIEndpoint;

#pragma mark - Rate Limiting

/*! @abstract Whether rate limiting is enabled. */
@property (nonatomic, readonly) BOOL rateLimitEnabled;

#pragma mark - Blob Storage

/*! @abstract Video processing mode: "internal" (in-PDS) or "external" (side-car). Defaults to "internal". */
@property (nonatomic, readonly) NSString *videoMode;

/*! @abstract Blob storage type ("disk" or "s3"). Defaults to "disk". */
@property (nonatomic, readonly) NSString *blobStorageType;

/*! @abstract S3 bucket name for blob storage. */
@property (nonatomic, readonly, nullable) NSString *s3Bucket;

/*! @abstract S3 region (e.g. "us-east-1"). */
@property (nonatomic, readonly, nullable) NSString *s3Region;

/*! @abstract S3 endpoint URL for S3-compatible services (MinIO, R2, B2, etc). */
@property (nonatomic, readonly, nullable) NSString *s3Endpoint;

/*! @abstract Optional prefix for all S3 object keys (e.g. "blobs/"). */
@property (nonatomic, readonly, nullable) NSString *s3KeyPrefix;

/*! @abstract S3 access key ID. May also be read from S3_ACCESS_KEY_ID environment variable. */
@property (nonatomic, readonly, nullable) NSString *s3AccessKeyId;

/*! @abstract S3 secret access key. May also be read from S3_SECRET_ACCESS_KEY environment variable. */
@property (nonatomic, readonly, nullable) NSString *s3SecretAccessKey;

/*! @abstract Optional CDN URL for 302 redirects in blob endpoints. If set, blob requests return a redirect to {cdnURL}/{cid}. */
@property (nonatomic, readonly, nullable) NSString *cdnURL;

#pragma mark - Rate Limiting Details

/*! @abstract Requests per minute limit. */
@property (nonatomic, readonly) NSUInteger rateLimitRequestsPerMinute;

/*! @abstract Burst size for rate limiting. */
@property (nonatomic, readonly) NSUInteger rateLimitBurstSize;

/*! @abstract DID rate limit (requests per window). */
@property (nonatomic, readonly) NSUInteger rateLimitDidLimit;

/*! @abstract DID window size in seconds. */
@property (nonatomic, readonly) NSTimeInterval rateLimitDidWindowSeconds;

/*! @abstract IP rate limit (requests per window). */
@property (nonatomic, readonly) NSUInteger rateLimitIpLimit;

/*! @abstract IP window size in seconds. */
@property (nonatomic, readonly) NSTimeInterval rateLimitIpWindowSeconds;

/*! @abstract Blob upload limit (requests per window). */
@property (nonatomic, readonly) NSUInteger rateLimitBlobLimit;

/*! @abstract Blob upload window size in seconds. */
@property (nonatomic, readonly) NSTimeInterval rateLimitBlobWindowSeconds;

#pragma mark - AppView

/*! @abstract URL of the remote AppView for proxying app.bsky.* requests. */
@property (nonatomic, readonly, nullable) NSString *appViewURL;

/*! @abstract DID of the remote AppView for service-to-service auth. */
@property (nonatomic, readonly, nullable) NSString *appViewDID;

#pragma mark - Chat Service

/*! @abstract URL of the remote Chat service for proxying chat.bsky.* requests. */
@property (nonatomic, readonly, nullable) NSString *chatServiceURL;

/*! @abstract DID of the remote Chat service for service-to-service auth. */
@property (nonatomic, readonly, nullable) NSString *chatServiceDID;

#pragma mark - Ozone

/*! @abstract URL of the remote Ozone moderation service for proxying tools.ozone.* requests. */
@property (nonatomic, readonly, nullable) NSString *ozoneURL;

/*! @abstract DID of the remote Ozone service for service-to-service auth. */
@property (nonatomic, readonly, nullable) NSString *ozoneDID;

#pragma mark - Logging & Monitoring

/*! @abstract Path to write log file, or nil to disable file logging. */
@property (nonatomic, readonly, nullable) NSString *logFilePath;

/*! @abstract Minimum log level to output. */
@property (nonatomic, readonly) PDSLogLevel logLevel;

/*! @abstract Log output format (text, JSON, or both). */
@property (nonatomic, readonly) PDSLogFormat logFormat;

/*! @abstract Maximum log file size in bytes before rotation. */
@property (nonatomic, readonly) NSUInteger maxLogFileSize;

/*! @abstract Maximum number of rotated log files to keep. */
@property (nonatomic, readonly) NSUInteger maxLogFiles;

/*! @abstract If YES, use async logging with background queue. */
@property (nonatomic, readonly) BOOL asyncLogging;

/*! @abstract Array of enabled component tags, or nil for all components. */
@property (nonatomic, readonly, nullable) NSArray<NSString *> *enabledComponents;

#pragma mark - NodeInfo & Metadata

/*! @abstract Whether NodeInfo endpoint is enabled. */
@property (nonatomic, readonly) BOOL nodeinfoEnabled;

/*! @abstract NodeInfo software name. */
@property (nonatomic, readonly, nullable) NSString *nodeinfoSoftwareName;

/*! @abstract NodeInfo software version. */
@property (nonatomic, readonly, nullable) NSString *nodeinfoSoftwareVersion;

/*! @abstract NodeInfo software repository URL. */
@property (nonatomic, readonly, nullable) NSString *nodeinfoRepositoryURL;

/*! @abstract NodeInfo software homepage URL. */
@property (nonatomic, readonly, nullable) NSString *nodeinfoHomepageURL;

/*! @abstract Whether NodeInfo open registrations field is enabled. */
@property (nonatomic, readonly) BOOL nodeinfoOpenRegistrations;

/*! @abstract URL for the privacy policy. */
@property (nonatomic, readonly, nullable) NSString *privacyPolicyURL;

/*! @abstract URL for the terms of service. */
@property (nonatomic, readonly, nullable) NSString *termsOfServiceURL;

/*! @abstract List of relay hostnames to notify on updates. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *crawlRelays;

#pragma mark - Security & Key Management

/*! @abstract Whether biometric protection is enabled for signing keys (default: YES). */
@property (nonatomic, assign) BOOL useBiometricProtection;

/*! @abstract Whether to use the system Keychain for storing keys (default: YES). */
@property (nonatomic, assign) BOOL useKeychain;

/*! @abstract Whether to use the Secure Enclave for hardware-backed keys (default: NO). */
@property (nonatomic, assign) BOOL useSecureEnclave;

/*! @abstract Master secret used for encryption at rest. */
@property (nonatomic, copy, nullable) NSString *masterSecret;

/*! @abstract Whether to require DPoP nonces for all DPoP-bound requests (default: NO). */
@property (nonatomic, assign) BOOL requireDPoPNonce;

/*! @abstract Whether SSL pinning is enabled. */
@property (nonatomic, readonly) BOOL sslPinningEnabled;

#pragma mark - Debug Settings

/*! @abstract Enable verbose logging. */
@property (nonatomic, readonly) BOOL debugVerboseLogging;

/*! @abstract Use in-memory databases. */
@property (nonatomic, readonly) BOOL debugInMemoryDatabases;

/*! @abstract Reset data on startup. */
@property (nonatomic, readonly) BOOL debugResetOnStartup;

#pragma mark - Soft Quotas

/*! @abstract Soft quota for blob storage in bytes (0 = unlimited). When exceeded, a warning is logged and a Prometheus counter incremented. */
@property (nonatomic, readonly) unsigned long long softQuotaBlobBytes;

/*! @abstract Soft quota for total record count (0 = unlimited). When exceeded, a warning is logged and a Prometheus counter incremented. */
@property (nonatomic, readonly) NSUInteger softQuotaRecordCount;

/*! @abstract Soft quota for repo storage in bytes (0 = unlimited). When exceeded, a warning is logged and a Prometheus counter incremented. */
@property (nonatomic, readonly) unsigned long long softQuotaRepoBytes;

/*! @abstract Whether per-account Prometheus labels are enabled (default: NO, high cardinality risk on large hosts). */
@property (nonatomic, readonly) BOOL metricsPerAccountLabels;

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

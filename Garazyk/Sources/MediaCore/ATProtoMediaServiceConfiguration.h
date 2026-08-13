// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMediaServiceConfiguration.h

 @abstract Configuration for a media CDN service (video, audio, etc.).
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Configuration parameters for an ATProto media processing service.
 */
@interface ATProtoMediaServiceConfiguration : NSObject

/// Server listening port.
@property (nonatomic, assign) NSUInteger port;

/// Path to the data directory (database, workspace).
@property (nonatomic, copy) NSString *dataDirectory;

/// Path to the blob storage directory (disk mode).
@property (nonatomic, copy) NSString *blobDirectory;

/// Base URL of the PDS for uploading processed blobs.
@property (nonatomic, copy) NSString *pdsURL;

/// PLC directory URL.
@property (nonatomic, copy, nullable) NSString *plcURL;

/// Service DID for authorization.
@property (nonatomic, copy) NSString *serviceDID;

/// Maximum concurrent processing jobs.
@property (nonatomic, assign) NSInteger maxConcurrentJobs;

/// Job polling interval in seconds.
@property (nonatomic, assign) NSTimeInterval pollInterval;

/// Maximum upload size in bytes.
@property (nonatomic, assign) NSUInteger maxUploadBytes;

/// Maximum output size in bytes.
@property (nonatomic, assign) NSUInteger maxOutputBytes;

/// Maximum media duration in seconds.
@property (nonatomic, assign) NSInteger maxDurationSeconds;

/// Directory for output assets (e.g. HLS segments).
@property (nonatomic, copy, nullable) NSString *outputDirectory;

/// Base URL for serving output assets.
@property (nonatomic, copy, nullable) NSString *outputBaseUrl;

/// Option to include high-quality variants.
@property (nonatomic, assign) BOOL includeHighQuality;

/**
 Whether to assemble a content-addressed VOD MASL manifest after HLS (WS12 Phase 3).

 Defaults to NO until Phase 5 can serve the manifest. When enabled, requires a
 usable @c caObjectStoreDirectory.
 */
@property (nonatomic, assign) BOOL enableContentAddressedManifest;

/**
 Root directory for the jelcz CA object store (@c objects/ + @c proofs/).

 Defaults to @c {dataDirectory}/ca-objects when the feature flag is on and this
 property is unset.
 */
@property (nonatomic, copy, nullable) NSString *caObjectStoreDirectory;

/**
 When YES, zero-refcount CA objects are deleted after the grace period (WS12 Phase 6).

 Defaults to NO — sweep off leaves orphans on disk (growth, not data loss).
 */
@property (nonatomic, assign) BOOL caObjectSweepEnabled;

/**
 When YES and a mirror fetcher is injected, watch/RASL miss paths may fetch
 verified objects from @c caMirrorProviders (WS12 Phase 10). Default NO.
 */
@property (nonatomic, assign) BOOL enableCAMirrorFetch;

/**
 Absolute HTTPS provider base URLs for CA mirror fetch (comma-separated env).
 */
@property (nonatomic, copy, nullable) NSArray<NSString *> *caMirrorProviders;

/**
 Operator Streamplace node base URL (WS15). Merged into @c caMirrorProviders.
 Env: @c JELCZ_STREAMPLACE_MIRROR_BASE.
 */
@property (nonatomic, copy, nullable) NSString *streamplaceMirrorBase;

/**
 DID passed as getVideoBlob @c did= for egress accounting (WS15).
 Env: @c JELCZ_STREAMPLACE_ATTRIBUTION_DID.
 */
@property (nonatomic, copy, nullable) NSString *streamplaceAttributionDID;

/**
 When YES, register Streamplace-shaped getVideoBlob against the local CA store.
 Env: @c JELCZ_STREAMPLACE_SERVE_COMPAT. Default NO.
 */
@property (nonatomic, assign) BOOL enableStreamplaceServeCompat;

/**
 When YES, register the Streamplace peership demo UI + APIs on jelcz.
 Env: @c JELCZ_STREAMPLACE_DEMO. Default NO.
 */
@property (nonatomic, assign) BOOL enableStreamplacePeerDemo;

/**
 Grace period before reclaiming zero-refcount CA objects.

 Default six hours; clamped to a one-hour minimum (ADR 0013 shape).
 */
@property (nonatomic, assign) NSTimeInterval caObjectGracePeriodSeconds;

/// S3 bucket name (cloud storage, optional).
@property (nonatomic, copy, nullable) NSString *s3Bucket;

/// AWS region.
@property (nonatomic, copy) NSString *s3Region;

/// Custom S3 endpoint URL.
@property (nonatomic, copy, nullable) NSString *s3Endpoint;

/// AWS access key.
@property (nonatomic, copy, nullable) NSString *s3AccessKey;

/// AWS secret key.
@property (nonatomic, copy, nullable) NSString *s3SecretKey;

/// Creates a configuration populated from environment variables using the given prefix.
+ (instancetype)configurationFromEnvironmentWithPrefix:(NSString *)prefix;

@end

NS_ASSUME_NONNULL_END

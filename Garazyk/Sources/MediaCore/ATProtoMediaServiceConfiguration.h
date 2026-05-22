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

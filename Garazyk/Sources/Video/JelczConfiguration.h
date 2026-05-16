// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Configuration parameters for the Jelcz video service.
 */
@interface JelczConfiguration : NSObject

/** @abstract Server listening port. */
@property (nonatomic, assign) NSUInteger port;
/** @abstract Path to the data directory. */
@property (nonatomic, copy) NSString *dataDirectory;
/** @abstract Path to the blob storage directory. */
@property (nonatomic, copy) NSString *blobDirectory;
/** @abstract Base URL for PDS connectivity. */
@property (nonatomic, copy) NSString *pdsURL;
/** @abstract PLC directory URL. */
@property (nonatomic, copy, nullable) NSString *plcURL;
/** @abstract Service DID. */
@property (nonatomic, copy) NSString *serviceDID;
/** @abstract Maximum concurrent jobs. */
@property (nonatomic, assign) NSInteger maxConcurrentJobs;
/** @abstract Job polling interval. */
@property (nonatomic, assign) NSTimeInterval pollInterval;
/** @abstract Maximum allowed upload size in bytes. */
@property (nonatomic, assign) NSUInteger maxUploadBytes;
/** @abstract Maximum allowed output size in bytes. */
@property (nonatomic, assign) NSUInteger maxOutputBytes;
/** @abstract Maximum allowed video duration. */
@property (nonatomic, assign) NSInteger maxDurationSeconds;

/** @name HLS configuration */
/** @abstract Directory path for HLS output. */
@property (nonatomic, copy, nullable) NSString *hlsOutputDirectory;
/** @abstract Base URL for HLS content. */
@property (nonatomic, copy, nullable) NSString *hlsBaseUrl;
/** @abstract Flag to include 1080p resolution in HLS. */
@property (nonatomic, assign) BOOL hlsInclude1080p;

/** @name S3 configuration */
/** @abstract Name of the S3 bucket. */
@property (nonatomic, copy, nullable) NSString *s3Bucket;
/** @abstract AWS region. */
@property (nonatomic, copy) NSString *s3Region;
/** @abstract Custom S3 endpoint URL. */
@property (nonatomic, copy, nullable) NSString *s3Endpoint;
/** @abstract AWS access key. */
@property (nonatomic, copy, nullable) NSString *s3AccessKey;
/** @abstract AWS secret key. */
@property (nonatomic, copy, nullable) NSString *s3SecretKey;

/**
 * @abstract Creates configuration from environment variables.
 * @return Configuration instance populated from the environment.
 */
+ (instancetype)configurationFromEnvironment;

@end

NS_ASSUME_NONNULL_END

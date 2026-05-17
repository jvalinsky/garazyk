// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @interface PDSCloudStorageBlobProvider

 @abstract S3-compatible cloud storage blob provider using AWS Signature V4.

 @discussion Implements the PDSBlobProvider protocol for storing blobs in
 S3-compatible endpoints (AWS S3, MinIO, Cloudflare R2, Backblaze B2, etc).
 Uses NSURLSession for HTTP requests with AWS Signature V4 authentication.
 All operations are thread-safe.
 */
@interface PDSCloudStorageBlobProvider : NSObject <PDSBlobProvider>

/*!
 @brief Initializes cloud storage provider with S3 configuration.

 @param bucket The S3 bucket name
 @param region The AWS region (e.g. "us-east-1")
 @param endpoint Optional S3 endpoint URL for S3-compatible services.
                 Defaults to AWS S3 endpoint if nil.
 @param keyPrefix Optional prefix for all object keys (e.g. "blobs/")
 @param accessKeyId AWS access key ID (or equivalent)
 @param secretAccessKey AWS secret access key (or equivalent)
 @return Initialized provider instance, or nil if configuration is invalid
 */
/**
 * @abstract Performs the initWithBucket operation.
 */
- (nullable instancetype)initWithBucket:(NSString *)bucket
                                 region:(NSString *)region
                               endpoint:(nullable NSString *)endpoint
                              keyPrefix:(nullable NSString *)keyPrefix
                          accessKeyId:(NSString *)accessKeyId
                       secretAccessKey:(NSString *)secretAccessKey;

/**
 * @abstract Exposes the bucket value.
 */
@property (nonatomic, strong, readonly) NSString *bucket;
@property (nonatomic, strong, readonly) NSString *region;
@property (nonatomic, strong, readonly, nullable) NSString *endpoint;
@property (nonatomic, strong, readonly, nullable) NSString *keyPrefix;
@property (nonatomic, strong, readonly) NSString *accessKeyId;

@end

NS_ASSUME_NONNULL_END

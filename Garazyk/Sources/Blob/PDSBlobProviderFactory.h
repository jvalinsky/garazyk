// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoServiceConfiguration;

/**
 * @abstract Factory for creating blob provider instances based on configuration.
 * @discussion Reads configuration and instantiates the appropriate blob provider (disk or S3-compatible cloud storage).
 */
@interface PDSBlobProviderFactory : NSObject

/**
 * @abstract Creates a blob provider based on configuration.
 * @param configuration The PDS configuration instance.
 * @param error Receives failure details.
 * @return An instance of PDSBlobProvider, or nil if configuration is invalid.
 * @discussion Reads blobStorageType from configuration:
 * - "disk": returns PDSDiskBlobProvider
 * - "s3": returns PDSCloudStorageBlobProvider with S3 settings
 */
+ (nullable id<PDSBlobProvider>)blobProviderWithConfiguration:(ATProtoServiceConfiguration *)configuration
                                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

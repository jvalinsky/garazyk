// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSConfiguration;

/*!
 @interface PDSBlobProviderFactory

 @abstract Factory for creating blob provider instances based on configuration.

 @discussion Reads configuration and instantiates the appropriate blob provider
 (disk or S3-compatible cloud storage). The factory pattern allows easy switching
 between storage backends without affecting client code.
 */
@interface PDSBlobProviderFactory : NSObject

/*!
 @brief Creates a blob provider based on configuration.

 @param configuration The PDS configuration instance
 @param error Output error if provider creation fails
 @return An instance of PDSBlobProvider (PDSDiskBlobProvider or
         PDSCloudStorageBlobProvider), or nil if configuration is invalid
 @discussion
    Reads blobStorageType from configuration:
    - "disk": returns PDSDiskBlobProvider
    - "s3": returns PDSCloudStorageBlobProvider with S3 settings
    - other values: returns nil with error
 */
+ (nullable id<PDSBlobProvider>)blobProviderWithConfiguration:(PDSConfiguration *)configuration
                                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

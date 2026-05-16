// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Implementation of PDSBlobProvider for local disk storage.
 */
@interface PDSDiskBlobProvider : NSObject <PDSBlobProvider>

/**
 * @abstract The base directory path where blobs are stored.
 */
@property (nonatomic, strong, readonly) NSURL *storageDirectory;

/**
 * @abstract Initializes a new local disk blob provider.
 * @param storageDirectory The local URL path for blob persistence.
 */
- (instancetype)initWithStorageDirectory:(NSURL *)storageDirectory;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  PDSBlobAuditOperation_Protected.h
//  ATProtoPDS
//
//  Protected interface for PDSBlobAuditOperation subclasses.
//  Import this header in subclass implementations to access protected properties.
//

#import "PDSBlobAuditOperation.h"
#import "Compat/PDSTypes.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Protected interface for blob audit operation subclasses.
 *
 * Subclasses should import this header to access blobStorage and serviceDatabases.
 */
/**
 * @abstract Extends PDSBlobAuditOperation with protected behavior.
 */
@interface PDSBlobAuditOperation (Protected)

/// Blob storage instance for accessing blobs
/**
 * @abstract Exposes the blob storage value.
 */
@property (nonatomic, strong, readonly) BlobStorage *blobStorage;

/// Service databases for account lookups
@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;

/// Serial queue for thread-safe operations
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, readonly) dispatch_queue_t queue;

@end

NS_ASSUME_NONNULL_END

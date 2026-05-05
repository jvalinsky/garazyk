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
@interface PDSBlobAuditOperation (Protected)

/// Blob storage instance for accessing blobs
@property (nonatomic, strong, readonly) BlobStorage *blobStorage;

/// Service databases for account lookups
@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;

/// Serial queue for thread-safe operations
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, readonly) dispatch_queue_t queue;

@end

NS_ASSUME_NONNULL_END

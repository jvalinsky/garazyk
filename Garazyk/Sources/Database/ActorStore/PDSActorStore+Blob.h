/*!
 @file PDSActorStore+Blob.h

 @abstract PDSActorStore category for blob-related database operations.

 @discussion Extends PDSActorStore with methods for managing binary large objects
 (blobs) in the actor's SQLite database. Blobs are user-uploaded files such as
 images and videos.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Database/ActorStore/ActorStore.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @category PDSActorStore (Blob)

 @abstract Blob management methods for PDSActorStore.

 @discussion This category extends PDSActorStore with blob-specific database
 operations. Blobs are large binary objects uploaded by users, including:

 - Images (profile pictures, post attachments)
 - Videos
 - Other binary content

 Blobs are content-addressed by CID and tracked separately from repository
 blocks. The blob table stores metadata while actual blob data may be stored
 on disk or in cloud storage.

 @note Blob methods are available through the PDSActorStoreReader protocol
 for read operations.

 @see PDSActorStore
 @see PDSDatabaseBlob
 */
@interface PDSActorStore (Blob)

@end

NS_ASSUME_NONNULL_END

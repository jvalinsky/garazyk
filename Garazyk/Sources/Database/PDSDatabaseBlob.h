// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/** Blob has been uploaded but is not yet referenced by any record: not
    retrievable, not listed, and eligible for the grace-period sweep. */
extern NSString * const PDSDatabaseBlobStateTemporary;

/** Blob is referenced by at least one current record: publicly
    retrievable and listed. */
extern NSString * const PDSDatabaseBlobStateReferenced;

/**
 * @class PDSDatabaseBlob
 * 
 * @abstract Represents a blob reference stored in the database.
 * 
 * @discussion Blobs are large binary data attachments stored separately from
 * repository blocks. This class tracks blob metadata for retrieval and quota
 * management.
 * 
 * @see PDSDatabase (Blobs)
 */
/**
 * @abstract Represents blob metadata stored for an actor.
 */
@interface PDSDatabaseBlob : NSObject <PDSDatabaseModel>

/** The ATProtoCID of the blob. */
@property (nonatomic, copy) NSData *cid;

/** The DID of the account that uploaded this blob. */
@property (nonatomic, copy) NSString *did;

/** The MIME type of the blob content. */
@property (nonatomic, copy, nullable) NSString *mimeType;

/** The size of the blob in bytes. */
@property (nonatomic, assign) NSInteger size;

/** Date when the blob was uploaded. */
@property (nonatomic, strong) NSDate *createdAt;

/** Lifecycle state: PDSDatabaseBlobStateTemporary or
    PDSDatabaseBlobStateReferenced. */
@property (nonatomic, copy) NSString *state;

@end

NS_ASSUME_NONNULL_END

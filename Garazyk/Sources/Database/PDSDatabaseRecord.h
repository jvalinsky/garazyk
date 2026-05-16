// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSDatabaseRecord
 * 
 * @abstract Represents a single record in a repository.
 * 
 * @discussion Records are the fundamental data units in ATProto repositories.
 * Each record is identified by a URI (repo DID + collection + rkey) and has
 * an associated CID for content-addressable retrieval.
 * 
 * @see PDSDatabase (Records)
 */
@interface PDSDatabaseRecord : NSObject <PDSDatabaseModel>

/** The AT-URI identifying this record (e.g., at://did:plc:z.../app.bsky.actor.profile/self). */
@property (nonatomic, copy) NSString *uri;

/** The DID of the repository that contains this record. */
@property (nonatomic, copy) NSString *did;

/** The collection namespace for this record (e.g., app.bsky.actor.profile). */
@property (nonatomic, copy) NSString *collection;

/** The record key within the collection. */
@property (nonatomic, copy) NSString *rkey;

/** The CID of the record content. */
@property (nonatomic, copy) NSString *cid;

/** Date when the record was created. */
@property (nonatomic, strong) NSDate *createdAt;

/** The raw value of the record (JSON string). */
@property (nonatomic, copy, nullable) NSString *value;

/** Revision TID when this record was last written. */
@property (nonatomic, copy, nullable) NSString *rev;

/** The subject DID for relationship records (e.g. follow target). */
@property (nonatomic, copy, nullable) NSString *subjectDid;

/** Date when the record was indexed by the PDS. */
@property (nonatomic, strong, nullable) NSDate *indexedAt;

@end

NS_ASSUME_NONNULL_END

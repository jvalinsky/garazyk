// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

#import "Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoCARBlock;
@class ATProtoMST;
@class ATProtoMSTNode;
@class ATProtoMSTNodeEntry;

/*!
 @header STAR.h

 @abstract STreaming ARchive format utilities.

 @discussion This header defines classes for reading and writing STAR
 (STreaming ARchive) format, a stricter, verifiable, deterministic alternative
 to CAR files for ATProto repository serialization.

 STAR offers:
 - Bounded-resource streaming readers (strict depth-first ordering)
 - Reduced archive size (~80% fewer CIDs than CAR)
 - Canonical, deterministic encoding (no ordering ambiguity)
 - No garbage blocks allowed (unlike CAR)

 Two variants are supported:
 - STAR-L0: preserves ATProtoMST structure, best for streaming verification
 - STAR-lite: flat key-record encoding, best compression

 @copyright Copyright (c) 2025-2026 Jack Valinsky

 @see https://tangled.org/microcosm.blue/star
 */

/*!

 @abstract Specifies the STAR format variant.

 @constant STARVariantL0  STAR-L0: ATProtoMST-structured, streaming verification
 @constant STARVariantLite STAR-lite: flat key-record, best compression
 */
typedef NS_ENUM(NSUInteger, STARVariant) {
    STARVariantL0,
    STARVariantLite
};

/*!

 @abstract Type of item encountered during STAR stream parsing.
 */
typedef NS_ENUM(NSUInteger, STARItemType) {
    STARItemTypeCommit,
    STARItemTypeNode,
    STARItemTypeRecord
};

#pragma mark - STAR Commit

/*!
 @class ATProtoSTARCommit

 @abstract Represents a STAR commit object (the archive header).
 */
@interface ATProtoSTARCommit : NSObject

@property (nonatomic, copy) NSString *did;
@property (nonatomic, assign) NSInteger version;
@property (nonatomic, strong, nullable) ATProtoCID *data;
@property (nonatomic, copy) NSString *rev;
@property (nonatomic, strong, nullable) ATProtoCID *prev;
@property (nonatomic, copy, nullable) NSData *sig;

/**
 * @abstract Performs the commitWithDid operation.
 */
+ (instancetype)commitWithDid:(NSString *)did
                      version:(NSInteger)version
                        data:(nullable ATProtoCID *)data
                         rev:(NSString *)rev
                        prev:(nullable ATProtoCID *)prev
                         sig:(nullable NSData *)sig;

/**
 * @abstract Performs the serializeToDagCBOR operation.
 */
- (nullable NSData *)serializeToDagCBOR:(NSError **)error;

@end

#pragma mark - STAR ATProtoMST Entry (wire format)

/*!
 @class ATProtoSTARMstEntry

 @abstract A single entry in a STAR ATProtoMST node (wire format).

 @discussion In the STAR wire format, layer-0 entries may omit `v` (record ATProtoCID)
 when the record is included in the archive. The `V` flag indicates that the
 record follows in the stream. Similarly, `T` indicates that the subtree
 follows in the archive.
 */
@interface ATProtoSTARMstEntry : NSObject

/**
 * @abstract Exposes the prefix len value.
 */
@property (nonatomic, assign) NSUInteger prefixLen;
@property (nonatomic, copy) NSData *keySuffix;
@property (nonatomic, strong, nullable) ATProtoCID *value;
@property (nonatomic, assign) BOOL valueArchived;
@property (nonatomic, strong, nullable) ATProtoCID *tree;
@property (nonatomic, assign) BOOL treeArchived;

/**
 * @abstract Performs the entryWithPrefixLen operation.
 */
+ (instancetype)entryWithPrefixLen:(NSUInteger)prefixLen
                         keySuffix:(NSData *)keySuffix
                             value:(nullable ATProtoCID *)value
                      valueArchived:(BOOL)valueArchived
                              tree:(nullable ATProtoCID *)tree
                       treeArchived:(BOOL)treeArchived;

@end

#pragma mark - STAR ATProtoMST Node (wire format)

/*!
 @class ATProtoSTARMstNode

 @abstract A ATProtoMST node in STAR wire format.

 @discussion STAR ATProtoMST nodes differ from repo-spec ATProtoMST nodes:
 - `l` is the left pointer ATProtoCID (optional)
 - `L` is a bool flag indicating the left subtree is in the archive
 - `e` is the array of entries (ATProtoSTARMstEntry)
 - Layer-0 entries may omit `v` when records are included
 */
@interface ATProtoSTARMstNode : NSObject

/**
 * @abstract Exposes the left value.
 */
@property (nonatomic, strong, nullable) ATProtoCID *left;
@property (nonatomic, assign) BOOL leftArchived;
@property (nonatomic, copy) NSArray<ATProtoSTARMstEntry *> *entries;

/**
 * @abstract Performs the nodeWithLeft operation.
 */
+ (instancetype)nodeWithLeft:(nullable ATProtoCID *)left
                leftArchived:(BOOL)leftArchived
                    entries:(NSArray<ATProtoSTARMstEntry *> *)entries;

/**
 * @abstract Performs the serializeToDagCBOR operation.
 */
- (nullable NSData *)serializeToDagCBOR:(NSError **)error;

@end

#pragma mark - ATProtoSTARL0Writer

/*!
 @class ATProtoSTARL0Writer

 @abstract Writes STAR-L0 format archives.

 @discussion STAR-L0 preserves the ATProtoMST structure and enables streaming
 verification. The writer walks the ATProtoMST depth-first, emitting nodes and
 records in strict traversal order. Layer-0 nodes omit record CIDs when
 the records follow in the archive.

 Usage:
     ATProtoSTARL0Writer *writer = [[ATProtoSTARL0Writer alloc] initWithCommit:commit];
     [writer writeFromMST:mst blockProvider:provider error:&err];
     NSData *starData = [writer serialize];
 */
/**
 * @abstract Declares the ATProtoSTARL0Writer public API.
 */
@interface ATProtoSTARL0Writer : NSObject

/**
 * @abstract Exposes the commit value.
 */
@property (nonatomic, strong, readonly) ATProtoSTARCommit *commit;

/**
 * @abstract Performs the initWithCommit operation.
 */
- (instancetype)initWithCommit:(ATProtoSTARCommit *)commit;

/*!
 @method initWithCommit:outputBlock:

 @abstract Initialize a writer with a commit and a streaming output block.

 @param commit The commit header.
 @param outputBlock Block called whenever a new chunk of data is ready.
 @return A new ATProtoSTARL0Writer instance.
 */
- (instancetype)initWithCommit:(ATProtoSTARCommit *)commit outputBlock:(void (^)(NSData *chunk))outputBlock;

/*!
 @method writeFromMST:blockProvider:error:

 @abstract Walk the ATProtoMST depth-first and serialize as STAR-L0.

 @param mst The ATProtoMST to serialize.
 @param blockProvider Block that returns record data for a given ATProtoCID.
 @param error Error pointer for serialization failures.
 @return YES on success, NO on failure.
 */
- (BOOL)writeFromMST:(ATProtoMST *)mst
       blockProvider:(nullable NSData * _Nullable (^)(ATProtoCID *cid))blockProvider
               error:(NSError **)error;

/*!
 @method serialize

 @abstract Returns the complete STAR-L0 archive data.

 @return STAR-L0 encoded data.
 */
- (nullable NSData *)serialize;

/*!
 @method writeToPath:error:

 @abstract Writes the STAR-L0 archive to a file.

 @param path Destination file path.
 @param error Error pointer for write failures.
 @return YES on success, NO on failure.
 */
- (BOOL)writeToPath:(NSString *)path error:(NSError **)error;

@end

#pragma mark - ATProtoSTARLiteWriter

/*!
 @class ATProtoSTARLiteWriter

 @abstract Writes STAR-lite format archives.

 @discussion STAR-lite is a flat key-record encoding with no ATProtoMST structure.
 It provides the best compression ratio but requires disk spilling or two
 passes for ATProtoMST recovery. Records are emitted in sorted key order.

 Usage:
     ATProtoSTARLiteWriter *writer = [[ATProtoSTARLiteWriter alloc] initWithCommit:commit];
     [writer writeFromMST:mst blockProvider:provider error:&err];
     NSData *starData = [writer serialize];
 */
/**
 * @abstract Declares the ATProtoSTARLiteWriter public API.
 */
@interface ATProtoSTARLiteWriter : NSObject

/**
 * @abstract Exposes the commit value.
 */
@property (nonatomic, strong, readonly) ATProtoSTARCommit *commit;

/**
 * @abstract Performs the initWithCommit operation.
 */
- (instancetype)initWithCommit:(ATProtoSTARCommit *)commit;

/*!
 @method writeFromMST:blockProvider:error:

 @abstract Walk the ATProtoMST and serialize as STAR-lite (flat key-record).

 @param mst The ATProtoMST to serialize.
 @param blockProvider Block that returns record data for a given ATProtoCID.
 @param error Error pointer for serialization failures.
 @return YES on success, NO on failure.
 */
- (BOOL)writeFromMST:(ATProtoMST *)mst
       blockProvider:(nullable NSData * _Nullable (^)(ATProtoCID *cid))blockProvider
               error:(NSError **)error;

/*!
 @method addRecordWithKey:data:

 @abstract Add a single record to the STAR-lite archive.

 @param key The record key (e.g., "app.bsky.feed.post/abc123").
 @param data The raw DAG-CBOR record data.
 */
- (void)addRecordWithKey:(NSString *)key data:(NSData *)data;

/*!
 @method serialize

 @abstract Returns the complete STAR-lite archive data.

 @return STAR-lite encoded data.
 */
- (nullable NSData *)serialize;

/*!
 @method writeToPath:error:

 @abstract Writes the STAR-lite archive to a file.

 @param path Destination file path.
 @param error Error pointer for write failures.
 @return YES on success, NO on failure.
 */
- (BOOL)writeToPath:(NSString *)path error:(NSError **)error;

@end

#pragma mark - ATProtoSTARLiteV0Writer

/*!
 @class ATProtoSTARLiteV0Writer

 @abstract Writes upstream STAR-lite version 0 archives (`*l\0`).

 @discussion This is the interoperable STAR-lite defined by the upstream spec
 at https://tangled.org/microcosm.blue/star, distinct from the local variant
 written by ATProtoSTARLiteWriter. The wire format is:

     [ 2A 6C 00 | mst-root-cid (36 bytes) | varint(len) | commit ]
     [ varint(keyLen) | key | varint(recLen) | record ] ...

 The header CID links the repo's ATProtoMST root directly, so the commit
 carried in the header is *partial*: the `data` key is stripped. A reader
 re-inserts `data` from the header CID to recover the signed commit, so the
 remaining commit keys must be preserved byte-faithfully — this writer strips
 `data` from the stored commit block rather than rebuilding the map from a
 fixed field list.

 Records are emitted in strict lexicographic key order with no duplicates.
 There is no representation for a partial (`since`) export: the record stream
 must rebuild the exact ATProtoMST root named in the header.
 */
@interface ATProtoSTARLiteV0Writer : NSObject

/*! The ATProtoMST root ATProtoCID committed to by the header. */
@property (nonatomic, strong, readonly) ATProtoCID *mstRootCID;

/*! The partial (data-stripped) commit as DAG-CBOR. */
@property (nonatomic, copy, readonly) NSData *partialCommit;

/*!
 @method initWithMSTRootCID:commitBlock:error:

 @abstract Initialize a writer from the repo's ATProtoMST root and stored commit.

 @param mstRootCID The ATProtoMST root ATProtoCID. Pass nil for an empty repository to
 use ATProtoMSTEmptyRootCID().
 @param commitBlock The stored commit block as DAG-CBOR, including `data`.
 @param error Error pointer for decoding failures.
 @return A new writer, or nil if the commit block could not be decoded, or if
 re-inserting `data` into the partial commit does not reproduce the stored
 commit byte-for-byte.
 */
- (nullable instancetype)initWithMSTRootCID:(nullable ATProtoCID *)mstRootCID
                                commitBlock:(NSData *)commitBlock
                                      error:(NSError **)error;

/*!
 @method headerData

 @abstract Returns the encoded archive header.

 @return magic + root ATProtoCID + varint-prefixed partial commit.
 */
- (NSData *)headerData;

/*!
 @method recordChunkWithKey:data:

 @abstract Encodes one key/record pair as a standalone archive chunk.

 @param key The record key (e.g. "app.bsky.feed.post/abc123").
 @param recordData The raw DAG-CBOR record data.
 @return varint(keyLen) | key | varint(dataLen) | record.
 */
+ (NSData *)recordChunkWithKey:(NSString *)key data:(NSData *)recordData;

/*!
 @method writeFromMST:blockProvider:error:

 @abstract Walk the ATProtoMST in key order and serialize as STAR-lite v0.

 @param mst The ATProtoMST to serialize.
 @param blockProvider Block that returns record data for a given ATProtoCID.
 @param error Error pointer for serialization failures.
 @return YES on success, NO on failure.
 */
- (BOOL)writeFromMST:(nullable ATProtoMST *)mst
       blockProvider:(nullable NSData * _Nullable (^)(ATProtoCID *cid))blockProvider
               error:(NSError **)error;

/*!
 @method serialize

 @abstract Returns the complete STAR-lite v0 archive data.

 @return STAR-lite v0 encoded data.
 */
- (nullable NSData *)serialize;

@end

/*! Maximum record key length: 317 (collection) + 1 (slash) + 512 (rkey). */
FOUNDATION_EXPORT const NSUInteger STARLiteV0MaxKeyLength;

/*! Maximum record size, per atproto limits. */
FOUNDATION_EXPORT const NSUInteger STARLiteV0MaxRecordLength;

#pragma mark - ATProtoSTARReader

/*!
 @class ATProtoSTARReader

 @abstract Reads and parses STAR archives (both L0 and lite).

 @discussion Detects the variant from the header and parses the archive,
 reconstituting blocks as ATProtoCARBlock objects for compatibility with existing
 code that expects CAR-format blocks.

 Usage:
     ATProtoSTARReader *reader = [ATProtoSTARReader readFromData:data error:&err];
     for (ATProtoCARBlock *block in reader.blocks) { ... }
 */
@interface ATProtoSTARReader : NSObject

/**
 * @abstract Exposes the root cid value.
 */
@property (nonatomic, strong, readonly, nullable) ATProtoCID *rootCID;
@property (nonatomic, copy, readonly) NSArray<ATProtoCARBlock *> *blocks;
@property (nonatomic, assign, readonly) STARVariant variant;
@property (nonatomic, strong, readonly, nullable) ATProtoSTARCommit *commit;

/**
 * @abstract Performs the readFromData operation.
 */
+ (nullable instancetype)readFromData:(NSData *)data error:(NSError **)error;
/**
 * @abstract Performs the readFromPath operation.
 */
+ (nullable instancetype)readFromPath:(NSString *)path error:(NSError **)error;

/*!
 @method blockWithCID:

 @abstract Retrieves a block by its ATProtoCID.

 @param cid The ATProtoCID to look up.
 @return The block with the given ATProtoCID, or nil if not found.
 */
- (nullable ATProtoCARBlock *)blockWithCID:(ATProtoCID *)cid;

@end

#pragma mark - STAR Converter

/*!
 @class ATProtoSTARConverter

 @abstract Conversion from STAR to CAR format.

 @discussion Provides verifying STAR-to-CAR conversion. The reader
 validates every ATProtoMST node ATProtoCID against the commit's data ATProtoCID chain,
 rehydrates layer-0 record links, and strips wire-format flags. CAR-to-STAR
 conversion is not supported; use the live-ATProtoMST writer (ATProtoSTARL0Writer)
 for export.
 */
@interface ATProtoSTARConverter : NSObject

/*!
 @method carDataFromSTARData:error:

 @abstract Convert STAR data (L0 or lite) to CAR format.

 @discussion STAR-to-CAR conversion is verifying: the reader validates
 every ATProtoMST node ATProtoCID against the commit's data ATProtoCID chain, rehydrates
 layer-0 record links, and strips wire-format flags before
 re-serializing to repo-spec form. Sig-less STAR archives are rejected
 because they cannot produce a compliant CAR.

 @param starData STAR-encoded archive data.
 @param error Error pointer for conversion failures.
 @return CAR-encoded data with the commit ATProtoCID as root, or nil on failure.
 */
+ (nullable NSData *)carDataFromSTARData:(NSData *)starData error:(NSError **)error;

@end

#pragma mark - STAR Format Detection

/*!
 @function STARDetectFormatFromData

 @abstract Detect whether data is STAR format by checking the magic byte.

 @param data The first bytes of the data to check.
 @return YES if the data starts with the STAR magic byte (0x2A).
 */
FOUNDATION_EXPORT BOOL STARDetectFormatFromData(NSData *data);

/*!
 @function STARDetectFormatFromPath

 @abstract Detect whether a file contains STAR format.

 @param path Path to the file.
 @return YES if the file starts with the STAR magic byte (0x2A).
 */
FOUNDATION_EXPORT BOOL STARDetectFormatFromPath(NSString *path);

#pragma mark - STAR Content Types

FOUNDATION_EXPORT NSString *const STARContentTypeL0;
FOUNDATION_EXPORT NSString *const STARContentTypeLite;
FOUNDATION_EXPORT NSString *const STARContentTypeLiteV0;
FOUNDATION_EXPORT NSString *const CARContentType;

/*!

 @abstract Repository serialization format for content negotiation.

 @constant PDSRepoFormatCAR CAR v1, the protocol default.
 @constant PDSRepoFormatSTARL0 STAR-L0 (local variant, version 1).
 @constant PDSRepoFormatSTARLite STAR-lite (local variant, version 2).
 @constant PDSRepoFormatSTARLiteV0 Upstream STAR-lite version 0, the
 interoperable variant consumed by microcosm's Hubble.
 */
typedef NS_ENUM(NSUInteger, PDSRepoFormat) {
    PDSRepoFormatCAR,
    PDSRepoFormatSTARL0,
    PDSRepoFormatSTARLite,
    PDSRepoFormatSTARLiteV0
};

/*!
 @function PDSRepoFormatFromAcceptHeader

 @abstract Negotiate the desired repo format from an HTTP Accept header.

 @param acceptHeader The value of the Accept header (may be nil).
 @return The highest-quality supported format. Defaults to CAR when no
 supported representation has a positive quality.
 */
FOUNDATION_EXPORT PDSRepoFormat PDSRepoFormatFromAcceptHeader(NSString * _Nullable acceptHeader);

/*!
 @function PDSRepoFormatFromAcceptQueryParameter

 @abstract Negotiate the desired repo format from an `accept` query parameter.

 @discussion A non-standard convenience parameter mirroring Hubble's own
 `getRepo?accept=star-lite`. When present and recognized it overrides the
 Accept header; unrecognized values leave negotiation to the header.

 @param value The raw `accept` query parameter value (may be nil).
 @param format On return, the negotiated format when the value is recognized.
 @return YES if the parameter named a supported format.
 */
FOUNDATION_EXPORT BOOL PDSRepoFormatFromAcceptQueryParameter(NSString * _Nullable value,
                                                             PDSRepoFormat *format);

/*!
 @function ContentTypeForPDSRepoFormat

 @abstract Get the Content-Type string for a repo format.

 @param format The format.
 @return The MIME type string.
 */
FOUNDATION_EXPORT NSString *ContentTypeForPDSRepoFormat(PDSRepoFormat format);

/*!
 @function PDSRepoAcceptHeaderForPreferredFormat

 @abstract Build an HTTP Accept header for a preferred repository format.

 @discussion STAR preferences include compatible fallbacks so callers can
 interoperate with services that only produce CAR.

 @param format The preferred repository format.
 @return An Accept header value ordered by preference.
 */
FOUNDATION_EXPORT NSString *PDSRepoAcceptHeaderForPreferredFormat(PDSRepoFormat format);

NS_ASSUME_NONNULL_END

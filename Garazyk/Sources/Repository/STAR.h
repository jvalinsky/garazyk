// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

#import "Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

@class CARBlock;
@class MST;
@class MSTNode;
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
 - STAR-L0: preserves MST structure, best for streaming verification
 - STAR-lite: flat key-record encoding, best compression

 @copyright Copyright (c) 2025-2026 Jack Valinsky

 @see https://tangled.org/microcosm.blue/star
 */

/*!

 @abstract Specifies the STAR format variant.

 @constant STARVariantL0  STAR-L0: MST-structured, streaming verification
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

#pragma mark - STAR MST Entry (wire format)

/*!
 @class ATProtoSTARMstEntry

 @abstract A single entry in a STAR MST node (wire format).

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

#pragma mark - STAR MST Node (wire format)

/*!
 @class ATProtoSTARMstNode

 @abstract A MST node in STAR wire format.

 @discussion STAR MST nodes differ from repo-spec MST nodes:
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

 @discussion STAR-L0 preserves the MST structure and enables streaming
 verification. The writer walks the MST depth-first, emitting nodes and
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

 @abstract Walk the MST depth-first and serialize as STAR-L0.

 @param mst The MST to serialize.
 @param blockProvider Block that returns record data for a given ATProtoCID.
 @param error Error pointer for serialization failures.
 @return YES on success, NO on failure.
 */
- (BOOL)writeFromMST:(MST *)mst
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

 @discussion STAR-lite is a flat key-record encoding with no MST structure.
 It provides the best compression ratio but requires disk spilling or two
 passes for MST recovery. Records are emitted in sorted key order.

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

 @abstract Walk the MST and serialize as STAR-lite (flat key-record).

 @param mst The MST to serialize.
 @param blockProvider Block that returns record data for a given ATProtoCID.
 @param error Error pointer for serialization failures.
 @return YES on success, NO on failure.
 */
- (BOOL)writeFromMST:(MST *)mst
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

#pragma mark - ATProtoSTARReader

/*!
 @class ATProtoSTARReader

 @abstract Reads and parses STAR archives (both L0 and lite).

 @discussion Detects the variant from the header and parses the archive,
 reconstituting blocks as CARBlock objects for compatibility with existing
 code that expects CAR-format blocks.

 Usage:
     ATProtoSTARReader *reader = [ATProtoSTARReader readFromData:data error:&err];
     for (CARBlock *block in reader.blocks) { ... }
 */
@interface ATProtoSTARReader : NSObject

/**
 * @abstract Exposes the root cid value.
 */
@property (nonatomic, strong, readonly, nullable) ATProtoCID *rootCID;
@property (nonatomic, copy, readonly) NSArray<CARBlock *> *blocks;
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
- (nullable CARBlock *)blockWithCID:(ATProtoCID *)cid;

@end

#pragma mark - STAR Converter

/*!
 @class ATProtoSTARConverter

 @abstract Conversion from STAR to CAR format.

 @discussion Provides verifying STAR-to-CAR conversion. The reader
 validates every MST node ATProtoCID against the commit's data ATProtoCID chain,
 rehydrates layer-0 record links, and strips wire-format flags. CAR-to-STAR
 conversion is not supported; use the live-MST writer (ATProtoSTARL0Writer)
 for export.
 */
@interface ATProtoSTARConverter : NSObject

/*!
 @method carDataFromSTARData:error:

 @abstract Convert STAR data (L0 or lite) to CAR format.

 @discussion STAR-to-CAR conversion is verifying: the reader validates
 every MST node ATProtoCID against the commit's data ATProtoCID chain, rehydrates
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
FOUNDATION_EXPORT NSString *const CARContentType;

/*!

 @abstract Repository serialization format for content negotiation.
 */
typedef NS_ENUM(NSUInteger, PDSRepoFormat) {
    PDSRepoFormatCAR,
    PDSRepoFormatSTARL0,
    PDSRepoFormatSTARLite
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

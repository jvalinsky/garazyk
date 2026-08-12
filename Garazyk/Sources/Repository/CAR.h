// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Core/CID.h"
#import "Core/CBOR.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoMASLDocument;

/*!
 @header CAR.h
 
 @abstract Content Addressable Records (CAR) format utilities.
 
 @discussion This header defines classes for reading and writing Content
 Addressable Records (CAR) format, used by ATProto for serializing
 repository data. CAR files contain blocks indexed by their CIDs.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

/*!
 @class ATProtoCARBlock
 
 @abstract A single block in a CAR archive.
 
 @discussion ATProtoCARBlock represents a content-addressable block with its
 ATProtoCID and data. Blocks are the fundamental units of storage in CAR format.
 
 @code
 ATProtoCARBlock *block = [ATProtoCARBlock blockWithCID:cid data:blockData];
 @endcode
 */
@interface ATProtoCARBlock : NSObject

/*! The content identifier for this block. */
@property (nonatomic, strong, readonly) ATProtoCID *cid;

/*! The block data content. */
@property (nonatomic, copy, readonly) NSData *data;

/*!
 @method blockWithCID:data:
 
 @abstract Creates a CAR block with ATProtoCID and data.
 
 @param cid The ATProtoCID identifying this block.
 @param data The block content data.
 @return A new ATProtoCARBlock instance.
 */
+ (instancetype)blockWithCID:(ATProtoCID *)cid data:(NSData *)data;

/*!
 @method initWithCID:data:
 
 @abstract Initializes a CAR block.
 
 @param cid The ATProtoCID identifying this block.
 @param data The block content data.
 @return An initialized ATProtoCARBlock instance.
 */
- (instancetype)initWithCID:(ATProtoCID *)cid data:(NSData *)data;

@end

/*!
 @class ATProtoCARReader
 
 @abstract Reads and parses CAR archives.
 
 @discussion ATProtoCARReader provides functionality for reading existing CAR
 archives, either from in-memory data or from a file path. It supports
 looking up blocks by ATProtoCID.
 
 @code
 // Read CAR from file
 ATProtoCARReader *reader = [ATProtoCARReader readFromPath:@"/path/to/repo.car" error:nil];
 
 // Look up a block
 ATProtoCARBlock *block = [reader blockWithCID:cid];
 
 // Get all blocks
 NSArray *blocks = reader.blocks;
 @endcode
 */
/**
 * @abstract Declares the ATProtoCARReader public API.
 */
@interface ATProtoCARReader : NSObject

/*! All root CIDs declared in the CAR header. For a standard single-root CAR
 *  this array contains exactly one element; for a space CAR it contains two
 *  (signed commit + DRISL index). */
@property (nonatomic, copy, readonly, nullable) NSArray<ATProtoCID *> *roots;

/*! The complete DRISL metadata map from the CAR header. */
@property (nonatomic, copy, readonly, nullable) NSDictionary *metadata;

/*! The header metadata as a validated MASL document, when it is valid MASL. */
@property (nonatomic, strong, readonly, nullable) ATProtoMASLDocument *maslDocument;

/*! The first root ATProtoCID, equivalent to @c roots.firstObject.  Preserved for
 *  backward compatibility with callers that expect a single root. */
@property (nonatomic, strong, readonly, nullable) ATProtoCID *rootCID;

/*! All blocks contained in the archive. */
@property (nonatomic, copy, readonly) NSArray<ATProtoCARBlock *> *blocks;

/*!
 @method readFromData:error:
 
 @abstract Creates a reader from CAR data in memory.
 
 @param data The CAR-encoded data.
 @param error On return, contains an error if parsing failed.
 @return A new ATProtoCARReader instance, or nil on failure.
 */
+ (nullable instancetype)readFromData:(NSData *)data error:(NSError **)error;

/*!
 @method readFromPath:error:
 
 @abstract Creates a reader from a CAR file.
 
 @param path The file path to the CAR archive.
 @param error On return, contains an error if reading failed.
 @return A new ATProtoCARReader instance, or nil on failure.
 */
+ (nullable instancetype)readFromPath:(NSString *)path error:(NSError **)error;

/*!
 @method readFromData:strict:error:

 @abstract Creates a reader from CAR data, optionally enforcing the DASL CAR
 spec.

 @param data The CAR-encoded data.
 @param strict When YES, apply the rules from https://dasl.ing/car.html: the
 header must be canonical DRISL; every block ATProtoCID must be a conformant DASL ATProtoCID
 whose digest matches SHA-256 of the block payload; every declared root must
 be present in the body; and the non-standard legacy fallback layout is not
 attempted.
 @param error On return, contains an error if parsing or verification failed.
 @return A new ATProtoCARReader instance, or nil on failure.

 @discussion Non-strict reading, which is what @c readFromData:error: does,
 trusts the ATProtoCID stated for each block. That is fine for archives this process
 produced, and wrong for archives that arrived over the network: nothing
 otherwise stops a peer claiming any ATProtoCID for any bytes.
 */
+ (nullable instancetype)readFromData:(NSData *)data
                               strict:(BOOL)strict
                                error:(NSError **)error;

/*!
 @method readFromPath:strict:error:

 @abstract Creates a reader from a CAR file, optionally enforcing the DASL CAR
 spec.

 @param path The file path to the CAR archive.
 @param strict See @c readFromData:strict:error:.
 @param error On return, contains an error if reading or verification failed.
 @return A new ATProtoCARReader instance, or nil on failure.
 */
+ (nullable instancetype)readFromPath:(NSString *)path
                               strict:(BOOL)strict
                                error:(NSError **)error;

/*!
 @method blockWithCID:
 
 @abstract Retrieves a block by its ATProtoCID.
 
 @param cid The ATProtoCID to look up.
 @return The block with the given ATProtoCID, or nil if not found.
 */
- (nullable ATProtoCARBlock *)blockWithCID:(ATProtoCID *)cid;

/**
 Looks up a CAR block referenced by a MASL bundle path.

 Query strings and fragments are ignored during path resolution. The reader
 returns nil with an NSError when the header is not a MASL bundle or the
 referenced CID is not present in the body.
 */
- (nullable ATProtoCARBlock *)blockForMASLPath:(NSString *)path error:(NSError **)error;

@end

/*!
 @class ATProtoCARStreamReader

 @abstract Incremental, block-at-a-time CAR reader.

 @discussion Parses the CAR header up front and then yields blocks one at a
 time from the body without materializing a full block array. In strict mode
 each block's ATProtoCID is verified against a SHA-256 of its payload as it
 is read, and every declared root must be present in the body by the time
 the stream is exhausted. A CID-to-block index is maintained as blocks
 stream so callers that need random access (e.g. an MST walk) can look up
 blocks already seen; blocks not yet streamed are simply not present yet.

 Memory is bounded by the index rather than by the archive: the underlying
 NSData is retained (the blocks are subdata ranges into it), but no
 additional full-size copy is made. Suitable for reading large
 repositories (multi-hundred-MB CARs) with a single pass.
 */
@interface ATProtoCARStreamReader : NSObject

/*! All root CIDs declared in the CAR header. */
@property (nonatomic, copy, readonly, nullable) NSArray<ATProtoCID *> *roots;

/*! The first root ATProtoCID, equivalent to @c roots.firstObject. */
@property (nonatomic, strong, readonly, nullable) ATProtoCID *rootCID;

/*! The complete DRISL metadata map from the CAR header. */
@property (nonatomic, copy, readonly, nullable) NSDictionary *metadata;

/*! The header metadata as a validated MASL document, when it is valid MASL. */
@property (nonatomic, strong, readonly, nullable) ATProtoMASLDocument *maslDocument;

/*!
 @method initWithData:strict:error:

 @abstract Parses the CAR header, leaving the body ready to be streamed.

 @param data The CAR-encoded data. Retained for the lifetime of the reader.
 @param strict When YES, enforce DASL CAR rules: canonical DRISL header,
 conformant CIDs, per-block SHA-256 digest verification, and root presence
 in the body (checked when the stream is exhausted).
 @param error On return, contains an error if the header could not be parsed.
 @return An initialized reader, or nil on header failure.
 */
- (nullable instancetype)initWithData:(NSData *)data
                               strict:(BOOL)strict
                                error:(NSError **)error;

/*!
 @method nextBlockWithError:

 @abstract Returns the next block in the archive, or nil at the end.

 @param error On return, contains an error if the block could not be parsed
 or (in strict mode) failed verification. At natural exhaustion the error is
 left nil and the reader reports finished.
 @return The next ATProtoCARBlock, or nil when the archive is exhausted or
 parsing failed.
 */
- (nullable ATProtoCARBlock *)nextBlockWithError:(NSError **)error;

/*!
 @method enumerateBlocksWithError:handler:

 @abstract Streams every block through a handler.

 @param error On return, contains an error if streaming failed.
 @param handler Invoked once per block. Return NO to stop early; set
 *stopError to report a reason, in which case enumerate returns NO with that
 error. In strict mode root presence is verified after the last block.
 @return YES if every block was delivered (or the handler stopped with a
 nil stopError), NO on parse/verification failure.
 */
- (BOOL)enumerateBlocksWithError:(NSError **)error
                         handler:(BOOL (^)(ATProtoCARBlock *block, NSError **stopError))handler;

/*!
 @method blockWithCID:

 @abstract Returns a block already streamed by this reader, or nil if it has
 not been seen yet (or is absent from the archive).
 */
- (nullable ATProtoCARBlock *)blockWithCID:(ATProtoCID *)cid;

/*!
 @method reset

 @abstract Rewinds the stream to the first block. The block index is cleared
 and rebuilt as blocks are re-read. Header parsing is not repeated.
 */
- (void)reset;

/*!
 @method isFinished

 @abstract YES once the stream has reached the end of the archive.
 */
@property (nonatomic, readonly) BOOL isFinished;

@end

/*!
 @class ATProtoCARWriter
 
 @abstract Creates and writes CAR archives.
 
 @discussion ATProtoCARWriter provides functionality for building CAR archives
 by adding blocks. The writer maintains a root ATProtoCID and collection of
 blocks, supporting serialization to data or file output.
 
 @code
 // Create a new CAR archive
 ATProtoCARWriter *writer = [ATProtoCARWriter writerWithRootCID:rootCID];
 
 // Add blocks
 [writer addBlock:block1];
 [writer addBlock:block2];
 
 // Get serialized data
 NSData *carData = [writer serialize];
 
 // Or write to file
 [writer writeToPath:@"/path/to/output.car" error:nil];
 @endcode
 */
/**
 * @abstract Declares the ATProtoCARWriter public API.
 */
@interface ATProtoCARWriter : NSObject

/*! The root ATProtoCID of this CAR archive. */
@property (nonatomic, strong, readonly, nullable) ATProtoCID *rootCID;

/*! The validated MASL document used as the CAR header, when supplied. */
@property (nonatomic, strong, readonly, nullable) ATProtoMASLDocument *maslDocument;

/*! The collection of blocks that have been added. */
@property (nonatomic, strong, readonly) NSMutableArray<ATProtoCARBlock *> *blocks;

/*!
 @method writerWithRootCID:
 
 @abstract Creates a new CAR writer with a root ATProtoCID.
 
 @param rootCID The ATProtoCID that will serve as the archive root.
 @return A new ATProtoCARWriter instance.
 */
+ (instancetype)writerWithRootCID:(ATProtoCID *)rootCID;

/*! Initializes a writer; a nil root is used only for an empty MASL roots array. */
- (instancetype)initWithRootCID:(nullable ATProtoCID *)rootCID NS_DESIGNATED_INITIALIZER;

/**
 Creates a writer whose CAR header is the supplied MASL document.

 The document must contain CAR-compatible integer @c version 1 and a
 CID-only @c roots array. The roots array may be empty, as permitted by CAR.
 */
+ (nullable instancetype)writerWithMASLDocument:(ATProtoMASLDocument *)document
                                           error:(NSError **)error;

/*!
 @method addBlock:
 
 @abstract Adds a block to the archive.
 
 @param block The block to add.
 */
- (void)addBlock:(ATProtoCARBlock *)block;

/*!
 @method serialize
 
 @abstract Serializes the archive to CAR format.
 
 @return CAR-encoded data suitable for storage or transmission.
 */
- (NSData *)serialize;

/*!
 @method writeToPath:error:
 
 @abstract Writes the archive to a file.
 
 @param path The destination file path.
 @param error On return, contains an error if writing failed.
 @return YES if the file was written successfully, NO otherwise.
 */
- (BOOL)writeToPath:(NSString *)path error:(NSError **)error;

/*!
 @method encodedHeaderWithRootCID:error:

 @abstract Encodes a CAR v1 header for the given root ATProtoCID.

 @param rootCID The CAR root ATProtoCID.
 @param error On return, contains an error if encoding failed.
 @return Encoded header bytes or nil on failure.
 */
+ (nullable NSData *)encodedHeaderWithRootCID:(ATProtoCID *)rootCID error:(NSError **)error;

/*! Encodes a CAR v1 header from a validated MASL document. */
+ (nullable NSData *)encodedHeaderWithMASLDocument:(ATProtoMASLDocument *)document
                                              error:(NSError **)error;

/*!
 @method encodedBlock:error:

 @abstract Encodes one CAR block entry (length varint + ATProtoCID + block data).

 @param block The block to encode.
 @param error On return, contains an error if encoding failed.
 @return Encoded block entry bytes or nil on failure.
 */
+ (nullable NSData *)encodedBlock:(ATProtoCARBlock *)block error:(NSError **)error;

/*!
 @method writeHeaderWithRootCID:toFileHandle:error:

 @abstract Writes a CAR v1 header directly to an open file handle.

 @param rootCID The CAR root ATProtoCID.
 @param fileHandle Destination file handle.
 @param error On return, contains an error if writing failed.
 @return YES on success, NO on failure.
 */
+ (BOOL)writeHeaderWithRootCID:(ATProtoCID *)rootCID
                 toFileHandle:(NSFileHandle *)fileHandle
                        error:(NSError **)error;

/*! Writes a CAR v1 MASL metadata header directly to an open file handle. */
+ (BOOL)writeHeaderWithMASLDocument:(ATProtoMASLDocument *)document
                       toFileHandle:(NSFileHandle *)fileHandle
                              error:(NSError **)error;

/*!
 @method writeBlock:toFileHandle:error:

 @abstract Appends one CAR block entry directly to an open file handle.

 @param block The block to append.
 @param fileHandle Destination file handle.
 @param error On return, contains an error if writing failed.
 @return YES on success, NO on failure.
 */
+ (BOOL)writeBlock:(ATProtoCARBlock *)block
      toFileHandle:(NSFileHandle *)fileHandle
             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

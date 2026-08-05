// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Core/CID.h"
#import "Core/CBOR.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @header CAR.h
 
 @abstract Content Addressable Records (CAR) format utilities.
 
 @discussion This header defines classes for reading and writing Content
 Addressable Records (CAR) format, used by ATProto for serializing
 repository data. CAR files contain blocks indexed by their CIDs.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

/*!
 @class CARBlock
 
 @abstract A single block in a CAR archive.
 
 @discussion CARBlock represents a content-addressable block with its
 ATProtoCID and data. Blocks are the fundamental units of storage in CAR format.
 
 @code
 CARBlock *block = [CARBlock blockWithCID:cid data:blockData];
 @endcode
 */
@interface CARBlock : NSObject

/*! The content identifier for this block. */
@property (nonatomic, strong, readonly) ATProtoCID *cid;

/*! The block data content. */
@property (nonatomic, copy, readonly) NSData *data;

/*!
 @method blockWithCID:data:
 
 @abstract Creates a CAR block with ATProtoCID and data.
 
 @param cid The ATProtoCID identifying this block.
 @param data The block content data.
 @return A new CARBlock instance.
 */
+ (instancetype)blockWithCID:(ATProtoCID *)cid data:(NSData *)data;

/*!
 @method initWithCID:data:
 
 @abstract Initializes a CAR block.
 
 @param cid The ATProtoCID identifying this block.
 @param data The block content data.
 @return An initialized CARBlock instance.
 */
- (instancetype)initWithCID:(ATProtoCID *)cid data:(NSData *)data;

@end

/*!
 @class CARReader
 
 @abstract Reads and parses CAR archives.
 
 @discussion CARReader provides functionality for reading existing CAR
 archives, either from in-memory data or from a file path. It supports
 looking up blocks by ATProtoCID.
 
 @code
 // Read CAR from file
 CARReader *reader = [CARReader readFromPath:@"/path/to/repo.car" error:nil];
 
 // Look up a block
 CARBlock *block = [reader blockWithCID:cid];
 
 // Get all blocks
 NSArray *blocks = reader.blocks;
 @endcode
 */
/**
 * @abstract Declares the CARReader public API.
 */
@interface CARReader : NSObject

/*! All root CIDs declared in the CAR header. For a standard single-root CAR
 *  this array contains exactly one element; for a space CAR it contains two
 *  (signed commit + DRISL index). */
@property (nonatomic, copy, readonly, nullable) NSArray<ATProtoCID *> *roots;

/*! The first root ATProtoCID, equivalent to @c roots.firstObject.  Preserved for
 *  backward compatibility with callers that expect a single root. */
@property (nonatomic, strong, readonly, nullable) ATProtoCID *rootCID;

/*! All blocks contained in the archive. */
@property (nonatomic, copy, readonly) NSArray<CARBlock *> *blocks;

/*!
 @method readFromData:error:
 
 @abstract Creates a reader from CAR data in memory.
 
 @param data The CAR-encoded data.
 @param error On return, contains an error if parsing failed.
 @return A new CARReader instance, or nil on failure.
 */
+ (nullable instancetype)readFromData:(NSData *)data error:(NSError **)error;

/*!
 @method readFromPath:error:
 
 @abstract Creates a reader from a CAR file.
 
 @param path The file path to the CAR archive.
 @param error On return, contains an error if reading failed.
 @return A new CARReader instance, or nil on failure.
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
 @return A new CARReader instance, or nil on failure.

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
 @return A new CARReader instance, or nil on failure.
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
- (nullable CARBlock *)blockWithCID:(ATProtoCID *)cid;

@end

/*!
 @class CARWriter
 
 @abstract Creates and writes CAR archives.
 
 @discussion CARWriter provides functionality for building CAR archives
 by adding blocks. The writer maintains a root ATProtoCID and collection of
 blocks, supporting serialization to data or file output.
 
 @code
 // Create a new CAR archive
 CARWriter *writer = [CARWriter writerWithRootCID:rootCID];
 
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
 * @abstract Declares the CARWriter public API.
 */
@interface CARWriter : NSObject

/*! The root ATProtoCID of this CAR archive. */
@property (nonatomic, strong, readonly) ATProtoCID *rootCID;

/*! The collection of blocks that have been added. */
@property (nonatomic, strong, readonly) NSMutableArray<CARBlock *> *blocks;

/*!
 @method writerWithRootCID:
 
 @abstract Creates a new CAR writer with a root ATProtoCID.
 
 @param rootCID The ATProtoCID that will serve as the archive root.
 @return A new CARWriter instance.
 */
+ (instancetype)writerWithRootCID:(ATProtoCID *)rootCID;

/*!
 @method addBlock:
 
 @abstract Adds a block to the archive.
 
 @param block The block to add.
 */
- (void)addBlock:(CARBlock *)block;

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

/*!
 @method encodedBlock:error:

 @abstract Encodes one CAR block entry (length varint + ATProtoCID + block data).

 @param block The block to encode.
 @param error On return, contains an error if encoding failed.
 @return Encoded block entry bytes or nil on failure.
 */
+ (nullable NSData *)encodedBlock:(CARBlock *)block error:(NSError **)error;

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

/*!
 @method writeBlock:toFileHandle:error:

 @abstract Appends one CAR block entry directly to an open file handle.

 @param block The block to append.
 @param fileHandle Destination file handle.
 @param error On return, contains an error if writing failed.
 @return YES on success, NO on failure.
 */
+ (BOOL)writeBlock:(CARBlock *)block
      toFileHandle:(NSFileHandle *)fileHandle
             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

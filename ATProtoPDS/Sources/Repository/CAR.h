#import <Foundation/Foundation.h>
#import "Core/CID.h"
#import "Repository/CBOR.h"

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
 CID and data. Blocks are the fundamental units of storage in CAR format.
 
 @code
 CARBlock *block = [CARBlock blockWithCID:cid data:blockData];
 @endcode
 */
@interface CARBlock : NSObject

/*! The content identifier for this block. */
@property (nonatomic, strong, readonly) CID *cid;

/*! The block data content. */
@property (nonatomic, strong, readonly) NSData *data;

/*!
 @method blockWithCID:data:
 
 @abstract Creates a CAR block with CID and data.
 
 @param cid The CID identifying this block.
 @param data The block content data.
 @return A new CARBlock instance.
 */
+ (instancetype)blockWithCID:(CID *)cid data:(NSData *)data;

/*!
 @method initWithCID:data:
 
 @abstract Initializes a CAR block.
 
 @param cid The CID identifying this block.
 @param data The block content data.
 @return An initialized CARBlock instance.
 */
- (instancetype)initWithCID:(CID *)cid data:(NSData *)data;

@end

/*!
 @class CARReader
 
 @abstract Reads and parses CAR archives.
 
 @discussion CARReader provides functionality for reading existing CAR
 archives, either from in-memory data or from a file path. It supports
 looking up blocks by CID.
 
 @code
 // Read CAR from file
 CARReader *reader = [CARReader readFromPath:@"/path/to/repo.car" error:nil];
 
 // Look up a block
 CARBlock *block = [reader blockWithCID:cid];
 
 // Get all blocks
 NSArray *blocks = reader.blocks;
 @endcode
 */
@interface CARReader : NSObject

/*! The root CID of the CAR archive (the first block). */
@property (nonatomic, strong, readonly, nullable) CID *rootCID;

/*! All blocks contained in the archive. */
@property (nonatomic, strong, readonly) NSArray<CARBlock *> *blocks;

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
 @method blockWithCID:
 
 @abstract Retrieves a block by its CID.
 
 @param cid The CID to look up.
 @return The block with the given CID, or nil if not found.
 */
- (nullable CARBlock *)blockWithCID:(CID *)cid;

@end

/*!
 @class CARWriter
 
 @abstract Creates and writes CAR archives.
 
 @discussion CARWriter provides functionality for building CAR archives
 by adding blocks. The writer maintains a root CID and collection of
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
@interface CARWriter : NSObject

/*! The root CID of this CAR archive. */
@property (nonatomic, strong, readonly) CID *rootCID;

/*! The collection of blocks that have been added. */
@property (nonatomic, strong, readonly) NSMutableArray<CARBlock *> *blocks;

/*!
 @method writerWithRootCID:
 
 @abstract Creates a new CAR writer with a root CID.
 
 @param rootCID The CID that will serve as the archive root.
 @return A new CARWriter instance.
 */
+ (instancetype)writerWithRootCID:(CID *)rootCID;

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

@end

NS_ASSUME_NONNULL_END

/**
 * @file CAR.h
 * @brief Content Addressable Records (CAR) format reader and writer for ATProto PDS.
 *
 * This header defines the classes for reading and writing Content Addressable Records,
 * which is a format used by the AT Protocol (bluesky social) for storing repository data.
 * The CAR format is a simple container that stores blocks of data indexed by their CIDs
 * (Content Identifiers).
 *
 * The CAR format consists of:
 * - A header containing the root CID of the data structure
 * - An index section mapping CIDs to block positions
 * - A data section containing the actual binary blocks
 *
 * This implementation provides streaming read/write capabilities for efficient
 * handling of large repositories.
 *
 * @see https://ipld.io/specs/codecs/dag-cbor/
 * @see https://atproto.com/specs/repository
 */

#import <Foundation/Foundation.h>
#import "../CID.h"
#import "CBOR.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class CARBlock
 * @brief Represents a single block of data with its content identifier.
 *
 * CARBlock is a container that associates binary data with its CID (Content Identifier).
 * Blocks are the fundamental unit of storage in the CAR format and are used to store
 * serialized objects such as MST nodes, records, and other data structures.
 *
 * Each block maintains its CID, which is computed from the data itself, enabling
 * content-addressable storage and verification.
 */
@interface CARBlock : NSObject

/** The content identifier for this block, computed from the data. */
@property (nonatomic, strong, readonly) CID *cid;

/** The raw binary data stored in this block. */
@property (nonatomic, strong, readonly) NSData *data;

/**
 * @brief Creates a new CAR block with the specified CID and data.
 * @param cid The content identifier for this block.
 * @param data The binary data to store.
 * @return A new CARBlock instance.
 */
+ (instancetype)blockWithCID:(CID *)cid data:(NSData *)data;

/**
 * @brief Initializes a new CAR block with the specified CID and data.
 * @param cid The content identifier for this block.
 * @param data The binary data to store.
 * @return A new CARBlock instance.
 */
- (instancetype)initWithCID:(CID *)cid data:(NSData *)data;

@end

/**
 * @class CARReader
 * @brief Reads and parses Content Addressable Records (CAR) files.
 *
 * CARReader provides deserialization of CAR-formatted data, enabling extraction
 * of blocks and navigation of content-addressable structures. It supports both
 * in-memory data and file-based reading.
 *
 * The reader maintains an index of all blocks for efficient lookup by CID,
 * and provides access to the root CID that identifies the primary data structure.
 */
@interface CARReader : NSObject

/** The root CID of the data structure stored in this CAR file. */
@property (nonatomic, strong, readonly, nullable) CID *rootCID;

/** Array of all blocks contained in this CAR file, in order. */
@property (nonatomic, strong, readonly) NSArray<CARBlock *> *blocks;

/**
 * @brief Reads and parses a CAR file from in-memory data.
 * @param data The CAR-encoded binary data.
 * @param error On return, contains an error if parsing failed.
 * @return A new CARReader instance, or nil if an error occurred.
 */
+ (nullable instancetype)readFromData:(NSData *)data error:(NSError **)error;

/**
 * @brief Reads and parses a CAR file from disk.
 * @param path The file path to read from.
 * @param error On return, contains an error if reading failed.
 * @return A new CARReader instance, or nil if an error occurred.
 */
+ (nullable instancetype)readFromPath:(NSString *)path error:(NSError **)error;

/**
 * @brief Retrieves a specific block by its CID.
 * @param cid The content identifier to look up.
 * @return The CARBlock with the specified CID, or nil if not found.
 */
- (nullable CARBlock *)blockWithCID:(CID *)cid;

@end

/**
 * @class CARWriter
 * @brief Creates and writes Content Addressable Records (CAR) files.
 *
 * CARWriter provides serialization of blocks into the CAR format. It maintains
 * an in-memory collection of blocks and produces a complete CAR file when serialized.
 *
 * The writer handles:
 * - Block collection and indexing
 * - Header generation with root CID
 * - Efficient binary serialization
 * - File output with error handling
 *
 * Typical usage involves creating blocks, adding them to the writer, and then
 * serializing to memory or writing to disk.
 */
@interface CARWriter : NSObject

/** The root CID of the data structure being written. */
@property (nonatomic, strong, readonly) CID *rootCID;

/** Mutable array of blocks that will be written to the CAR file. */
@property (nonatomic, strong, readonly) NSMutableArray<CARBlock *> *blocks;

/**
 * @brief Creates a new CAR writer for the specified root CID.
 * @param rootCID The CID of the primary data structure (e.g., MST root).
 * @return A new CARWriter instance.
 */
+ (instancetype)writerWithRootCID:(CID *)rootCID;

/**
 * @brief Adds a block to the CAR file.
 * @param block The CARBlock to add.
 */
- (void)addBlock:(CARBlock *)block;

/**
 * @brief Serializes the CAR file to binary data.
 * @return NSData containing the complete CAR-encoded file.
 */
- (NSData *)serialize;

/**
 * @brief Writes the CAR file to disk.
 * @param path The file path to write to.
 * @param error On return, contains an error if writing failed.
 * @return YES if successful, NO otherwise.
 */
- (BOOL)writeToPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CID;

/*!
 @class CARv1Builder
 
 @abstract Builds CAR v1 format archives per IPLD CAR spec.
 
 @discussion This class creates properly formatted CAR v1 archives with
 varint length prefixes and DAG-CBOR encoded headers. This format is
 required for ATProto record verification.
 
 CAR v1 format:
 - Header: varint-length + DAG-CBOR({version: 1, roots: [cid]})
 - Blocks: varint-length + CID-bytes + block-data
 */
@interface CARv1Builder : NSObject

/*! The root CID(s) for this CAR. */
@property (nonatomic, strong, readonly) NSArray<CID *> *roots;

/*! Creates a builder with a single root CID. */
+ (instancetype)builderWithRoot:(CID *)root;

/*! Creates a builder with multiple root CIDs. */
+ (instancetype)builderWithRoots:(NSArray<CID *> *)roots;

/*!
 @method addBlockWithCID:data:
 
 @abstract Adds a block to the CAR.
 
 @param cid The CID for this block.
 @param data The raw block data (DAG-CBOR encoded).
 */
- (void)addBlockWithCID:(CID *)cid data:(NSData *)data;

/*!
 @method build
 
 @abstract Builds the final CAR v1 data.
 
 @return The serialized CAR v1 data ready for transmission.
 */
- (NSData *)build;

#pragma mark - Utility Methods

/*! Encodes an unsigned integer as an unsigned varint. */
+ (NSData *)encodeVarint:(uint64_t)value;

/*! Decodes an unsigned varint from data, returning bytes consumed. */
+ (uint64_t)decodeVarint:(NSData *)data bytesConsumed:(NSUInteger *)consumed;

@end

NS_ASSUME_NONNULL_END

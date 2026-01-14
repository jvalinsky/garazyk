/*!
 @file CID.h

 @abstract Content Identifier (CID) implementation for ATProto repositories.

 @discussion Implements CIDv1 content-addressed identifiers using multibase,
 multicodec, and multihash. CIDs provide cryptographic verification of data
 integrity through SHA-256 hashing. Used for blob references, commit roots,
 and MST node addressing.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class CID

 @abstract Content Identifier with cryptographic hash verification.

 @discussion Represents a CIDv1 identifier containing version, codec, and
 multihash components. Supports base32 encoding for string representation
 and provides SHA-256 hashing utilities.

 @see https://github.com/multiformats/cid
 */
@interface CID : NSObject <NSCopying, NSSecureCoding>

/// Version of the CID (currently 1)
@property (readonly, nonatomic) NSUInteger version;

/// Codec identifier (e.g., 0x55 for raw, 0x71 for dag-cbor)
@property (readonly, nonatomic) NSUInteger codec;

/// Multihash data (algorithm + digest)
@property (readonly, nonatomic, strong) NSData *multihash;

/// Create CID from raw digest data
/// @param digest The raw digest bytes (e.g., 32 bytes for SHA-256)
/// @param codec The codec identifier
+ (nullable instancetype)cidWithDigest:(NSData *)digest codec:(NSUInteger)codec;

/// Create CID from multihash data
/// @param multihash The multihash bytes (algorithm + digest)
/// @param codec The codec identifier
+ (nullable instancetype)cidWithMultihash:(NSData *)multihash codec:(NSUInteger)codec;

/// Create CID from base-encoded string
/// @param string Base-encoded CID string
+ (nullable instancetype)cidFromString:(NSString *)string;

/// Create CID from binary data
/// @param data Binary CID data (version + codec + multihash)
+ (nullable instancetype)cidFromBytes:(NSData *)data;

/// Base32 encode data
+ (NSString *)base32Encode:(NSData *)data;

/// Convert CID to base-encoded string
- (NSString *)stringValue;

/// Compare two CIDs for equality
- (BOOL)isEqualToCID:(CID *)other;

/// Get the raw bytes representation
- (NSData *)bytes;

/// Compute SHA-256 hash and return as CID with raw codec
/// @param data The data to hash
+ (CID *)sha256:(NSData *)data;

/// Compute multihash SHA-256 digest
/// @param data The data to hash
+ (NSData *)sha256Digest:(NSData *)data;

/// Compute raw SHA-256 digest (32 bytes)
/// @param data The data to hash
+ (NSData *)rawSha256:(NSData *)data;

@end

NS_ASSUME_NONNULL_END

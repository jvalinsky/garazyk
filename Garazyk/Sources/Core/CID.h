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

/*! Version of the CID (currently 1). */
@property (readonly, nonatomic) NSUInteger version;

/*! Codec identifier (e.g., 0x55 for raw, 0x71 for dag-cbor). */
@property (readonly, nonatomic) NSUInteger codec;

/*! Multihash data (algorithm + digest). */
@property (readonly, nonatomic, strong) NSData *multihash;

/*!
 @method cidWithDigest:codec:
 @abstract Create CID from raw digest data.
 @param digest The raw digest bytes (e.g., 32 bytes for SHA-256).
 @param codec The codec identifier.
 @return A new CID instance.
 */
+ (nullable instancetype)cidWithDigest:(NSData *)digest codec:(NSUInteger)codec;

/*!
 @method cidWithMultihash:codec:
 @abstract Create CID from multihash data.
 @param multihash The multihash bytes (algorithm + digest).
 @param codec The codec identifier.
 @return A new CID instance.
 */
+ (nullable instancetype)cidWithMultihash:(NSData *)multihash codec:(NSUInteger)codec;

/*!
 @method cidFromString:
 @abstract Create CID from base-encoded string.
 @param string Base-encoded CID string.
 @return A new CID instance.
 */
+ (nullable instancetype)cidFromString:(NSString *)string;

/*!
 @method cidFromBytes:
 @abstract Create CID from binary data.
 @param data Binary CID data (version + codec + multihash).
 @return A new CID instance.
 */
+ (nullable instancetype)cidFromBytes:(NSData *)data;

/*!
 @method cidFromBuffer:length:consumed:
 @abstract Parse a CID from the start of a buffer, reporting how many
 bytes were consumed. Unlike cidFromBytes:, this accepts trailing data
 after the CID (as occurs inside a CAR block entry where the CID is
 immediately followed by the block payload).
 @param bytes Pointer to the buffer.
 @param length Maximum number of bytes the parser may read.
 @param consumed On success, set to the number of bytes the CID occupied.
 May be NULL if the caller does not care.
 @return A parsed CID, or nil if the buffer is malformed, truncated, or
 exceeds bounds.
 */
+ (nullable instancetype)cidFromBuffer:(const uint8_t *)bytes
                                length:(NSUInteger)length
                              consumed:(nullable NSUInteger *)consumed;

/*!
 @method base32Encode:
 @abstract Base32 encode data.
 @param data The data to encode.
 @return Base32 encoded string.
 */
+ (NSString *)base32Encode:(NSData *)data;

/*!
 @method base32Decode:
 @abstract Base32 decode a string.
 @param string The base32 string to decode.
 @return Decoded data or nil on failure.
 */
+ (nullable NSData *)base32Decode:(NSString *)string;

/*!
|  @method base58btcDecode:
|  @abstract Base58btc decode a string.
|  @param string The base58btc string to decode.
|  @return Decoded data or nil on failure.
|  */
+ (nullable NSData *)base58btcDecode:(NSString *)string;

/*!
|  @method base58btcEncode:
|  @abstract Base58btc encode data.
|  @param data The data to encode.
|  @return Base58btc encoded string.
|  */
+ (NSString *)base58btcEncode:(NSData *)data;


/*!
 @method stringValue
 @abstract Convert CID to base-encoded string.
 @return The CID string representation.
 */
- (NSString *)stringValue;

/*!
 @method isEqualToCID:
 @abstract Compare two CIDs for equality.
 @param other The other CID to compare.
 @return YES if CIDs are equal, NO otherwise.
 */
- (BOOL)isEqualToCID:(CID *)other;

/*!
 @method bytes
 @abstract Get the raw bytes representation.
 @return The raw CID bytes.
 */
- (NSData *)bytes;

/*!
 @method sha256:
 @abstract Compute SHA-256 hash and return as CID with raw codec.
 @param data The data to hash.
 @return A new CID instance.
 */
+ (CID *)sha256:(NSData *)data;

/*!
  @method sha256Digest:
  @abstract Compute raw SHA-256 digest (32 bytes).
  @param data The data to hash.
  @return The raw 32-byte hash digest.
  */
+ (NSData *)sha256Digest:(NSData *)data;

/*!
 @method rawSha256:
 @abstract Compute raw SHA-256 digest (32 bytes).
 @param data The data to hash.
 @return The raw 32-byte hash.
 */
+ (NSData *)rawSha256:(NSData *)data;

@end

NS_ASSUME_NONNULL_END

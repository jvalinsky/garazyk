#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Base58btc encoding/decoding for multibase compatibility.
 * Uses Bitcoin's base58 alphabet: 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
 */
@interface Base58 : NSObject

/**
 * Encode data as base58btc string (without multibase prefix).
 * @param data The data to encode
 * @return Base58btc encoded string
 */
+ (NSString *)encodeData:(NSData *)data;

/**
 * Decode a base58btc string to data (without multibase prefix).
 * @param string The base58btc encoded string
 * @return Decoded data, or nil if invalid
 */
+ (nullable NSData *)decodeString:(NSString *)string;

/**
 * Encode data as multibase base58btc (with 'z' prefix).
 * @param data The data to encode
 * @return Multibase base58btc string starting with 'z'
 */
+ (NSString *)encodeMultibase:(NSData *)data;

/**
 * Decode a multibase string (expects 'z' prefix for base58btc).
 * @param string The multibase string
 * @return Decoded data, or nil if invalid or wrong prefix
 */
+ (nullable NSData *)decodeMultibase:(NSString *)string;

@end

NS_ASSUME_NONNULL_END

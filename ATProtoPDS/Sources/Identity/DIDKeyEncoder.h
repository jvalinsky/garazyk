#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const DIDKeyErrorDomain;

typedef NS_ENUM(NSInteger, DIDKeyEncoderErrorCode) {
    DIDKeyEncoderErrorInvalidFormat = 1,
    DIDKeyEncoderErrorUnsupportedKeyType = 3,
    DIDKeyEncoderErrorInvalidKey = 10,
    DIDKeyEncoderErrorEncodingFailed = 11,
};

typedef NS_ENUM(NSUInteger, DIDKeyType) {
    DIDKeyTypeSecp256k1 = 0xE7,      // secp256k1 compressed public key
    DIDKeyTypeP256 = 0x1200,         // P-256 (secp256r1) compressed public key
    DIDKeyTypeEd25519 = 0xED,        // Ed25519 public key
};

/**
 * Encodes and decodes did:key identifiers.
 * 
 * did:key format: did:key:<multibase(multicodec-prefix + raw-key)>
 * For secp256k1: multicodec 0xe7, compressed 33-byte public key
 * For P-256: multicodec 0x1200 (varint: 0x80 0x24), compressed 33-byte public key
 */
@interface DIDKeyEncoder : NSObject

/**
 * Encode a compressed public key as a did:key identifier.
 * @param compressedPublicKey The compressed public key (33 bytes for secp256k1/P-256)
 * @param keyType The key type (curve)
 * @param error Error output
 * @return The did:key identifier, or nil on error
 */
+ (nullable NSString *)encodeDIDKeyFromCompressedPublicKey:(NSData *)compressedPublicKey
                                                   keyType:(DIDKeyType)keyType
                                                     error:(NSError **)error;

/**
 * Decode a did:key identifier to extract the public key.
 * @param didKey The did:key identifier
 * @param outKeyType If non-null, receives the key type
 * @param error Error output
 * @return The compressed public key, or nil on error
 */
+ (nullable NSData *)decodePublicKeyFromDIDKey:(NSString *)didKey
                                       keyType:(nullable DIDKeyType *)outKeyType
                                         error:(NSError **)error;

/**
 * Encode an uncompressed secp256k1 public key (65 bytes) as did:key.
 * Will compress the key automatically.
 * @param uncompressedPublicKey The uncompressed public key (65 bytes)
 * @param error Error output
 * @return The did:key identifier, or nil on error
 */
+ (nullable NSString *)encodeDIDKeyFromUncompressedSecp256k1:(NSData *)uncompressedPublicKey
                                                       error:(NSError **)error;

/**
 * Check if a string is a valid did:key identifier.
 */
+ (BOOL)isValidDIDKey:(NSString *)didKey;

@end

NS_ASSUME_NONNULL_END

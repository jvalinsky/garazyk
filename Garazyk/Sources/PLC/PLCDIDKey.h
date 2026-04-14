/*!
 @file PLCDIDKey.h

 @abstract DID key parsing and validation for PLC operations.

 @discussion Provides parsing and validation for did:key formatted keys used
 in PLC rotation key operations. Supports secp256k1 and P-256 key types.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @enum PLCDIDKeyType

 @abstract Key types supported for DID keys in PLC operations.

 @constant PLCDIDKeyTypeSecp256k1 secp256k1 elliptic curve key.
 @constant PLCDIDKeyTypeP256 NIST P-256 elliptic curve key.
 */
typedef NS_ENUM(NSUInteger, PLCDIDKeyType) {
    PLCDIDKeyTypeSecp256k1 = 0,
    PLCDIDKeyTypeP256 = 1,
};

/*!
 @class PLCDIDKey

 @abstract Represents a parsed DID key with its type and public key bytes.

 @discussion
    Parses did:key strings to extract the key type and raw public key bytes.
    Used for validating rotation keys in PLC operations.
 */
@interface PLCDIDKey : NSObject

/*! The key type (secp256k1 or P-256). */
@property (nonatomic, readonly) PLCDIDKeyType type;

/*! The raw public key bytes. */
@property (nonatomic, readonly) NSData *publicKeyBytes;

/*!
 @method parseFromString:error:

 @abstract Parses a did:key string into a PLCDIDKey object.

 @param didKey The did:key string to parse.
 @param error On failure, set to an error describing the parse failure.
 @return A PLCDIDKey instance, or nil if parsing failed.
 */
+ (nullable instancetype)parseFromString:(NSString *)didKey error:(NSError **)error;

/*!
 @method isValidDidKeyString:error:

 @abstract Validates a did:key string without creating an object.

 @param didKey The did:key string to validate.
 @param error On failure, set to an error describing why validation failed.
 @return YES if the string is a valid did:key, NO otherwise.
 */
+ (BOOL)isValidDidKeyString:(NSString *)didKey error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

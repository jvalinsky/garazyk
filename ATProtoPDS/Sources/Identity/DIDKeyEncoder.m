#import "Identity/DIDKeyEncoder.h"
#import "Identity/Base58.h"
#import "Auth/Secp256k1.h"

NSErrorDomain const DIDKeyErrorDomain = @"com.atproto.didkey";

@implementation DIDKeyEncoder

+ (nullable NSString *)encodeDIDKeyFromCompressedPublicKey:(NSData *)compressedPublicKey
                                                   keyType:(DIDKeyType)keyType
                                                     error:(NSError **)error {
    // Validate key length
    NSUInteger expectedLength;
    switch (keyType) {
        case DIDKeyTypeSecp256k1:
        case DIDKeyTypeP256:
            expectedLength = 33;
            break;
        case DIDKeyTypeEd25519:
            expectedLength = 32;
            break;
        default:
            if (error) {
                *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                             code:DIDKeyErrorUnsupportedKeyType
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported key type"}];
            }
            return nil;
    }
    
    if (compressedPublicKey.length != expectedLength) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidKey
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         [NSString stringWithFormat:@"Invalid key length: expected %lu, got %lu",
                                          (unsigned long)expectedLength, (unsigned long)compressedPublicKey.length]}];
        }
        return nil;
    }
    
    // Build multicodec-prefixed key
    NSMutableData *prefixedKey = [NSMutableData data];
    
    // Encode multicodec as unsigned varint
    NSUInteger codec = keyType;
    if (codec < 0x80) {
        uint8_t byte = (uint8_t)codec;
        [prefixedKey appendBytes:&byte length:1];
    } else if (codec < 0x4000) {
        // 2-byte varint
        uint8_t bytes[2];
        bytes[0] = (codec & 0x7F) | 0x80;
        bytes[1] = (codec >> 7) & 0x7F;
        [prefixedKey appendBytes:bytes length:2];
    } else {
        // 3-byte varint (for larger codecs)
        uint8_t bytes[3];
        bytes[0] = (codec & 0x7F) | 0x80;
        bytes[1] = ((codec >> 7) & 0x7F) | 0x80;
        bytes[2] = (codec >> 14) & 0x7F;
        [prefixedKey appendBytes:bytes length:3];
    }
    
    [prefixedKey appendData:compressedPublicKey];
    
    // Encode as multibase base58btc
    NSString *multibase = [Base58 encodeMultibase:prefixedKey];
    
    return [NSString stringWithFormat:@"did:key:%@", multibase];
}

+ (nullable NSData *)decodePublicKeyFromDIDKey:(NSString *)didKey
                                       keyType:(nullable DIDKeyType *)outKeyType
                                         error:(NSError **)error {
    // Validate prefix
    if (![didKey hasPrefix:@"did:key:z"]) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:key format"}];
        }
        return nil;
    }
    
    // Extract multibase part (after "did:key:")
    NSString *multibase = [didKey substringFromIndex:8];
    NSData *decoded = [Base58 decodeMultibase:multibase];
    
    if (!decoded || decoded.length < 2) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode multibase"}];
        }
        return nil;
    }
    
    // Decode multicodec varint
    const uint8_t *bytes = decoded.bytes;
    NSUInteger offset = 0;
    NSUInteger codec = 0;
    NSUInteger shift = 0;
    
    while (offset < decoded.length) {
        uint8_t byte = bytes[offset++];
        codec |= ((NSUInteger)(byte & 0x7F)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
        if (shift > 21) { // Sanity check
            if (error) {
                *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                             code:DIDKeyErrorInvalidFormat
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid varint in multicodec"}];
            }
            return nil;
        }
    }
    
    // Validate codec
    DIDKeyType keyType;
    NSUInteger expectedKeyLength;
    
    switch (codec) {
        case DIDKeyTypeSecp256k1:
            keyType = DIDKeyTypeSecp256k1;
            expectedKeyLength = 33;
            break;
        case DIDKeyTypeP256:
            keyType = DIDKeyTypeP256;
            expectedKeyLength = 33;
            break;
        case DIDKeyTypeEd25519:
            keyType = DIDKeyTypeEd25519;
            expectedKeyLength = 32;
            break;
        default:
            if (error) {
                *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                             code:DIDKeyErrorUnsupportedKeyType
                                         userInfo:@{NSLocalizedDescriptionKey: 
                                             [NSString stringWithFormat:@"Unsupported multicodec: 0x%lx", (unsigned long)codec]}];
            }
            return nil;
    }
    
    // Extract key data
    NSUInteger keyLength = decoded.length - offset;
    if (keyLength != expectedKeyLength) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidKey
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         [NSString stringWithFormat:@"Invalid key length: expected %lu, got %lu",
                                          (unsigned long)expectedKeyLength, (unsigned long)keyLength]}];
        }
        return nil;
    }
    
    if (outKeyType) {
        *outKeyType = keyType;
    }
    
    return [decoded subdataWithRange:NSMakeRange(offset, keyLength)];
}

+ (nullable NSString *)encodeDIDKeyFromUncompressedSecp256k1:(NSData *)uncompressedPublicKey
                                                       error:(NSError **)error {
    if (uncompressedPublicKey.length != 65) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Uncompressed secp256k1 key must be 65 bytes"}];
        }
        return nil;
    }
    
    const uint8_t *bytes = uncompressedPublicKey.bytes;
    if (bytes[0] != 0x04) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid uncompressed key format"}];
        }
        return nil;
    }
    
    // Compress the key: prefix byte (0x02 or 0x03) + X coordinate
    // Prefix is 0x02 if Y is even, 0x03 if Y is odd
    uint8_t compressed[33];
    compressed[0] = (bytes[64] & 1) ? 0x03 : 0x02; // Y's last byte determines parity
    memcpy(compressed + 1, bytes + 1, 32); // Copy X coordinate
    
    NSData *compressedKey = [NSData dataWithBytes:compressed length:33];
    return [self encodeDIDKeyFromCompressedPublicKey:compressedKey
                                             keyType:DIDKeyTypeSecp256k1
                                               error:error];
}

+ (BOOL)isValidDIDKey:(NSString *)didKey {
    NSError *error;
    NSData *key = [self decodePublicKeyFromDIDKey:didKey keyType:nil error:&error];
    return key != nil;
}

@end

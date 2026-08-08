// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Core/ATProtoMultibase.h"

#import "Auth/Crypto/JWT.h"
#import "Core/CID.h"
#import "Core/DID.h"

@implementation ATProtoMultibase

+ (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase
                                           error:(NSError **)error {
    if (multibase.length < 2) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                         code:DIDErrorInvalidDocument
                                     userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             @"Invalid publicKeyMultibase value"
                                     }];
        }
        return nil;
    }

    unichar prefix = [multibase characterAtIndex:0];
    NSString *payload = [multibase substringFromIndex:1];
    NSData *data = nil;
    switch (prefix) {
        case 'z':
        case 'Z':
            data = [ATProtoCID base58btcDecode:payload];
            break;
        case 'b':
            data = [ATProtoCID base32Decode:payload];
            break;
        case 'u':
            data = [ATProtoJWT base64URLDecode:payload error:error];
            break;
        default:
            if (error) {
                *error = [NSError errorWithDomain:DIDErrorDomain
                                             code:DIDErrorInvalidDocument
                                         userInfo:@{
                                             NSLocalizedDescriptionKey :
                                                 @"Unsupported multibase encoding for signing key"
                                         }];
            }
            return nil;
    }

    if (!data) {
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    if (data.length > 2 && bytes[0] == 0xE7 && bytes[1] == 0x01) {
        return [data subdataWithRange:NSMakeRange(2, data.length - 2)];
    }
    return data;
}

+ (nullable NSData *)secp256k1PublicKeyBytesFromMultibase:(NSString *)multibase
                                                     error:(NSError **)error {
    if (![multibase hasPrefix:@"z"]) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                         code:DIDErrorInvalidDocument
                                     userInfo:@{NSLocalizedDescriptionKey: @"Repository signing key must use base58btc multibase"}];
        }
        return nil;
    }

    NSData *decoded = [ATProtoCID base58btcDecode:[multibase substringFromIndex:1]];
    const uint8_t *bytes = decoded.bytes;
    if (decoded.length != 35 || bytes[0] != 0xe7 || bytes[1] != 0x01) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                         code:DIDErrorInvalidDocument
                                     userInfo:@{NSLocalizedDescriptionKey: @"Repository signing key is not a secp256k1 public key"}];
        }
        return nil;
    }
    return [decoded subdataWithRange:NSMakeRange(2, 33)];
}

@end

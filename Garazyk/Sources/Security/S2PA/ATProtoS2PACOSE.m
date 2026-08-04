// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PACOSE.m

 @abstract Strict COSE_Sign1 ES256K implementation for S2PA.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import "Security/S2PA/ATProtoS2PACOSE.h"
#import "Core/CBOR.h"
#import <CommonCrypto/CommonDigest.h>
#include <stdint.h>
#include <string.h>

NSString * const ATProtoS2PAErrorDomain = @"com.atproto.s2pa";

static const NSInteger kS2PAAlgorithmES256K = -47;
static const NSUInteger kS2PASignatureLength = 64;

static NSError *S2PAError(ATProtoS2PAErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoS2PAErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void S2PASetError(NSError **error, ATProtoS2PAErrorCode code, NSString *message) {
    if (error) *error = S2PAError(code, message);
}

static ATProtoCBORValue *S2PAUnsigned(uint64_t value) {
    return [ATProtoCBORValue unsignedInteger:(NSUInteger)value];
}

static ATProtoCBORValue *S2PANegative(NSInteger value) {
    return [ATProtoCBORValue negativeInteger:value];
}

static NSData *S2PAEncodeValue(ATProtoCBORValue *value) {
    return [value encode];
}

static ATProtoCBORValue *S2PAProtectedHeaderValue(void) {
    // COSE protected headers are a CBOR map with integer key 1 (alg) and
    // negative integer value -47 (ES256K). ATProtoCBORValue is used instead of
    // ATProtoDagCBOR because COSE maps intentionally permit integer keys.
    ATProtoCBORValue *key = S2PAUnsigned(1);
    ATProtoCBORValue *algorithm = S2PANegative(kS2PAAlgorithmES256K);
    return [ATProtoCBORValue map:@{key: algorithm}];
}

static BOOL S2PAIsCanonicalProtectedHeaders(NSData *data) {
    NSData *expected = S2PAEncodeValue(S2PAProtectedHeaderValue());
    return [data isEqualToData:expected];
}

static BOOL S2PAExtractEnvelope(NSData *envelope,
                                NSData **protectedHeaders,
                                NSData **payload,
                                NSData **signature,
                                NSError **error) {
    if (![envelope isKindOfClass:[NSData class]] || envelope.length == 0) {
        S2PASetError(error, ATProtoS2PAErrorInvalidInput, @"COSE envelope must not be empty");
        return NO;
    }

    NSUInteger offset = 0;
    ATProtoCBORValue *root = [ATProtoCBORDecoder decode:envelope offset:&offset];
    if (!root || offset != envelope.length || root.type != CBORTypeArray || root.array.count != 4) {
        S2PASetError(error, ATProtoS2PAErrorInvalidEnvelope,
                     @"COSE_Sign1 must be exactly one four-element CBOR array");
        return NO;
    }
    // Generic ATProtoCBORDecoder is intentionally lenient. Re-encoding the parsed
    // value and comparing bytes rejects non-minimal lengths, duplicate map keys,
    // and other alternate spellings before any signature is trusted.
    if (![root.encode isEqualToData:envelope]) {
        S2PASetError(error, ATProtoS2PAErrorNonCanonicalEncoding,
                     @"COSE_Sign1 must use one canonical CBOR encoding");
        return NO;
    }

    ATProtoCBORValue *protectedValue = root.array[0];
    ATProtoCBORValue *unprotectedValue = root.array[1];
    ATProtoCBORValue *payloadValue = root.array[2];
    ATProtoCBORValue *signatureValue = root.array[3];
    if (protectedValue.type != CBORTypeByteString ||
        unprotectedValue.type != CBORTypeMap || unprotectedValue.map.count != 0 ||
        payloadValue.type != CBORTypeByteString ||
        signatureValue.type != CBORTypeByteString ||
        signatureValue.byteString.length != kS2PASignatureLength) {
        S2PASetError(error, ATProtoS2PAErrorInvalidEnvelope,
                     @"COSE_Sign1 has an invalid protected, unprotected, payload, or signature field");
        return NO;
    }

    if (!S2PAIsCanonicalProtectedHeaders(protectedValue.byteString)) {
        S2PASetError(error, ATProtoS2PAErrorUnsupportedAlgorithm,
                     @"COSE protected headers must be exactly canonical ES256K ({1: -47})");
        return NO;
    }

    if (protectedHeaders) *protectedHeaders = protectedValue.byteString;
    if (payload) *payload = payloadValue.byteString;
    if (signature) *signature = signatureValue.byteString;
    return YES;
}

@implementation ATProtoS2PACOSE

+ (NSData *)canonicalProtectedHeaders {
    return S2PAEncodeValue(S2PAProtectedHeaderValue());
}

+ (nullable NSData *)sigStructureForPayload:(NSData *)payload
                                      error:(NSError **)error {
    if (![payload isKindOfClass:[NSData class]]) {
        S2PASetError(error, ATProtoS2PAErrorInvalidInput, @"S2PA payload must be NSData");
        return nil;
    }

    ATProtoCBORValue *structure = [ATProtoCBORValue array:@[
        [ATProtoCBORValue textString:@"Signature1"],
        [ATProtoCBORValue byteString:[self canonicalProtectedHeaders]],
        [ATProtoCBORValue byteString:[NSData data]],
        [ATProtoCBORValue byteString:payload]
    ]];
    return S2PAEncodeValue(structure);
}

+ (nullable NSData *)signPayload:(NSData *)payload
                    withKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                           error:(NSError **)error {
    if (![keyPair isKindOfClass:[ATProtoSecp256k1KeyPair class]]) {
        S2PASetError(error, ATProtoS2PAErrorInvalidInput, @"S2PA signing requires a secp256k1 key pair");
        return nil;
    }

    NSError *structureError = nil;
    NSData *structure = [self sigStructureForPayload:payload error:&structureError];
    if (!structure) {
        if (error) *error = structureError;
        return nil;
    }

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(structure.bytes, (CC_LONG)structure.length, digest);
    NSData *hash = [NSData dataWithBytes:digest length:sizeof(digest)];
    NSError *signError = nil;
    NSData *signature = [keyPair signHash:hash error:&signError];
    if (!signature || signature.length != kS2PASignatureLength) {
        if (error) {
            *error = signError ?: S2PAError(ATProtoS2PAErrorInvalidSignature,
                                             @"secp256k1 did not produce a 64-byte signature");
        }
        return nil;
    }

    ATProtoCBORValue *envelope = [ATProtoCBORValue array:@[
        [ATProtoCBORValue byteString:[self canonicalProtectedHeaders]],
        [ATProtoCBORValue map:@{}],
        [ATProtoCBORValue byteString:payload],
        [ATProtoCBORValue byteString:signature]
    ]];
    return S2PAEncodeValue(envelope);
}

+ (nullable NSData *)payloadFromEnvelope:(NSData *)envelope
                                   error:(NSError **)error {
    NSData *payload = nil;
    if (!S2PAExtractEnvelope(envelope, NULL, &payload, NULL, error)) {
        return nil;
    }
    return payload;
}

+ (BOOL)verifyEnvelope:(NSData *)envelope
         withPublicKey:(NSData *)publicKey
                 error:(NSError **)error {
    if (![publicKey isKindOfClass:[NSData class]] ||
        (publicKey.length != 33 && publicKey.length != 65)) {
        S2PASetError(error, ATProtoS2PAErrorInvalidInput,
                     @"S2PA public key must be a 33- or 65-byte secp256k1 key");
        return NO;
    }

    NSData *protectedHeaders = nil;
    NSData *payload = nil;
    NSData *signature = nil;
    if (!S2PAExtractEnvelope(envelope, &protectedHeaders, &payload, &signature, error)) {
        return NO;
    }

    NSError *structureError = nil;
    NSData *structure = [self sigStructureForPayload:payload error:&structureError];
    if (!structure) {
        if (error) *error = structureError;
        return NO;
    }

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(structure.bytes, (CC_LONG)structure.length, digest);
    NSData *hash = [NSData dataWithBytes:digest length:sizeof(digest)];
    NSError *verifyError = nil;
    BOOL valid = [[Secp256k1 shared] verifySignature:signature
                                             forHash:hash
                                       withPublicKey:publicKey
                                               error:&verifyError];
    if (!valid && error) {
        *error = S2PAError(ATProtoS2PAErrorVerificationFailed,
                           verifyError.localizedDescription ?: @"S2PA signature verification failed");
    }
    return valid;
}

@end

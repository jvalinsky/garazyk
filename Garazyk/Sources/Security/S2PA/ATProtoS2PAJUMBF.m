// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Security/S2PA/ATProtoS2PACOSE.h"
#import "Security/S2PA/ATProtoS2PALeafCertificate.h"
#include <string.h>

NSString * const ATProtoS2PAJUMBFErrorDomain = @"com.atproto.s2pa.jumbf";

// C2PA Manifest Store type UUID "c2pa" (0x63327061-0011-0010-8000-00AA00389B71)
static const uint8_t kC2PAStoreType[16] = {
    0x63, 0x32, 0x70, 0x61, 0x00, 0x11, 0x00, 0x10,
    0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
};
// Claim Signature type "c2cs"
static const uint8_t kC2PASignatureType[16] = {
    0x63, 0x32, 0x63, 0x73, 0x00, 0x11, 0x00, 0x10,
    0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
};
// Credentials type "c2cr"
static const uint8_t kC2PACredentialType[16] = {
    0x63, 0x32, 0x63, 0x72, 0x00, 0x11, 0x00, 0x10,
    0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
};
// CBOR content type "cbor"
static const uint8_t kJUMBFCBORType[16] = {
    0x63, 0x62, 0x6F, 0x72, 0x00, 0x11, 0x00, 0x10,
    0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
};
// Embedded file content type markers used as opaque content boxes.
static const char kSigContentType[4] = {'b', 'i', 'd', 'b'};
static const char kCertContentType[4] = {'b', 'i', 'd', 'b'};

static NSError *S2PAJUMBFError(ATProtoS2PAJUMBFErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoS2PAJUMBFErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void S2PAJUMBFSetError(NSError **error, ATProtoS2PAJUMBFErrorCode code,
                              NSString *message) {
    if (error) *error = S2PAJUMBFError(code, message);
}

static void S2PAAppendUInt32BE(uint32_t value, NSMutableData *data) {
    uint8_t bytes[4] = {
        (uint8_t)(value >> 24), (uint8_t)(value >> 16),
        (uint8_t)(value >> 8), (uint8_t)value
    };
    [data appendBytes:bytes length:4];
}

static uint32_t S2PAReadUInt32BE(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | bytes[3];
}

static NSData *S2PAWriteBox(const char *type, NSData *body) {
    NSMutableData *box = [NSMutableData dataWithCapacity:8 + body.length];
    S2PAAppendUInt32BE((uint32_t)(8 + body.length), box);
    [box appendBytes:type length:4];
    [box appendData:body];
    return box;
}

/** jumd: TYPE(16) + TOGGLES(1) + LABEL (NUL-terminated) when requestable. */
static NSData *S2PAWriteJUMD(const uint8_t type[16], NSString *label) {
    NSMutableData *body = [NSMutableData data];
    [body appendBytes:type length:16];
    uint8_t toggles = 0x03; // requestable | label present
    [body appendBytes:&toggles length:1];
    NSData *labelUTF8 = [label dataUsingEncoding:NSUTF8StringEncoding];
    [body appendData:labelUTF8];
    uint8_t nul = 0;
    [body appendBytes:&nul length:1];
    return S2PAWriteBox("jumd", body);
}

static NSData *S2PAWriteJUMB(NSData *jumd, NSArray<NSData *> *children) {
    NSMutableData *body = [jumd mutableCopy];
    for (NSData *child in children) {
        [body appendData:child];
    }
    return S2PAWriteBox("jumb", body);
}

static NSData *S2PAWriteOpaqueContent(const char type[4], NSData *payload) {
    return S2PAWriteBox(type, payload);
}

@implementation ATProtoS2PAJUMBF

+ (NSData *)c2paBMFFUUID {
    static const uint8_t uuid[16] = {
        0xd8, 0xfe, 0xc3, 0xd6, 0x1b, 0x0e, 0x48, 0x3c,
        0x92, 0x97, 0x58, 0x28, 0x87, 0x7e, 0xc4, 0x81
    };
    return [NSData dataWithBytes:uuid length:16];
}

+ (nullable NSData *)manifestStoreWithSignature:(NSData *)signature
                                   certificate:(NSData *)certificate
                                         error:(NSError **)error {
    if (![signature isKindOfClass:[NSData class]] || signature.length == 0 ||
        ![certificate isKindOfClass:[NSData class]] || certificate.length == 0) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidArgument,
                          @"S2PA JUMBF requires non-empty signature and certificate");
        return nil;
    }

    NSData *sigContent = S2PAWriteOpaqueContent(kSigContentType, signature);
    NSData *sigSuper = S2PAWriteJUMB(S2PAWriteJUMD(kC2PASignatureType, @"c2pa.signature"),
                                     @[sigContent]);

    NSData *certContent = S2PAWriteOpaqueContent(kCertContentType, certificate);
    NSData *credSuper = S2PAWriteJUMB(S2PAWriteJUMD(kC2PACredentialType, @"c2pa.credentials"),
                                      @[certContent]);

    // Active manifest: signature + credentials only (no claim/assertions yet).
    NSData *manifest = S2PAWriteJUMB(S2PAWriteJUMD(kC2PAStoreType, @"c2pa"),
                                     @[sigSuper, credSuper]);
    NSData *store = S2PAWriteJUMB(S2PAWriteJUMD(kC2PAStoreType, @"c2pa"),
                                  @[manifest]);
    (void)kJUMBFCBORType;
    return store;
}

+ (nullable NSData *)bmffUUIDBoxWithManifestStore:(NSData *)store
                                            error:(NSError **)error {
    if (![store isKindOfClass:[NSData class]] || store.length < 8) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidArgument,
                          @"S2PA JUMBF store is required");
        return nil;
    }
    if (store.length > (NSUInteger)UINT32_MAX - 24U) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidArgument,
                          @"S2PA JUMBF store exceeds BMFF size");
        return nil;
    }
    NSMutableData *box = [NSMutableData dataWithCapacity:24 + store.length];
    S2PAAppendUInt32BE((uint32_t)(24 + store.length), box);
    [box appendBytes:"uuid" length:4];
    [box appendData:[self c2paBMFFUUID]];
    [box appendData:store];
    return box;
}

+ (nullable NSData *)manifestStoreFromBMFFUUIDBox:(NSData *)box
                                            error:(NSError **)error {
    if (![box isKindOfClass:[NSData class]] || box.length < 24) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidStructure,
                          @"S2PA BMFF uuid box is truncated");
        return nil;
    }
    const uint8_t *bytes = box.bytes;
    uint32_t size = S2PAReadUInt32BE(bytes);
    if (size != box.length || memcmp(bytes + 4, "uuid", 4) != 0 ||
        memcmp(bytes + 8, [self c2paBMFFUUID].bytes, 16) != 0) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidStructure,
                          @"Not an exact C2PA BMFF uuid box");
        return nil;
    }
    return [box subdataWithRange:NSMakeRange(24, box.length - 24)];
}

/** Depth-first collect of every `bidb` payload under nested `jumb` boxes. */
static BOOL S2PACollectBidbPayloads(const uint8_t *bytes, NSUInteger length,
                                    NSMutableArray<NSData *> *out,
                                    NSError **error) {
    NSUInteger offset = 0;
    while (offset + 8 <= length) {
        uint32_t size = S2PAReadUInt32BE(bytes + offset);
        if (size < 8 || offset + size > length) {
            S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidStructure,
                              @"S2PA JUMBF has an invalid box size");
            return NO;
        }
        const uint8_t *type = bytes + offset + 4;
        if (memcmp(type, "bidb", 4) == 0) {
            [out addObject:[NSData dataWithBytes:bytes + offset + 8 length:size - 8]];
        } else if (memcmp(type, "jumb", 4) == 0) {
            // Superbox body is jumd + nested boxes; recurse over the body.
            if (!S2PACollectBidbPayloads(bytes + offset + 8, size - 8, out, error)) {
                return NO;
            }
        }
        offset += size;
    }
    if (offset != length) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidStructure,
                          @"S2PA JUMBF has trailing bytes inside a box");
        return NO;
    }
    return YES;
}

+ (BOOL)extractSignature:(NSData * _Nullable * _Nonnull)outSignature
            certificate:(NSData * _Nullable * _Nonnull)outCertificate
      fromManifestStore:(NSData *)store
                  error:(NSError **)error {
    if (outSignature) *outSignature = nil;
    if (outCertificate) *outCertificate = nil;
    if (![store isKindOfClass:[NSData class]] || store.length < 8) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidStructure,
                          @"S2PA JUMBF store is truncated");
        return NO;
    }

    NSMutableArray<NSData *> *bidbPayloads = [NSMutableArray array];
    if (!S2PACollectBidbPayloads(store.bytes, store.length, bidbPayloads, error)) {
        return NO;
    }
    if (bidbPayloads.count < 2) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidStructure,
                          @"S2PA JUMBF store missing signature/certificate content");
        return NO;
    }
    // Deterministic layout: first bidb = signature, second = certificate.
    if (outSignature) *outSignature = bidbPayloads[0];
    if (outCertificate) *outCertificate = bidbPayloads[1];
    return YES;
}

+ (nullable NSData *)uuidBoxSigningPayload:(NSData *)payload
                              withKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                      did:(nullable NSString *)did
                                notBefore:(NSDate *)notBefore
                                 notAfter:(NSDate *)notAfter
                                    error:(NSError **)error {
    NSData *cose = [ATProtoS2PACOSE signPayload:payload withKeyPair:keyPair error:error];
    if (!cose) return nil;
    NSData *leaf = [ATProtoS2PALeafCertificate certificateWithKeyPair:keyPair
                                                                  did:did
                                                            notBefore:notBefore
                                                             notAfter:notAfter
                                                                error:error];
    if (!leaf) return nil;
    NSData *store = [self manifestStoreWithSignature:cose certificate:leaf error:error];
    if (!store) return nil;
    return [self bmffUUIDBoxWithManifestStore:store error:error];
}

+ (BOOL)verifyUUIDBox:(NSData *)box
       expectedPayload:(NSData *)payload
           expectedDID:(nullable NSString *)expectedDID
                 error:(NSError **)error {
    NSData *store = [self manifestStoreFromBMFFUUIDBox:box error:error];
    if (!store) return NO;
    NSData *signature = nil;
    NSData *certificate = nil;
    if (![self extractSignature:&signature certificate:&certificate
              fromManifestStore:store error:error]) {
        return NO;
    }
    if (![ATProtoS2PALeafCertificate verifyCertificate:certificate
                                           expectedDID:expectedDID
                                                 error:error]) {
        return NO;
    }
    // Verify COSE against the same key used to mint the leaf by extracting
    // payload and checking signature with the leaf's SPKI via COSE verify
    // using the keypair public material from the certificate path:
    // COSE verify needs public key bytes — re-verify envelope against
    // expected payload equality after structural checks.
    NSData *attached = [ATProtoS2PACOSE payloadFromEnvelope:signature error:error];
    if (![attached isEqual:payload]) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorVerificationFailed,
                          @"S2PA JUMBF COSE payload mismatch");
        return NO;
    }
    // Extract uncompressed public key from leaf via re-mint check is heavy;
    // use COSE verify with key recovered by verifying leaf self-sig already done.
    // Parse SPKI from certificate: scan for 0x04 || 64-byte key pattern after secp256k1 OID.
    NSData *publicKey = nil;
    const uint8_t *cbytes = certificate.bytes;
    static const uint8_t kSecp256k1[] = {0x2B, 0x81, 0x04, 0x00, 0x0A};
    for (NSUInteger i = 0; i + sizeof(kSecp256k1) + 2 + 65 < certificate.length; i++) {
        if (memcmp(cbytes + i, kSecp256k1, sizeof(kSecp256k1)) == 0) {
            // Look ahead for BIT STRING of uncompressed key.
            for (NSUInteger j = i + sizeof(kSecp256k1); j + 67 < certificate.length; j++) {
                if (cbytes[j] == 0x03 && cbytes[j + 1] == 0x42 && cbytes[j + 2] == 0x00 &&
                    cbytes[j + 3] == 0x04) {
                    publicKey = [NSData dataWithBytes:cbytes + j + 3 length:65];
                    break;
                }
            }
            break;
        }
    }
    if (!publicKey) {
        S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorVerificationFailed,
                          @"S2PA JUMBF could not recover leaf public key");
        return NO;
    }
    if (![ATProtoS2PACOSE verifyEnvelope:signature withPublicKey:publicKey error:error]) {
        if (error && !*error) {
            S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorVerificationFailed,
                              @"S2PA JUMBF COSE verification failed");
        }
        return NO;
    }
    return YES;
}

+ (nullable NSData *)presentationWithUUIDBox:(NSData *)uuidBox
                                   mediaData:(NSData *)mediaData
                                       error:(NSError **)error {
    if (![uuidBox isKindOfClass:[NSData class]] ||
        ![self manifestStoreFromBMFFUUIDBox:uuidBox error:error] ||
        ![mediaData isKindOfClass:[NSData class]] || mediaData.length == 0) {
        if (error && !*error) {
            S2PAJUMBFSetError(error, ATProtoS2PAJUMBFErrorInvalidArgument,
                              @"S2PA presentation requires uuid box and media bytes");
        }
        return nil;
    }
    NSMutableData *out = [uuidBox mutableCopy];
    [out appendData:mediaData];
    return out;
}

@end

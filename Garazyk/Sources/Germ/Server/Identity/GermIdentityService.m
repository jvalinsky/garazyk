// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "GermIdentityService.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import <Security/Security.h>
#import <dlfcn.h>

// ed25519 key type constant — available at runtime on macOS 12+
// but not declared in public headers. Resolve via dlsym.
static CFStringRef _kSecAttrKeyTypeEd25519 = nil;
static SecKeyAlgorithm _kSecKeyAlgorithmEd25519Signature = nil;

static void GermInitEd25519Constants(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Resolve key type from Security framework
        void *handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
        if (handle) {
            CFStringRef *keyTypePtr = dlsym(handle, "kSecAttrKeyTypeEd25519");
            if (keyTypePtr) _kSecAttrKeyTypeEd25519 = *keyTypePtr;

            SecKeyAlgorithm *algoPtr = dlsym(handle, "kSecKeyAlgorithmEd25519Signature");
            if (algoPtr) _kSecKeyAlgorithmEd25519Signature = *algoPtr;
        }

        // Fallback: construct the algorithm string if dlsym failed.
        // SecKeyAlgorithm values are CFString constants with known
        // formats. The ed25519 signature algorithm is:
        // "ecdsaSignatureMessageEd25519" (pure ed25519, no prehash)
        if (!_kSecAttrKeyTypeEd25519) {
            _kSecAttrKeyTypeEd25519 = CFSTR("ed25519");
        }
        if (!_kSecKeyAlgorithmEd25519Signature) {
            _kSecKeyAlgorithmEd25519Signature = CFSTR("ecdsaSignatureMessageEd25519");
        }
    });
}

const uint8_t kGermAlgorithmCurve25519Signing = 0x03;

// TypedKeyMaterial: 1 byte algorithm prefix + 32 bytes key data
static const NSInteger kTypedKeyMaterialSize = 33;

// TypedSignature: 1 byte algorithm prefix + 64 bytes signature = 65 bytes
static const NSInteger kTypedSignatureSize = 65;

// Each succession proof = TypedKeyMaterial + TypedSignature = 98 bytes
static const NSInteger kSuccessionProofSize = 33 + 65;

// AnchorSuccession discriminator (from AC Protocol spec)
static NSString *const kAnchorSuccessionDiscriminator = @"AnchorSuccession";

@interface GermIdentityService ()
@property (nonatomic, unsafe_unretained) id<PDSQueryDatabase> database;
@end

@implementation GermIdentityService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

#pragma mark - Declaration Verification

- (BOOL)verifyDeclaration:(NSData *)anchorKeyWireFormat
                      did:(NSString *)did
                    error:(NSError **)error {
    if (!anchorKeyWireFormat || anchorKeyWireFormat.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Anchor key wire format is required"}];
        }
        return NO;
    }

    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return NO;
    }

    // Parse TypedKeyMaterial: 1-byte algorithm prefix + key data
    if (anchorKeyWireFormat.length < 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Anchor key too short"}];
        }
        return NO;
    }

    const uint8_t *bytes = (const uint8_t *)anchorKeyWireFormat.bytes;
    uint8_t algorithm = bytes[0];

    if (algorithm != kGermAlgorithmCurve25519Signing) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Unsupported algorithm: 0x%02x (only ed25519 supported)", algorithm]}];
        }
        return NO;
    }

    // ed25519 public key is 32 bytes
    if (anchorKeyWireFormat.length != kTypedKeyMaterialSize) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Expected %ld bytes for ed25519 key, got %lu",
                                                      (long)kTypedKeyMaterialSize,
                                                      (unsigned long)anchorKeyWireFormat.length]}];
        }
        return NO;
    }

    // Verify the key is a valid ed25519 public key by attempting
    // to create a SecKey from it. On macOS 12+, ed25519 keys are
    // supported via the key type identifier string.
    NSData *keyData = [anchorKeyWireFormat subdataWithRange:NSMakeRange(1, 32)];
    SecKeyRef secKey = [self createEd25519PublicKeyFromData:keyData];
    if (!secKey) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ed25519 public key"}];
        }
        return NO;
    }
    CFRelease(secKey);

    GZ_LOG_DEBUG(@"Verified declaration anchor key for DID");
    return YES;
}

#pragma mark - Succession Verification

- (nullable NSArray<NSData *> *)verifySuccessionProofs:(NSData *)proofsWireFormat
                                           currentKey:(NSData *)currentKeyWireFormat
                                          attestation:(NSData *)attestationWireFormat
                                                error:(NSError **)error {
    if (!proofsWireFormat || proofsWireFormat.length == 0) {
        // No proofs is valid — means this is the first key
        return @[];
    }

    if (!currentKeyWireFormat || !attestationWireFormat) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"Current key and attestation are required"}];
        }
        return nil;
    }

    if (proofsWireFormat.length % kSuccessionProofSize != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Invalid proofs wire format: %lu bytes is not a multiple of %ld",
                                                      (unsigned long)proofsWireFormat.length,
                                                      (long)kSuccessionProofSize]}];
        }
        return nil;
    }

    NSInteger proofCount = proofsWireFormat.length / kSuccessionProofSize;
    NSMutableArray<NSData *> *predecessorKeys = [NSMutableArray arrayWithCapacity:proofCount];

    // Track the current successor key for verification
    NSData *successorKeyData = [currentKeyWireFormat subdataWithRange:NSMakeRange(1, 32)];
    SecKeyRef successorSecKey = [self createEd25519PublicKeyFromData:successorKeyData];
    if (!successorSecKey) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid successor ed25519 public key"}];
        }
        return nil;
    }

    NSData *currentSuccessorWireFormat = currentKeyWireFormat;

    for (NSInteger i = 0; i < proofCount; i++) {
        NSInteger offset = i * kSuccessionProofSize;
        NSData *proofData = [proofsWireFormat subdataWithRange:NSMakeRange(offset, kSuccessionProofSize)];

        // Split into predecessor key and signature
        NSData *predecessorWireFormat = [proofData subdataWithRange:NSMakeRange(0, 33)];
        NSData *signatureWireFormat = [proofData subdataWithRange:NSMakeRange(33, 65)];

        // Verify predecessor key format
        const uint8_t *predBytes = (const uint8_t *)predecessorWireFormat.bytes;
        if (predBytes[0] != kGermAlgorithmCurve25519Signing) {
            CFRelease(successorSecKey);
            if (error) {
                *error = [NSError errorWithDomain:@"GermIdentity"
                                             code:4
                                         userInfo:@{NSLocalizedDescriptionKey: @"Predecessor key must be ed25519"}];
            }
            return nil;
        }

        // Verify signature algorithm
        const uint8_t *sigBytes = (const uint8_t *)signatureWireFormat.bytes;
        if (sigBytes[0] != kGermAlgorithmCurve25519Signing) {
            CFRelease(successorSecKey);
            if (error) {
                *error = [NSError errorWithDomain:@"GermIdentity"
                                             code:9
                                         userInfo:@{NSLocalizedDescriptionKey: @"Signature must be ed25519"}];
            }
            return nil;
        }

        // Build the signature body:
        // AnchorSuccession.signatureBody = (discriminator, attestation, predecessor, successor)
        NSData *sigBody = [self buildSuccessionSignatureBody:attestationWireFormat
                                                 predecessor:predecessorWireFormat
                                                   successor:currentSuccessorWireFormat];

        NSData *signatureData = [signatureWireFormat subdataWithRange:NSMakeRange(1, 64)];
        BOOL valid = [self verifyEd25519Signature:signatureData
                                         forData:sigBody
                                    withPublicKey:successorSecKey];
        if (!valid) {
            CFRelease(successorSecKey);
            if (error) {
                *error = [NSError errorWithDomain:@"GermIdentity"
                                             code:10
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                         [NSString stringWithFormat:@"Succession proof %ld failed verification", (long)i]}];
            }
            return nil;
        }

        [predecessorKeys addObject:predecessorWireFormat];

        // Move to the predecessor for the next proof
        CFRelease(successorSecKey);
        NSData *predecessorKeyData = [predecessorWireFormat subdataWithRange:NSMakeRange(1, 32)];
        successorSecKey = [self createEd25519PublicKeyFromData:predecessorKeyData];
        if (!successorSecKey) {
            if (error) {
                *error = [NSError errorWithDomain:@"GermIdentity"
                                             code:6
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid predecessor ed25519 public key"}];
            }
            return nil;
        }

        currentSuccessorWireFormat = predecessorWireFormat;
    }

    CFRelease(successorSecKey);

    GZ_LOG_DEBUG(@"Verified %ld succession proofs", (long)proofCount);
    return [predecessorKeys copy];
}

#pragma mark - Key Lookup

- (nullable NSData *)getAnchorKeyForDid:(NSString *)did
                                  error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermIdentity"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return nil;
    }

    // Look up the most recent declaration record for this DID.
    // The declaration record is stored at rkey "self" in the
    // com.germnetwork.declaration collection.
    NSString *sql = @"SELECT r.value FROM records r "
                    @"WHERE r.did = ? AND r.collection = 'com.germnetwork.declaration' "
                    @"ORDER BY r.rkey LIMIT 1";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:sql
                                                                     params:@[did]
                                                                      error:error];
    if (!rows || rows.count == 0) {
        return nil;
    }

    NSDictionary *row = rows.firstObject;
    // The value is the full record JSON. Parse out the currentKey field.
    NSData *valueData = row[@"value"];
    if (![valueData isKindOfClass:[NSData class]]) {
        NSString *valueStr = row[@"value"];
        if (![valueStr isKindOfClass:[NSString class]]) return nil;
        valueData = [valueStr dataUsingEncoding:NSUTF8StringEncoding];
    }

    NSError *parseError = nil;
    NSDictionary *record = [NSJSONSerialization JSONObjectWithData:valueData
                                                          options:0
                                                            error:&parseError];
    if (!record) return nil;

    // Extract currentKey — it's a $bytes field
    id currentKey = record[@"currentKey"];
    if (!currentKey) return nil;

    if ([currentKey isKindOfClass:[NSDictionary class]]) {
        NSString *base64 = currentKey[@"$bytes"];
        if (base64) {
            return [self decodeBase64:base64];
        }
    }

    return nil;
}

#pragma mark - Key History

- (nullable NSArray<NSData *> *)getKeyHistoryForDid:(NSString *)did
                                              error:(NSError **)error {
    // For now, return just the current key. Full history tracking
    // requires storing succession events, which is a future
    // enhancement.
    NSData *currentKey = [self getAnchorKeyForDid:did error:error];
    if (!currentKey) return nil;
    return @[currentKey];
}

#pragma mark - Private Helpers

- (nullable SecKeyRef)createEd25519PublicKeyFromData:(NSData *)keyData {
    if (keyData.length != 32) return nil;

    GermInitEd25519Constants();

    // On macOS 12+, ed25519 is supported via SecKeyCreateWithData
    // with the key type string identifier.
    NSDictionary *attrs = @{
        (id)kSecAttrKeyType: (__bridge NSString *)_kSecAttrKeyTypeEd25519,
        (id)kSecAttrKeyClass: (__bridge NSString *)kSecAttrKeyClassPublic,
    };
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)keyData,
                                         (__bridge CFDictionaryRef)attrs,
                                         &error);
    if (error) {
        CFRelease(error);
        return nil;
    }
    return key;
}

- (BOOL)verifyEd25519Signature:(NSData *)signature
                        forData:(NSData *)data
                   withPublicKey:(SecKeyRef)publicKey {
    if (!signature || !data || !publicKey) return NO;

    GermInitEd25519Constants();

    CFErrorRef error = NULL;
    BOOL result = SecKeyVerifySignature(publicKey,
                                        _kSecKeyAlgorithmEd25519Signature,
                                        (__bridge CFDataRef)data,
                                        (__bridge CFDataRef)signature,
                                        &error);
    if (error) {
        CFRelease(error);
        return NO;
    }
    return result;
}

- (nullable NSData *)buildSuccessionSignatureBody:(NSData *)attestation
                                       predecessor:(NSData *)predecessorWireFormat
                                         successor:(NSData *)successorWireFormat {
    // Build the signature body for AnchorSuccession verification.
    // Format: LinearEncodedQuad (discriminator, attestation, predecessor, successor)
    // Each element is encoded as: 4-byte big-endian length + data
    NSData *discriminatorData = [kAnchorSuccessionDiscriminator dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *body = [NSMutableData data];

    // Element 1: discriminator
    uint32_t len1 = CFSwapInt32HostToBig((uint32_t)discriminatorData.length);
    [body appendBytes:&len1 length:4];
    [body appendData:discriminatorData];

    // Element 2: attestation
    uint32_t len2 = CFSwapInt32HostToBig((uint32_t)attestation.length);
    [body appendBytes:&len2 length:4];
    [body appendData:attestation];

    // Element 3: predecessor
    uint32_t len3 = CFSwapInt32HostToBig((uint32_t)predecessorWireFormat.length);
    [body appendBytes:&len3 length:4];
    [body appendData:predecessorWireFormat];

    // Element 4: successor
    uint32_t len4 = CFSwapInt32HostToBig((uint32_t)successorWireFormat.length);
    [body appendBytes:&len4 length:4];
    [body appendData:successorWireFormat];

    return [body copy];
}

- (nullable NSData *)decodeBase64:(NSString *)base64 {
    NSMutableString *standard = [base64 mutableCopy];
    [standard replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, standard.length)];
    [standard replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, standard.length)];
    while (standard.length % 4 != 0) {
        [standard appendString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:standard options:0];
}

@end

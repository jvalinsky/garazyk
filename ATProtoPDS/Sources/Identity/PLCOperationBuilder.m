#import "Identity/PLCOperationBuilder.h"
#import "Identity/DIDKeyEncoder.h"
#import "Auth/Secp256k1.h"
#import "Repository/CBOR.h"
#import "Core/ATProtoBase32.h"
#import <CommonCrypto/CommonDigest.h>

NSErrorDomain const PLCOperationErrorDomain = @"com.atproto.plc.operation";

@interface PLCOperationBuilder ()

@property (nonatomic, strong, readwrite) NSData *rotationPrivateKey;
@property (nonatomic, copy, readwrite) NSString *rotationDIDKey;
@property (nonatomic, strong) Secp256k1KeyPair *rotationKeyPair;

@end

@implementation PLCOperationBuilder

- (nullable instancetype)initWithRotationPrivateKey:(NSData *)rotationPrivateKey
                                              error:(NSError **)error {
    self = [super init];
    if (self) {
        if (rotationPrivateKey.length != 32) {
            if (error) {
                *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                             code:PLCOperationErrorInvalidKey
                                         userInfo:@{NSLocalizedDescriptionKey: @"Rotation key must be 32 bytes"}];
            }
            return nil;
        }
        
        // Create key pair from private key
        NSError *keyError;
        _rotationKeyPair = [Secp256k1KeyPair keyPairWithPrivateKey:rotationPrivateKey error:&keyError];
        if (!_rotationKeyPair) {
            if (error) *error = keyError;
            return nil;
        }
        
        _rotationPrivateKey = rotationPrivateKey;
        
        // Encode as did:key
        _rotationDIDKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:_rotationKeyPair.compressedPublicKey
                                                                     keyType:DIDKeyTypeSecp256k1
                                                                       error:&keyError];
        if (!_rotationDIDKey) {
            if (error) *error = keyError;
            return nil;
        }
        
        _additionalRotationKeys = @[];
    }
    return self;
}

- (nullable instancetype)initWithNewRotationKeyWithError:(NSError **)error {
    NSError *keyError;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&keyError];
    if (!keyPair) {
        if (error) *error = keyError;
        return nil;
    }
    
    return [self initWithRotationPrivateKey:keyPair.privateKey error:error];
}

- (nullable NSDictionary *)buildGenesisOperationWithError:(NSError **)error {
    return [self buildOperationWithPrev:nil error:error];
}

- (nullable NSDictionary *)buildUpdateOperationWithPrev:(NSString *)prevCID
                                                  error:(NSError **)error {
    if (!prevCID || prevCID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"Update operation requires prev CID"}];
        }
        return nil;
    }
    return [self buildOperationWithPrev:prevCID error:error];
}

- (nullable NSDictionary *)buildOperationWithPrev:(nullable NSString *)prevCID
                                            error:(NSError **)error {
    // Validate required fields
    if (!self.signingDIDKey || self.signingDIDKey.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"signingDIDKey is required"}];
        }
        return nil;
    }
    
    if (!self.handle || self.handle.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"handle is required"}];
        }
        return nil;
    }
    
    if (!self.pdsEndpoint || self.pdsEndpoint.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"pdsEndpoint is required"}];
        }
        return nil;
    }
    
    // Build rotation keys array
    NSMutableArray *rotationKeys = [NSMutableArray arrayWithObject:self.rotationDIDKey];
    [rotationKeys addObjectsFromArray:self.additionalRotationKeys];
    
    // Build operation without signature
    NSMutableDictionary *operation = [NSMutableDictionary dictionary];
    operation[@"type"] = @"plc_operation";
    operation[@"rotationKeys"] = rotationKeys;
    operation[@"verificationMethods"] = @{
        @"atproto": self.signingDIDKey
    };
    
    // Format handle as at:// URI
    NSString *handleURI = self.handle;
    if (![handleURI hasPrefix:@"at://"]) {
        handleURI = [NSString stringWithFormat:@"at://%@", self.handle];
    }
    operation[@"alsoKnownAs"] = @[handleURI];
    
    operation[@"services"] = @{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": self.pdsEndpoint
        }
    };
    
    // prev is null for genesis, CID string for updates
    operation[@"prev"] = prevCID ?: [NSNull null];
    
    // Sign the operation
    NSString *signature = [self signOperation:operation error:error];
    if (!signature) {
        return nil;
    }
    
    operation[@"sig"] = signature;
    
    return [operation copy];
}

- (nullable NSString *)signOperation:(NSDictionary *)operation error:(NSError **)error {
    // Encode operation as DAG-CBOR
    NSData *cborData = [self encodeAsDAGCBOR:operation error:error];
    if (!cborData) {
        return nil;
    }
    
    // SHA-256 hash
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cborData.bytes, (CC_LONG)cborData.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    
    // Sign with rotation key
    NSError *signError;
    NSData *signature = [self.rotationKeyPair signHash:hashData error:&signError];
    if (!signature) {
        if (error) *error = signError;
        return nil;
    }
    
    // Encode as base64url (no padding)
    NSString *base64 = [signature base64EncodedStringWithOptions:0];
    // Convert to base64url
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
              stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    // Remove padding
    while ([base64 hasSuffix:@"="]) {
        base64 = [base64 substringToIndex:base64.length - 1];
    }
    
    return base64;
}

- (nullable NSData *)encodeAsDAGCBOR:(NSDictionary *)dict error:(NSError **)error {
    // Convert NSDictionary to CBORValue map with sorted keys
    CBORValue *cborValue = [self convertToCBORValue:dict];
    if (!cborValue) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorEncodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to convert to CBOR"}];
        }
        return nil;
    }
    
    return [CBOREncoder encode:cborValue];
}

- (CBORValue *)convertToCBORValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return [CBORValue textString:value];
    } else if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *num = value;
        // Check if it's a boolean (CFBooleanRef)
        if (strcmp([num objCType], @encode(BOOL)) == 0 || 
            strcmp([num objCType], @encode(char)) == 0) {
            return [num boolValue] ? [CBORValue simple:21] : [CBORValue simple:20];
        }
        // Integer
        if ([num doubleValue] == floor([num doubleValue])) {
            NSInteger intVal = [num integerValue];
            if (intVal >= 0) {
                return [CBORValue unsignedInteger:intVal];
            } else {
                return [CBORValue negativeInteger:intVal];
            }
        }
        return [CBORValue floatingPoint:[num doubleValue]];
    } else if ([value isKindOfClass:[NSNull class]]) {
        return [CBORValue nilValue];
    } else if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray<CBORValue *> *cborArray = [NSMutableArray array];
        for (id item in value) {
            CBORValue *cborItem = [self convertToCBORValue:item];
            if (cborItem) {
                [cborArray addObject:cborItem];
            }
        }
        return [CBORValue array:cborArray];
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary<CBORValue *, CBORValue *> *cborMap = [NSMutableDictionary dictionary];
        for (NSString *key in value) {
            CBORValue *cborKey = [CBORValue textString:key];
            CBORValue *cborValue = [self convertToCBORValue:value[key]];
            if (cborValue) {
                cborMap[cborKey] = cborValue;
            }
        }
        return [CBORValue map:cborMap];
    } else if ([value isKindOfClass:[NSData class]]) {
        return [CBORValue byteString:value];
    }
    return nil;
}

+ (nullable NSString *)computeDIDFromGenesisOperation:(NSDictionary *)operation
                                                error:(NSError **)error {
    // Validate it's a genesis operation
    id prev = operation[@"prev"];
    if (prev != nil && ![prev isKindOfClass:[NSNull class]]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot compute DID from non-genesis operation"}];
        }
        return nil;
    }
    
    // Must have signature
    if (!operation[@"sig"]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"Operation must be signed to compute DID"}];
        }
        return nil;
    }
    
    // Encode as DAG-CBOR
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] init];
    NSData *cborData = [builder encodeAsDAGCBOR:operation error:error];
    if (!cborData) {
        return nil;
    }
    
    // SHA-256 hash
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cborData.bytes, (CC_LONG)cborData.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    
    // Base32 lower encode
    NSString *base32 = [ATProtoBase32 encodeData:hashData];
    
    // Take first 24 characters
    if (base32.length < 24) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorEncodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Base32 encoding too short"}];
        }
        return nil;
    }
    
    NSString *identifier = [[base32 substringToIndex:24] lowercaseString];
    return [NSString stringWithFormat:@"did:plc:%@", identifier];
}

+ (BOOL)validateOperation:(NSDictionary *)operation error:(NSError **)error {
    // Check type
    NSString *type = operation[@"type"];
    if (![type isEqualToString:@"plc_operation"]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid operation type"}];
        }
        return NO;
    }
    
    // Check rotationKeys
    NSArray *rotationKeys = operation[@"rotationKeys"];
    if (!rotationKeys || rotationKeys.count == 0 || rotationKeys.count > 5) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"rotationKeys must have 1-5 entries"}];
        }
        return NO;
    }
    
    for (NSString *key in rotationKeys) {
        if (![DIDKeyEncoder isValidDIDKey:key]) {
            if (error) {
                *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                             code:PLCOperationErrorInvalidOperation
                                         userInfo:@{NSLocalizedDescriptionKey: 
                                             [NSString stringWithFormat:@"Invalid rotation key: %@", key]}];
            }
            return NO;
        }
    }
    
    // Check verificationMethods
    NSDictionary *verificationMethods = operation[@"verificationMethods"];
    if (!verificationMethods || !verificationMethods[@"atproto"]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"verificationMethods.atproto is required"}];
        }
        return NO;
    }
    
    // Check services
    NSDictionary *services = operation[@"services"];
    if (!services || !services[@"atproto_pds"]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"services.atproto_pds is required"}];
        }
        return NO;
    }
    
    NSDictionary *pdsService = services[@"atproto_pds"];
    if (!pdsService[@"type"] || !pdsService[@"endpoint"]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"PDS service missing type or endpoint"}];
        }
        return NO;
    }
    
    // Check alsoKnownAs
    NSArray *alsoKnownAs = operation[@"alsoKnownAs"];
    if (!alsoKnownAs || alsoKnownAs.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"alsoKnownAs is required"}];
        }
        return NO;
    }
    
    // Check signature is present
    if (!operation[@"sig"]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidOperation
                                     userInfo:@{NSLocalizedDescriptionKey: @"sig is required"}];
        }
        return NO;
    }
    
    return YES;
}

// For internal use when not initializing with a key
- (instancetype)init {
    return [super init];
}

@end

#import "PLCOperation.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Core/ATProtoBase32.h"
#import "Debug/PDSLogger.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const PLCErrorDomain = @"com.atproto.plc";

// Error Codes
typedef NS_ENUM(NSInteger, PLCErrorCode) {
    PLCErrorMissingSignature = 1,
    PLCErrorUnsupportedType = 2,
    PLCErrorInvalidDIDFormat = 3,
    PLCErrorExceedsSizeLimit = 4,
    PLCErrorInvalidRotationKeys = 5,
    PLCErrorInvalidVerificationMethods = 6,
    PLCErrorInvalidAlsoKnownAs = 7,
    PLCErrorInvalidServices = 8
};

static NSString *PLCNormalizeAtprotoHandle(NSString *value) {
    if ([value hasPrefix:@"at://"]) {
        return value;
    }
    NSString *stripped = [value stringByReplacingOccurrencesOfString:@"http://" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"https://" withString:@""];
    return [NSString stringWithFormat:@"at://%@", stripped];
}

static NSString *PLCNormalizeServiceEndpoint(NSString *value) {
    if ([value hasPrefix:@"http://"] || [value hasPrefix:@"https://"]) {
        return value;
    }
    return [NSString stringWithFormat:@"https://%@", value];
}

static BOOL isBase32Char(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= '2' && c <= '7');
}

@implementation PLCOperation

+ (NSString *)calculateDIDForData:(NSDictionary *)data {
    NSError *error = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:data error:&error];
    if (!cborData || cborData.length > 7500) {
        return @"";
    }
    
    // Debug: print CBOR hex for DID derivation debugging
    NSMutableString *hexStr = [NSMutableString stringWithCapacity:cborData.length * 2];
    const unsigned char *bytes = cborData.bytes;
    for (NSUInteger i = 0; i < cborData.length; i++) {
        [hexStr appendFormat:@"%02x", bytes[i]];
    }
    PDS_LOG_INFO(@"DID derivation CBOR hex (%lu bytes): %@", (unsigned long)cborData.length, hexStr);
    
    NSData *hash = [CID rawSha256:cborData];
    
    // Debug: print SHA256 hex
    NSMutableString *hashHex = [NSMutableString stringWithCapacity:hash.length * 2];
    const unsigned char *hashBytes = hash.bytes;
    for (NSUInteger i = 0; i < hash.length; i++) {
        [hashHex appendFormat:@"%02x", hashBytes[i]];
    }
    PDS_LOG_INFO(@"DID derivation SHA256: %@", hashHex);
    
    NSString *base32 = [ATProtoBase32 encodeData:hash];
    PDS_LOG_INFO(@"DID derivation base32 full: %@", base32);
    // did:plc is first 24 chars of base32 hash
    if (base32.length > 24) {
        base32 = [base32 substringToIndex:24];
    }
    return [NSString stringWithFormat:@"did:plc:%@", base32];
}

+ (BOOL)isValidDidPlc:(NSString *)did {
    if (!did || did.length != 32 || ![did hasPrefix:@"did:plc:"]) {
        return NO;
    }
    for (NSUInteger i = 8; i < 32; i++) {
        if (!isBase32Char([did characterAtIndex:i])) {
            return NO;
        }
    }
    return YES;
}

+ (BOOL)assertDidPlc:(NSString *)did error:(NSError **)error {
    if (!did) {
        if (error) *error = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorInvalidDIDFormat userInfo:@{NSLocalizedDescriptionKey: @"DID must be a string"}];
        return NO;
    }
    if (![did hasPrefix:@"did:plc:"]) {
        if (error) *error = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorInvalidDIDFormat userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:plc prefix"}];
        return NO;
    }
    if (did.length != 32) {
        if (error) *error = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorInvalidDIDFormat userInfo:@{NSLocalizedDescriptionKey: @"did:plc must be exactly 32 characters long"}];
        return NO;
    }
    for (NSUInteger i = 8; i < 32; i++) {
        if (!isBase32Char([did characterAtIndex:i])) {
            if (error) *error = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorInvalidDIDFormat userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Invalid character at position %lu", (unsigned long)i] forKey:NSLocalizedDescriptionKey]];
            return NO;
        }
    }
    return YES;
}

+ (nullable NSString *)calculateCIDForOperation:(NSDictionary *)operation error:(NSError **)error {
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:operation error:error];
    if (!cborData) {
        return nil;
    }
    if (cborData.length > 7500) {
        if (error) {
            *error = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorExceedsSizeLimit userInfo:@{NSLocalizedDescriptionKey: @"Operation exceeds 7500 bytes DAG-CBOR limit"}];
        }
        return nil;
    }
    NSData *digest = [CID sha256Digest:cborData];
    CID *cid = [CID cidWithDigest:digest codec:0x71];
    return cid.stringValue;
}

+ (nullable instancetype)operationFromDictionary:(NSDictionary *)entry error:(NSError **)outError {
    // PLC audit log wraps each operation in metadata (cid, createdAt, etc.)
    // Handle both wrapped and unwrapped formats.
    NSDictionary *dict = entry[@"operation"];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        dict = entry;
    }

    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = dict[@"did"];
    
    if (op.did && [op.did isKindOfClass:[NSString class]]) {
        if (![self assertDidPlc:op.did error:outError]) {
            return nil;
        }
    }
    
    op.sig = dict[@"sig"];
    if (![op.sig isKindOfClass:[NSString class]]) {
        if (outError) {
            *outError = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorMissingSignature userInfo:@{NSLocalizedDescriptionKey: @"Invalid operation dictionary: missing or invalid sig"}];
        }
        return nil;
    }
    
    id prev = dict[@"prev"];
    if (prev && [prev isKindOfClass:[NSString class]]) {
        op.prev = prev;
    }
    
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isEqualToString:@"sig"]) {
            data[key] = obj;
        }
    }];
    op.data = [data copy];
    
    NSString *type = op.data[@"type"];
    if (![type isKindOfClass:[NSString class]]) {
        if (outError) {
            *outError = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorUnsupportedType userInfo:@{NSLocalizedDescriptionKey: @"Operation missing valid type"}];
        }
        return nil;
    }
    
    if ([type isEqualToString:@"update_handle"]) {
        if (outError) {
            *outError = [NSError errorWithDomain:PLCErrorDomain
                                          code:PLCErrorUnsupportedType
                                      userInfo:@{NSLocalizedDescriptionKey: @"update_handle is not supported in spec-compliant PLC"}];
        }
        return nil;
    }
    
    if ([type isEqualToString:@"plc_operation"]) {
        NSArray *rotationKeys = op.data[@"rotationKeys"];
        if (![rotationKeys isKindOfClass:[NSArray class]] || rotationKeys.count == 0) {
            if (outError) *outError = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorInvalidRotationKeys userInfo:@{NSLocalizedDescriptionKey: @"plc_operation requires rotationKeys array"}];
            return nil;
        }
        for (NSString *key in rotationKeys) {
            if (![key isKindOfClass:[NSString class]] || ![key hasPrefix:@"did:key:"]) {
                if (outError) *outError = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorInvalidRotationKeys userInfo:@{NSLocalizedDescriptionKey: @"rotationKeys must be valid did:key strings"}];
                return nil;
            }
        }
        
        NSDictionary *verificationMethods = op.data[@"verificationMethods"];
        if (verificationMethods && ![verificationMethods isKindOfClass:[NSDictionary class]]) {
            if (outError) *outError = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorInvalidVerificationMethods userInfo:@{NSLocalizedDescriptionKey: @"verificationMethods must be an object"}];
            return nil;
        }
        
        NSArray *alsoKnownAs = op.data[@"alsoKnownAs"];
        if (alsoKnownAs && ![alsoKnownAs isKindOfClass:[NSArray class]]) {
            if (outError) *outError = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorInvalidAlsoKnownAs userInfo:@{NSLocalizedDescriptionKey: @"alsoKnownAs must be an array"}];
            return nil;
        }
        // Strict at:// check removed as some legacy entries might differ, but PDS should be lenient on replay
        
        NSDictionary *services = op.data[@"services"];
        if (services && ![services isKindOfClass:[NSDictionary class]]) {
            if (outError) *outError = [NSError errorWithDomain:PLCErrorDomain code:PLCErrorInvalidServices userInfo:@{NSLocalizedDescriptionKey: @"services must be an object"}];
            return nil;
        }
    }
    
    return op;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [self.data mutableCopy];
    dict[@"sig"] = self.sig;
    if (self.prev) {
        dict[@"prev"] = self.prev;
    }
    return [dict copy];
}

@end

@implementation PLCDIDState

- (NSDictionary *)toDIDDocument {
    NSMutableArray *verificationMethods = [NSMutableArray array];
    [self.verificationMethods enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *multibase, BOOL *stop) {
        [verificationMethods addObject:@{
            @"id": [NSString stringWithFormat:@"%@#%@", self.did, key],
            @"type": @"Multikey",
            @"controller": self.did,
            @"publicKeyMultibase": multibase
        }];
    }];
    
    NSMutableArray *services = [NSMutableArray array];
    [self.services enumerateKeysAndObjectsUsingBlock:^(id key, id service, BOOL *stop) {
        [services addObject:@{
            @"id": [NSString stringWithFormat:@"#%@", key],
            @"type": ((NSDictionary *)service)[@"type"],
            @"serviceEndpoint": ((NSDictionary *)service)[@"endpoint"]
        }];
    }];
    
    return @{
        @"@context": @[
            @"https://www.w3.org/ns/did/v1",
            @"https://w3id.org/security/multikey/v1",
            @"https://w3id.org/security/suites/secp256k1-2019/v1"
        ],
        @"id": self.did,
        @"alsoKnownAs": self.alsoKnownAs ?: @[],
        @"verificationMethod": verificationMethods,
        @"service": services
    };
}

@end

@implementation PLCStateReplayer

+ (nullable PLCDIDState *)replayHistory:(NSArray<PLCOperation *> *)history error:(NSError **)error {
    if (history.count == 0) return nil;
    
    PLCDIDState *state = [[PLCDIDState alloc] init];
    state.did = history[0].did;
    state.alsoKnownAs = @[];
    
    for (PLCOperation *op in history) {
        NSString *type = op.data[@"type"];
        if (![type isKindOfClass:[NSString class]]) continue;
        
        if ([type isEqualToString:@"plc_operation"]) {
            state.rotationKeys = op.data[@"rotationKeys"];
            state.verificationMethods = op.data[@"verificationMethods"];
            state.alsoKnownAs = op.data[@"alsoKnownAs"];
            state.services = op.data[@"services"];
            state.tombstoned = NO;
        } else if ([type isEqualToString:@"plc_tombstone"]) {
            state.tombstoned = YES;
        } else if ([type isEqualToString:@"create"]) {
            state.rotationKeys = @[op.data[@"recoveryKey"], op.data[@"signingKey"]];
            state.verificationMethods = @{@"atproto": op.data[@"signingKey"]};
            NSString *handle = op.data[@"handle"] ?: @"";
            NSString *service = op.data[@"service"] ?: @"";
            state.alsoKnownAs = @[PLCNormalizeAtprotoHandle(handle)];
            state.services = @{@"atproto_pds": @{@"type": @"AtprotoPersonalDataServer",
                                                 @"endpoint": PLCNormalizeServiceEndpoint(service)}};
            state.tombstoned = NO;
        }
    }
    
    return state;
}

@end

NS_ASSUME_NONNULL_END

#import "PLCOperation.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Core/ATProtoBase32.h"
#import "Identity/ATProtoHandleValidator.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const PLCErrorDomain = @"com.atproto.plc";

@implementation PLCOperation

+ (NSString *)calculateDIDForData:(NSDictionary *)data {
    NSError *error = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:data error:&error];
    if (!cborData) {
        return @"";
    }
    
    NSData *hash = [CID rawSha256:cborData];
    NSString *base32 = [ATProtoBase32 encodeData:hash];
    // did:plc is first 24 chars of base32 hash
    if (base32.length > 24) {
        base32 = [base32 substringToIndex:24];
    }
    return [NSString stringWithFormat:@"did:plc:%@", base32];
}

+ (nullable instancetype)operationFromDictionary:(NSDictionary *)dict error:(NSError **)error {
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = dict[@"did"];
    op.sig = dict[@"sig"];
    
    id prev = dict[@"prev"];
    if (prev && [prev isKindOfClass:[NSString class]]) {
        op.prev = prev;
    }
    
    NSMutableDictionary *data = [dict mutableCopy];
    [data removeObjectForKey:@"sig"];
    op.data = [data copy];
    
    if (!op.sig) {
        if (error) {
            *error = [NSError errorWithDomain:PLCErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid operation dictionary: missing sig"}];
        }
        return nil;
    }
    
    NSString *type = op.data[@"type"];
    if ([type isEqualToString:@"update_handle"]) {
        NSString *handle = op.data[@"handle"];
        if (!handle || ![handle isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:PLCErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"update_handle operation requires 'handle' field"}];
            }
            return nil;
        }
        NSError *validationError = nil;
        if (![ATProtoHandleValidator validateHandle:handle error:&validationError]) {
            if (error) {
                *error = [NSError errorWithDomain:PLCErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid handle: %@", validationError.localizedDescription]}];
            }
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
    } else {
        dict[@"prev"] = [NSNull null];
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
    [self.services enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *service, BOOL *stop) {
        [services addObject:@{
            @"id": [NSString stringWithFormat:@"#%@", key],
            @"type": service[@"type"],
            @"serviceEndpoint": service[@"endpoint"]
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
            state.rotationKeys = @[op.data[@"recoveryKey"]];
            state.verificationMethods = @{@"atproto": op.data[@"signingKey"]};
            state.alsoKnownAs = @[op.data[@"handle"]];
            state.services = @{@"atproto_pds": @{@"type": @"AtprotoPersonalDataServer", @"endpoint": op.data[@"service"]}};
            state.tombstoned = NO;
        } else if ([type isEqualToString:@"update_handle"]) {
            NSString *newHandle = op.data[@"handle"];
            if (newHandle && [newHandle isKindOfClass:[NSString class]]) {
                NSMutableArray *handles = [state.alsoKnownAs mutableCopy] ?: [NSMutableArray array];
                NSString *existingHandle = handles.firstObject;
                if (existingHandle) {
                    [handles replaceObjectAtIndex:0 withObject:newHandle];
                } else {
                    [handles addObject:newHandle];
                }
                state.alsoKnownAs = [handles copy];
            }
            state.tombstoned = NO;
        }
    }
    
    return state;
}

@end

NS_ASSUME_NONNULL_END


#import "PLCOperation.h"
#import "Identity/PLCOperationBuilder.h"
#import "Core/ATProtoCBORSerialization.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const kPLCOperationType = @"plc_operation";
static NSString * const kPLCTombstoneType = @"plc_tombstone";

@implementation PLCOperation

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)genesisOperationWithRotationKeys:(NSArray<NSString *> *)rotationKeys
                               verificationMethods:(NSDictionary<NSString *, NSString *> *)verificationMethods
                                      alsoKnownAs:(NSArray<NSString *> *)alsoKnownAs
                                         services:(NSDictionary<NSString *, NSDictionary *> *)services {
    PLCOperation *op = [[PLCOperation alloc] init];
    op.type = kPLCOperationType;
    op.rotationKeys = rotationKeys ?: @[];
    op.verificationMethods = verificationMethods ?: @{};
    op.alsoKnownAs = alsoKnownAs ?: @[];
    op.services = services ?: @{};
    op.prev = nil;
    op.sig = nil;
    return op;
}

+ (instancetype)tombstoneOperationWithPrev:(NSString *)prevCID
                             rotationKeys:(NSArray<NSString *> *)rotationKeys {
    PLCOperation *op = [[PLCOperation alloc] init];
    op.type = kPLCTombstoneType;
    op.rotationKeys = rotationKeys ?: @[];
    op.verificationMethods = @{};
    op.alsoKnownAs = @[];
    op.services = @{};
    op.prev = prevCID;
    op.sig = nil;
    return op;
}

- (BOOL)isGenesis {
    return self.prev == nil && [self.type isEqualToString:kPLCOperationType];
}

- (BOOL)isTombstone {
    return [self.type isEqualToString:kPLCTombstoneType];
}

- (nullable NSData *)serializeForSigning:(NSError **)error {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"type"] = self.type;
    dict[@"rotationKeys"] = self.rotationKeys;
    dict[@"verificationMethods"] = self.verificationMethods;
    dict[@"alsoKnownAs"] = self.alsoKnownAs;
    dict[@"services"] = self.services;

    if (self.prev) {
        dict[@"prev"] = self.prev;
    } else {
        dict[@"prev"] = [NSNull null];
    }

    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:dict error:error];
    if (!cbor) {
        return nil;
    }

    return cbor;
}

- (nullable NSString *)computeCID:(NSError **)error {
    // CID is computed from the SIGNED operation (includes sig field)
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"type"] = self.type;
    dict[@"rotationKeys"] = self.rotationKeys;
    dict[@"verificationMethods"] = self.verificationMethods;
    dict[@"alsoKnownAs"] = self.alsoKnownAs;
    dict[@"services"] = self.services;

    if (self.prev) {
        dict[@"prev"] = self.prev;
    } else {
        dict[@"prev"] = [NSNull null];
    }

    if (self.sig) {
        dict[@"sig"] = self.sig;
    }

    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:dict error:error];
    if (!cbor) {
        return nil;
    }

    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cbor.bytes, (CC_LONG)cbor.length, hash);

    // Base32 encode the hash (RFC 4648 base32 lowercase, no padding)
    // Each 5 bytes produces 8 characters
    NSMutableString *base32 = [NSMutableString stringWithCapacity:52]; // 32 bytes -> 52 chars
    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    
    uint64_t buffer = 0;
    int bitsInBuffer = 0;
    
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        buffer = (buffer << 8) | hash[i];
        bitsInBuffer += 8;
        
        while (bitsInBuffer >= 5) {
            bitsInBuffer -= 5;
            int index = (buffer >> bitsInBuffer) & 0x1f;
            [base32 appendFormat:@"%c", alphabet[index]];
        }
    }
    
    // Handle remaining bits (pad with zeros on the right)
    if (bitsInBuffer > 0) {
        int index = (buffer << (5 - bitsInBuffer)) & 0x1f;
        [base32 appendFormat:@"%c", alphabet[index]];
    }

    // Truncate to 24 characters for did:plc identifier
    if (base32.length > 24) {
        return [base32 substringToIndex:24];
    }
    return [base32 copy];
}

+ (nullable instancetype)operationFromJSON:(NSDictionary *)json error:(NSError **)error {
    if (!json || ![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidType
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON for PLC operation"}];
        }
        return nil;
    }

    NSString *type = json[@"type"];
    if (!type || ![type isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCOperationErrorDomain
                                         code:PLCOperationErrorInvalidType
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing or invalid 'type' field"}];
        }
        return nil;
    }

    PLCOperation *op = [[PLCOperation alloc] init];
    op.type = type;
    op.rotationKeys = json[@"rotationKeys"] ?: @[];
    op.verificationMethods = json[@"verificationMethods"] ?: @{};
    op.alsoKnownAs = json[@"alsoKnownAs"] ?: @[];
    op.services = json[@"services"] ?: @{};

    id prev = json[@"prev"];
    if (prev && ![prev isKindOfClass:[NSNull class]]) {
        op.prev = prev;
    } else {
        op.prev = nil;
    }

    op.sig = json[@"sig"];

    return op;
}

- (NSDictionary *)toJSON {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"type"] = self.type;
    dict[@"rotationKeys"] = self.rotationKeys;
    dict[@"verificationMethods"] = self.verificationMethods;
    dict[@"alsoKnownAs"] = self.alsoKnownAs;
    dict[@"services"] = self.services;

    if (self.prev) {
        dict[@"prev"] = self.prev;
    } else {
        dict[@"prev"] = [NSNull null];
    }

    if (self.sig) {
        dict[@"sig"] = self.sig;
    }

    return [dict copy];
}

#pragma mark - NSSecureCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.type forKey:@"type"];
    [coder encodeObject:self.rotationKeys forKey:@"rotationKeys"];
    [coder encodeObject:self.verificationMethods forKey:@"verificationMethods"];
    [coder encodeObject:self.alsoKnownAs forKey:@"alsoKnownAs"];
    [coder encodeObject:self.services forKey:@"services"];
    [coder encodeObject:self.prev forKey:@"prev"];
    [coder encodeObject:self.sig forKey:@"sig"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _type = [coder decodeObjectOfClass:[NSString class] forKey:@"type"];
        _rotationKeys = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSString class], nil] forKey:@"rotationKeys"];
        _verificationMethods = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSDictionary class], [NSString class], nil] forKey:@"verificationMethods"];
        _alsoKnownAs = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSString class], nil] forKey:@"alsoKnownAs"];
        _services = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSDictionary class], [NSDictionary class], [NSString class], nil] forKey:@"services"];
        _prev = [coder decodeObjectOfClass:[NSString class] forKey:@"prev"];
        _sig = [coder decodeObjectOfClass:[NSString class] forKey:@"sig"];
    }
    return self;
}

@end

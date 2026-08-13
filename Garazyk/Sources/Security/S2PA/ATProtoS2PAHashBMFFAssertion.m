// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Security/S2PA/ATProtoS2PAHashBMFFAssertion.h"
#import "Core/CBOR.h"
#import <CommonCrypto/CommonDigest.h>
#include <string.h>

NSString * const ATProtoS2PAHashBMFFAssertionErrorDomain = @"com.atproto.s2pa.hashbmff";
NSString * const ATProtoS2PAHashBMFFAssertionLabel = @"c2pa.hash.bmff.v3";

static NSError *S2PABMFFErr(ATProtoS2PAHashBMFFAssertionErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoS2PAHashBMFFAssertionErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void S2PABMFFSetErr(NSError **error, ATProtoS2PAHashBMFFAssertionErrorCode code,
                           NSString *message) {
    if (error) *error = S2PABMFFErr(code, message);
}

static ATProtoCBORValue *S2PAText(NSString *s) {
    return [ATProtoCBORValue textString:s];
}

static ATProtoCBORValue *S2PAUInt(NSUInteger v) {
    return [ATProtoCBORValue unsignedInteger:v];
}

static ATProtoCBORValue *S2PAInt(NSInteger v) {
    if (v < 0) return [ATProtoCBORValue negativeInteger:v];
    return [ATProtoCBORValue unsignedInteger:(NSUInteger)v];
}

static NSData *S2PASha256(NSData *data) {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

@implementation ATProtoS2PAHashBMFFDataMatch
+ (instancetype)matchWithOffset:(NSUInteger)offset value:(NSData *)value {
    ATProtoS2PAHashBMFFDataMatch *m = [[ATProtoS2PAHashBMFFDataMatch alloc] init];
    m.offset = offset;
    m.value = [value copy];
    return m;
}
@end

@implementation ATProtoS2PAHashBMFFSubset
+ (instancetype)subsetWithOffset:(NSUInteger)offset length:(NSUInteger)length {
    ATProtoS2PAHashBMFFSubset *s = [[ATProtoS2PAHashBMFFSubset alloc] init];
    s.offset = offset;
    s.length = length;
    return s;
}
@end

@implementation ATProtoS2PAHashBMFFExclusion
+ (instancetype)exclusionWithXPath:(NSString *)xpath
                       dataMatches:(NSArray<ATProtoS2PAHashBMFFDataMatch *> *)dataMatches
                           subsets:(NSArray<ATProtoS2PAHashBMFFSubset *> *)subsets {
    ATProtoS2PAHashBMFFExclusion *ex = [[ATProtoS2PAHashBMFFExclusion alloc] init];
    ex.xpath = [xpath copy];
    ex.dataMatches = [dataMatches copy];
    ex.subsets = [subsets copy];
    return ex;
}
@end

@implementation ATProtoS2PAMerkleMap
- (instancetype)initWithUniqueId:(NSInteger)uniqueId
                         localId:(NSInteger)localId
                           count:(NSUInteger)count
                          hashes:(NSArray<NSData *> *)hashes
                             alg:(NSString *)alg
                  fixedBlockSize:(NSNumber *)fixedBlockSize
             variableBlockSizes:(NSArray<NSNumber *> *)variableBlockSizes
            initializationHash:(NSData *)initializationHash {
    self = [super init];
    if (self) {
        _uniqueId = uniqueId;
        _localId = localId;
        _count = count;
        _hashes = [hashes copy] ?: @[];
        _alg = [alg copy];
        _fixedBlockSize = fixedBlockSize;
        _variableBlockSizes = [variableBlockSizes copy];
        _initializationHash = [initializationHash copy];
    }
    return self;
}

- (nullable NSData *)encodeCBORMap:(NSError **)error {
    if (self.count == 0 || self.hashes.count == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"merkle-map requires count and hashes");
        return nil;
    }
    if (self.fixedBlockSize && self.variableBlockSizes.count > 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"merkle-map cannot set both fixedBlockSize and variableBlockSizes");
        return nil;
    }
    if (self.variableBlockSizes.count > 0 && self.variableBlockSizes.count != self.count) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"variableBlockSizes length must equal count");
        return nil;
    }
    for (NSData *h in self.hashes) {
        if (h.length != CC_SHA256_DIGEST_LENGTH) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                           @"merkle hashes must be 32-byte sha256 digests");
            return nil;
        }
    }
    NSMutableArray *hashArr = [NSMutableArray array];
    for (NSData *h in self.hashes) {
        [hashArr addObject:[ATProtoCBORValue byteString:h]];
    }
    NSMutableDictionary *dict = [@{
        S2PAText(@"uniqueId"): S2PAInt(self.uniqueId),
        S2PAText(@"localId"): S2PAInt(self.localId),
        S2PAText(@"count"): S2PAUInt(self.count),
        S2PAText(@"hashes"): [ATProtoCBORValue array:hashArr],
    } mutableCopy];
    if (self.alg.length > 0) dict[S2PAText(@"alg")] = S2PAText(self.alg);
    if (self.fixedBlockSize) {
        dict[S2PAText(@"fixedBlockSize")] = S2PAUInt(self.fixedBlockSize.unsignedIntegerValue);
    }
    if (self.variableBlockSizes.count > 0) {
        NSMutableArray *sizes = [NSMutableArray array];
        for (NSNumber *n in self.variableBlockSizes) {
            [sizes addObject:S2PAUInt(n.unsignedIntegerValue)];
        }
        dict[S2PAText(@"variableBlockSizes")] = [ATProtoCBORValue array:sizes];
    }
    if (self.initializationHash.length > 0) {
        dict[S2PAText(@"initHash")] = [ATProtoCBORValue byteString:self.initializationHash];
    }
    NSData *encoded = [[ATProtoCBORValue map:dict] encode];
    if (!encoded) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"failed to encode merkle-map CBOR");
    }
    return encoded;
}

+ (nullable instancetype)merkleMapFromCBORMap:(ATProtoCBORValue *)val error:(NSError **)error {
    if (val.type != CBORTypeMap) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"merkle-map must be a CBOR map");
        return nil;
    }
    __block NSNumber *uniqueId = nil;
    __block NSNumber *localId = nil;
    __block NSNumber *count = nil;
    __block NSString *alg = nil;
    __block NSNumber *fixedBlockSize = nil;
    __block NSData *initializationHash = nil;
    NSMutableArray<NSData *> *hashes = [NSMutableArray array];
    NSMutableArray<NSNumber *> *variableBlockSizes = [NSMutableArray array];
    [val.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *k, ATProtoCBORValue *v, BOOL *stop) {
        (void)stop;
        if (k.type != CBORTypeTextString) return;
        NSString *key = k.textString;
        if ([key isEqualToString:@"uniqueId"] &&
            (v.type == CBORTypeUnsignedInteger || v.type == CBORTypeNegativeInteger)) {
            uniqueId = (v.type == CBORTypeUnsignedInteger) ? v.unsignedInteger : v.negativeInteger;
        } else if ([key isEqualToString:@"localId"] &&
                   (v.type == CBORTypeUnsignedInteger || v.type == CBORTypeNegativeInteger)) {
            localId = (v.type == CBORTypeUnsignedInteger) ? v.unsignedInteger : v.negativeInteger;
        } else if ([key isEqualToString:@"count"] && v.type == CBORTypeUnsignedInteger) {
            count = v.unsignedInteger;
        } else if ([key isEqualToString:@"alg"] && v.type == CBORTypeTextString) {
            alg = v.textString;
        } else if ([key isEqualToString:@"fixedBlockSize"] && v.type == CBORTypeUnsignedInteger) {
            fixedBlockSize = v.unsignedInteger;
        } else if ([key isEqualToString:@"initHash"] && v.type == CBORTypeByteString) {
            initializationHash = v.byteString;
        } else if ([key isEqualToString:@"hashes"] && v.type == CBORTypeArray) {
            for (ATProtoCBORValue *item in v.array) {
                if (item.type == CBORTypeByteString) [hashes addObject:item.byteString];
            }
        } else if ([key isEqualToString:@"variableBlockSizes"] && v.type == CBORTypeArray) {
            for (ATProtoCBORValue *item in v.array) {
                if (item.type == CBORTypeUnsignedInteger) [variableBlockSizes addObject:item.unsignedInteger];
            }
        }
    }];
    if (!uniqueId || !localId || !count || hashes.count == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"merkle-map missing uniqueId, localId, count, or hashes");
        return nil;
    }
    if (fixedBlockSize && variableBlockSizes.count > 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"merkle-map cannot set both fixedBlockSize and variableBlockSizes");
        return nil;
    }
    return [[self alloc] initWithUniqueId:uniqueId.integerValue
                                  localId:localId.integerValue
                                    count:count.unsignedIntegerValue
                                   hashes:hashes
                                      alg:alg
                           fixedBlockSize:fixedBlockSize
                      variableBlockSizes:variableBlockSizes.count > 0 ? variableBlockSizes : nil
                     initializationHash:initializationHash];
}
@end

@interface ATProtoS2PAHashBMFFAssertion ()
@property (nonatomic, copy, readwrite) NSString *alg;
@property (nonatomic, copy, readwrite, nullable) NSData *digest;
@property (nonatomic, copy, readwrite) NSArray<ATProtoS2PAHashBMFFExclusion *> *exclusions;
@property (nonatomic, copy, readwrite, nullable) NSArray<ATProtoS2PAMerkleMap *> *merkle;
@property (nonatomic, copy, readwrite, nullable) NSString *name;
@end

/** C2PA BMFF user-type UUID (same bytes as ATProtoS2PAJUMBF c2paBMFFUUID). */
static NSData *S2PAC2PABMFFUUID(void) {
    static const uint8_t uuid[16] = {
        0xd8, 0xfe, 0xc3, 0xd6, 0x1b, 0x0e, 0x48, 0x3c,
        0x92, 0x97, 0x58, 0x28, 0x87, 0x7e, 0xc4, 0x81
    };
    return [NSData dataWithBytes:uuid length:16];
}

@interface S2PABMFFBoxInfo : NSObject
@property (nonatomic, assign) NSUInteger fileOffset;
@property (nonatomic, assign) NSUInteger length;
@property (nonatomic, copy) NSString *type;
@end

@implementation S2PABMFFBoxInfo
@end

@implementation ATProtoS2PAHashBMFFAssertion

- (instancetype)initWithDigest:(NSData *)digest
                    exclusions:(NSArray<ATProtoS2PAHashBMFFExclusion *> *)exclusions
                        merkle:(NSArray<ATProtoS2PAMerkleMap *> *)merkle
                          name:(NSString *)name {
    self = [super init];
    if (self) {
        _alg = @"sha256";
        _digest = [digest copy];
        _exclusions = [exclusions copy] ?: @[];
        _merkle = [merkle copy];
        _name = [name copy];
    }
    return self;
}

- (instancetype)initWithDigest:(NSData *)digest
                    exclusions:(NSArray<ATProtoS2PAHashBMFFExclusion *> *)exclusions
                          name:(NSString *)name {
    return [self initWithDigest:digest exclusions:exclusions merkle:nil name:name];
}

+ (ATProtoS2PAHashBMFFExclusion *)c2paUUIDBoxExclusion {
    ATProtoS2PAHashBMFFDataMatch *match =
        [ATProtoS2PAHashBMFFDataMatch matchWithOffset:8 value:S2PAC2PABMFFUUID()];
    return [ATProtoS2PAHashBMFFExclusion exclusionWithXPath:@"/uuid"
                                                dataMatches:@[match]
                                                    subsets:nil];
}

+ (ATProtoS2PAHashBMFFExclusion *)mdatMerklePayloadExclusion {
    ATProtoS2PAHashBMFFSubset *subset = [ATProtoS2PAHashBMFFSubset subsetWithOffset:16 length:0];
    return [ATProtoS2PAHashBMFFExclusion exclusionWithXPath:@"/mdat"
                                                dataMatches:nil
                                                    subsets:@[subset]];
}

+ (nullable S2PABMFFBoxInfo *)readBoxAt:(NSUInteger)offset
                                 inData:(NSData *)data
                                  error:(NSError **)error {
    if (offset + 8 > data.length) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"BMFF box header truncated");
        return nil;
    }
    const uint8_t *b = data.bytes;
    uint32_t size32 = ((uint32_t)b[offset] << 24) | ((uint32_t)b[offset + 1] << 16) |
                      ((uint32_t)b[offset + 2] << 8) | (uint32_t)b[offset + 3];
    NSUInteger boxLen = 0;
    if (size32 == 1) {
        if (offset + 16 > data.length) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                           @"BMFF largesize header truncated");
            return nil;
        }
        uint64_t size64 = 0;
        for (int i = 0; i < 8; i++) {
            size64 = (size64 << 8) | b[offset + 8 + i];
        }
        if (size64 < 16 || size64 > data.length - offset) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                           @"BMFF largesize invalid");
            return nil;
        }
        boxLen = (NSUInteger)size64;
    } else if (size32 == 0) {
        boxLen = data.length - offset;
    } else {
        if (size32 < 8 || size32 > data.length - offset) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                           @"BMFF box size invalid");
            return nil;
        }
        boxLen = size32;
    }
    char typeBytes[5] = {0};
    memcpy(typeBytes, b + offset + 4, 4);
    NSString *type = [[NSString alloc] initWithBytes:typeBytes length:4 encoding:NSASCIIStringEncoding];
    if (type.length != 4) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"BMFF box type invalid");
        return nil;
    }
    S2PABMFFBoxInfo *box = [[S2PABMFFBoxInfo alloc] init];
    box.fileOffset = offset;
    box.length = boxLen;
    box.type = type;
    return box;
}

+ (nullable NSArray<S2PABMFFBoxInfo *> *)parseRootBoxes:(NSData *)data error:(NSError **)error {
    NSMutableArray<S2PABMFFBoxInfo *> *boxes = [NSMutableArray array];
    NSUInteger offset = 0;
    while (offset < data.length) {
        S2PABMFFBoxInfo *box = [self readBoxAt:offset inData:data error:error];
        if (!box) return nil;
        [boxes addObject:box];
        if (box.length == 0) break;
        offset += box.length;
    }
    return boxes;
}

+ (nullable NSArray<NSString *> *)xpathComponents:(NSString *)xpath error:(NSError **)error {
    if (![xpath hasPrefix:@"/"] || xpath.length < 2) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"BMFF exclusion xpath must be an absolute path");
        return nil;
    }
    NSArray *parts = [[xpath substringFromIndex:1] componentsSeparatedByString:@"/"];
    if (parts.count == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"BMFF exclusion xpath empty");
        return nil;
    }
    for (NSString *part in parts) {
        if (part.length < 4) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                           @"BMFF xpath node must be a 4cc");
            return nil;
        }
        NSString *type = [part componentsSeparatedByString:@"["].firstObject;
        if (type.length != 4) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                           @"BMFF xpath node must be a 4cc");
            return nil;
        }
    }
    return parts;
}

+ (BOOL)node:(NSString *)node matchesType:(NSString *)type occurrence:(NSUInteger)occurrenceIndex {
    NSString *wantType = [node componentsSeparatedByString:@"["].firstObject;
    if (![wantType isEqualToString:type]) return NO;
    NSRange open = [node rangeOfString:@"["];
    if (open.location == NSNotFound) return YES;
    NSRange close = [node rangeOfString:@"]"];
    if (close.location == NSNotFound || close.location <= open.location + 1) return NO;
    NSString *num =
        [node substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)];
    NSInteger want = num.integerValue;
    if (want <= 0) return NO;
    return occurrenceIndex == (NSUInteger)want;
}

+ (BOOL)box:(S2PABMFFBoxInfo *)box
    inData:(NSData *)data
matchesExclusion:(ATProtoS2PAHashBMFFExclusion *)ex {
    for (ATProtoS2PAHashBMFFDataMatch *m in ex.dataMatches ?: @[]) {
        if (m.offset + m.value.length > box.length) return NO;
        NSData *slice = [data subdataWithRange:NSMakeRange(box.fileOffset + m.offset, m.value.length)];
        if (![slice isEqualToData:m.value]) return NO;
    }
    return YES;
}

+ (nullable NSData *)bytesForBox:(S2PABMFFBoxInfo *)box
                          inData:(NSData *)data
                         subsets:(NSArray<ATProtoS2PAHashBMFFSubset *> *)subsets
                           error:(NSError **)error {
    NSData *full = [data subdataWithRange:NSMakeRange(box.fileOffset, box.length)];
    if (subsets.count == 0) return full;
    NSUInteger cursor = 0;
    NSMutableData *out = [NSMutableData data];
    for (ATProtoS2PAHashBMFFSubset *s in subsets) {
        if (s.offset < cursor) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                           @"BMFF subsets must be ordered and non-overlapping");
            return nil;
        }
        if (s.offset > cursor) {
            NSUInteger end = MIN(s.offset, full.length);
            [out appendData:[full subdataWithRange:NSMakeRange(cursor, end - cursor)]];
        }
        NSUInteger skipLen = s.length == 0 ? (full.length > s.offset ? full.length - s.offset : 0)
                                           : s.length;
        cursor = s.offset + skipLen;
        if (cursor > full.length) cursor = full.length;
    }
    if (cursor < full.length) {
        [out appendData:[full subdataWithRange:NSMakeRange(cursor, full.length - cursor)]];
    }
    return out;
}

+ (void)hashUpdate:(CC_SHA256_CTX *)ctx
        offsetBE64:(NSUInteger)fileOffset
              data:(NSData *)data {
    uint8_t off[8];
    uint64_t v = (uint64_t)fileOffset;
    for (int i = 7; i >= 0; i--) {
        off[i] = (uint8_t)(v & 0xff);
        v >>= 8;
    }
    CC_SHA256_Update(ctx, off, 8);
    if (data.length > 0) {
        CC_SHA256_Update(ctx, data.bytes, (CC_LONG)data.length);
    }
}

+ (BOOL)hashRootBoxes:(NSArray<S2PABMFFBoxInfo *> *)rootBoxes
               inData:(NSData *)data
           exclusions:(NSArray<ATProtoS2PAHashBMFFExclusion *> *)exclusions
                  ctx:(CC_SHA256_CTX *)ctx
                error:(NSError **)error {
    NSMutableDictionary<NSString *, NSNumber *> *seen = [NSMutableDictionary dictionary];
    for (S2PABMFFBoxInfo *box in rootBoxes) {
        NSUInteger occ = seen[box.type].unsignedIntegerValue + 1;
        seen[box.type] = @(occ);

        ATProtoS2PAHashBMFFExclusion *matched = nil;
        for (ATProtoS2PAHashBMFFExclusion *ex in exclusions) {
            NSArray *parts = [self xpathComponents:ex.xpath error:error];
            if (!parts) return NO;
            // Profile: root-only xpath (single 4cc). Nested paths are ignored.
            if (parts.count != 1) {
                continue;
            }
            if (![self node:parts[0] matchesType:box.type occurrence:occ]) {
                continue;
            }
            if (![self box:box inData:data matchesExclusion:ex]) continue;
            matched = ex;
            break;
        }

        if (matched) {
            if (matched.subsets.count == 0) {
                continue; // fully excluded
            }
            NSData *partial = [self bytesForBox:box inData:data subsets:matched.subsets error:error];
            if (!partial) return NO;
            [self hashUpdate:ctx offsetBE64:box.fileOffset data:partial];
            continue;
        }
        NSData *full = [data subdataWithRange:NSMakeRange(box.fileOffset, box.length)];
        [self hashUpdate:ctx offsetBE64:box.fileOffset data:full];
    }
    return YES;
}

+ (nullable NSData *)sha256DigestForBMFFData:(NSData *)data
                                  exclusions:(NSArray<ATProtoS2PAHashBMFFExclusion *> *)exclusions
                                       error:(NSError **)error {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"bmffHash requires non-empty BMFF bytes");
        return nil;
    }
    if (exclusions.count == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"bmffHash requires at least one exclusion");
        return nil;
    }
    for (ATProtoS2PAHashBMFFExclusion *ex in exclusions) {
        if (![self xpathComponents:ex.xpath error:error]) return nil;
    }
    NSArray *roots = [self parseRootBoxes:data error:error];
    if (!roots) return nil;
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    if (![self hashRootBoxes:roots inData:data exclusions:exclusions ctx:&ctx error:error]) {
        return nil;
    }
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

+ (nullable NSArray<NSData *> *)leafDigestsForMDATPayload:(NSData *)payload
                                           fixedBlockSize:(NSNumber *)fixedBlockSize
                                      variableBlockSizes:(NSArray<NSNumber *> *)variableBlockSizes
                                                    error:(NSError **)error {
    if (![payload isKindOfClass:[NSData class]]) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"mdat payload required");
        return nil;
    }
    if (fixedBlockSize && variableBlockSizes.count > 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"cannot set both fixedBlockSize and variableBlockSizes");
        return nil;
    }
    NSMutableArray<NSData *> *leaves = [NSMutableArray array];
    if (!fixedBlockSize && variableBlockSizes.count == 0) {
        [leaves addObject:S2PASha256(payload)];
        return leaves;
    }
    if (fixedBlockSize) {
        NSUInteger block = fixedBlockSize.unsignedIntegerValue;
        if (block == 0) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                           @"fixedBlockSize must be > 0");
            return nil;
        }
        NSUInteger offset = 0;
        while (offset < payload.length) {
            NSUInteger end = MIN(offset + block, payload.length);
            NSData *chunk = [payload subdataWithRange:NSMakeRange(offset, end - offset)];
            [leaves addObject:S2PASha256(chunk)];
            offset = end;
        }
        if (leaves.count == 0) {
            [leaves addObject:S2PASha256([NSData data])];
        }
        return leaves;
    }
    NSUInteger sum = 0;
    for (NSNumber *n in variableBlockSizes) {
        sum += n.unsignedIntegerValue;
    }
    if (sum != payload.length) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"variableBlockSizes sum must equal mdat payload length");
        return nil;
    }
    NSUInteger offset = 0;
    for (NSNumber *n in variableBlockSizes) {
        NSUInteger len = n.unsignedIntegerValue;
        NSData *chunk = [payload subdataWithRange:NSMakeRange(offset, len)];
        [leaves addObject:S2PASha256(chunk)];
        offset += len;
    }
    return leaves;
}

+ (NSArray<NSArray<NSData *> *> *)merkleLayersFromLeafHashes:(NSArray<NSData *> *)leafHashes {
    if (leafHashes.count == 0) return @[];
    NSMutableArray<NSArray<NSData *> *> *layers = [NSMutableArray array];
    [layers addObject:[leafHashes copy]];
    NSArray<NSData *> *current = leafHashes;
    while (current.count > 1) {
        NSMutableArray<NSData *> *parent = [NSMutableArray array];
        for (NSUInteger i = 0; i < current.count; i += 2) {
            if (i + 1 == current.count) {
                [parent addObject:current[i]];
                continue;
            }
            NSMutableData *concat = [current[i] mutableCopy];
            [concat appendData:current[i + 1]];
            [parent addObject:S2PASha256(concat)];
        }
        [layers addObject:parent];
        current = parent;
    }
    return layers;
}

+ (nullable NSData *)mdatPayloadAtLocalId:(NSInteger)localId
                                   inData:(NSData *)data
                                    error:(NSError **)error {
    if (localId < 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"localId must be >= 0");
        return nil;
    }
    NSArray *roots = [self parseRootBoxes:data error:error];
    if (!roots) return nil;
    NSInteger mdatIndex = -1;
    for (S2PABMFFBoxInfo *box in roots) {
        if (![box.type isEqualToString:@"mdat"]) continue;
        mdatIndex++;
        if (mdatIndex != localId) continue;
        if (box.length < 8) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                           @"mdat box truncated");
            return nil;
        }
        // Standard size header: payload starts at +8. (largesize would be +16; not used here.)
        NSUInteger header = 8;
        const uint8_t *b = data.bytes;
        uint32_t size32 = ((uint32_t)b[box.fileOffset] << 24) | ((uint32_t)b[box.fileOffset + 1] << 16) |
                          ((uint32_t)b[box.fileOffset + 2] << 8) | (uint32_t)b[box.fileOffset + 3];
        if (size32 == 1) header = 16;
        if (box.length < header) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                           @"mdat header exceeds box");
            return nil;
        }
        return [data subdataWithRange:NSMakeRange(box.fileOffset + header, box.length - header)];
    }
    S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                   @"mdat localId not found");
    return nil;
}

+ (nullable instancetype)assertionExcludingC2PAUUIDForBMFFData:(NSData *)bmffData
                                                          name:(NSString *)name
                                                         error:(NSError **)error {
    NSArray *exclusions = @[ [self c2paUUIDBoxExclusion] ];
    NSData *digest = [self sha256DigestForBMFFData:bmffData exclusions:exclusions error:error];
    if (!digest) return nil;
    return [[self alloc] initWithDigest:digest exclusions:exclusions merkle:nil name:name];
}

+ (nullable instancetype)assertionExcludingC2PAUUIDWithMerkleForBMFFData:(NSData *)bmffData
                                                                uniqueId:(NSInteger)uniqueId
                                                                 localId:(NSInteger)localId
                                                          fixedBlockSize:(NSNumber *)fixedBlockSize
                                                     variableBlockSizes:(NSArray<NSNumber *> *)variableBlockSizes
                                                                    name:(NSString *)name
                                                                   error:(NSError **)error {
    NSData *payload = [self mdatPayloadAtLocalId:localId inData:bmffData error:error];
    if (!payload) return nil;
    NSArray<NSData *> *leaves = [self leafDigestsForMDATPayload:payload
                                                 fixedBlockSize:fixedBlockSize
                                            variableBlockSizes:variableBlockSizes
                                                          error:error];
    if (!leaves) return nil;
    ATProtoS2PAMerkleMap *map =
        [[ATProtoS2PAMerkleMap alloc] initWithUniqueId:uniqueId
                                               localId:localId
                                                 count:leaves.count
                                                hashes:leaves
                                                   alg:@"sha256"
                                        fixedBlockSize:fixedBlockSize
                                   variableBlockSizes:variableBlockSizes
                                  initializationHash:nil];
    NSArray *exclusions = @[
        [self c2paUUIDBoxExclusion],
        [self mdatMerklePayloadExclusion],
    ];
    NSData *digest = [self sha256DigestForBMFFData:bmffData exclusions:exclusions error:error];
    if (!digest) return nil;
    return [[self alloc] initWithDigest:digest exclusions:exclusions merkle:@[map] name:name];
}

- (nullable NSData *)encodeCBOR:(NSError **)error {
    if (self.digest && (self.digest.length != CC_SHA256_DIGEST_LENGTH ||
                        ![self.alg isEqualToString:@"sha256"])) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"only sha256 32-byte hashes are supported");
        return nil;
    }
    if (!self.digest && self.merkle.count == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"bmffHash requires hash and/or merkle");
        return nil;
    }
    if (self.exclusions.count == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"bmffHash CBOR requires exclusions");
        return nil;
    }
    NSMutableArray<ATProtoCBORValue *> *exArr = [NSMutableArray array];
    for (ATProtoS2PAHashBMFFExclusion *ex in self.exclusions) {
        NSMutableDictionary *map = [@{
            S2PAText(@"xpath"): S2PAText(ex.xpath),
        } mutableCopy];
        if (ex.dataMatches.count > 0) {
            NSMutableArray *dataArr = [NSMutableArray array];
            for (ATProtoS2PAHashBMFFDataMatch *m in ex.dataMatches) {
                [dataArr addObject:[ATProtoCBORValue map:@{
                    S2PAText(@"offset"): S2PAUInt(m.offset),
                    S2PAText(@"value"): [ATProtoCBORValue byteString:m.value],
                }]];
            }
            map[S2PAText(@"data")] = [ATProtoCBORValue array:dataArr];
        }
        if (ex.subsets.count > 0) {
            NSMutableArray *subArr = [NSMutableArray array];
            for (ATProtoS2PAHashBMFFSubset *s in ex.subsets) {
                [subArr addObject:[ATProtoCBORValue map:@{
                    S2PAText(@"offset"): S2PAUInt(s.offset),
                    S2PAText(@"length"): S2PAUInt(s.length),
                }]];
            }
            map[S2PAText(@"subset")] = [ATProtoCBORValue array:subArr];
        }
        [exArr addObject:[ATProtoCBORValue map:map]];
    }
    NSMutableDictionary *dict = [@{
        S2PAText(@"alg"): S2PAText(self.alg),
        S2PAText(@"exclusions"): [ATProtoCBORValue array:exArr],
    } mutableCopy];
    if (self.digest) {
        dict[S2PAText(@"hash")] = [ATProtoCBORValue byteString:self.digest];
    }
    if (self.merkle.count > 0) {
        NSMutableArray *merkleArr = [NSMutableArray array];
        for (ATProtoS2PAMerkleMap *mm in self.merkle) {
            NSData *mapCBOR = [mm encodeCBORMap:error];
            if (!mapCBOR) return nil;
            NSUInteger off = 0;
            ATProtoCBORValue *decoded = [ATProtoCBORDecoder decode:mapCBOR offset:&off];
            if (!decoded) {
                S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                               @"failed to re-decode merkle-map");
                return nil;
            }
            [merkleArr addObject:decoded];
        }
        dict[S2PAText(@"merkle")] = [ATProtoCBORValue array:merkleArr];
    }
    if (self.name.length > 0) {
        dict[S2PAText(@"name")] = S2PAText(self.name);
    }
    NSData *encoded = [[ATProtoCBORValue map:dict] encode];
    if (!encoded) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"failed to encode bmffHash CBOR");
    }
    return encoded;
}

+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error {
    if (![cbor isKindOfClass:[NSData class]] || cbor.length == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument,
                       @"bmffHash CBOR is empty");
        return nil;
    }
    NSUInteger offset = 0;
    ATProtoCBORValue *root = [ATProtoCBORDecoder decode:cbor offset:&offset];
    if (!root || offset != cbor.length || root.type != CBORTypeMap) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"bmffHash must be a single CBOR map");
        return nil;
    }
    if (![root.encode isEqualToData:cbor]) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"bmffHash CBOR must be canonical");
        return nil;
    }
    __block NSString *alg = nil;
    __block NSData *digestBytes = nil;
    __block NSString *name = nil;
    NSMutableArray<ATProtoS2PAHashBMFFExclusion *> *exclusions = [NSMutableArray array];
    NSMutableArray<ATProtoS2PAMerkleMap *> *merkle = [NSMutableArray array];
    __block NSError *parseError = nil;
    [root.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *key, ATProtoCBORValue *val,
                                                  BOOL *stop) {
        if (key.type != CBORTypeTextString) return;
        NSString *k = key.textString;
        if ([k isEqualToString:@"alg"] && val.type == CBORTypeTextString) {
            alg = val.textString;
        } else if ([k isEqualToString:@"hash"] && val.type == CBORTypeByteString) {
            digestBytes = val.byteString;
        } else if ([k isEqualToString:@"name"] && val.type == CBORTypeTextString) {
            name = val.textString;
        } else if ([k isEqualToString:@"merkle"] && val.type == CBORTypeArray) {
            for (ATProtoCBORValue *item in val.array) {
                ATProtoS2PAMerkleMap *mm = [ATProtoS2PAMerkleMap merkleMapFromCBORMap:item
                                                                                error:&parseError];
                if (!mm) {
                    *stop = YES;
                    return;
                }
                [merkle addObject:mm];
            }
        } else if ([k isEqualToString:@"exclusions"] && val.type == CBORTypeArray) {
            for (ATProtoCBORValue *item in val.array) {
                if (item.type != CBORTypeMap) continue;
                __block NSString *xpath = nil;
                NSMutableArray *dataMatches = [NSMutableArray array];
                NSMutableArray *subsets = [NSMutableArray array];
                [item.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *ik,
                                                              ATProtoCBORValue *iv, BOOL *s2) {
                    (void)s2;
                    if (ik.type != CBORTypeTextString) return;
                    NSString *ikKey = ik.textString;
                    if ([ikKey isEqualToString:@"xpath"] && iv.type == CBORTypeTextString) {
                        xpath = iv.textString;
                    } else if ([ikKey isEqualToString:@"data"] && iv.type == CBORTypeArray) {
                        for (ATProtoCBORValue *dm in iv.array) {
                            if (dm.type != CBORTypeMap) continue;
                            __block NSUInteger off = NSNotFound;
                            __block NSData *bytes = nil;
                            [dm.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *dk,
                                                                        ATProtoCBORValue *dv,
                                                                        BOOL *s3) {
                                (void)s3;
                                if (dk.type != CBORTypeTextString) return;
                                if ([dk.textString isEqualToString:@"offset"] &&
                                    dv.type == CBORTypeUnsignedInteger) {
                                    off = dv.unsignedInteger.unsignedIntegerValue;
                                } else if ([dk.textString isEqualToString:@"value"] &&
                                           dv.type == CBORTypeByteString) {
                                    bytes = dv.byteString;
                                }
                            }];
                            if (off != NSNotFound && bytes) {
                                [dataMatches addObject:[ATProtoS2PAHashBMFFDataMatch matchWithOffset:off
                                                                                               value:bytes]];
                            }
                        }
                    } else if ([ikKey isEqualToString:@"subset"] && iv.type == CBORTypeArray) {
                        for (ATProtoCBORValue *sm in iv.array) {
                            if (sm.type != CBORTypeMap) continue;
                            __block NSUInteger off = NSNotFound;
                            __block NSUInteger len = NSNotFound;
                            [sm.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *sk,
                                                                        ATProtoCBORValue *sv,
                                                                        BOOL *s3) {
                                (void)s3;
                                if (sk.type != CBORTypeTextString) return;
                                if ([sk.textString isEqualToString:@"offset"] &&
                                    sv.type == CBORTypeUnsignedInteger) {
                                    off = sv.unsignedInteger.unsignedIntegerValue;
                                } else if ([sk.textString isEqualToString:@"length"] &&
                                           sv.type == CBORTypeUnsignedInteger) {
                                    len = sv.unsignedInteger.unsignedIntegerValue;
                                }
                            }];
                            if (off != NSNotFound && len != NSNotFound) {
                                [subsets addObject:[ATProtoS2PAHashBMFFSubset subsetWithOffset:off
                                                                                        length:len]];
                            }
                        }
                    }
                }];
                if (xpath.length > 0) {
                    [exclusions addObject:[ATProtoS2PAHashBMFFExclusion exclusionWithXPath:xpath
                                                                               dataMatches:dataMatches
                                                                                   subsets:subsets]];
                }
            }
        }
    }];
    if (parseError) {
        if (error) *error = parseError;
        return nil;
    }
    if (alg && ![alg isEqualToString:@"sha256"]) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"bmffHash only supports alg=sha256");
        return nil;
    }
    if (digestBytes && digestBytes.length != CC_SHA256_DIGEST_LENGTH) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"bmffHash hash must be 32 bytes");
        return nil;
    }
    if (!digestBytes && merkle.count == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"bmffHash requires hash and/or merkle");
        return nil;
    }
    if (exclusions.count == 0) {
        S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                       @"bmffHash requires exclusions");
        return nil;
    }
    return [[self alloc] initWithDigest:digestBytes
                             exclusions:exclusions
                                 merkle:merkle.count > 0 ? merkle : nil
                                   name:name];
}

- (BOOL)verifyMerkleMapsAgainstBMFFData:(NSData *)bmffData error:(NSError **)error {
    for (ATProtoS2PAMerkleMap *mm in self.merkle ?: @[]) {
        if (mm.alg.length > 0 && ![mm.alg isEqualToString:@"sha256"] &&
            ![mm.alg isEqualToString:self.alg]) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                           @"merkle-map alg must be sha256");
            return NO;
        }
        // Leaf-row profile: hashes.count == count.
        if (mm.hashes.count != mm.count) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                           @"this profile stores the leaf row (hashes.count == count)");
            return NO;
        }
        NSData *payload = [[self class] mdatPayloadAtLocalId:mm.localId inData:bmffData error:error];
        if (!payload) return NO;
        NSArray<NSData *> *leaves =
            [[self class] leafDigestsForMDATPayload:payload
                                     fixedBlockSize:mm.fixedBlockSize
                                variableBlockSizes:mm.variableBlockSizes
                                              error:error];
        if (!leaves) return NO;
        if (leaves.count != mm.count) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorInvalidStructure,
                           @"merkle leaf count mismatch");
            return NO;
        }
        for (NSUInteger i = 0; i < leaves.count; i++) {
            if (![leaves[i] isEqualToData:mm.hashes[i]]) {
                S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorHashMismatch,
                               @"merkle leaf digest mismatch");
                return NO;
            }
        }
    }
    return YES;
}

- (BOOL)verifyAgainstBMFFData:(NSData *)bmffData error:(NSError **)error {
    if (self.digest) {
        NSData *computed = [[self class] sha256DigestForBMFFData:bmffData
                                                      exclusions:self.exclusions
                                                           error:error];
        if (!computed) return NO;
        if (![computed isEqualToData:self.digest]) {
            S2PABMFFSetErr(error, ATProtoS2PAHashBMFFAssertionErrorHashMismatch,
                           @"bmffHash digest mismatch");
            return NO;
        }
    }
    if (self.merkle.count > 0) {
        if (![self verifyMerkleMapsAgainstBMFFData:bmffData error:error]) return NO;
    }
    return YES;
}

@end
